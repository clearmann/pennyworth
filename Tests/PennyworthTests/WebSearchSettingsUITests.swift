@testable import Pennyworth
import AppKit
import XCTest

final class WebSearchSettingsUITests: XCTestCase {
    @MainActor func testAddEditAndDeleteCustomSearchViaSheetAndInlineControls() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "WebSearchSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("网页搜索")

        let content = try XCTUnwrap(controller.window?.contentView)
        let add = try XCTUnwrap(descendants(content)
            .compactMap { $0 as? NSButton }
            .first { $0.title == "添加自定义搜索" })
        add.performClick(nil)

        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let sheetViews = descendants(try XCTUnwrap(sheet.contentView))
        for (label, value) in [
            ("网页搜索关键词", "gh"),
            ("网页搜索显示名称", "GitHub"),
            ("网页搜索 URL 模板", "https://github.com/search?q={query}"),
        ] {
            let field = try XCTUnwrap(sheetViews.compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == label
            })
            field.stringValue = value
        }
        let saveButton = try XCTUnwrap(sheetViews.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        saveButton.performClick(nil)

        let custom = try XCTUnwrap(store.settings.webSearches.first { $0.keyword == "gh" })
        XCTAssertEqual(custom.title, "GitHub")
        XCTAssertEqual(custom.urlTemplate, "https://github.com/search?q={query}")
        XCTAssertTrue(custom.isCustom)
        XCTAssertTrue(custom.isEnabled)
        XCTAssertEqual(store.settings.webSearches.count, WebSearchDefinition.builtIns.count + 1)

        // Edit custom search via row pencil button.
        let editButton = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "编辑 GitHub 网页搜索"
        })
        editButton.performClick(nil)
        let editSheet = try XCTUnwrap(controller.window?.attachedSheet)
        let editViews = descendants(try XCTUnwrap(editSheet.contentView))
        let titleField = try XCTUnwrap(editViews.compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == "网页搜索显示名称"
        })
        titleField.stringValue = "GitHub Code"
        let editSave = try XCTUnwrap(editViews.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        editSave.performClick(nil)
        XCTAssertEqual(store.settings.webSearches.last?.title, "GitHub Code")

        // Delete custom search immediately via row trash button.
        let deleteButton = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "删除 GitHub Code 网页搜索"
        })
        deleteButton.performClick(nil)
        XCTAssertNil(store.settings.webSearches.first { $0.keyword == "gh" })
        XCTAssertEqual(store.settings.webSearches, WebSearchDefinition.builtIns)
    }

    @MainActor func testBuiltInSearchCanBeDisabledButHasNoEditOrDeleteButtons() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "WebSearchSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("网页搜索")

        let content = try XCTUnwrap(controller.window?.contentView)
        let firstBuiltIn = try XCTUnwrap(WebSearchDefinition.builtIns.first)
        let views = descendants(content)
        XCTAssertNil(views.compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "编辑 \(firstBuiltIn.title) 网页搜索"
        })
        XCTAssertNil(views.compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "删除 \(firstBuiltIn.title) 网页搜索"
        })

        let toggle = try XCTUnwrap(views.compactMap { $0 as? NSSwitch }.first {
            $0.accessibilityLabel() == "启用 \(firstBuiltIn.title) 网页搜索"
        })
        XCTAssertEqual(toggle.state, .on)
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        XCTAssertFalse(try XCTUnwrap(store.settings.webSearches.first).isEnabled)
    }

    @MainActor func testWebSearchPageFitsMinimumWindowWidthWithoutOverflow() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "WebSearchSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) { _ in }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("网页搜索")
        controller.window?.setContentSize(NSSize(width: 780, height: 580))

        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let webSearchView = try XCTUnwrap(descendants(content).compactMap { $0 as? WebSearchSettingsView }.first)
        XCTAssertLessThanOrEqual(webSearchView.frame.width, 780 - SettingsStyle.sidebarWidth)
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
