@testable import Pennyworth
import XCTest

final class AppShortcutTests: XCTestCase {
    func testLeftCommandAndRightCommandWCoexistWithoutConflict() throws {
        let name = "AppShortcutTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)

        let wechatRightW = AppShortcut(
            id: "app.wechat",
            bundleIdentifier: "com.tencent.xinWeChat",
            appPath: "/Applications/WeChat.app",
            appName: "微信",
            hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        )
        let chromeLeftW = AppShortcut(
            id: "app.chrome",
            bundleIdentifier: "com.google.Chrome",
            appPath: "/Applications/Google Chrome.app",
            appName: "Google Chrome",
            hotKey: .custom(keyCode: 13, modifiers: 256)
        )
        let sysPrefsRightComma = AppShortcut(
            id: "app.sysprefs",
            bundleIdentifier: "com.apple.systempreferences",
            appPath: "/System/Applications/System Settings.app",
            appName: "系统设置",
            hotKey: .custom(keyCode: 43, modifiers: HotKeyModifiers.rightCommand)
        )

        let settings = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            appShortcuts: [wechatRightW, chromeLeftW, sysPrefsRightComma]
        )
        try store.save(settings)

        let reloaded = SettingsStore(defaults: defaults).settings
        XCTAssertEqual(reloaded.appShortcuts, [wechatRightW, chromeLeftW, sysPrefsRightComma])
    }

    func testLegacySettingsDefaultToEmptyAppShortcuts() throws {
        let name = "LegacyAppShortcuts.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(
            Data("{\"hotKey\":\"optionSpace\",\"searchDirectories\":[],\"searchEngine\":\"google\",\"rememberUsage\":true}".utf8),
            forKey: "launcher.settings.v1"
        )

        XCTAssertEqual(SettingsStore(defaults: defaults).settings.appShortcuts, [])
    }

    func testValidationRejectsDuplicateAndConflictingAppShortcuts() throws {
        let name = "ConflictAppShortcuts.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)

        let rightW = HotKeyPreset.custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        let first = AppShortcut(id: "app.1", bundleIdentifier: nil, appPath: "/Applications/WeChat.app", appName: "微信", hotKey: rightW)
        let duplicateKey = AppShortcut(id: "app.2", bundleIdentifier: nil, appPath: "/Applications/Safari.app", appName: "Safari", hotKey: rightW)

        XCTAssertThrowsError(try store.save(LauncherSettings(
            hotKey: .optionSpace, searchDirectories: [], searchEngine: .google, rememberUsage: true,
            appShortcuts: [first, duplicateKey]
        )))

        XCTAssertThrowsError(try store.save(LauncherSettings(
            hotKey: rightW, searchDirectories: [], searchEngine: .google, rememberUsage: true,
            appShortcuts: [first]
        )))

        let commandCommaConflict = AppShortcut(
            id: "app.comma", bundleIdentifier: nil, appPath: "/Applications/Safari.app",
            appName: "Safari", hotKey: .commandComma
        )
        XCTAssertThrowsError(try store.save(LauncherSettings(
            hotKey: .optionSpace, searchDirectories: [], searchEngine: .google, rememberUsage: true,
            appShortcuts: [commandCommaConflict]
        )))

        let bothCommandFlags = AppShortcut(
            id: "app.invalid", bundleIdentifier: nil, appPath: "/Applications/Safari.app",
            appName: "Safari", hotKey: .custom(keyCode: 13, modifiers: 256 | HotKeyModifiers.rightCommand)
        )
        XCTAssertThrowsError(try store.save(LauncherSettings(
            hotKey: .optionSpace, searchDirectories: [], searchEngine: .google, rememberUsage: true,
            appShortcuts: [bothCommandFlags]
        )))
    }

    @MainActor func testAppShortcutLauncherUsesPathOrFallsBackToBundleIdentifier() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let existingApp = directory.appendingPathComponent("WeChat.app")
        let fallbackApp = directory.appendingPathComponent("RelocatedWeChat.app")
        try FileManager.default.createDirectory(at: existingApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallbackApp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var openedURLs: [URL] = []
        let launcher = AppShortcutLauncher(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            resolveBundleURL: { bundleID in bundleID == "com.tencent.xinWeChat" ? fallbackApp : nil },
            openApplication: { url in openedURLs.append(url) }
        )

        let directShortcut = AppShortcut(
            id: "1", bundleIdentifier: "com.tencent.xinWeChat", appPath: existingApp.path,
            appName: "微信", hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        )
        XCTAssertTrue(launcher.launch(directShortcut))
        XCTAssertEqual(openedURLs.map(\.path), [existingApp.path])

        let movedShortcut = AppShortcut(
            id: "2", bundleIdentifier: "com.tencent.xinWeChat", appPath: "/NonExistent/WeChat.app",
            appName: "微信", hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        )
        XCTAssertTrue(launcher.launch(movedShortcut))
        XCTAssertEqual(openedURLs.map(\.path), [existingApp.path, fallbackApp.path])

        let missingShortcut = AppShortcut(
            id: "3", bundleIdentifier: "com.missing.app", appPath: "/NonExistent/Missing.app",
            appName: "Missing", hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        )
        XCTAssertFalse(launcher.launch(missingShortcut))
    }

    func testTransactionalHotKeyApplierSwapsShortcutsAndRollsBackOnBackendFailure() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor)

        let wechat = AppShortcut(
            id: "app.wechat",
            bundleIdentifier: "com.tencent.xinWeChat",
            appPath: "/Applications/WeChat.app",
            appName: "微信",
            hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        )
        let disabledChrome = AppShortcut(
            id: "app.chrome",
            bundleIdentifier: "com.google.Chrome",
            appPath: "/Applications/Google Chrome.app",
            appName: "Google Chrome",
            hotKey: .custom(keyCode: 8, modifiers: HotKeyModifiers.rightCommand),
            isEnabled: false
        )
        let initial = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            clipboardHotKey: .optionCommandC,
            appShortcuts: [wechat, disabledChrome]
        )

        var triggeredApps: [String] = []
        var screenshotTriggers = 0
        try HotKeyConfigurationApplier.apply(
            next: initial,
            previous: .defaults,
            manager: manager,
            onLauncher: {},
            onClipboard: {},
            onScreenshot: { screenshotTriggers += 1 },
            onAppShortcut: { triggeredApps.append($0.appName) }
        )

        monitor.setRightCommand(true)
        XCTAssertEqual(backend.active.count, 4, "Launcher, clipboard, screenshot, and enabled Right-Command app shortcut should be active")
        let wechatSlotID = try XCTUnwrap(backend.active.first { $0.value.keyCode == 13 }?.key)
        backend.emit(id: wechatSlotID)
        XCTAssertEqual(triggeredApps, ["微信"])
        let screenshotSlotID = try XCTUnwrap(backend.active.first { $0.value.keyCode == HotKeyPreset.controlOptionP.keyCode }?.key)
        backend.emit(id: screenshotSlotID)
        XCTAssertEqual(screenshotTriggers, 1)
        monitor.setRightCommand(false)
        XCTAssertEqual(backend.active.count, 3, "Only launcher, clipboard, and screenshot remain registered when Right Command is released")

        let swapped = LauncherSettings(
            hotKey: .custom(keyCode: 8, modifiers: 2048 | 256),
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            clipboardHotKey: .custom(keyCode: 49, modifiers: 2048),
            screenshotHotKey: .custom(keyCode: 31, modifiers: 4096 | 2048),
            appShortcuts: [
                AppShortcut(
                    id: "app.safari",
                    bundleIdentifier: "com.apple.Safari",
                    appPath: "/Applications/Safari.app",
                    appName: "Safari",
                    hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
                ),
            ]
        )
        try HotKeyConfigurationApplier.apply(
            next: swapped,
            previous: initial,
            manager: manager,
            onLauncher: {},
            onClipboard: {},
            onScreenshot: { screenshotTriggers += 1 },
            onAppShortcut: { triggeredApps.append($0.appName) }
        )

        backend.failOnKeyCode = 99
        let failingNext = LauncherSettings(
            hotKey: .controlOptionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            clipboardHotKey: .controlOptionC,
            screenshotHotKey: nil,
            appShortcuts: [
                AppShortcut(
                    id: "app.conflict",
                    bundleIdentifier: nil,
                    appPath: "/Applications/Terminal.app",
                    appName: "Terminal",
                    hotKey: .custom(keyCode: 99, modifiers: HotKeyModifiers.rightCommand)
                ),
            ]
        )
        XCTAssertThrowsError(try HotKeyConfigurationApplier.apply(
            next: failingNext,
            previous: swapped,
            manager: manager,
            onLauncher: {},
            onClipboard: {},
            onScreenshot: { screenshotTriggers += 1 },
            onAppShortcut: { triggeredApps.append($0.appName) }
        ))

        monitor.setRightCommand(true)
        let restoredSafariSlotID = try XCTUnwrap(backend.active.first { $0.value.keyCode == 13 }?.key)
        backend.emit(id: restoredSafariSlotID)
        XCTAssertEqual(triggeredApps, ["微信", "Safari"], "Rollback must restore previous Right-Command app shortcut")
        let restoredScreenshotSlotID = try XCTUnwrap(backend.active.first { $0.value.keyCode == 31 }?.key)
        backend.emit(id: restoredScreenshotSlotID)
        XCTAssertEqual(screenshotTriggers, 2, "Rollback must restore previous screenshot hotkey")
    }

    func testHotKeyApplierSwapsScreenshotAndAppShortcutAndPartiallyRestoresWhenPreviousScreenshotFails() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor)

        let previous = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            clipboardHotKey: .optionCommandC,
            screenshotHotKey: .controlOptionP,
            appShortcuts: [
                AppShortcut(
                    id: "app.wechat",
                    bundleIdentifier: "com.tencent.xinWeChat",
                    appPath: "/Applications/WeChat.app",
                    appName: "微信",
                    hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
                ),
            ]
        )
        let swapped = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            clipboardHotKey: .optionCommandC,
            screenshotHotKey: nil,
            appShortcuts: [
                AppShortcut(
                    id: "app.wechat",
                    bundleIdentifier: "com.tencent.xinWeChat",
                    appPath: "/Applications/WeChat.app",
                    appName: "微信",
                    hotKey: .controlOptionP
                ),
            ]
        )

        var triggeredApps: [String] = []
        try HotKeyConfigurationApplier.apply(
            next: previous,
            previous: .defaults,
            manager: manager,
            onLauncher: {},
            onClipboard: {},
            onScreenshot: {},
            onAppShortcut: { triggeredApps.append($0.appName) }
        )
        try HotKeyConfigurationApplier.apply(
            next: swapped,
            previous: previous,
            manager: manager,
            onLauncher: {},
            onClipboard: {},
            onScreenshot: {},
            onAppShortcut: { triggeredApps.append($0.appName) }
        )
        let appSlotID = try XCTUnwrap(backend.active.first { $0.value.keyCode == HotKeyPreset.controlOptionP.keyCode }?.key)
        backend.emit(id: appSlotID)
        XCTAssertEqual(triggeredApps, ["微信"])

        // Simulate screenshot hotkey owned by another app during rollback: app shortcuts must still be restored.
        backend.failOnKeyCode = HotKeyPreset.controlOptionP.keyCode
        let failingNext = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            clipboardHotKey: .optionCommandC,
            screenshotHotKey: .controlOptionP,
            appShortcuts: previous.appShortcuts
        )
        XCTAssertThrowsError(try HotKeyConfigurationApplier.apply(
            next: failingNext,
            previous: previous,
            manager: manager,
            onLauncher: {},
            onClipboard: {},
            onScreenshot: {},
            onAppShortcut: { triggeredApps.append($0.appName) }
        ))
        monitor.setRightCommand(true)
        let restoredWeChatID = try XCTUnwrap(backend.active.first { $0.value.keyCode == 13 }?.key)
        backend.emit(id: restoredWeChatID)
        XCTAssertEqual(triggeredApps, ["微信", "微信"])
    }

    func testValidationRejectsInvalidPathsIdentifiersAndExcessiveCount() {
        let validKey = HotKeyPreset.custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        XCTAssertThrowsError(try AppShortcut.validate(
            [AppShortcut(id: "", bundleIdentifier: nil, appPath: "/Applications/WeChat.app", appName: "微信", hotKey: validKey)],
            reservedHotKeys: []
        ))
        XCTAssertThrowsError(try AppShortcut.validate(
            [
                AppShortcut(id: "dup", bundleIdentifier: nil, appPath: "/Applications/WeChat.app", appName: "微信", hotKey: validKey),
                AppShortcut(id: "dup", bundleIdentifier: nil, appPath: "/Applications/Safari.app", appName: "Safari",
                            hotKey: .custom(keyCode: 1, modifiers: HotKeyModifiers.rightCommand)),
            ],
            reservedHotKeys: []
        ))
        XCTAssertThrowsError(try AppShortcut.validate(
            [AppShortcut(id: "rel", bundleIdentifier: nil, appPath: "Applications/WeChat.app", appName: "微信", hotKey: validKey)],
            reservedHotKeys: []
        ))
        XCTAssertThrowsError(try AppShortcut.validate(
            [AppShortcut(id: "txt", bundleIdentifier: nil, appPath: "/Applications/WeChat.txt", appName: "微信", hotKey: validKey)],
            reservedHotKeys: []
        ))
        XCTAssertThrowsError(try AppShortcut.validate(
            [AppShortcut(id: "blankBundle", bundleIdentifier: "  ", appPath: "/Applications/WeChat.app", appName: "微信", hotKey: validKey)],
            reservedHotKeys: []
        ))
        let tooMany = (0..<65).map { idx in
            AppShortcut(
                id: "id.\(idx)",
                bundleIdentifier: nil,
                appPath: "/Applications/App\(idx).app",
                appName: "App \(idx)",
                hotKey: .custom(keyCode: UInt32(idx), modifiers: HotKeyModifiers.rightCommand)
            )
        }
        XCTAssertThrowsError(try AppShortcut.validate(tooMany, reservedHotKeys: []))

        let allErrors: [AppShortcutValidationError] = [
            .tooManyShortcuts, .invalidIdentifier, .duplicateIdentifier,
            .invalidApplication, .missingHotKey, .invalidHotKey, .duplicateHotKey("右⌘W"),
        ]
        for error in allErrors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    func testStartupAppShortcutsRegisterOnlyEnabledEntries() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor)
        var launched: [String] = []

        let shortcuts = [
            AppShortcut(id: "1", bundleIdentifier: nil, appPath: "/Applications/WeChat.app", appName: "微信",
                        hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand), isEnabled: true),
            AppShortcut(id: "2", bundleIdentifier: nil, appPath: "/Applications/Safari.app", appName: "Safari",
                        hotKey: .custom(keyCode: 1, modifiers: HotKeyModifiers.rightCommand), isEnabled: false),
        ]
        HotKeyConfigurationApplier.registerStartupAppShortcuts(shortcuts, in: manager) {
            launched.append($0.appName)
        }

        monitor.setRightCommand(true)
        XCTAssertEqual(backend.active.count, 1)
        let id = try XCTUnwrap(backend.active.first?.key)
        backend.emit(id: id)
        XCTAssertEqual(launched, ["微信"])
    }
}
