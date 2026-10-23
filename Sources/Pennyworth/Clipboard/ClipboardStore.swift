import Foundation
import os

final class ClipboardStore {
    static let maxItems = 200
    static let maxImageItems = 20
    static let maxImageBytes = 100 * 1024 * 1024
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    let storageURL: URL
    private(set) var items: [ClipboardItem] = []
    private let ioQueue = DispatchQueue(label: "com.clearmann.pennyworth.clipboard-store", qos: .utility)

    init(storageURL: URL = ClipboardStore.defaultStorageURL) {
        self.storageURL = storageURL
        load()
    }

    func add(_ item: ClipboardItem) {
        let withoutConsecutiveDuplicate = items.first?.content == item.content ? Array(items.dropFirst()) : items
        let retained = withoutConsecutiveDuplicate.filter { !isExpired($0, relativeTo: item.timestamp) }
        items = limitedItems(([item] + retained).prefix(Self.maxItems))
        scheduleSave()
    }

    func clear() {
        items = []
        save()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            items = []
            return
        }
        let now = Date()
        items = limitedItems(decoded.filter { !isExpired($0, relativeTo: now) }.prefix(Self.maxItems))
    }

    /// Flushes the latest snapshot to disk. Runtime captures use scheduleSave() so the main thread stays responsive.
    func save() {
        let snapshot = items
        ioQueue.sync { write(snapshot) }
    }

    private func scheduleSave() {
        let snapshot = items
        ioQueue.async { [weak self] in self?.write(snapshot) }
    }

    private func write(_ snapshot: [ClipboardItem]) {
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        } catch {
            Logger(subsystem: "com.clearmann.pennyworth", category: "Clipboard")
                .error("无法保存剪贴板历史：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func limitedItems<S: Sequence>(_ values: S) -> [ClipboardItem] where S.Element == ClipboardItem {
        var imageCount = 0
        var imageBytes = 0
        var result: [ClipboardItem] = []
        result.reserveCapacity(Self.maxItems)
        for item in values {
            if case .image = item.content {
                let bytes = item.storageByteCount
                guard imageCount < Self.maxImageItems,
                      imageBytes + bytes <= Self.maxImageBytes else { continue }
                imageCount += 1
                imageBytes += bytes
            }
            result.append(item)
            if result.count == Self.maxItems { break }
        }
        return result
    }

    private func isExpired(_ item: ClipboardItem, relativeTo date: Date) -> Bool {
        item.timestamp < date.addingTimeInterval(-Self.retention)
    }

    private static var defaultStorageURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport.appendingPathComponent("Pennyworth/clipboard.json")
    }
}
