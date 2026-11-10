@testable import Pennyworth
import AppKit
import XCTest

final class LocalizationTests: XCTestCase {
    func testSystemLanguageUsesChineseOnlyWhenPreferred() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-US", "zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW", "en-US"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: []), "en")
        XCTAssertEqual(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedIdentifier(preferredLanguages: ["en-US"]), "zh-Hans")
    }

    func testLanguagePreferenceSurvivesStoreReload() throws {
        let name = "LocalizationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var settings = store.settings
        settings = LauncherSettings(
            hotKey: settings.hotKey,
            searchDirectories: settings.searchDirectories,
            searchEngine: settings.searchEngine,
            rememberUsage: settings.rememberUsage,
            webSearches: settings.webSearches,
            fallbackOnlyWhenNoResults: settings.fallbackOnlyWhenNoResults,
            clipboardHotKey: settings.clipboardHotKey,
            language: .english
        )

        try store.save(settings)

        XCTAssertEqual(SettingsStore(defaults: defaults).settings.language, .english)
    }

    func testOldSettingsWithoutLanguageFollowSystem() throws {
        let name = "LocalizationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("{\"hotKey\":\"optionSpace\",\"searchDirectories\":[],\"searchEngine\":\"google\",\"rememberUsage\":true}".utf8),
                     forKey: "launcher.settings.v1")

        XCTAssertEqual(SettingsStore(defaults: defaults).settings.language, .system)
    }

    func testEnglishAndChineseResourcesTranslateTheSameKey() {
        XCTAssertEqual(AppLocalization.string("settings.language", language: .english), "Language")
        XCTAssertEqual(AppLocalization.string("settings.language", language: .simplifiedChinese), "语言")
        XCTAssertEqual(AppLocalization.string("settings.language", language: .system,
                                              preferredLanguages: ["en-US"]), "Language")
    }

    func testCurrentLanguageConfigurationSelectsResourceBundle() {
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .english)
        XCTAssertEqual(L10n.tr("settings.save"), "Save")
        AppLocalization.configure(language: .simplifiedChinese)
        XCTAssertEqual(L10n.tr("settings.save"), "保存")
    }

    func testLocalizationTablesHaveMatchingKeysAndFormatSpecifiers() throws {
        let english = try localizationTable(language: .english)
        let chinese = try localizationTable(language: .simplifiedChinese)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        for (key, value) in english {
            XCTAssertEqual(formatSpecifiers(value), formatSpecifiers(chinese[key] ?? ""), key)
        }
    }

    private func localizationTable(language: AppLanguage) throws -> [String: String] {
        let identifier = language.resolvedIdentifier()
        let directory = try XCTUnwrap(Bundle.module.path(forResource: identifier.lowercased(), ofType: "lproj"))
        let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("Localizable.strings"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    private func formatSpecifiers(_ value: String) -> [String] {
        let characters = Array(value)
        return characters.indices.compactMap { index in
            guard characters[index] == "%", index + 1 < characters.count,
                  "@df".contains(characters[index + 1]) else { return nil }
            return String(characters[index...index + 1])
        }
    }

    @MainActor func testSettingsSaveSelectedLanguage() throws {
        _ = NSApplication.shared
        let name = "LocalizationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store, usage: UsageStore(defaults: defaults)) {
            try store.save($0)
        }
        controller.showWindow(nil)
        defer { controller.close() }
        let content = try XCTUnwrap(controller.window?.contentView)
        let views = descendants(content)
        let popup = try XCTUnwrap(views.compactMap { $0 as? NSPopUpButton }.first {
            $0.itemTitles == AppLanguage.allCases.map(\.title)
        })

        popup.selectItem(at: 2)
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == L10n.tr("settings.save") })
        save.performClick(nil)

        XCTAssertEqual(store.settings.language, .english)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.language, .english)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
