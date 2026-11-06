import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import ZipArchive
import WGCore

/// «Бейджи»: the bundled Wraithgram badge plus the user's own, selection, the studio, sharing
/// (`.ggbadge` = the old Wraithgram's JSON package, `WGBadgePackage`; the zip of earlier builds is
/// still read), import from a file, a link or a chat. Thumbnails are
/// the badges' `render.png`, decoded once into the store's cache — never per rebuild.
enum WGBadgeGallery {
    static let bundledId = "wraithgram"
    private static let maxImportBytes = 8 * 1024 * 1024

    static func makeScreen(context: AccountContext) -> ViewController {
        weak var controllerRef: ViewController?
        let documents = Promise<[WGBadgeDocument]>([])
        documents.set(WGBadgeStore.shared.documents)
        let box = WGBadgeGalleryBox()
        let update = documents.get()
        |> deliverOnMainQueue
        |> map { value -> Void in
            box.documents = value
            return Void()
        }

        let actions = WGListActions(select: { id in
            switch id {
            case "create":
                WGBadgeGallery.openStudio(context: context, from: controllerRef, document: nil)
            case "importLink":
                WGBadgeGallery.importFromLink(context: context, from: controllerRef)
            case "importFile":
                WGBadgeGallery.importFromFile(context: context, from: controllerRef)
            default:
                WGBadgeGallery.presentBadgeActions(id: id, document: box.documents.first(where: { $0.id == id }), context: context, from: controllerRef)
            }
        })
        let controller = wgMakeInterfaceList(context: context, title: { WGStrings.Interface.Badge.galleryTitle }, update: update, sections: { _ in
            let selection = InterfaceSettings.islandBadgeSelection.value
            let isOn = InterfaceSettings.islandBadge.value
            var rows: [WGListRow] = [.header(WGStrings.Interface.Badge.galleryHeader)]
            let bundledLabel = (isOn && !WGBadgeStore.isValidId(selection)) ? WGStrings.Interface.Badge.selectedLabel : ""
            rows.append(.disclosure(id: WGBadgeGallery.bundledId, title: WGStrings.Interface.Badge.bundledName, label: bundledLabel, icon: WGBadgeGallery.thumbnail(selection: WGBadgeGallery.bundledId)))
            for document in box.documents {
                let label = (isOn && selection == document.id) ? WGStrings.Interface.Badge.selectedLabel : ""
                rows.append(.disclosure(id: document.id, title: document.name, label: label, icon: WGBadgeGallery.thumbnail(selection: document.id)))
            }
            rows.append(.footer(WGStrings.Interface.Badge.galleryFooter))
            return [
                WGListSection(rows),
                WGListSection([
                    .action(id: "create", title: WGStrings.Interface.Badge.create, isDestructive: false),
                    .action(id: "importFile", title: WGStrings.Interface.Badge.importFile, isDestructive: false),
                    .action(id: "importLink", title: WGStrings.Interface.Badge.importLink, isDestructive: false)
                ])
            ]
        }, actions: actions)
        controllerRef = controller
        return controller
    }

    /// 52 pt wide: what fits the icon column of a list row.
    private static let thumbnails = Atomic<[String: UIImage]>(value: [:])

    static func thumbnail(selection: String) -> UIImage? {
        guard let image = WGBadgeStore.shared.image(selection: selection) else {
            return nil
        }
        let key = "\(selection)|\(ObjectIdentifier(image).hashValue)"
        if let cached = WGBadgeGallery.thumbnails.with({ $0[key] }) {
            return cached
        }
        let width: CGFloat = 52.0
        let size = CGSize(width: width, height: floor(width * WGBadgeDocument.canvasSize.height / WGBadgeDocument.canvasSize.width))
        guard let thumbnail = generateImage(size, rotatedContext: { contextSize, context in
            let rect = CGRect(origin: CGPoint(), size: contextSize)
            context.clear(rect)
            // The island behind it, as on the phone.
            context.setFillColor(UIColor.black.cgColor)
            context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: contextSize.height * 0.5).cgPath)
            context.fillPath()
            UIGraphicsPushContext(context)
            image.draw(in: rect)
            UIGraphicsPopContext()
        }) else {
            return nil
        }
        let _ = WGBadgeGallery.thumbnails.modify { current in
            var updated = current
            updated[key] = thumbnail
            return updated
        }
        return thumbnail
    }

    private static func select(_ id: String) {
        InterfaceSettings.islandBadgeSelection.set(id)
        InterfaceSettings.islandBadge.set(true)
    }

    private static func presentBadgeActions(id: String, document: WGBadgeDocument?, context: AccountContext, from controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var buttons: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        buttons.append((WGStrings.Interface.Badge.select, false, {
            WGBadgeGallery.select(id)
        }))
        if let document {
            buttons.append((WGStrings.Interface.Badge.edit, false, {
                WGBadgeGallery.openStudio(context: context, from: controller, document: document)
            }))
            buttons.append((WGStrings.Interface.Common.rename, false, {
                wgPresentTextPrompt(from: controller, title: WGStrings.Interface.Badge.namePrompt, text: document.name, placeholder: WGStrings.Interface.Badge.defaultName, cancel: presentationData.strings.Common_Cancel, done: presentationData.strings.Common_Done, completion: { text in
                    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    if trimmed.isEmpty {
                        return
                    }
                    var updated = document
                    updated.name = trimmed
                    guard let render = WGBadgeStore.shared.image(selection: document.id) else {
                        return
                    }
                    let _ = WGBadgeStore.shared.save(updated, render: render).start()
                })
            }))
            buttons.append((WGStrings.Interface.Badge.share, false, {
                WGBadgeGallery.share(document, from: controller)
            }))
            buttons.append((presentationData.strings.Common_Delete, true, {
                wgConfirmDestructive(context: context, from: controller, title: WGStrings.Interface.Badge.deleteTitle, text: WGStrings.Interface.Badge.deleteText(name: document.name), confirm: presentationData.strings.Common_Delete, action: {
                    if InterfaceSettings.islandBadgeSelection.value == document.id {
                        InterfaceSettings.islandBadgeSelection.reset()
                    }
                    let _ = WGBadgeStore.shared.delete(document.id).start()
                })
            }))
        }
        wgPresentActionSheet(context: context, from: controller, buttons: buttons)
    }

    /// The badge's pictures are read and decoded off the main thread first; the studio opens with them.
    static func openStudio(context: AccountContext, from controller: ViewController?, document: WGBadgeDocument?) {
        let _ = (Signal<[String: UIImage], NoError> { subscriber in
            var assets: [String: UIImage] = [:]
            if let document {
                for layer in document.layers {
                    if let name = layer.fileName, assets[name] == nil, let image = WGBadgeStore.shared.assetImage(name, badgeId: document.id) {
                        assets[name] = image
                    }
                }
            }
            subscriber.putNext(assets)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(wgInterfaceQueue)
        |> deliverOnMainQueue).start(next: { [weak controller] assets in
            let studio = WGBadgeStudioController(context: context, document: document, assets: assets, completion: { saved in
                WGBadgeGallery.select(saved.id)
                WGIslandBadge.shared.reloadImage()
            })
            (controller?.navigationController as? NavigationController)?.pushViewController(studio)
        })
    }

    // MARK: Sharing

    private static func share(_ document: WGBadgeDocument, from controller: ViewController?) {
        let _ = (WGBadgeGallery.archive(document)
        |> deliverOnMainQueue).start(next: { url in
            guard let url else {
                return
            }
            wgPresentNative(UIActivityViewController(activityItems: [url], applicationActivities: nil), from: controller)
        })
    }

    /// `<tmp>/<name>.ggbadge`: the JSON package the old Wraithgram reads and writes
    /// (`WGBadgePackage`), pictures inline; `render.png` is re-made on import.
    private static func archive(_ document: WGBadgeDocument) -> Signal<URL?, NoError> {
        let source = WGBadgeStore.shared.badgeDirectory(document.id)
        return Signal { subscriber in
            guard let source else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            var assets: [String: Data] = [:]
            for layer in document.layers {
                if let name = layer.fileName, assets[name] == nil {
                    let path = ((source as NSString).appendingPathComponent("assets") as NSString).appendingPathComponent(name)
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                        assets[name] = data
                    }
                }
            }
            guard let package = WGBadgePackage.encode(document, assets: assets) else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let staging = (NSTemporaryDirectory() as NSString).appendingPathComponent("wg-badge-" + UUID().uuidString)
            try? FileManager.default.createDirectory(atPath: staging, withIntermediateDirectories: true, attributes: nil)
            let safeName = document.name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
            let destination = (staging as NSString).appendingPathComponent((safeName.isEmpty ? "badge" : safeName) + "." + WGBadgePackage.fileExtension)
            if (try? package.write(to: URL(fileURLWithPath: destination), options: .atomic)) != nil {
                subscriber.putNext(URL(fileURLWithPath: destination))
            } else {
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(wgInterfaceQueue)
    }

    // MARK: Import

    private static func importFromLink(context: AccountContext, from controller: ViewController?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        wgPresentTextPrompt(from: controller, title: WGStrings.Interface.Badge.importLink, message: WGStrings.Interface.Badge.importLinkText, text: "", placeholder: "https://", keyboard: .URL, cancel: presentationData.strings.Common_Cancel, done: presentationData.strings.Common_Done, completion: { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else {
                WGBadgeGallery.showError(context: context, from: controller, text: WGStrings.Interface.Badge.errorLink)
                return
            }
            let _ = (WGNetwork.shared.fetch(WGNetworkRequest(url: url, maxBytes: WGBadgeGallery.maxImportBytes))
            |> deliverOnMainQueue).start(next: { response in
                guard let data = response.data else {
                    WGBadgeGallery.showError(context: context, from: controller, text: WGStrings.Interface.Badge.errorDownload)
                    return
                }
                WGBadgeGallery.importData(data, name: url.deletingPathExtension().lastPathComponent, context: context, from: controller)
            }, error: { error in
                WGBadgeGallery.showError(context: context, from: controller, text: error == .tooLarge ? WGStrings.Interface.Badge.errorTooLarge : WGStrings.Interface.Badge.errorDownload)
            })
        })
    }

    private static func importFromFile(context: AccountContext, from controller: ViewController?) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        let delegate = WGBadgeDocumentPickerDelegate(completion: { url in
            WGBadgeGallery.importFile(url, context: context, from: controller)
        })
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &wgBadgePickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        wgPresentNative(picker, from: controller)
    }

    /// A local file: from the document picker, or a `.ggbadge` tapped in a chat. Read off the main thread.
    static func importFile(_ url: URL, context: AccountContext, from controller: ViewController?) {
        let _ = (Signal<Data?, NoError> { subscriber in
            subscriber.putNext(try? Data(contentsOf: url, options: .mappedIfSafe))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(wgInterfaceQueue)
        |> deliverOnMainQueue).start(next: { data in
            guard let data, data.count <= WGBadgeGallery.maxImportBytes else {
                WGBadgeGallery.showError(context: context, from: controller, text: WGStrings.Interface.Badge.errorTooLarge)
                return
            }
            WGBadgeGallery.importData(data, name: url.deletingPathExtension().lastPathComponent, context: context, from: controller)
        })
    }

    /// A `.ggbadge` becomes a badge as it was made — the JSON package of the old Wraithgram (and of
    /// this one, `WGBadgePackage`) or the zip archive of earlier builds; a picture becomes a
    /// one-picture badge that fills the pill. Either way it is re-rendered here, nothing from the
    /// file is trusted as a finished image.
    private static func importData(_ data: Data, name: String, context: AccountContext, from controller: ViewController?) {
        let isZip = data.count > 4 && data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
        if !isZip, let first = data.first(where: { !($0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) }), first == UInt8(ascii: "{") {
            let _ = (Signal<(document: WGBadgeDocument, assets: [(String, UIImage)])?, NoError> { subscriber in
                subscriber.putNext(WGBadgePackage.decode(data))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(wgInterfaceQueue)
            |> deliverOnMainQueue).start(next: { result in
                guard let result else {
                    WGBadgeGallery.showError(context: context, from: controller, text: WGStrings.Interface.Badge.errorInvalid)
                    return
                }
                WGBadgeGallery.finishImport(result.document, assets: result.assets, context: context, from: controller)
            })
            return
        }
        if isZip {
            let _ = (WGBadgeGallery.unpack(data)
            |> deliverOnMainQueue).start(next: { result in
                guard let (document, assets) = result else {
                    WGBadgeGallery.showError(context: context, from: controller, text: WGStrings.Interface.Badge.errorInvalid)
                    return
                }
                WGBadgeGallery.finishImport(document, assets: assets, context: context, from: controller)
            })
            return
        }
        // A picture: decoded off the main thread, at most 900 px, never whole.
        let _ = (Signal<UIImage?, NoError> { subscriber in
            subscriber.putNext(WGBadgeImages.decode(data))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(wgInterfaceQueue)
        |> deliverOnMainQueue).start(next: { image in
            guard let image else {
                WGBadgeGallery.showError(context: context, from: controller, text: WGStrings.Interface.Badge.errorInvalid)
                return
            }
            let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            var document = WGBadgeDocument.new(name: trimmed.isEmpty ? WGStrings.Interface.Badge.defaultName : trimmed, text: "")
            document.layers = []
            WGBadgeGallery.finishImport(document, assets: [("picture", image)], context: context, from: controller)
        })
    }

    /// Stores the assets under the new badge (PNG files, off the main thread), renders and saves it,
    /// selects it.
    private static func finishImport(_ source: WGBadgeDocument, assets: [(String, UIImage)], context: AccountContext, from controller: ViewController?) {
        var renumbered = source
        renumbered.id = "custom." + UUID().uuidString.lowercased()
        let document = renumbered
        let badgeId = document.id
        let _ = (Signal<(renamed: [String: String], images: [String: UIImage]), NoError> { subscriber in
            var renamed: [String: String] = [:]
            var images: [String: UIImage] = [:]
            for (oldName, image) in assets {
                if let stored = WGBadgeStore.shared.storeAsset(image, badgeId: badgeId) {
                    renamed[oldName] = stored
                    images[stored] = image
                }
            }
            subscriber.putNext((renamed, images))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(wgInterfaceQueue)
        |> deliverOnMainQueue).start(next: { stored in
            WGBadgeGallery.finishImport(document, renamed: stored.renamed, images: stored.images, context: context, from: controller)
        })
    }

    private static func finishImport(_ document: WGBadgeDocument, renamed: [String: String], images: [String: UIImage], context: AccountContext, from controller: ViewController?) {
        var document = document
        if document.layers.isEmpty, let stored = renamed["picture"] {
            document.layers = [.makeImage(stored, fitMode: .fill)]
        } else {
            document.layers = document.layers.compactMap { layer -> WGBadgeDocument.Layer? in
                var layer = layer
                if layer.kind == .image {
                    guard let old = layer.fileName, let stored = renamed[old] else {
                        return nil
                    }
                    layer.fileName = stored
                }
                return layer
            }
        }
        guard let render = WGBadgeRenderer.render(document, assets: { images[$0] }) else {
            WGBadgeGallery.showError(context: context, from: controller, text: WGStrings.Interface.Badge.errorInvalid)
            return
        }
        let _ = (WGBadgeStore.shared.save(document, render: render)
        |> deliverOnMainQueue).start(completed: {
            WGBadgeGallery.select(document.id)
            WGIslandBadge.shared.reloadImage()
            controller?.present(wgToast(context: context, text: WGStrings.Interface.Badge.imported), in: .window(.root))
        })
    }

    /// Limits: ≤ 64 entries, each ≤ 4 MB, ≤ 12 MB unpacked, compression ≤ 250×, `badge.json` ≤ 256 KB,
    /// assets are PNG/JPEG pictures referenced by the document.
    private static func unpack(_ data: Data) -> Signal<(WGBadgeDocument, [(String, UIImage)])?, NoError> {
        return Signal { subscriber in
            let staging = (NSTemporaryDirectory() as NSString).appendingPathComponent("wg-badge-in-" + UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(atPath: staging)
            }
            try? FileManager.default.createDirectory(atPath: staging, withIntermediateDirectories: true, attributes: nil)
            let archivePath = (staging as NSString).appendingPathComponent("in.zip")
            let content = (staging as NSString).appendingPathComponent("content")
            func fail() {
                subscriber.putNext(nil)
                subscriber.putCompletion()
            }
            guard (try? data.write(to: URL(fileURLWithPath: archivePath))) != nil, let entries = SSZipArchive.getEntriesForFile(atPath: archivePath), entries.count <= 64 else {
                fail()
                return EmptyDisposable
            }
            var total = 0
            for entry in entries {
                if entry.uncompressedSize > 4 * 1024 * 1024 {
                    fail()
                    return EmptyDisposable
                }
                total += Int(entry.uncompressedSize)
            }
            if total > 12 * 1024 * 1024 || Double(total) / Double(max(1, data.count)) > 250.0 {
                fail()
                return EmptyDisposable
            }
            // Never through a symbolic link, never out of the directory (WGSafeUnzip).
            guard WGSafeUnzip.unzip(archive: archivePath, to: content) else {
                fail()
                return EmptyDisposable
            }
            var root = content
            if !FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent("badge.json")), let items = try? FileManager.default.contentsOfDirectory(atPath: root), items.count == 1 {
                root = (root as NSString).appendingPathComponent(items[0])
            }
            let jsonPath = (root as NSString).appendingPathComponent("badge.json")
            guard let json = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)), json.count <= 256 * 1024, var document = try? JSONDecoder().decode(WGBadgeDocument.self, from: json) else {
                fail()
                return EmptyDisposable
            }
            document.layers = Array(document.layers.prefix(WGBadgeDocument.maxLayers))
            document.name = String(document.name.prefix(40))
            var assets: [(String, UIImage)] = []
            for layer in document.layers where layer.kind == .image {
                guard let name = layer.fileName, !name.contains("/"), !name.contains(".."), !assets.contains(where: { $0.0 == name }) else {
                    continue
                }
                let path = ((root as NSString).appendingPathComponent("assets") as NSString).appendingPathComponent(name)
                if let image = WGBadgeImages.decode(url: URL(fileURLWithPath: path)) {
                    assets.append((name, image))
                }
            }
            subscriber.putNext((document, assets))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(wgInterfaceQueue)
    }

    private static func showError(context: AccountContext, from controller: ViewController?, text: String) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }
}

private final class WGBadgeGalleryBox {
    var documents: [WGBadgeDocument] = []
}

private var wgBadgePickerDelegateKey: UInt8 = 0

final class WGBadgeDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL) -> Void

    init(completion: @escaping (URL) -> Void) {
        self.completion = completion
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        self.completion(url)
    }
}

enum WGBadgeImages {
    /// Pictures are kept at most 900 px on the long side: the pill is 279×66 px at 3x.
    static let maxPixelSize = 900

    /// A picture from outside (a `.ggbadge`, a file, a link, the photo library) decoded straight to at
    /// most 900 px — never whole, so a 30000×30000 PNG neither hangs nor kills the app — and refused
    /// past 100 MP. Off the main thread.
    static func decode(_ data: Data) -> UIImage? {
        return WGImageDecoding.thumbnail(data: data, maxPixelSize: WGBadgeImages.maxPixelSize, maxSourcePixels: WGImageDecoding.maxPictureSourcePixels)
    }

    static func decode(url: URL) -> UIImage? {
        return WGImageDecoding.thumbnail(url: url, maxPixelSize: WGBadgeImages.maxPixelSize, maxSourcePixels: WGImageDecoding.maxPictureSourcePixels)
    }
}
