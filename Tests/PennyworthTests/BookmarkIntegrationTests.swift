@testable import Pennyworth
import XCTest

final class BookmarkIntegrationTests: XCTestCase {
    @MainActor func testImportedBookmarksFlowThroughMixedAndDedicatedSearch() async throws {
        let name = "BookmarkFlow.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        let profile = root.appendingPathComponent("Chrome/Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let fixture = #"{"version":1,"roots":{"bookmark_bar":{"type":"folder","name":"书签栏","children":[{"id":"1","type":"url","name":"GitHub","url":"https://github.com/"}]},"other":{"type":"folder","name":"其他","children":[]},"synced":{"type":"folder","name":"移动","children":[]}}}"#
        try Data(fixture.utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        let bookmarks = BookmarkStore(fileURL: root.appendingPathComponent("store/bookmarks.json"))
        try await bookmarks.discoverProfiles(root: root.appendingPathComponent("Chrome"))
        let source = try XCTUnwrap(bookmarks.profiles.first)
        try bookmarks.setSelected(true, profileID: source.id)
        var preferences = bookmarks.preferences
        preferences.enabled = true
        try bookmarks.updatePreferences(preferences)
        try await bookmarks.refreshSelected()

        let executor = TestExecutor()
        let model = LauncherModel(settings: SettingsStore(defaults: defaults), usage: UsageStore(defaults: defaults),
                                  executor: executor, bookmarks: bookmarks)
        model.beginSession()
        model.setApplications([AppItem(name: "GitHub Desktop", url: URL(fileURLWithPath: "/GitHub.app"))])
        model.updateQuery("github")
        XCTAssertEqual(model.snapshot.results.count, 3)
        XCTAssertTrue(model.snapshot.results[0].id.hasPrefix("app:"))
        XCTAssertTrue(model.snapshot.results[1].id.hasPrefix("bookmark:"))
        XCTAssertTrue(model.snapshot.results[2].id.hasPrefix("web:"))
        model.updateQuery("")
        XCTAssertEqual(model.snapshot.results.count, 1)
        preferences.includeInDefaultResults = false
        try bookmarks.updatePreferences(preferences)
        model.updateQuery("github")
        XCTAssertEqual(model.snapshot.results.count, 2)
        model.updateQuery("bm github")
        XCTAssertEqual(model.snapshot.results.count, 1)
        model.executeSelected()
        model.executeSelected()
        XCTAssertEqual(executor.actions, [.openURL(URL(string: "https://github.com/")!)])
        executor.finish?(.success(()))
        model.beginSession()
        try bookmarks.setSelected(false, profileID: source.id)
        model.updateQuery("bm")
        XCTAssertTrue(model.snapshot.results.isEmpty)
        XCTAssertEqual(bookmarks.snapshots[source.id]?.entries.count, 1)
    }

    func testBookmarkKeywordDoesNotHijackOtherModes() {
        XCTAssertEqual(QueryParser.parse("bm github")?.intent, .bookmarks)
        XCTAssertEqual(QueryParser.parse("BM")?.intent, .bookmarks)
        XCTAssertEqual(QueryParser.parse("bmx")?.intent, .applications)
        XCTAssertEqual(QueryParser.parse(" bm")?.intent, .fileSearch(.open))
        XCTAssertEqual(QueryParser.parse("google bm")?.intent, .web(.google))
    }

    func testOldSettingsDecodeWithNewFallbackDefault() throws {
        let data = Data(#"{"hotKey":"controlOptionSpace","searchDirectories":["/tmp"],"searchEngine":"bing","rememberUsage":false}"#.utf8)
        let value = try JSONDecoder().decode(LauncherSettings.self, from: data)
        XCTAssertEqual(value.hotKey, .controlOptionSpace)
        XCTAssertFalse(value.fallbackOnlyWhenNoResults)
        XCTAssertEqual(value.searchDirectories, ["/tmp"])
    }

    func testWebURLValidationAllowsHTTPButNotExecutableSchemesOrCredentials() {
        for text in ["https://example.com/a?q=1#section", "http://localhost:8080", "HTTPS://example.com"] {
            XCTAssertTrue(ActionExecutor.isAllowedWebURL(URL(string: text)!), text)
        }
        for text in ["javascript:alert(1)", "file:///tmp/a", "data:text/html,hello", "chrome://settings", "https:///", "https://user:pass@example.com"] {
            XCTAssertFalse(ActionExecutor.isAllowedWebURL(URL(string: text)!), text)
        }
    }

    @MainActor func testFallbackPreferenceAndDisabledBookmarks() throws {
        let name = "BookmarkIntegration.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        try settings.save(LauncherSettings(hotKey: .optionSpace, searchDirectories: [], searchEngine: .google,
                                           rememberUsage: false, fallbackOnlyWhenNoResults: true))
        let model = LauncherModel(settings: settings, usage: UsageStore(defaults: defaults), executor: TestExecutor())
        model.beginSession()
        model.setApplications([AppItem(name: "Safari", url: URL(fileURLWithPath: "/Safari.app"))])
        model.updateQuery("Safari")
        XCTAssertEqual(model.snapshot.results.count, 1)
        model.updateQuery("no-match")
        XCTAssertEqual(model.snapshot.results.count, 1)
        XCTAssertTrue(model.snapshot.results[0].title.contains("Google"))
        model.updateQuery("bm")
        XCTAssertTrue(model.snapshot.results.isEmpty)
        XCTAssertTrue(model.snapshot.message.contains("书签"))
    }
}
