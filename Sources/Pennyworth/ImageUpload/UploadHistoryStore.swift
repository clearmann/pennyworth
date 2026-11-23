import Foundation
import os

struct UploadHistoryItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let url: String
    let filename: String
    let hostName: String
    let provider: ImageHostProvider
    let fileSize: Int
    let uploadedAt: Date
    let thumbnailData: Data?

    init(
        id: String = UUID().uuidString,
        url: String,
        filename: String,
        hostName: String,
        provider: ImageHostProvider,
        fileSize: Int,
        uploadedAt: Date = Date(),
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.hostName = hostName
        self.provider = provider
        self.fileSize = fileSize
        self.uploadedAt = uploadedAt
        self.thumbnailData = thumbnailData
    }
}

final class UploadHistoryStore {
    static let maxItems = 100
    static let maxThumbnailBytes = 32 * 1024

    let storageURL: URL
    private(set) var items: [UploadHistoryItem] = []
    private let ioQueue = DispatchQueue(label: "com.clearmann.pennyworth.upload-history", qos: .utility)

    init(storageURL: URL = UploadHistoryStore.defaultStorageURL) {
        self.storageURL = storageURL
        load()
    }

    func add(_ item: UploadHistoryItem) {
        let sanitized = sanitizeThumbnail(item)
        let deduplicated = items.filter { $0.id != sanitized.id }
        items = Array(([sanitized] + deduplicated).prefix(Self.maxItems))
        scheduleSave()
    }

    func remove(id: String) {
        items = items.filter { $0.id != id }
        scheduleSave()
    }

    func clear() {
        items = []
        save()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([UploadHistoryItem].self, from: data) else {
            items = []
            return
        }
        items = Array(decoded.prefix(Self.maxItems))
    }

    func save() {
        let snapshot = items
        ioQueue.sync { write(snapshot) }
    }

    private func scheduleSave() {
        let snapshot = items
        ioQueue.async { [weak self] in self?.write(snapshot) }
    }

    private func sanitizeThumbnail(_ item: UploadHistoryItem) -> UploadHistoryItem {
        guard let thumb = item.thumbnailData, thumb.count > Self.maxThumbnailBytes else {
            return item
        }
        return UploadHistoryItem(
            id: item.id,
            url: item.url,
            filename: item.filename,
            hostName: item.hostName,
            provider: item.provider,
            fileSize: item.fileSize,
            uploadedAt: item.uploadedAt,
            thumbnailData: nil
        )
    }

    private func write(_ snapshot: [UploadHistoryItem]) {
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        } catch {
            Logger(subsystem: "com.clearmann.pennyworth", category: "ImageUpload")
                .error("Failed to save upload history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var defaultStorageURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport.appendingPathComponent("Pennyworth/upload-history.json")
    }
}
