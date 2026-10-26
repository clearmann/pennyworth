@testable import Pennyworth
import AppKit
import XCTest

final class WebSearchSettingsUITests: XCTestCase {
    @MainActor func testAddEditAndSaveCustomSearch() throws {
        _ = NSApplication.shared
        let name = "WebSearchSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("网页搜索")

        let add = try XCTUnwrap(descendants(try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSButton }
            .first { $0.title == "添加自定义搜索" })
        add.performClick(nil)

        let views = descendants(try XCTUnwrap(controller.window?.contentView))
        let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first {
            $0.accessibilityLabel() == "网页搜索列表"
        })
        XCTAssertTrue(table.visibleRect.intersects(table.rect(ofRow: table.selectedRow)))
        let fields = try [
            ("网页搜索关键词", "gh"),
            ("网页搜索显示名称", "GitHub"),
            ("网页搜索 URL 模板", "https://github.com/search?q={query}"),
        ].map { label, value -> NSTextField in
            let field = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == label
            })
            field.stringValue = value
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            return field
        }
        XCTAssertEqual(fields.count, 3)
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        save.performClick(nil)

        let custom = try XCTUnwrap(store.settings.webSearches.first { $0.keyword == "gh" })
        XCTAssertEqual(custom.title, "GitHub")
        XCTAssertEqual(custom.urlTemplate, "https://github.com/search?q={query}")
        XCTAssertTrue(custom.isCustom)
        XCTAssertTrue(custom.isEnabled)
        XCTAssertEqual(store.settings.webSearches.count, WebSearchDefinition.builtIns.count + 1)
        if let output = ProcessInfo.processInfo.environment["PENNYWORTH_SCREENSHOT_DIR"] {
            let destination = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let content = try XCTUnwrap(controller.window?.contentView)
            content.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: destination.appendingPathComponent("web-search.png"))
        }
    }

    @MainActor func testBuiltInSearchCanBeDisabledButNotEditedOrDeleted() throws {
        _ = NSApplication.shared
        let name = "WebSearchSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("网页搜索")
        let views = descendants(try XCTUnwrap(controller.window?.contentView))
        let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first {
            $0.accessibilityLabel() == "网页搜索列表"
        })
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.delegate?.tableViewSelectionDidChange?(Notification(name: NSTableView.selectionDidChangeNotification, object: table))

        let keyword = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == "网页搜索关键词"
        })
        let enabled = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "启用所选网页搜索"
        })
        let remove = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == "删除自定义搜索"
        })
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        XCTAssertFalse(keyword.isEditable)
        XCTAssertFalse(remove.isEnabled)
        XCTAssertEqual(enabled.state, .on)

        enabled.performClick(nil)
        save.performClick(nil)

        XCTAssertFalse(try XCTUnwrap(store.settings.webSearches.first).isEnabled)
    }

    @MainActor func testExistingCustomSearchCanBeEditedAndDeleted() throws {
        _ = NSApplication.shared
        let name = "WebSearchSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let custom = WebSearchDefinition(
            id: "custom.github", keyword: "gh", title: "GitHub",
            urlTemplate: "https://github.com/search?q={query}"
        )
        let store = SettingsStore(defaults: defaults)
        try store.save(LauncherSettings(
            hotKey: .optionSpace, searchDirectories: [], searchEngine: .google,
            rememberUsage: true, webSearches: WebSearchDefinition.builtIns + [custom]
        ))
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("网页搜索")
        let views = descendants(try XCTUnwrap(controller.window?.contentView))
        let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first {
            $0.accessibilityLabel() == "网页搜索列表"
        })
        table.selectRowIndexes(IndexSet(integer: table.numberOfRows - 1), byExtendingSelection: false)
        table.delegate?.tableViewSelectionDidChange?(Notification(name: NSTableView.selectionDidChangeNotification, object: table))
        let title = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == "网页搜索显示名称"
        })
        let remove = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "删除自定义搜索" })
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        XCTAssertTrue(title.isEditable)
        XCTAssertTrue(remove.isEnabled)

        title.stringValue = "GitHub Code"
        title.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: title))
        save.performClick(nil)
        XCTAssertEqual(store.settings.webSearches.last?.title, "GitHub Code")
        remove.performClick(nil)
        save.performClick(nil)

        XCTAssertNil(store.settings.webSearches.first { $0.keyword == "gh" })
        XCTAssertEqual(store.settings.webSearches, WebSearchDefinition.builtIns)
    }

    @MainActor func testAllColumnsFitMinimumWindowWidth() throws {
        _ = NSApplication.shared
        let name = "WebSearchSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) { _ in }
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("网页搜索")
        controller.window?.setContentSize(NSSize(width: 780, height: 580))
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTableView }.first {
            $0.accessibilityLabel() == "网页搜索列表"
        })
        let clip = try XCTUnwrap(table.enclosingScrollView?.contentView)
        clip.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()

        let enabledColumn = table.rect(ofColumn: table.numberOfColumns - 1)
        XCTAssertLessThanOrEqual(enabledColumn.maxX, clip.bounds.width)
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
