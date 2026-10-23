import XCTest
@testable import Pennyworth

final class ClipboardHistoryModelTests: XCTestCase {
    @MainActor func testFiltersAndMovesSelectionThroughClipboardHistory() {
        let first = ClipboardItem(content: .text("github issue"), timestamp: Date())
        let second = ClipboardItem(content: .text("meeting notes"), timestamp: Date())
        let model = ClipboardHistoryModel(items: [first, second])

        XCTAssertEqual(model.visibleItems.map(\.id), [first.id, second.id])
        model.updateQuery("issue")
        XCTAssertEqual(model.visibleItems.map(\.id), [first.id])
        XCTAssertEqual(model.selectedItem?.id, first.id)

        model.updateQuery("")
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedItem?.id, second.id)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedItem?.id, second.id)
    }

    @MainActor func testReopeningClearsPreviousQuery() {
        let item = ClipboardItem(content: .text("persistent"), timestamp: Date())
        let model = ClipboardHistoryModel(items: [item])
        model.updateQuery("missing")
        model.updateQuery("")

        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.visibleItems, [item])
    }

    @MainActor func testEmptyHistoryExposesHelpfulMessage() {
        let model = ClipboardHistoryModel(items: [])

        XCTAssertTrue(model.visibleItems.isEmpty)
        XCTAssertEqual(model.message, "暂无剪贴板历史")
    }
}
