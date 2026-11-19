import Carbon
import XCTest
@testable import Pennyworth

final class ScreenshotSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "ScreenshotSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func settings(hotKey: HotKeyPreset = .optionSpace,
                          clipboard: HotKeyPreset = .optionCommandC,
                          screenshot: HotKeyPreset? = .controlOptionP) -> LauncherSettings {
        LauncherSettings(hotKey: hotKey, searchDirectories: [], searchEngine: .google,
                         rememberUsage: true, clipboardHotKey: clipboard, screenshotHotKey: screenshot)
    }

    // MARK: - Preset

    func testControlOptionPPresetValues() {
        let preset = HotKeyPreset.controlOptionP
        XCTAssertEqual(preset.title, "⌃ ⌥ P")
        XCTAssertEqual(preset.keyCode, UInt32(kVK_ANSI_P))
        XCTAssertEqual(preset.modifiers, UInt32(controlKey | optionKey))
        XCTAssertFalse(preset.isCustom)
    }

    func testControlOptionPCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(HotKeyPreset.controlOptionP)
        XCTAssertEqual(try JSONDecoder().decode(HotKeyPreset.self, from: data), .controlOptionP)
    }

    // MARK: - Persistence

    func testScreenshotHotKeyPersistsAcrossStores() throws {
        let defaults = makeDefaults()
        try SettingsStore(defaults: defaults).save(settings(screenshot: .custom(keyCode: 120, modifiers: 256)))
        let reloaded = SettingsStore(defaults: defaults).settings
        XCTAssertEqual(reloaded.screenshotHotKey, .custom(keyCode: 120, modifiers: 256))
    }

    func testExplicitNullMeansDisabledAndRoundTrips() throws {
        let defaults = makeDefaults()
        try SettingsStore(defaults: defaults).save(settings(screenshot: nil))
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.settings.screenshotHotKey)
        XCTAssertNil(store.warning)
    }

    func testLegacyJSONWithoutScreenshotKeyGetsDefault() throws {
        let defaults = makeDefaults()
        let legacy = #"{"hotKey":"optionSpace","searchDirectories":[],"searchEngine":"google","rememberUsage":true}"#
        defaults.set(Data(legacy.utf8), forKey: "launcher.settings.v1")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.screenshotHotKey, .controlOptionP)
        XCTAssertNil(store.warning)
    }

    func testLegacyCollisionMigratesToDisabledWithWarningAndKeepsOtherSettings() throws {
        let defaults = makeDefaults()
        // Legacy launcher hotkey is physically ⌃⌥P (keyCode 35, controlKey|optionKey = 6144),
        // colliding with the screenshot default.
        let legacy = """
        {"hotKey":{"keyCode":35,"modifiers":6144},"searchDirectories":["/tmp"],"searchEngine":"bing",
        "rememberUsage":false,"clipboardHotKey":"optionCommandC"}
        """
        defaults.set(Data(legacy.utf8), forKey: "launcher.settings.v1")
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.settings.screenshotHotKey)
        XCTAssertEqual(store.settings.searchDirectories, ["/tmp"])
        XCTAssertEqual(store.settings.searchEngine, .bing)
        XCTAssertFalse(store.settings.rememberUsage)
        XCTAssertNotNil(store.warning)
    }

    // MARK: - Validation

    func testScreenshotConflictingWithLauncherIsRejected() {
        let store = SettingsStore(defaults: makeDefaults())
        // .custom(⌥Space) collides with the launcher's .optionSpace preset.
        let customLauncher = HotKeyPreset.custom(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        XCTAssertThrowsError(try store.save(settings(screenshot: customLauncher)))
        XCTAssertThrowsError(try store.save(settings(screenshot: .optionSpace)))
    }

    func testScreenshotConflictingWithClipboardAndCommandCommaIsRejected() {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertThrowsError(try store.save(settings(screenshot: .optionCommandC)))
        XCTAssertThrowsError(try store.save(settings(screenshot: .commandComma)))
    }

    func testCustomBindingPhysicallyEqualToPresetStillConflicts() {
        // .custom(⌥⌘C) and .optionCommandC are the same physical hotkey.
        let customClipboard = HotKeyPreset.custom(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | cmdKey))
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertThrowsError(try store.save(settings(screenshot: customClipboard)))
        XCTAssertThrowsError(try store.save(settings(hotKey: customClipboard, clipboard: .optionCommandC)))
    }

    func testDisabledScreenshotSkipsValidation() throws {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertNoThrow(try store.save(settings(screenshot: nil)))
    }

    func testBareKeyScreenshotBindingIsRejected() {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertThrowsError(try store.save(settings(screenshot: .custom(keyCode: 35, modifiers: 0))))
        // F13–F20 may be used without modifiers.
        XCTAssertNoThrow(try store.save(settings(screenshot: .custom(keyCode: UInt32(kVK_F13), modifiers: 0))))
    }

    func testScreenshotConflictingWithAppShortcutIsRejected() {
        let store = SettingsStore(defaults: makeDefaults())
        let shortcut = AppShortcut(
            id: "app.wechat",
            bundleIdentifier: "com.tencent.xinWeChat",
            appPath: "/Applications/WeChat.app",
            appName: "微信",
            hotKey: .custom(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey))
        )
        let conflicting = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            screenshotHotKey: .controlOptionP,
            appShortcuts: [shortcut]
        )
        XCTAssertThrowsError(try store.save(conflicting))

        let nonConflicting = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            screenshotHotKey: nil,
            appShortcuts: [shortcut]
        )
        XCTAssertNoThrow(try store.save(nonConflicting))
    }

    func testLegacyCollisionWithAppShortcutMigratesScreenshotToDisabledWithWarning() throws {
        let defaults = makeDefaults()
        let legacy = """
        {"hotKey":"optionSpace","searchDirectories":[],"searchEngine":"google","rememberUsage":true,
        "clipboardHotKey":"optionCommandC",
        "appShortcuts":[{"id":"app.1","bundleIdentifier":"com.apple.Safari","appPath":"/Applications/Safari.app",
        "appName":"Safari","hotKey":{"keyCode":35,"modifiers":6144},"isEnabled":true}]}
        """
        defaults.set(Data(legacy.utf8), forKey: "launcher.settings.v1")

        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.settings.screenshotHotKey)
        XCTAssertEqual(store.settings.appShortcuts.count, 1)
        XCTAssertEqual(store.settings.appShortcuts.first?.appName, "Safari")
        XCTAssertNotNil(store.warning)
    }

    func testScreenshotAndAppShortcutsRoundTripTogether() throws {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let shortcut = AppShortcut(
            id: "app.wechat",
            bundleIdentifier: "com.tencent.xinWeChat",
            appPath: "/Applications/WeChat.app",
            appName: "微信",
            hotKey: .custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand)
        )
        let saved = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            screenshotHotKey: nil,
            appShortcuts: [shortcut]
        )
        try store.save(saved)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertNil(reloaded.settings.screenshotHotKey)
        XCTAssertEqual(reloaded.settings.appShortcuts, [shortcut])
        XCTAssertNil(reloaded.warning)
    }
}
