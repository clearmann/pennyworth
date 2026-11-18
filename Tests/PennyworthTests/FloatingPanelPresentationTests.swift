@testable import Pennyworth
import AppKit
import XCTest

final class FloatingPanelPresentationTests: XCTestCase {
    @MainActor func testLauncherUsesSingleVisualEffectLayerAndUpdatesModeBadge() throws {
        _ = NSApplication.shared
        let name = "FloatingPanelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = LauncherModel(
            settings: SettingsStore(defaults: defaults),
            usage: UsageStore(defaults: defaults),
            executor: TestExecutor()
        )
        let controller = LauncherViewController(model: model)
        var openedSettings = false
        controller.onSettings = { openedSettings = true }
        controller.focusSearchField()

        let effectViews = descendants(controller.view).compactMap { $0 as? NSVisualEffectView }
        XCTAssertEqual(effectViews.count, 1)

        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.selectionHighlightStyle, .none)

        let header = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? SearchHeaderView }.first)
        let headerLabels = descendants(header.badge).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(headerLabels, ["⌘,"])

        header.badge.onTap?()
        XCTAssertTrue(openedSettings)

        model.updateQuery("=23*17")
        let calcLabels = descendants(header.badge).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(calcLabels, [L10n.tr("launcher.badge.calculator")])
        model.endSession()
    }

    @MainActor func testClipboardPanelUsesSingleVisualEffectLayerAndUpdatesTypeBadge() throws {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 64, height: 64))
        let picture = ClipboardItem(content: .image(image, size: image.size), timestamp: Date())
        let text = ClipboardItem(content: .text("hello world"), timestamp: Date())
        let controller = ClipboardHistoryViewController(
            model: ClipboardHistoryModel(items: [picture, text]),
            onRestore: { _ in }
        )
        _ = controller.view

        let effectViews = descendants(controller.view).compactMap { $0 as? NSVisualEffectView }
        XCTAssertEqual(effectViews.count, 1)

        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.selectionHighlightStyle, .none)

        let header = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? SearchHeaderView }.first)
        let imageLabels = descendants(header.badge).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(imageLabels, [L10n.tr("clipboard.badge.image")])

        let searchField = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTextField }.first {
            $0.placeholderString != nil
        })
        let editor = NSTextView()
        _ = controller.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        let textLabels = descendants(header.badge).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(textLabels, [L10n.tr("clipboard.badge.text")])
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
