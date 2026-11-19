@testable import Pennyworth
import XCTest

final class MouseScrollSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "MouseScrollSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsAreInactiveAndSafe() {
        let defaults = MouseScrollSettings.defaults
        XCTAssertFalse(defaults.reverseScrollDirection)
        XCTAssertFalse(defaults.smoothScrolling)
        XCTAssertEqual(defaults.scrollSpeed, 1.0, accuracy: 0.0001)
        XCTAssertEqual(defaults.smoothness, .balanced)
        XCTAssertFalse(defaults.isActive)
    }

    func testIsActiveReflectsAnyEnabledScrollEnhancement() {
        XCTAssertTrue(MouseScrollSettings(reverseScrollDirection: true).isActive)
        XCTAssertTrue(MouseScrollSettings(smoothScrolling: true).isActive)
        XCTAssertTrue(MouseScrollSettings(scrollSpeed: 1.5).isActive)
        XCTAssertFalse(MouseScrollSettings(reverseScrollDirection: false, smoothScrolling: false, scrollSpeed: 1.0, smoothness: .silky).isActive)
    }

    func testValidationAcceptsBoundariesAndRejectsOutOfRangeOrNonFiniteSpeed() {
        XCTAssertNoThrow(try MouseScrollSettings.validate(MouseScrollSettings(scrollSpeed: 0.5)))
        XCTAssertNoThrow(try MouseScrollSettings.validate(MouseScrollSettings(scrollSpeed: 3.0)))
        XCTAssertThrowsError(try MouseScrollSettings.validate(MouseScrollSettings(scrollSpeed: 0.49)))
        XCTAssertThrowsError(try MouseScrollSettings.validate(MouseScrollSettings(scrollSpeed: 3.01)))
        XCTAssertThrowsError(try MouseScrollSettings.validate(MouseScrollSettings(scrollSpeed: .nan)))
        XCTAssertThrowsError(try MouseScrollSettings.validate(MouseScrollSettings(scrollSpeed: .infinity)))
    }

    func testSettingsStoreRoundTripsMouseScrollSettings() throws {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let customMouse = MouseScrollSettings(
            reverseScrollDirection: true,
            smoothScrolling: true,
            scrollSpeed: 1.75,
            smoothness: .silky
        )
        let saved = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            mouseScroll: customMouse
        )

        try store.save(saved)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.mouseScroll, customMouse)
        XCTAssertNil(reloaded.warning)
    }

    func testLegacySettingsWithoutMouseScrollDefaultToInactive() throws {
        let defaults = makeDefaults()
        let legacy = #"{"hotKey":"optionSpace","searchDirectories":[],"searchEngine":"google","rememberUsage":true}"#
        defaults.set(Data(legacy.utf8), forKey: "launcher.settings.v1")

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.mouseScroll, .defaults)
        XCTAssertNil(store.warning)
    }

    func testSettingsStoreRejectsInvalidMouseScrollSpeed() {
        let store = SettingsStore(defaults: makeDefaults())
        let invalid = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            mouseScroll: MouseScrollSettings(scrollSpeed: 5.0)
        )
        XCTAssertThrowsError(try store.save(invalid))
    }
}
