@testable import Pennyworth
import AppKit
import XCTest

final class SettingsNavigationTests: XCTestCase {
    @MainActor func testNavigationAndInstantApplyAcrossPages() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "SettingsNavigation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }

        let views = descendants(try XCTUnwrap(controller.window?.contentView))
        let hotKey = try XCTUnwrap(views.compactMap { $0 as? HotKeyRecorderView }.first {
            $0.accessibilityLabel() == "全局热键"
        })
        hotKey.beginRecording()
        XCTAssertTrue(hotKey.processKey(
            keyCode: HotKeyPreset.controlOptionSpace.keyCode,
            modifiers: HotKeyPreset.controlOptionSpace.modifiers
        ))
        // Instant apply persists immediately without a global Save button.
        XCTAssertEqual(store.settings.hotKey, .custom(
            keyCode: HotKeyPreset.controlOptionSpace.keyCode,
            modifiers: HotKeyPreset.controlOptionSpace.modifiers
        ))

        for title in SettingsWindowController.pageTitles {
            controller.selectPage(title)
            XCTAssertEqual(controller.selectedPageTitle, title)
        }
        controller.selectPage("通用")
        XCTAssertEqual(hotKey.binding, .custom(
            keyCode: HotKeyPreset.controlOptionSpace.keyCode,
            modifiers: HotKeyPreset.controlOptionSpace.modifiers
        ))
        controller.selectPage("不存在")
        XCTAssertEqual(controller.selectedPageTitle, "通用")
    }

    @MainActor func testBookmarkSwitchesShareOnePreferenceAndPersistImmediately() async throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let name = "SettingsNavigation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmarkStore = BookmarkStore(fileURL: directory.appendingPathComponent("bookmarks.json"))
        let controller = SettingsWindowController(store: SettingsStore(defaults: defaults),
                                                  usage: UsageStore(defaults: defaults), bookmarks: bookmarkStore) { _ in }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }
        let switches = descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSSwitch }
        let defaultToggle = try XCTUnwrap(switches.first { $0.accessibilityLabel() == "默认结果中的网页书签" })
        let bookmarkToggle = try XCTUnwrap(switches.first { $0.accessibilityLabel() == "在默认搜索结果中显示书签" })

        controller.selectPage("默认结果")
        defaultToggle.state = .off
        defaultToggle.sendAction(defaultToggle.action, to: defaultToggle.target)
        XCTAssertFalse(bookmarkStore.preferences.includeInDefaultResults)
        XCTAssertEqual(bookmarkToggle.state, .off)

        controller.selectPage("网页书签")
        bookmarkToggle.state = .on
        bookmarkToggle.sendAction(bookmarkToggle.action, to: bookmarkToggle.target)
        XCTAssertTrue(bookmarkStore.preferences.includeInDefaultResults)
        XCTAssertEqual(defaultToggle.state, .on)
        XCTAssertTrue(BookmarkStore(fileURL: directory.appendingPathComponent("bookmarks.json")).preferences.includeInDefaultResults)

        // Optional visual inspection capture when PENNYWORTH_SCREENSHOT_DIR is set.
        guard let output = ProcessInfo.processInfo.environment["PENNYWORTH_SCREENSHOT_DIR"] else { return }
        let destination = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

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
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        controller.selectPage("网页书签")
        XCTAssertEqual(bookmarkStore.profiles.count, 2)
        XCTAssertEqual(bookmarkStore.snapshots.count, 1)

        let content = try XCTUnwrap(controller.window?.contentView)
        for (size, filename) in [(NSSize(width: 920, height: 650), "bookmarks.png"),
                                 (NSSize(width: 780, height: 580), "bookmarks-minimum.png")] {
            controller.window?.setContentSize(size)
            content.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: destination.appendingPathComponent(filename))
        }
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor func testCaptureSettingsDesignSnapshotsWhenRequested() throws {
        guard let output = ProcessInfo.processInfo.environment["PENNYWORTH_SCREENSHOT_DIR"] else { return }
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

        let destination = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let name = "SettingsDesignSnapshots.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()

        let host1 = ImageHostConfig(
            id: "host.r2",
            name: "我的 Cloudflare R2",
            provider: .s3,
            bucket: "blog-assets",
            region: "auto",
            endpoint: "https://acct.r2.cloudflarestorage.com",
            accessKey: "AKIA_DEMO",
            domain: "https://cdn.example.com",
            saveKeyPath: "uPic/{year}/{month}/{filename}{.suffix}",
            suffix: "",
            usePathStyle: true
        )
        let host2 = ImageHostConfig(
            id: "host.oss",
            name: "阿里云 OSS 备份",
            provider: .aliyunOSS,
            bucket: "docs-media",
            region: "oss-cn-hangzhou",
            endpoint: "",
            accessKey: "LTAI_DEMO",
            domain: "https://img.example.org",
            saveKeyPath: "images/{filename}{.suffix}",
            suffix: "?x-oss-process=image/format,webp",
            usePathStyle: false
        )
        try secretStore.setSecret("demo-secret-1", for: host1.id)
        try secretStore.setSecret("demo-secret-2", for: host2.id)

        let sampleSettings = LauncherSettings(
            hotKey: .custom(keyCode: 80, modifiers: 0), // F19
            searchDirectories: [
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path,
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path,
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path,
            ],
            searchEngine: .google,
            rememberUsage: true,
            webSearches: WebSearchDefinition.builtIns + [
                WebSearchDefinition(
                    id: "custom.gh",
                    keyword: "gh",
                    title: "GitHub",
                    urlTemplate: "https://github.com/search?q={query}",
                    isEnabled: true,
                    isCustom: true
                ),
            ],
            fallbackOnlyWhenNoResults: false,
            clipboardHotKey: .optionCommandC,
            language: .simplifiedChinese,
            screenshotHotKey: .controlOptionP,
            appShortcuts: [
                AppShortcut(id: "a1", bundleIdentifier: nil, appPath: "/Applications/WeChat.app", appName: "微信",
                            hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand), isEnabled: true),
                AppShortcut(id: "a2", bundleIdentifier: nil, appPath: "/Applications/Google Chrome.app", appName: "Google Chrome",
                            hotKey: .custom(keyCode: 8, modifiers: HotKeyModifiers.rightCommand), isEnabled: true),
                AppShortcut(id: "a3", bundleIdentifier: nil, appPath: "/Applications/Visual Studio Code.app", appName: "Visual Studio Code",
                            hotKey: .custom(keyCode: 9, modifiers: HotKeyModifiers.rightCommand), isEnabled: true),
                AppShortcut(id: "a4", bundleIdentifier: nil, appPath: "/Applications/DingTalk.app", appName: "钉钉",
                            hotKey: .custom(keyCode: 2, modifiers: HotKeyModifiers.rightCommand), isEnabled: false),
                AppShortcut(id: "a5", bundleIdentifier: nil, appPath: "/Applications/Safari.app", appName: "Safari",
                            hotKey: .custom(keyCode: 15, modifiers: HotKeyModifiers.rightCommand), isEnabled: true),
            ],
            mouseScroll: MouseScrollSettings(reverseScrollDirection: true, smoothScrolling: true, scrollSpeed: 1.5, smoothness: .balanced),
            imageUpload: ImageUploadSettings(
                hosts: [host1, host2],
                selectedHostID: host1.id,
                outputFormat: .markdown,
                compressFactor: 85,
                encodeURL: true,
                uploadClipboardHotKey: .custom(keyCode: 32, modifiers: UInt32(256 | 2048)),
                uploadFileHotKey: nil
            )
        )
        try store.save(sampleSettings)

        let apps = [
            AppItem(name: "微信", url: URL(fileURLWithPath: "/Applications/WeChat.app")),
            AppItem(name: "Google Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app")),
            AppItem(name: "Visual Studio Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")),
            AppItem(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app")),
            AppItem(name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")),
        ]
        let history = [
            UploadHistoryItem(id: "h1", url: "https://cdn.example.com/uPic/2026/11/architecture.png",
                              filename: "architecture.png", hostName: "我的 Cloudflare R2", provider: .s3, fileSize: 128_000),
            UploadHistoryItem(id: "h2", url: "https://img.example.org/images/release-notes.webp",
                              filename: "release-notes.webp", hostName: "阿里云 OSS 备份", provider: .aliyunOSS, fileSize: 64_000),
        ]

        let controller = SettingsWindowController(
            store: store,
            usage: UsageStore(defaults: defaults),
            applicationsProvider: { apps },
            mousePermissionProvider: { (.active, true) },
            imageUploadSecretStore: secretStore,
            uploadHistoryProvider: { history }
        ) { try store.save($0) }
        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)

        func capture(_ filename: String, appearance: NSAppearance.Name = .aqua) throws {
            window.appearance = NSAppearance(named: appearance)
            content.needsLayout = true
            content.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: destination.appendingPathComponent(filename))
        }

        controller.selectPage("应用快捷键")
        try capture("01-app-shortcuts-light.png", appearance: .aqua)
        try capture("02-app-shortcuts-dark.png", appearance: .darkAqua)

        controller.selectPage("通用")
        try capture("03-general-light.png", appearance: .aqua)

        controller.selectPage("文件搜索")
        try capture("04-file-search-light.png", appearance: .aqua)

        controller.selectPage("网页搜索")
        try capture("05-web-search-light.png", appearance: .aqua)

        controller.selectPage("鼠标")
        try capture("06-mouse-light.png", appearance: .aqua)

        controller.selectPage("图床")
        try capture("07-image-upload-hosts-light.png", appearance: .aqua)
        if let uploadView = descendants(content).compactMap({ $0 as? ImageUploadSettingsView }).first {
            uploadView.selectTab(.preferences)
            try capture("08-image-upload-prefs-light.png", appearance: .aqua)
            uploadView.selectTab(.history)
            try capture("09-image-upload-history-light.png", appearance: .aqua)
        }

        // Capture the Add App Shortcut sheet directly!
        controller.selectPage("应用快捷键")
        window.appearance = NSAppearance(named: .aqua)
        let addButton = try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }.first { $0.title == "添加应用快捷键" })
        addButton.performClick(nil)
        if let sheetContent = window.attachedSheet?.contentView {
            window.attachedSheet?.appearance = NSAppearance(named: .aqua)
            sheetContent.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(sheetContent.bitmapImageRepForCachingDisplay(in: sheetContent.bounds))
            sheetContent.cacheDisplay(in: sheetContent.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: destination.appendingPathComponent("10-app-shortcut-sheet-light.png"))
        }
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
    }
}
