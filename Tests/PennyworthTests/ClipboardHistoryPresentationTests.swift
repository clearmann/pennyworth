@testable import Pennyworth
import AppKit
import XCTest

final class ClipboardHistoryPresentationTests: XCTestCase {
    @MainActor func testSelectedImageShowsThumbnailAndLargePreview() throws {
        _ = NSApplication.shared
        let image = try XCTUnwrap(makeImage())
        let text = ClipboardItem(content: .text("plain text"), timestamp: Date())
        let picture = ClipboardItem(content: .image(image, size: image.size), timestamp: Date())
        let model = ClipboardHistoryModel(items: [picture, text])
        let controller = ClipboardHistoryViewController(model: model) { _ in }
        _ = controller.view

        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        let cell = try XCTUnwrap(controller.tableView(table, viewFor: table.tableColumns.first, row: 0) as? ResultCellView)
        XCTAssertTrue(cell.imageView?.image === image)

        let preview = try XCTUnwrap(imageView(identifier: "clipboard.imagePreview", in: controller.view))
        XCTAssertFalse(preview.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(preview.image === image)
        XCTAssertEqual(preview.imageScaling, .scaleProportionallyUpOrDown)
    }

    @MainActor func testPreviewFollowsKeyboardSelectionAndHidesForText() throws {
        _ = NSApplication.shared
        let image = try XCTUnwrap(makeImage())
        let picture = ClipboardItem(content: .image(image, size: image.size), timestamp: Date())
        let text = ClipboardItem(content: .text("plain text"), timestamp: Date())
        let controller = ClipboardHistoryViewController(model: ClipboardHistoryModel(items: [picture, text])) { _ in }
        _ = controller.view
        let searchField = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTextField }.first {
            $0.placeholderString == "搜索剪贴板历史…"
        })
        let preview = try XCTUnwrap(imageView(identifier: "clipboard.imagePreview", in: controller.view))
        let editor = NSTextView()

        XCTAssertTrue(controller.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(preview.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(controller.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertFalse(preview.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(preview.image === image)
    }

    @MainActor private func makeImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }

    @MainActor private func imageView(identifier: String, in view: NSView) -> NSImageView? {
        descendants(view).compactMap { $0 as? NSImageView }.first { $0.identifier?.rawValue == identifier }
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
