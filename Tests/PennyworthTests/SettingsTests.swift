@testable import Pennyworth
import XCTest

final class SettingsTests: XCTestCase {
    func testCustomHotKeysArePersistedAndConflictsAreRejected() throws {
        let name = "CustomHotKeys.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let custom = HotKeyPreset.custom(keyCode: 35, modifiers: 256 | 4096)
        try store.save(LauncherSettings(hotKey: custom, searchDirectories: [], searchEngine: .google,
                                        rememberUsage: true, clipboardHotKey: .optionCommandC))
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.hotKey, custom)
        XCTAssertThrowsError(try store.save(LauncherSettings(hotKey: custom, searchDirectories: [], searchEngine: .google,
                                                             rememberUsage: true, clipboardHotKey: custom)))
        XCTAssertThrowsError(try store.save(LauncherSettings(hotKey: .custom(keyCode: 43, modifiers: 256),
                                                             searchDirectories: [], searchEngine: .google,
                                                             rememberUsage: true, clipboardHotKey: .optionCommandC)))
    }

    func testSettingsPersistAndEmptyScopesStayEmpty() throws {
        let name = "PennyworthTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.searchDirectories, [])
        let changed = LauncherSettings(hotKey: .controlOptionSpace, searchDirectories: ["/tmp/test"],
                                       searchEngine: .bing, rememberUsage: false,
                                       clipboardHotKey: .controlOptionC)
        try store.save(changed)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, changed)
    }

    func testOldSettingsUseDefaultClipboardHotKey() throws {
        let name = "LauncherTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("{\"hotKey\":\"optionSpace\",\"searchDirectories\":[],\"searchEngine\":\"google\",\"rememberUsage\":true}".utf8),
                     forKey: "launcher.settings.v1")

        XCTAssertEqual(SettingsStore(defaults: defaults).settings.clipboardHotKey, .optionCommandC)
    }

    func testInvalidSettingsAreRejectedAndCorruptionIsReported() throws {
        let name = "PennyworthTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("bad JSON".utf8), forKey: "launcher.settings.v1")
        let store = SettingsStore(defaults: defaults)
        XCTAssertNotNil(store.warning)
        XCTAssertEqual(store.settings, .defaults)
        XCTAssertThrowsError(try store.save(LauncherSettings(hotKey: .optionSpace, searchDirectories: ["relative"], searchEngine: .google, rememberUsage: true)))
        try store.save(.defaults)
        XCTAssertNil(store.warning)
    }

    func testUsageRecencyAndDisabledHistory() throws {
        let name = "PennyworthTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = URL(fileURLWithPath: "/b.app")
        let usage = UsageStore(defaults: defaults, now: { Date(timeIntervalSince1970: 1000) })
        try usage.record(url)
        let later = UsageStore(defaults: defaults, now: { Date(timeIntervalSince1970: 900000) })
        XCTAssertGreaterThan(usage.bonus(for: url), later.bonus(for: url))
        let items = [AppItem(name: "Same", url: url), AppItem(name: "Same", url: URL(fileURLWithPath: "/a.app"))]
        XCTAssertEqual(ApplicationSearchProvider.results(items: items, query: "", usage: usage, enabled: false).first?.id, "app:/a.app")
        defaults.set(Data("invalid".utf8), forKey: "launcher.usage.v1")
        XCTAssertEqual(UsageStore(defaults: defaults).bonus(for: url), 0)
    }

    func testUsageOnlyReordersMatchingAppsAndCanBeCleared() throws {
        let name = "PennyworthTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let usage = UsageStore(defaults: defaults, now: { Date(timeIntervalSince1970: 1000) })
        let first = AppItem(name: "Mail One", url: URL(fileURLWithPath: "/a.app"))
        let second = AppItem(name: "Mail Two", url: URL(fileURLWithPath: "/b.app"))
        try usage.record(second.url)
        XCTAssertEqual(ApplicationSearchProvider.results(items: [first, second], query: "mail", usage: usage, enabled: true).first?.action,
                       .openApplication(second.url))
        XCTAssertEqual(ApplicationSearchProvider.results(items: [second], query: "xyz", usage: usage, enabled: true), [])
        XCTAssertGreaterThan(UsageStore(defaults: defaults).bonus(for: second.url), 0)
        usage.clear()
        XCTAssertEqual(usage.bonus(for: second.url), 0)
    }
}
