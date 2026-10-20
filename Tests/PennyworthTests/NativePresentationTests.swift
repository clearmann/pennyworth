@testable import Pennyworth
import AppKit
import XCTest

final class NativePresentationTests: XCTestCase {
    @MainActor func testSearchViewPresentsResultsAndKeyboardActions() throws {
        _ = NSApplication.shared
        let name = "PresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = LauncherModel(settings: SettingsStore(defaults: defaults), usage: UsageStore(defaults: defaults), executor: TestExecutor())
        let controller = LauncherViewController(model: model)
        let panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420), styleMask: [], backing: .buffered, defer: false)
        panel.contentViewController = controller
        defer { panel.orderOut(nil) }
        controller.focusSearchField()
        model.updateQuery("=23*17")
        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(controller.tableView(table, viewFor: table.tableColumns.first, row: 0) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, "391")
        let field = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTextField }.first { $0.placeholderString != nil })
        field.stringValue = "bing notes"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(model.snapshot.results.first?.title.contains("Bing") == true)
        let editor = NSTextView()
        XCTAssertTrue(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertFalse(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        var dismissed = false
        controller.onDismiss = { dismissed = true }
        XCTAssertTrue(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertTrue(dismissed)
        model.setApplications([AppItem(name: "Test App", url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))])
        model.updateQuery("Test")
        XCTAssertNotNil(controller.tableView(table, viewFor: table.tableColumns.first, row: 0)?.subviews.first)
        controller.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        XCTAssertTrue(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        model.endSession()
        model.beginSession()
        model.updateQuery("=1/0")
        XCTAssertEqual(table.numberOfRows, 0)
        XCTAssertTrue(panel.canBecomeKey)
        model.endSession()
    }

    @MainActor func testSettingsWindowSavesAndSurfacesErrorsWithoutRealPreferences() throws {
        _ = NSApplication.shared
        let name = "PresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        try store.save(LauncherSettings(hotKey: .controlOptionSpace, searchDirectories: ["/tmp"], searchEngine: .bing, rememberUsage: false))
        let usage = UsageStore(defaults: defaults)
        var shouldFail = false
        let controller = SettingsWindowController(store: store, usage: usage) { value in
            if shouldFail { throw SettingsError.invalidDirectories }
            try store.save(value)
        }
        controller.showWindow(nil)
        defer { controller.close() }
        let views = descendants(try XCTUnwrap(controller.window?.contentView))
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        save.performClick(nil)
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "设置已保存。" })
        let remove = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "移除所选" })
        remove.performClick(nil)
        save.performClick(nil)
        XCTAssertEqual(store.settings.searchDirectories, [])
        remove.performClick(nil)
        shouldFail = true
        save.performClick(nil)
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("绝对目录") })
        let clear = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "清除使用记录" })
        clear.performClick(nil)
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("已清除") })
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
