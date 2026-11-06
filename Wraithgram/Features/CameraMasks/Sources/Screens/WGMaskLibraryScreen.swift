import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ItemListUI
import PresentationDataUtils
import WGCore
import WGFeaturesShared

enum WGMaskLibraryTarget {
    /// The user's own choice for round videos and calls.
    case current
    /// The anonymous mode's mask.
    case anonymous
}

/// What the library screen shows: refreshed by the stores' signals, read by the content closure.
private final class WGMaskLibraryState {
    var userEntries: [WGMaskStoreEntry] = []
    var catalogEntries: [WGMaskCatalogEntry] = []
    var cacheSize: Int64?
}

/// «Маски»: pick a mask (built-in, own, from the catalog) and manage the catalog cache. Opening it
/// refreshes the catalog if it is stale (only while masks are in use); nothing else touches the
/// network, and the cache size is computed once in the background, not on every update.
func wgMakeMaskLibraryScreen(context: AccountContext, target: WGMaskLibraryTarget) -> ViewController {
    let state = WGMaskLibraryState()
    let accountId = context.account.id.wg
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshValue = 0
    let bump = {
        refreshValue += 1
        refresh.set(refreshValue)
    }
    let extra: Signal<Void, NoError> = combineLatest(
        WGMaskStore.shared.entries,
        WGMaskCatalog.shared.entries,
        WGMaskEngine.shared.changes.get(),
        refresh.get()
    )
    |> deliverOnMainQueue
    |> map { userEntries, catalogEntries, _, _ -> Void in
        state.userEntries = userEntries
        state.catalogEntries = catalogEntries
        return Void()
    }

    weak var controllerRef: ViewController?
    let languageCode = { WGLocalization.shared.languageCode }

    let currentSelection: () -> WGMaskSelection = {
        switch target {
        case .current:
            return WGMaskSelection(storage: WGMaskSettings.selection.value)
        case .anonymous:
            return WGMaskSelection(storage: WGAnonymousMode.mask.value)
        }
    }
    let select: (WGMaskSelection) -> Void = { selection in
        switch target {
        case .current:
            WGMaskEngine.shared.select(selection, account: accountId)
        case .anonymous:
            WGAnonymousMode.mask.set(selection.storage)
            WGMaskEngine.shared.retry(selection)
        }
    }

    let controller = wgMakeListScreen(context: context, extra: extra, content: {
        let selected = currentSelection()
        var rows: [WGListRow] = []

        rows.append(WGListRow(id: "builtin.header", section: 0, kind: .header(WGStrings.CameraMasks.Masks.builtInSection)))
        if case .current = target {
            rows.append(WGListRow(id: "none", section: 0, kind: .checkbox(title: WGStrings.CameraMasks.Masks.none, subtitle: nil, checked: selected == .none, enabled: true), action: {
                select(.none)
            }))
        }
        for id in WGBuiltInMasks.ids {
            let selection = WGMaskSelection.builtIn(id)
            rows.append(WGListRow(id: "builtin." + id, section: 0, kind: .checkbox(title: WGBuiltInMasks.glyph(id: id) + "  " + WGBuiltInMasks.title(id: id), subtitle: nil, checked: selected == selection, enabled: true), action: {
                select(selection)
            }))
        }

        rows.append(WGListRow(id: "user.header", section: 1, kind: .header(WGStrings.CameraMasks.Masks.ownSection)))
        for entry in state.userEntries {
            let selection = WGMaskSelection.user(entry.id)
            rows.append(WGListRow(id: "user." + entry.id, section: 1, kind: .checkbox(title: entry.manifest.displayName(languageCode: languageCode()), subtitle: WGStrings.CameraMasks.Studio.layers(count: entry.manifest.effects.count), checked: selected == selection, enabled: true), action: {
                select(selection)
            }))
        }
        rows.append(WGListRow(id: "user.create", section: 1, kind: .action(title: WGStrings.CameraMasks.Studio.create, destructive: false, enabled: true), action: {
            controllerRef?.push(wgMakeMaskStudioHome(context: context))
        }))

        rows.append(WGListRow(id: "catalog.header", section: 2, kind: .header(WGStrings.CameraMasks.Masks.catalogSection)))
        if !WGMaskCatalog.isAvailable {
            rows.append(WGListRow(id: "catalog.unavailable", section: 2, kind: .footer(WGStrings.CameraMasks.Masks.catalogUnavailable)))
        } else if state.catalogEntries.isEmpty {
            rows.append(WGListRow(id: "catalog.empty", section: 2, kind: .footer(WGStrings.CameraMasks.Masks.catalogEmpty)))
        } else {
            for entry in state.catalogEntries {
                let selection = WGMaskSelection.catalog(entry.id)
                rows.append(WGListRow(id: "catalog." + entry.id, section: 2, kind: .checkbox(title: entry.displayName(languageCode: languageCode()), subtitle: nil, checked: selected == selection, enabled: true), action: {
                    select(selection)
                }))
            }
        }

        if case .current = target, WGMaskCatalog.isAvailable {
            let fetchedAt = WGMaskSettings.catalogFetchedAt.value
            let fetchedLabel: String
            if fetchedAt > 0.0 {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                fetchedLabel = formatter.string(from: Date(timeIntervalSince1970: fetchedAt))
            } else {
                fetchedLabel = WGStrings.CameraMasks.Masks.never
            }
            rows.append(WGListRow(id: "cache.header", section: 3, kind: .header(WGStrings.CameraMasks.Masks.cacheSection)))
            rows.append(WGListRow(id: "cache.refresh", section: 3, kind: .disclosure(title: WGStrings.CameraMasks.Masks.refreshCatalog, label: fetchedLabel, icon: nil, enabled: true), action: {
                WGMaskCatalog.shared.refreshIfNeeded(force: true)
            }))
            let sizeLabel = state.cacheSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"
            rows.append(WGListRow(id: "cache.size", section: 3, kind: .disclosure(title: WGStrings.CameraMasks.Masks.cacheSize, label: sizeLabel, icon: nil, enabled: true), action: {
                guard let controller = controllerRef else {
                    return
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                controller.present(textAlertController(context: context, title: WGStrings.CameraMasks.Masks.clearCacheTitle, text: WGStrings.CameraMasks.Masks.clearCacheText, actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: WGStrings.CameraMasks.Masks.clearCacheConfirm, action: {
                        WGMaskCatalog.shared.clearCache(completion: {
                            state.cacheSize = 0
                            bump()
                        })
                    })
                ]), in: .window(.root))
            }))
            rows.append(WGListRow(id: "cache.limit", section: 3, kind: .disclosure(title: WGStrings.CameraMasks.Masks.cacheLimit, label: WGStrings.CameraMasks.Masks.megabytes(value: WGMaskSettings.cacheLimit.value), icon: nil, enabled: true), action: {
                let sheet = UIAlertController(title: WGStrings.CameraMasks.Masks.cacheLimit, message: nil, preferredStyle: .actionSheet)
                for value in ["50", "100", "200", "400", "800", "1024"] {
                    let prefix = value == WGMaskSettings.cacheLimit.value ? "✓ " : ""
                    sheet.addAction(UIAlertAction(title: prefix + WGStrings.CameraMasks.Masks.megabytes(value: value), style: .default, handler: { _ in
                        WGMaskSettings.cacheLimit.set(value)
                    }))
                }
                sheet.addAction(UIAlertAction(title: context.sharedContext.currentPresentationData.with({ $0 }).strings.Common_Cancel, style: .cancel))
                wgPresentNative(sheet, from: controllerRef)
            }))
        }
        rows.append(WGListRow(id: "footer", section: 4, kind: .footer(WGStrings.CameraMasks.Masks.footer)))

        let title: String
        switch target {
        case .current:
            title = WGStrings.CameraMasks.Masks.title
        case .anonymous:
            title = WGStrings.CameraMasks.Anonymous.mask
        }
        return WGListScreenContent(title: title, rows: rows)
    })
    controllerRef = controller

    if WGMaskEngine.isActive(for: accountId) || target == .anonymous {
        WGMaskCatalog.shared.refreshIfNeeded()
    }
    if case .current = target {
        WGMaskCatalog.shared.cacheSize(completion: { size in
            state.cacheSize = size
            bump()
        })
    }
    return controller
}

extension WGMaskLibraryTarget: Equatable {}
