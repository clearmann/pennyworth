@testable import Pennyworth
import AppKit
import XCTest

final class AppShortcutsSettingsUITests: XCTestCase {
    @MainActor func testAddRecordAndSaveRightCommandAppShortcut() throws {
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
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("应用快捷键")

        let content = try XCTUnwrap(controller.window?.contentView)
        let views = descendants(content)
        let add = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == "添加应用快捷键"
        })
        add.performClick(nil)

        let refreshedViews = descendants(content)
        let appPopup = try XCTUnwrap(refreshedViews.compactMap { $0 as? NSPopUpButton }.first {
            $0.accessibilityLabel() == "目标应用"
        })
        appPopup.selectItem(withTitle: "微信")
        appPopup.sendAction(appPopup.action, to: appPopup.target)

        let save = try XCTUnwrap(refreshedViews.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        save.performClick(nil)
        XCTAssertTrue(store.settings.appShortcuts.isEmpty, "Unrecorded shortcut must not be saved")

        let recorder = try XCTUnwrap(refreshedViews.compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "应用触发热键"
        })
        recorder.beginRecording()
        XCTAssertTrue(recorder.processKey(keyCode: 13, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertTrue(suspensionEvents.contains(true))
        XCTAssertEqual(suspensionEvents.last, false)

        save.performClick(nil)
        let saved = try XCTUnwrap(store.settings.appShortcuts.first)
        XCTAssertEqual(saved.appName, "微信")
        XCTAssertEqual(saved.appPath, "/Applications/WeChat.app")
        XCTAssertEqual(saved.hotKey, .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertTrue(saved.isEnabled)

        let enabledCheckbox = try XCTUnwrap(refreshedViews.compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "启用所选应用快捷键"
        })
        enabledCheckbox.performClick(nil)
        save.performClick(nil)
        XCTAssertEqual(store.settings.appShortcuts.first?.isEnabled, false)

        let removeButton = try XCTUnwrap(refreshedViews.compactMap { $0 as? NSButton }.first {
            $0.title == "删除所选"
        })
        removeButton.performClick(nil)
        save.performClick(nil)
        XCTAssertTrue(store.settings.appShortcuts.isEmpty)

        controller.selectPage("截图")
        let screenshotRecorder = try XCTUnwrap(refreshedViews.compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "截图热键"
        })
        suspensionEvents.removeAll()
        screenshotRecorder.beginRecording()
        XCTAssertEqual(suspensionEvents, [true])
        XCTAssertTrue(screenshotRecorder.processKey(keyCode: 31, modifiers: HotKeyModifiers.rightCommand))
        XCTAssertEqual(suspensionEvents, [true, false])
        save.performClick(nil)
        XCTAssertEqual(store.settings.screenshotHotKey, .custom(keyCode: 31, modifiers: HotKeyModifiers.rightCommand))
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
