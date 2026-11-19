@testable import Pennyworth
import AppKit
import XCTest

final class MouseScrollSettingsUITests: XCTestCase {
    @MainActor func testMousePageEditsAndSavesScrollSettings() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "MouseScrollSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var requestedPermission = false
        var openedSettings = false
        var refreshedPermission = false

        let controller = SettingsWindowController(
            store: store,
            usage: UsageStore(defaults: defaults),
            mousePermissionProvider: { (.awaitingAccessibilityPermission, false) },
            onRequestMousePermission: { requestedPermission = true },
            onOpenMouseAccessibilitySettings: { openedSettings = true; return true },
            onRefreshMousePermission: { refreshedPermission = true }
        ) {
            try store.save($0)
        }
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage("鼠标")
        XCTAssertEqual(controller.selectedPageTitle, "鼠标")

        let content = try XCTUnwrap(controller.window?.contentView)
        let views = descendants(content)

        let reverseCheckbox = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "反转鼠标滚轮方向"
        })
        let smoothCheckbox = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "启用平滑滚动"
        })
        let speedSlider = try XCTUnwrap(views.compactMap { $0 as? NSSlider }.first {
            $0.accessibilityLabel() == "滚动速度"
        })
        let smoothnessPopup = try XCTUnwrap(views.compactMap { $0 as? NSPopUpButton }.first {
            $0.accessibilityLabel() == "平滑度"
        })

        // Smoothness is disabled when smooth scrolling is off.
        XCTAssertFalse(smoothnessPopup.isEnabled)

        reverseCheckbox.performClick(nil)
        smoothCheckbox.performClick(nil)
        XCTAssertTrue(smoothnessPopup.isEnabled)

        speedSlider.doubleValue = 1.75
        speedSlider.sendAction(speedSlider.action, to: speedSlider.target)

        smoothnessPopup.selectItem(at: 2) // silky
        smoothnessPopup.sendAction(smoothnessPopup.action, to: smoothnessPopup.target)

        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        save.performClick(nil)

        XCTAssertEqual(
            store.settings.mouseScroll,
            MouseScrollSettings(
                reverseScrollDirection: true,
                smoothScrolling: true,
                scrollSpeed: 1.75,
                smoothness: .silky
            )
        )

        // Permission action buttons forward callbacks.
        let requestButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "请求权限" })
        let openButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "打开系统设置" })
        let refreshButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "重新检查" })
        requestButton.performClick(nil)
        openButton.performClick(nil)
        refreshButton.performClick(nil)
        XCTAssertTrue(requestedPermission)
        XCTAssertTrue(openedSettings)
        XCTAssertTrue(refreshedPermission)

        // Reset restores default values in UI.
        let resetButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "恢复默认" })
        resetButton.performClick(nil)
        save.performClick(nil)
        XCTAssertEqual(store.settings.mouseScroll, .defaults)
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
