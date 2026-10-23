@testable import Pennyworth
import AppKit
import XCTest

final class SettingsNavigationTests: XCTestCase {
    @MainActor func testNavigationPreservesUnsavedSettings() throws {
        _ = NSApplication.shared
        let name = "SettingsNavigation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.showWindow(nil)
        defer { controller.close() }
        let views = descendants(try XCTUnwrap(controller.window?.contentView))
        let hotKey = try XCTUnwrap(views.compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "全局热键"
        })
        hotKey.setBinding(.controlOptionSpace)
        for title in SettingsWindowController.pageTitles {
            controller.selectPage(title)
            XCTAssertEqual(controller.selectedPageTitle, title)
        }
        controller.selectPage("通用")
        XCTAssertEqual(hotKey.binding, .controlOptionSpace)
        XCTAssertEqual(store.settings.hotKey, .optionSpace)
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        save.performClick(nil)
        XCTAssertEqual(store.settings.hotKey, .controlOptionSpace)
        controller.selectPage("不存在")
        XCTAssertEqual(controller.selectedPageTitle, "通用")
    }

    @MainActor func testBookmarkCheckboxesShareOnePreferenceAndPersistImmediately() async throws {
        _ = NSApplication.shared
        let name = "SettingsNavigation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmarkStore = BookmarkStore(fileURL: directory.appendingPathComponent("bookmarks.json"))
        let controller = SettingsWindowController(store: SettingsStore(defaults: defaults),
                                                  usage: UsageStore(defaults: defaults), bookmarks: bookmarkStore) { _ in }
        controller.showWindow(nil)
        defer { controller.close() }
        let buttons = descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSButton }
        let defaultToggle = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == "默认结果中的网页书签" })
        let bookmarkToggle = try XCTUnwrap(buttons.first { $0.title == "在默认搜索结果中显示书签" })
        controller.selectPage("默认结果")
        defaultToggle.performClick(nil)
        XCTAssertFalse(bookmarkStore.preferences.includeInDefaultResults)
        XCTAssertEqual(bookmarkToggle.state, .off)
        controller.selectPage("网页书签")
        bookmarkToggle.performClick(nil)
        XCTAssertTrue(bookmarkStore.preferences.includeInDefaultResults)
        XCTAssertEqual(defaultToggle.state, .on)
        XCTAssertTrue(BookmarkStore(fileURL: directory.appendingPathComponent("bookmarks.json")).preferences.includeInDefaultResults)
        // The synthetic Chrome fixture is opt-in: AppKit's test host cannot safely
        // tear down a window while detached bookmark reads are still running.
        guard ProcessInfo.processInfo.environment["PENNYWORTH_SCREENSHOT_DIR"] != nil else { return }
        if let output = ProcessInfo.processInfo.environment["PENNYWORTH_SCREENSHOT_DIR"] {
            let destination = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let content = try XCTUnwrap(controller.window?.contentView)
            for (title, filename) in [("默认结果", "default-results.png"), ("网页书签", "bookmarks-empty.png")] {
                controller.selectPage(title)
                content.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: destination.appendingPathComponent(filename))
            }
        }
        let chrome = directory.appendingPathComponent("Chrome")
        for profile in ["Default", "Profile 1"] {
            try FileManager.default.createDirectory(at: chrome.appendingPathComponent(profile), withIntermediateDirectories: true)
        }
        let localState: [String: Any] = ["profile": ["info_cache": [
            "Default": ["name": "个人"],
            "Profile 1": ["name": "工作 · 用于验证极长个人资料名称不会超出设置窗口宽度的测试账户"]
        ]]]
        try JSONSerialization.data(withJSONObject: localState).write(to: chrome.appendingPathComponent("Local State"))
        let bookmarkData: [String: Any] = ["roots": ["bookmark_bar": ["type": "folder", "name": "开发", "children": [
            ["type": "url", "id": "1", "name": "GitHub", "url": "https://github.com"],
            ["type": "url", "id": "2", "name": "不支持的地址", "url": "javascript:alert(1)"]
        ]]]]
        try JSONSerialization.data(withJSONObject: bookmarkData).write(to: chrome.appendingPathComponent("Default/Bookmarks"))
        try await bookmarkStore.discoverProfiles(root: chrome)
        let defaultProfileID = try XCTUnwrap(bookmarkStore.profiles.first { $0.name == "个人" }?.id)
        try bookmarkStore.setSelected(true, profileID: defaultProfileID)
        try await bookmarkStore.refreshSelected()
        controller.showWindow(nil)
        controller.selectPage("网页书签")
        XCTAssertEqual(bookmarkStore.profiles.count, 2)
        XCTAssertEqual(bookmarkStore.snapshots.count, 1)
        if let output = ProcessInfo.processInfo.environment["PENNYWORTH_SCREENSHOT_DIR"] {
            let content = try XCTUnwrap(controller.window?.contentView)
            for (size, filename) in [(NSSize(width: 900, height: 640), "bookmarks.png"),
                                     (NSSize(width: 780, height: 580), "bookmarks-minimum.png")] {
                controller.window?.setContentSize(size)
                content.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: output).appendingPathComponent(filename))
            }
        }
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
