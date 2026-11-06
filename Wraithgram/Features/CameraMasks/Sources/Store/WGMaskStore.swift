import Foundation
import UIKit
import SwiftSignalKit
import WGCore

/// One own mask as the lists show it (read from disk once, kept in memory).
struct WGMaskStoreEntry: Equatable {
    let id: String
    let manifest: WGMaskManifest
    let modified: Date
}

enum WGMaskStoreError: Error {
    case notFound
    case write
    case read
    case package
    case version(Int)
    case emptyName
    case asset
}

/// The user's own masks: `Application Support/wraithgram/masks/user/<id>/` with `manifest.json`,
/// `assets/` and `preview.jpg`. Own masks are user data, so they live in Application Support (not
/// Documents, not Caches). Disk work runs on the store's queue; the lists read the in-memory
/// `entries` signal, so no screen re-reads the disk on every state change.
final class WGMaskStore {
    static let shared = WGMaskStore()

    static let packageFormat = "ggmask"
    static let packageVersion = 1
    static let packageExtension = "ggmask"

    private let queue = Queue(name: "org.wraithgram.masks.store")
    private let entriesPromise = Promise<[WGMaskStoreEntry]>()
    private var entriesValue: [WGMaskStoreEntry] = []
    private var didLoad = false
    private let thumbnailLock = NSLock()
    private var thumbnails: [String: UIImage] = [:]

    /// Bumped on every change (the engine drops the prepared copy of a changed mask).
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    private var revisionValue = 0

    var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("wraithgram/masks/user", isDirectory: true)
    }

    func directory(id: String) -> URL {
        return self.root.appendingPathComponent(WGMaskStore.safeComponent(id), isDirectory: true)
    }

    func assetsDirectory(id: String) -> URL {
        return self.directory(id: id).appendingPathComponent("assets", isDirectory: true)
    }

    /// Path components from a manifest or a package never escape their directory.
    static func safeComponent(_ name: String) -> String {
        var result = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_").replacingOccurrences(of: "..", with: "_")
        if result.isEmpty || result == "." {
            result = "_"
        }
        return result
    }

    static func makeId() -> String {
        return "user." + UUID().uuidString.lowercased()
    }

    // MARK: Lists

    /// Own masks, newest first. Loads from disk once.
    var entries: Signal<[WGMaskStoreEntry], NoError> {
        self.queue.async {
            if !self.didLoad {
                self.reloadFromDisk()
            }
        }
        return self.entriesPromise.get()
    }

    var currentEntries: [WGMaskStoreEntry] {
        return self.queue.isCurrent() ? self.entriesValue : self.entriesSnapshot()
    }

    private let snapshotLock = NSLock()
    private var snapshot: [WGMaskStoreEntry] = []

    private func entriesSnapshot() -> [WGMaskStoreEntry] {
        self.snapshotLock.lock()
        defer {
            self.snapshotLock.unlock()
        }
        return self.snapshot
    }

    private func publish(_ entries: [WGMaskStoreEntry]) {
        self.entriesValue = entries.sorted(by: { $0.modified > $1.modified })
        self.snapshotLock.lock()
        self.snapshot = self.entriesValue
        self.snapshotLock.unlock()
        self.entriesPromise.set(.single(self.entriesValue))
        self.revisionValue += 1
        self.revision.set(self.revisionValue)
    }

    private func reloadFromDisk() {
        self.didLoad = true
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
        var result: [WGMaskStoreEntry] = []
        let urls = (try? fileManager.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in urls {
            let manifestUrl = url.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestUrl), let manifest = try? JSONDecoder().decode(WGMaskManifest.self, from: data) else {
                continue
            }
            let modified = ((try? fileManager.attributesOfItem(atPath: manifestUrl.path))?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0.0)
            result.append(WGMaskStoreEntry(id: manifest.id, manifest: manifest, modified: modified))
        }
        self.publish(result)
    }

    // MARK: Changes (all on the store queue, completion on main)

    private func write(_ manifest: WGMaskManifest) -> Bool {
        let directory = self.directory(id: manifest.id)
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("assets", isDirectory: true), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(manifest) else {
            return false
        }
        do {
            try data.write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic])
        } catch {
            return false
        }
        var entries = self.entriesValue.filter { $0.id != manifest.id }
        entries.append(WGMaskStoreEntry(id: manifest.id, manifest: manifest, modified: Date()))
        self.publish(entries)
        return true
    }

    func create(name: String, completion: @escaping (Result<String, WGMaskStoreError>) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(.emptyName))
            return
        }
        let languageCode = WGLocalization.shared.languageCode
        self.queue.async {
            if !self.didLoad {
                self.reloadFromDisk()
            }
            let id = WGMaskStore.makeId()
            // Not a literal: with English as the language both keys are "en", and a dictionary
            // literal with a repeated key traps (crash of build 199 on «Создать маску»).
            var names: [String: String] = ["en": trimmed]
            names[languageCode] = trimmed
            let manifest = WGMaskManifest(id: id, name: names, effects: [])
            let success = self.write(manifest)
            DispatchQueue.main.async {
                completion(success ? .success(id) : .failure(.write))
            }
        }
    }

    /// Saves a manifest (the studio calls it when a gesture ends or the screen closes).
    func save(_ manifest: WGMaskManifest, completion: ((Bool) -> Void)? = nil) {
        self.queue.async {
            if !self.didLoad {
                self.reloadFromDisk()
            }
            let success = self.write(manifest)
            self.removeUnreferencedAssets(manifest)
            if let completion {
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }

    func manifest(id: String) -> WGMaskManifest? {
        return self.currentEntries.first(where: { $0.id == id })?.manifest
    }

    /// Reads a manifest from disk (the engine's preparation; not the frame path).
    func loadManifest(id: String) -> WGMaskManifest? {
        if let cached = self.manifest(id: id) {
            return cached
        }
        let url = self.directory(id: id).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(WGMaskManifest.self, from: data)
    }

    func rename(id: String, name: String, completion: @escaping (Bool) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageCode = WGLocalization.shared.languageCode
        self.queue.async {
            guard !trimmed.isEmpty, var manifest = self.entriesValue.first(where: { $0.id == id })?.manifest else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            manifest.name[languageCode] = trimmed
            manifest.name["en"] = trimmed
            let success = self.write(manifest)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    /// A copy with its assets and preview frame, named «<name> 2».
    func duplicate(id: String, completion: @escaping (String?) -> Void) {
        self.queue.async {
            guard var manifest = self.entriesValue.first(where: { $0.id == id })?.manifest else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let newId = WGMaskStore.makeId()
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: self.directory(id: newId), withIntermediateDirectories: true)
            try? fileManager.copyItem(at: self.assetsDirectory(id: id), to: self.assetsDirectory(id: newId))
            try? fileManager.copyItem(at: self.directory(id: id).appendingPathComponent("preview.jpg"), to: self.directory(id: newId).appendingPathComponent("preview.jpg"))
            manifest.id = newId
            for (key, value) in manifest.name {
                manifest.name[key] = value + " 2"
            }
            let success = self.write(manifest)
            DispatchQueue.main.async {
                completion(success ? newId : nil)
            }
        }
    }

    func delete(id: String, completion: (() -> Void)? = nil) {
        self.queue.async {
            try? FileManager.default.removeItem(at: self.directory(id: id))
            self.publish(self.entriesValue.filter { $0.id != id })
            self.thumbnailLock.lock()
            self.thumbnails[id] = nil
            self.thumbnailLock.unlock()
            if let completion {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    /// Stores an image as a mask asset (`img_<12 hex>.png`), downscaled to 1024 px.
    func importImage(_ image: UIImage, maskId: String, completion: @escaping (String?) -> Void) {
        self.queue.async {
            let scaled = WGMaskStore.downscaled(image, maxSide: 1024.0)
            guard let data = scaled.pngData() else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let name = "img_" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12)) + ".png"
            let directory = self.assetsDirectory(id: maskId)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                try data.write(to: directory.appendingPathComponent(name), options: [.atomic])
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            DispatchQueue.main.async {
                completion(name)
            }
        }
    }

    private func removeUnreferencedAssets(_ manifest: WGMaskManifest) {
        let referenced = manifest.referencedAssets
        let directory = self.assetsDirectory(id: manifest.id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1.0, maxSide / max(size.width, size.height, 1.0))
        let target = CGSize(width: floor(size.width * factor), height: floor(size.height * factor))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: Preview frames

    func thumbnail(id: String) -> UIImage? {
        self.thumbnailLock.lock()
        if let image = self.thumbnails[id] {
            self.thumbnailLock.unlock()
            return image
        }
        self.thumbnailLock.unlock()
        guard let image = UIImage(contentsOfFile: self.directory(id: id).appendingPathComponent("preview.jpg").path) else {
            return nil
        }
        self.thumbnailLock.lock()
        self.thumbnails[id] = image
        self.thumbnailLock.unlock()
        return image
    }

    /// A 200×200 centre crop of a real masked frame.
    func setThumbnail(id: String, image: UIImage) {
        self.queue.async {
            let side = min(image.size.width, image.size.height)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 200.0, height: 200.0), format: format).image { _ in
                let factor = 200.0 / max(1.0, side)
                let drawSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                image.draw(in: CGRect(x: (200.0 - drawSize.width) / 2.0, y: (200.0 - drawSize.height) / 2.0, width: drawSize.width, height: drawSize.height))
            }
            if let data = thumbnail.jpegData(compressionQuality: 0.8) {
                try? data.write(to: self.directory(id: id).appendingPathComponent("preview.jpg"), options: [.atomic])
            }
            self.thumbnailLock.lock()
            self.thumbnails[id] = thumbnail
            self.thumbnailLock.unlock()
            self.publish(self.entriesValue)
        }
    }

    // MARK: Size

    func diskSize(completion: @escaping (Int64) -> Void) {
        self.queue.async {
            let size = WGMaskStore.directorySize(self.root)
            DispatchQueue.main.async {
                completion(size)
            }
        }
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileUrl as URL in enumerator {
            total += Int64((try? fileUrl.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: .ggmask packages

    private struct Package: Codable {
        let format: String
        let version: Int
        let manifest: WGMaskManifest
        let assets: [String: String]?
    }

    /// Writes `<name>.ggmask` into a temporary directory for the share sheet.
    func export(id: String, completion: @escaping (URL?) -> Void) {
        self.queue.async {
            guard let manifest = self.entriesValue.first(where: { $0.id == id })?.manifest else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            var assets: [String: String] = [:]
            for name in manifest.referencedAssets {
                if let data = try? Data(contentsOf: self.assetsDirectory(id: id).appendingPathComponent(WGMaskStore.safeComponent(name))) {
                    assets[name] = data.base64EncodedString()
                }
            }
            let package = Package(format: WGMaskStore.packageFormat, version: WGMaskStore.packageVersion, manifest: manifest, assets: assets)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wg-mask-export", isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var fileName = manifest.displayName(languageCode: WGLocalization.shared.languageCode)
            for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"] {
                fileName = fileName.replacingOccurrences(of: character, with: "_")
            }
            fileName = String(fileName.trimmingCharacters(in: .whitespaces).prefix(60))
            if fileName.isEmpty {
                fileName = "mask"
            }
            let url = directory.appendingPathComponent(fileName).appendingPathExtension(WGMaskStore.packageExtension)
            guard let data = try? encoder.encode(package), (try? data.write(to: url, options: [.atomic])) != nil else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            DispatchQueue.main.async {
                completion(url)
            }
        }
    }

    /// Imports a `.ggmask` (always under a new id).
    func importPackage(at url: URL, completion: @escaping (Result<String, WGMaskStoreError>) -> Void) {
        self.queue.async {
            let result = self.importPackageSync(url)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func importPackageSync(_ url: URL) -> Result<String, WGMaskStoreError> {
        if !self.didLoad {
            self.reloadFromDisk()
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.read)
        }
        guard let package = try? JSONDecoder().decode(Package.self, from: data), package.format == WGMaskStore.packageFormat else {
            return .failure(.package)
        }
        guard package.version >= 1 && package.version <= WGMaskStore.packageVersion else {
            return .failure(.version(package.version))
        }
        var manifest = package.manifest
        manifest.id = WGMaskStore.makeId()
        let directory = self.assetsDirectory(id: manifest.id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, base64) in package.assets ?? [:] {
            guard manifest.referencedAssets.contains(name), let assetData = Data(base64Encoded: base64) else {
                continue
            }
            try? assetData.write(to: directory.appendingPathComponent(WGMaskStore.safeComponent(name)), options: [.atomic])
        }
        return self.write(manifest) ? .success(manifest.id) : .failure(.write)
    }

    // MARK: Migration

    /// Launch: a background existence check; the store is touched only when there is something
    /// of the old app to move.
    static func migrateLegacyMasksIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let hasMasks = FileManager.default.fileExists(atPath: documents.appendingPathComponent("usermasks", isDirectory: true).path)
            let hasCatalog = FileManager.default.fileExists(atPath: documents.appendingPathComponent("masks", isDirectory: true).path)
            if hasMasks || hasCatalog {
                WGMaskStore.shared.migrateLegacyMasks()
            }
        }
    }

    /// Moves the old app's own masks (`Documents/usermasks/<id>/`) here, once.
    func migrateLegacyMasks() {
        self.queue.async {
            let fileManager = FileManager.default
            guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            // The old catalog cache lived in Documents (backed up to iCloud): it is just dropped.
            try? fileManager.removeItem(at: documents.appendingPathComponent("masks", isDirectory: true))
            let legacy = documents.appendingPathComponent("usermasks", isDirectory: true)
            guard let urls = try? fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return
            }
            try? fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
            var keptAny = false
            for url in urls {
                let target = self.root.appendingPathComponent(WGMaskStore.safeComponent(url.lastPathComponent), isDirectory: true)
                // Already here (an earlier, interrupted move): the old copy is a duplicate.
                if fileManager.fileExists(atPath: target.path) {
                    continue
                }
                if (try? fileManager.moveItem(at: url, to: target)) == nil {
                    keptAny = true
                }
            }
            // A mask that could not be moved stays where it was (and is retried next launch).
            if !keptAny {
                try? fileManager.removeItem(at: legacy)
            }
            self.reloadFromDisk()
        }
    }
}
