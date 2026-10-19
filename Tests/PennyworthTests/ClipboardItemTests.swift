@testable import Pennyworth
import AppKit
import XCTest

final class ClipboardItemTests: XCTestCase {

    // MARK: - Text content display

    func testTextDisplayTitleShowsShortTextInFull() {
        let item = ClipboardItem(content: .text("hello world"), timestamp: Date())
        XCTAssertEqual(item.displayTitle, "hello world")
    }

    func testTextDisplayTitleTruncatesLongText() {
        let longText = String(repeating: "a", count: 100)
        let item = ClipboardItem(content: .text(longText), timestamp: Date())
        XCTAssertEqual(item.displayTitle.count, 61) // 60 chars + "…"
        XCTAssertTrue(item.displayTitle.hasSuffix("…"))
    }

    func testTextDisplayTitleStripsNewlinesForPreview() {
        let item = ClipboardItem(content: .text("line one\nline two"), timestamp: Date())
        XCTAssertFalse(item.displayTitle.contains("\n"))
    }

    func testTextDisplaySubtitleShowsCharacterCount() {
        let item = ClipboardItem(content: .text("hello"), timestamp: Date())
        XCTAssertTrue(item.displaySubtitle.contains("5"))
    }

    // MARK: - Image content display

    func testImageDisplayTitleShowsDimensions() {
        let image = NSImage(size: NSSize(width: 100, height: 200))
        let item = ClipboardItem(content: .image(image, size: NSSize(width: 100, height: 200)), timestamp: Date())
        XCTAssertEqual(item.displayTitle, "Image: 100×200")
    }

    // MARK: - File content display

    func testFileDisplayTitleShowsFileNameOnly() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/report.pdf")
        let item = ClipboardItem(content: .file(url), timestamp: Date())
        XCTAssertEqual(item.displayTitle, "report.pdf")
    }

    func testFileDisplaySubtitleShowsFullPath() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/report.pdf")
        let item = ClipboardItem(content: .file(url), timestamp: Date())
        XCTAssertTrue(item.displaySubtitle.contains("/Users/test"))
    }

    // MARK: - Equatable / Identifiable

    func testTwoItemsWithSameContentHaveDifferentIDs() {
        let item1 = ClipboardItem(content: .text("same"), timestamp: Date())
        let item2 = ClipboardItem(content: .text("same"), timestamp: Date())
        XCTAssertNotEqual(item1.id, item2.id)
    }

    func testEquatableComparesContentAndTimestamp() {
        let date = Date()
        let item1 = ClipboardItem(id: UUID(), content: .text("a"), timestamp: date)
        let item2 = ClipboardItem(id: UUID(), content: .text("a"), timestamp: date)
        // Different IDs → not equal (identity matters)
        XCTAssertNotEqual(item1, item2)
    }
}
