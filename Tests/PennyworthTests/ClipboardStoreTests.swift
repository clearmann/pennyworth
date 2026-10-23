@testable import Pennyworth
import XCTest

final class ClipboardStoreTests: XCTestCase {

    private var store: ClipboardStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = ClipboardStore(storageURL: tempDir.appendingPathComponent("clipboard.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
        super.tearDown()
    }

    // MARK: - add()

    func testAddInsertsAtHead() {
        store.add(makeTextItem("first"))
        store.add(makeTextItem("second"))
        XCTAssertEqual(store.items.first?.content, .text("second"))
    }

    func testAddDeduplicatesConsecutiveIdenticalContent() {
        store.add(makeTextItem("dup"))
        store.add(makeTextItem("dup"))
        XCTAssertEqual(store.items.count, 1)
    }

    func testAddAllowsNonConsecutiveDuplicates() {
        store.add(makeTextItem("a"))
        store.add(makeTextItem("b"))
        store.add(makeTextItem("a"))
        XCTAssertEqual(store.items.count, 3)
    }

    func testAddTruncatesToMaxItems() {
        for i in 0..<210 {
            store.add(makeTextItem("item \(i)"))
        }
        XCTAssertEqual(store.items.count, 200)
        // 最旧的第一条应被淘汰
        XCTAssertFalse(store.items.contains { $0.content == .text("item 0") })
        // 最新的应保留
        XCTAssertTrue(store.items.contains { $0.content == .text("item 209") })
    }

    // MARK: - load() / save()

    func testLoadFiltersExpiredItems() {
        let oldDate = Date().addingTimeInterval(-31 * 24 * 3600) // 31 天前
        let freshDate = Date()
        store.add(ClipboardItem(content: .text("old"), timestamp: oldDate))
        store.add(ClipboardItem(content: .text("fresh"), timestamp: freshDate))
        store.save()

        let loaded = ClipboardStore(storageURL: store.storageURL)
        loaded.load()

        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertEqual(loaded.items.first?.content, .text("fresh"))
    }

    func testSaveAndLoadRoundTrip() {
        store.add(makeTextItem("persist me"))
        store.add(makeFileItem(URL(fileURLWithPath: "/tmp/test.txt")))
        store.save()

        let loaded = ClipboardStore(storageURL: store.storageURL)
        loaded.load()

        XCTAssertEqual(loaded.items.count, 2)
        XCTAssertTrue(loaded.items.contains { $0.content == .text("persist me") })
        XCTAssertTrue(loaded.items.contains { $0.content == .file(URL(fileURLWithPath: "/tmp/test.txt")) })
    }

    func testLoadWithMissingFileYieldsEmptyStore() {
        let emptyStore = ClipboardStore(
            storageURL: tempDir.appendingPathComponent("nonexistent.json")
        )
        emptyStore.load()
        XCTAssertTrue(emptyStore.items.isEmpty)
    }

    func testSaveRestrictsHistoryFilePermissions() throws {
        store.add(makeTextItem("private"))
        store.save()
        let attributes = try FileManager.default.attributesOfItem(atPath: store.storageURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }

    // MARK: - clear()

    func testClearEmptiesItems() {
        store.add(makeTextItem("x"))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Helpers

    private func makeTextItem(_ text: String) -> ClipboardItem {
        ClipboardItem(content: .text(text), timestamp: Date())
    }

    private func makeFileItem(_ url: URL) -> ClipboardItem {
        ClipboardItem(content: .file(url), timestamp: Date())
    }
}
