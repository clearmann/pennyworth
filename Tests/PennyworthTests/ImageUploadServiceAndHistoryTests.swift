@testable import Pennyworth
import AppKit
import XCTest

private final class MockHTTPTransport: HTTPTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    private let handler: (URLRequest) throws -> (Data, Int)

    init(handler: @escaping (URLRequest) throws -> (Data, Int)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let (data, status) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }
}

final class ImageUploadServiceAndHistoryTests: XCTestCase {
    func testEndToEndUploadServiceBatchAndErrorCases() async throws {
        let host = ImageHostConfig(
            id: "r2-1",
            name: "My R2",
            provider: .s3,
            bucket: "images",
            region: "auto",
            endpoint: "https://r2.example.com",
            accessKey: "AK",
            domain: "https://cdn.example.com",
            saveKeyPath: "p/{filename}{.suffix}",
            usePathStyle: true
        )
        let secrets = InMemorySecretStore(initial: ["r2-1": "SK"])
        let transport = MockHTTPTransport { _ in (Data(), 200) }
        let service = ImageUploadService(
            transport: transport,
            secretStore: secrets,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            randomProvider: { "abc123" }
        )

        let settings = ImageUploadSettings(
            hosts: [host],
            selectedHostID: host.id,
            outputFormat: .markdown,
            compressFactor: 100,
            encodeURL: true
        )

        let inputs = [
            RawUploadInput(data: Data("one".utf8), filenameWithoutExtension: "first", fileExtension: "txt", mimeType: "text/plain"),
            RawUploadInput(data: Data("two".utf8), filenameWithoutExtension: "second file", fileExtension: "txt", mimeType: "text/plain"),
        ]
        let results = try await service.upload(inputs: inputs, settings: settings)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(results[0].url, "https://cdn.example.com/p/first.txt")
        XCTAssertEqual(results[0].formattedText, "![first.txt](https://cdn.example.com/p/first.txt)")
        XCTAssertEqual(results[1].url, "https://cdn.example.com/p/second%20file.txt")

        // No host configured
        do {
            _ = try await service.upload(inputs: inputs, settings: .defaults)
            XCTFail("Expected noHostConfigured")
        } catch let error as ImageUploadError {
            XCTAssertEqual(error, .noHostConfigured)
        }

        // Missing secret key
        try secrets.deleteSecret(for: host.id)
        do {
            _ = try await service.upload(inputs: inputs, settings: settings)
            XCTFail("Expected missingSecretKey")
        } catch let error as ImageUploadError {
            XCTAssertEqual(error, .missingSecretKey(hostName: "My R2"))
        }
    }

    func testUploadInputLoaderFilesAndPasteboard() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("UploadInputLoader.\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("note.txt")
        try Data("hello file".utf8).write(to: fileURL)

        let loaded = try UploadInputLoader.loadFromFileURLs([fileURL])
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].filenameWithoutExtension, "note")
        XCTAssertEqual(loaded[0].fileExtension, "txt")
        XCTAssertEqual(loaded[0].mimeType, "text/plain")

        XCTAssertThrowsError(try UploadInputLoader.loadSingleFile(tempDir)) { error in
            XCTAssertEqual(error as? ImageUploadError, .directoryNotSupported(tempDir.lastPathComponent))
        }

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        // Empty pasteboard fails cleanly
        XCTAssertThrowsError(try UploadInputLoader.loadFromPasteboard(pb)) { error in
            XCTAssertEqual(error as? ImageUploadError, .clipboardEmpty)
        }

        // GIF pasteboard data preserves gif extension
        pb.clearContents()
        let gifBytes = Data("GIF89a\u{01}\u{00}\u{01}\u{00};".utf8)
        pb.setData(gifBytes, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        let gifLoaded = try UploadInputLoader.loadFromPasteboard(pb, date: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(gifLoaded.count, 1)
        XCTAssertEqual(gifLoaded[0].fileExtension, "gif")
        XCTAssertEqual(gifLoaded[0].mimeType, "image/gif")
        XCTAssertEqual(gifLoaded[0].data, gifBytes)

        // File URL on pasteboard loads file bytes
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
        let fileFromPB = try UploadInputLoader.loadFromPasteboard(pb)
        XCTAssertEqual(fileFromPB.count, 1)
        XCTAssertEqual(fileFromPB[0].data, Data("hello file".utf8))
    }

    func testUploadHistoryStorePersistenceLimitAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("UploadHistory.\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("upload-history.json")
        let store = UploadHistoryStore(storageURL: file)
        for idx in 0..<(UploadHistoryStore.maxItems + 10) {
            store.add(UploadHistoryItem(
                id: "item-\(idx)",
                url: "https://cdn.example.com/\(idx).png",
                filename: "\(idx).png",
                hostName: "R2",
                provider: .s3,
                fileSize: 128,
                thumbnailData: idx == 0 ? Data(repeating: 1, count: UploadHistoryStore.maxThumbnailBytes + 100) : Data([1, 2, 3])
            ))
        }
        store.save()

        XCTAssertEqual(store.items.count, UploadHistoryStore.maxItems)
        XCTAssertEqual(store.items.first?.id, "item-\(UploadHistoryStore.maxItems + 9)")

        let reloaded = UploadHistoryStore(storageURL: file)
        XCTAssertEqual(reloaded.items.count, UploadHistoryStore.maxItems)
        XCTAssertEqual(reloaded.items.first?.url, "https://cdn.example.com/\(UploadHistoryStore.maxItems + 9).png")

        reloaded.remove(id: "item-\(UploadHistoryStore.maxItems + 9)")
        reloaded.save()
        XCTAssertEqual(UploadHistoryStore(storageURL: file).items.count, UploadHistoryStore.maxItems - 1)

        reloaded.clear()
        XCTAssertTrue(UploadHistoryStore(storageURL: file).items.isEmpty)
    }

    @MainActor func testImageUploadControllerWritesPasteboardHistoryAndFeedback() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("UploadController.\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let host = ImageHostConfig(
            id: "oss-1",
            name: "Aliyun",
            provider: .aliyunOSS,
            bucket: "my-blog",
            region: "oss-cn-hangzhou",
            accessKey: "LTAI",
            domain: "https://img.blog.dev",
            saveKeyPath: "{filename}{.suffix}"
        )
        let settings = ImageUploadSettings(hosts: [host], selectedHostID: host.id, outputFormat: .markdown)
        let secrets = InMemorySecretStore(initial: ["oss-1": "SECRET"])
        let transport = MockHTTPTransport { _ in (Data(), 200) }
        let historyStore = UploadHistoryStore(storageURL: tempDir.appendingPathComponent("history.json"))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var feedbacks: [(String, String?, UploadStatusToast.Style)] = []
        var states: [ImageUploadController.VisualState] = []

        let controller = ImageUploadController(
            settingsProvider: { settings },
            service: ImageUploadService(transport: transport, secretStore: secrets),
            historyStore: historyStore,
            pasteboard: pasteboard,
            onFeedback: { title, detail, style in feedbacks.append((title, detail, style)) }
        )
        controller.onStateChanged = { states.append($0) }

        let input = RawUploadInput(data: Data("img".utf8), filenameWithoutExtension: "shot", fileExtension: "png", mimeType: "image/png")
        let results = await controller.uploadInputsForTesting([input])

        XCTAssertEqual(results?.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "![shot.png](https://img.blog.dev/shot.png)")
        XCTAssertEqual(historyStore.items.count, 1)
        XCTAssertEqual(feedbacks.last?.2, .success)
        XCTAssertTrue(states.contains(.uploading(count: 1)))
        XCTAssertEqual(controller.visualState, .succeeded)

        // Copy history item with a different format
        controller.copyHistoryItem(historyStore.items[0], format: .html)
        XCTAssertEqual(pasteboard.string(forType: .string), "<img src=\"https://img.blog.dev/shot.png\" alt=\"shot.png\"/>")
    }
}
