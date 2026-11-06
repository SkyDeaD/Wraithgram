import Foundation
import SwiftSignalKit
import WGCore
import WGFeaturesShared

/// Resolves what the user picked into a mask ready to render.
///
/// The frame path only reads (`mask(for:)`: one lock, one dictionary lookup). A mask that is not
/// ready starts its preparation once — built-in masks are immediate, own masks are read from disk
/// on a background queue, catalog masks are downloaded — and frames pass through untouched until it
/// is ready. A mask that failed is remembered and is not retried from the frame path: only picking
/// it again (or opening the masks screen) retries it, so an unavailable remote mask never touches
/// the disk or the network per frame.
final class WGMaskEngine {
    static let shared = WGMaskEngine()

    private enum State {
        case preparing
        case ready(WGPreparedMask)
        case failed
    }

    private let lock = NSLock()
    private var states: [WGMaskSelection: State] = [:]
    private let queue = Queue(name: "org.wraithgram.masks.engine")
    private var storeRevisionDisposable: Disposable?

    /// Changes of what is selected or prepared (screens refresh their labels).
    let changes = ValuePromise<Int>(0, ignoreRepeated: false)
    private var changesValue = 0

    init() {
        // An edited own mask is re-read on its next frame.
        self.storeRevisionDisposable = (WGMaskStore.shared.revision.get() |> deliverOn(self.queue)).start(next: { [weak self] _ in
            self?.dropUserMasks()
        })
    }

    // MARK: Selection

    /// What a camera of this account shows: the anonymous mask while the mode is on, else the
    /// user's own choice.
    static func selection(for account: WGAccountID?) -> WGMaskSelection {
        if let account, let override = WGAnonymousMode.maskOverride(for: account) {
            let selection = WGMaskSelection(storage: override)
            if case .catalog = selection, !WGMaskCatalog.isAvailable {
                // A mask the catalog can not deliver would leave the face uncovered: the default
                // anonymous mask instead.
                return WGMaskSelection(storage: WGAnonymousMode.mask.defaultValue)
            }
            return selection
        }
        return WGMaskSelection(storage: WGMaskSettings.selection.value)
    }

    /// Whether the camera of this account needs the masks extension at all.
    static func isActive(for account: WGAccountID?) -> Bool {
        if WGMaskSettings.enabled.value {
            return true
        }
        if let account, WGAnonymousMode.isActive.value(for: account) {
            return true
        }
        return false
    }

    /// The user picked a mask by hand: it becomes the choice, the anonymous mode of this account
    /// turns off (the manual choice wins), a failure of it is forgotten and it is prepared now.
    func select(_ selection: WGMaskSelection, account: WGAccountID?) {
        WGMaskSettings.selection.set(selection.storage)
        if let account, WGAnonymousMode.isActive.value(for: account) {
            WGAnonymousMode.isActive.set(false, for: account)
        }
        self.retry(selection)
    }

    /// Forgets a failure and prepares the mask again.
    func retry(_ selection: WGMaskSelection) {
        self.lock.lock()
        if case .failed = self.states[selection] {
            self.states[selection] = nil
        }
        self.lock.unlock()
        let _ = self.mask(for: selection)
    }

    // MARK: Frame path

    /// Any thread. nil = no mask, or it is still being prepared, or it failed.
    func mask(for selection: WGMaskSelection) -> WGPreparedMask? {
        if case .none = selection {
            return nil
        }
        self.lock.lock()
        let state = self.states[selection]
        if state == nil {
            self.states[selection] = .preparing
        }
        self.lock.unlock()
        switch state {
        case let .ready(mask):
            return mask
        case .preparing, .failed:
            return nil
        case .none:
            self.prepare(selection)
            return nil
        }
    }

    /// For labels and the studio: the prepared mask if it is already there.
    func preparedMask(for selection: WGMaskSelection) -> WGPreparedMask? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if case let .ready(mask) = self.states[selection] {
            return mask
        }
        return nil
    }

    private func prepare(_ selection: WGMaskSelection) {
        switch selection {
        case .none:
            break
        case let .builtIn(id):
            if let manifest = WGBuiltInMasks.manifest(id: id) {
                self.finish(selection, WGPreparedMask(selection: selection, manifest: manifest, assets: nil))
            } else {
                self.finish(selection, nil)
            }
        case let .user(id):
            self.queue.async {
                let store = WGMaskStore.shared
                guard let manifest = store.loadManifest(id: id) else {
                    self.finish(selection, nil)
                    return
                }
                self.finish(selection, WGPreparedMask(selection: selection, manifest: manifest, assets: WGMaskAssets(directory: store.assetsDirectory(id: id))))
            }
        case let .catalog(id):
            WGMaskCatalog.shared.prepare(id: id, completion: { [weak self] mask in
                self?.finish(selection, mask)
            })
        }
    }

    private func finish(_ selection: WGMaskSelection, _ mask: WGPreparedMask?) {
        self.lock.lock()
        if let mask {
            self.states[selection] = .ready(mask)
        } else {
            self.states[selection] = .failed
        }
        self.lock.unlock()
        DispatchQueue.main.async {
            self.changesValue += 1
            self.changes.set(self.changesValue)
        }
    }

    private func dropUserMasks() {
        self.lock.lock()
        for key in Array(self.states.keys) {
            if case .user = key {
                self.states[key] = nil
            }
        }
        self.lock.unlock()
    }

    // MARK: Names

    /// The name of a choice for labels («Не выбрана», a built-in name, a catalog or own mask name).
    static func title(_ selection: WGMaskSelection) -> String {
        let languageCode = WGLocalization.shared.languageCode
        switch selection {
        case .none:
            return WGStrings.CameraMasks.Masks.none
        case let .builtIn(id):
            return WGBuiltInMasks.title(id: id)
        case let .catalog(id):
            if let entry = WGMaskCatalog.shared.entry(id: id) {
                return entry.displayName(languageCode: languageCode)
            }
            // The catalog is off: the mask will never come (not a raw id in the menu).
            return WGMaskCatalog.isAvailable ? id : WGStrings.CameraMasks.Masks.deletedMask
        case let .user(id):
            return WGMaskStore.shared.manifest(id: id)?.displayName(languageCode: languageCode) ?? WGStrings.CameraMasks.Masks.deletedMask
        }
    }
}
