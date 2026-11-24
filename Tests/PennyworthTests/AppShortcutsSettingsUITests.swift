@testable import Pennyworth
import AppKit
import XCTest

final class AppShortcutsSettingsUITests: XCTestCase {
    @MainActor func testAddRecordInlineEditToggleAndDeleteRightCommandAppShortcut() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "AppShortcutsSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let apps = [
            AppItem(name: "Google Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app")),
            AppItem(name: "微信", url: URL(fileURLWithPath: "/Applications/WeChat.app")),
        ]
        var suspensionEvents: [Bool] = []
        let controller = SettingsWindowController(
            store: store,
            usage: UsageStore(defaults: defaults),
            applicationsProvider: { apps },
            setHotKeySuspended: { suspensionEvents.append($0) }
        ) {
            try store.save($0)
        }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("应用快捷键")

        let content = try XCTUnwrap(controller.window?.contentView)
        let views = descendants(content)
        let add = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == "添加应用快捷键"
        })
        add.performClick(nil)

        // Sheet opens with searchable app list + hotkey recorder.
        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let sheetViews = descendants(try XCTUnwrap(sheet.contentView))
        let searchField = try XCTUnwrap(sheetViews.compactMap { $0 as? NSSearchField }.first)
        searchField.stringValue = "微信"
        searchField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: searchField))

        // Attempting to confirm without recording a shortcut keeps the sheet open and does not save.
        let confirm = try XCTUnwrap(sheetViews.compactMap { $0 as? NSButton }.first { $0.title == "添加" })
        confirm.performClick(nil)
        XCTAssertTrue(store.settings.appShortcuts.isEmpty)

        // Record Right Command + W inside the sheet and confirm.
        let recorder = try XCTUnwrap(sheetViews.compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "应用触发热键"
        })
        recorder.beginRecording()
        XCTAssertTrue(recorder.processKey(keyCode: 13, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertTrue(suspensionEvents.contains(true))
        XCTAssertEqual(suspensionEvents.last, false)

        confirm.performClick(nil)
        let saved = try XCTUnwrap(store.settings.appShortcuts.first)
        XCTAssertEqual(saved.appName, "微信")
        XCTAssertEqual(saved.appPath, "/Applications/WeChat.app")
        XCTAssertEqual(saved.hotKey, .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertTrue(saved.isEnabled)

        // Inline hotkey re-recording updates immediately.
        let updatedViews = descendants(content)
        let inlineRecorder = try XCTUnwrap(updatedViews.compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "微信 触发热键"
        })
        inlineRecorder.beginRecording()
        XCTAssertTrue(inlineRecorder.processKey(keyCode: 8, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertEqual(store.settings.appShortcuts.first?.hotKey, .custom(keyCode: 8, modifiers: HotKeyModifiers.rightCommand))

        // Inline NSSwitch toggles immediately.
        let toggle = try XCTUnwrap(descendants(content).compactMap { $0 as? NSSwitch }.first {
            $0.accessibilityLabel() == "启用 微信 快捷键"
        })
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        XCTAssertEqual(store.settings.appShortcuts.first?.isEnabled, false)

        // Inline delete button removes immediately.
        let deleteButton = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "删除 微信 快捷键"
        })
        deleteButton.performClick(nil)
        XCTAssertTrue(store.settings.appShortcuts.isEmpty)

        // Screenshot hotkey records and saves immediately on the Screenshots page.
        controller.selectPage("截图")
        let screenshotRecorder = try XCTUnwrap(descendants(content).compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "截图热键"
        })
        suspensionEvents.removeAll()
        screenshotRecorder.beginRecording()
        XCTAssertEqual(suspensionEvents, [true])
        XCTAssertTrue(screenshotRecorder.processKey(keyCode: 31, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertEqual(suspensionEvents, [true, false])
        XCTAssertEqual(store.settings.screenshotHotKey, .custom(keyCode: 31, modifiers: HotKeyModifiers.rightCommand))
    }

    @MainActor func testDuplicateShortcutShowsInlineErrorAndInlineConflictRollsBack() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "AppShortcutsConflict.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let wechatShortcut = AppShortcut(
            id: "app.wechat",
            bundleIdentifier: "com.tencent.xinWeChat",
            appPath: "/Applications/WeChat.app",
            appName: "微信",
            hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand),
            isEnabled: true
        )
        let chromeShortcut = AppShortcut(
            id: "app.chrome",
            bundleIdentifier: "com.google.Chrome",
            appPath: "/Applications/Google Chrome.app",
            appName: "Google Chrome",
            hotKey: .custom(keyCode: 8, modifiers: HotKeyModifiers.rightCommand),
            isEnabled: true
        )
        try store.save(LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            appShortcuts: [wechatShortcut, chromeShortcut]
        ))

        let apps = [
            AppItem(name: "微信", url: URL(fileURLWithPath: "/Applications/WeChat.app")),
            AppItem(name: "Google Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app")),
            AppItem(name: "Visual Studio Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")),
        ]
        let controller = SettingsWindowController(
            store: store,
            usage: UsageStore(defaults: defaults),
            applicationsProvider: { apps }
        ) {
            try store.save($0)
        }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("应用快捷键")

        let content = try XCTUnwrap(controller.window?.contentView)

        // 1. Adding a new shortcut with an already-used hotkey fails inline in the sheet.
        let add = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }.first {
            $0.title == "添加应用快捷键"
        })
        add.performClick(nil)
        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let sheetViews = descendants(try XCTUnwrap(sheet.contentView))
        let sheetRecorder = try XCTUnwrap(sheetViews.compactMap { $0 as? HotKeyRecorderView }.first)
        sheetRecorder.beginRecording()
        XCTAssertTrue(sheetRecorder.processKey(keyCode: 13, modifiers: HotKeyModifiers.rightCommand))
        let confirm = try XCTUnwrap(sheetViews.compactMap { $0 as? NSButton }.first { $0.title == "添加" })
        confirm.performClick(nil)
        XCTAssertEqual(store.settings.appShortcuts.count, 2)
        XCTAssertNotNil(controller.window?.attachedSheet)
        let cancel = try XCTUnwrap(sheetViews.compactMap { $0 as? NSButton }.first { $0.title == "取消" })
        cancel.performClick(nil)

        // 2. Re-recording Chrome's inline hotkey to conflict with WeChat's reverts Chrome's pill and surfaces banner error.
        let chromeRecorder = try XCTUnwrap(descendants(content).compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "Google Chrome 触发热键"
        })
        chromeRecorder.beginRecording()
        XCTAssertTrue(chromeRecorder.processKey(keyCode: 13, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertEqual(chromeRecorder.binding, chromeShortcut.hotKey)
        XCTAssertEqual(store.settings.appShortcuts[1].hotKey, chromeShortcut.hotKey)
        XCTAssertTrue(descendants(content).compactMap { $0 as? NSTextField }.contains {
            $0.stringValue.contains("已被其他功能或应用占用")
        })
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
