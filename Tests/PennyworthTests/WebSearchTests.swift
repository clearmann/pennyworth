@testable import Pennyworth
import XCTest

final class WebSearchTests: XCTestCase {
    func testCustomSearchExpandsQueryTemplateWithStrictEncoding() throws {
        let definition = WebSearchDefinition(
            id: "custom.github",
            keyword: "gh",
            title: "GitHub",
            urlTemplate: "https://github.com/search?q={query}&type=code"
        )

        let result = try XCTUnwrap(WebSearchProvider.result(for: "C++ 中文 & #", definition: definition))

        XCTAssertEqual(result.title, "Search GitHub for C++ 中文 & #")
        XCTAssertEqual(
            result.action,
            .openURL(URL(string: "https://github.com/search?q=C%2B%2B%20%E4%B8%AD%E6%96%87%20%26%20%23&type=code")!)
        )
    }

    func testParserRoutesCustomKeywordCaseInsensitively() throws {
        let definition = WebSearchDefinition(
            id: "custom.github",
            keyword: "gh",
            title: "GitHub",
            urlTemplate: "https://github.com/search?q={query}"
        )

        let request = try XCTUnwrap(QueryParser.parse("GH swift", webSearches: [definition]))

        XCTAssertEqual(request.intent, .web(definition))
        XCTAssertEqual(request.query, "swift")
    }

    func testDisabledSearchDoesNotCaptureKeyword() {
        let definition = WebSearchDefinition(
            id: "custom.github",
            keyword: "gh",
            title: "GitHub",
            urlTemplate: "https://github.com/search?q={query}",
            isEnabled: false
        )

        let request = QueryParser.parse("gh swift", webSearches: [definition])

        XCTAssertEqual(request?.intent, .applications)
        XCTAssertEqual(request?.query, "gh swift")
    }

    func testCustomWebSearchesPersistWithLauncherSettings() throws {
        let name = "WebSearchTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let custom = WebSearchDefinition(
            id: "custom.github",
            keyword: "gh",
            title: "GitHub",
            urlTemplate: "https://github.com/search?q={query}"
        )
        let changed = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            webSearches: WebSearchDefinition.builtIns + [custom]
        )

        try SettingsStore(defaults: defaults).save(changed)
        let restored = SettingsStore(defaults: defaults).settings.webSearches

        XCTAssertEqual(restored, changed.webSearches)
        XCTAssertFalse(try XCTUnwrap(restored.first).isCustom)
        XCTAssertTrue(try XCTUnwrap(restored.last).isCustom)
    }

    @MainActor func testLauncherUsesSavedCustomSearch() throws {
        let name = "WebSearchTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let custom = WebSearchDefinition(
            id: "custom.github",
            keyword: "gh",
            title: "GitHub",
            urlTemplate: "https://github.com/search?q={query}"
        )
        let store = SettingsStore(defaults: defaults)
        try store.save(LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: false,
            webSearches: [custom]
        ))
        let model = LauncherModel(
            settings: store,
            usage: UsageStore(defaults: defaults),
            executor: TestExecutor()
        )
        model.beginSession()
        defer { model.endSession() }

        model.updateQuery("gh swift")

        XCTAssertEqual(model.snapshot.results.count, 1)
        XCTAssertEqual(model.snapshot.results.first?.title, "Search GitHub for swift")
        XCTAssertEqual(
            model.snapshot.results.first?.action,
            .openURL(URL(string: "https://github.com/search?q=swift")!)
        )
    }

    func testLegacySettingsReceiveBuiltInWebSearches() throws {
        let name = "WebSearchTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(
            Data("{\"hotKey\":\"optionSpace\",\"searchDirectories\":[],\"searchEngine\":\"google\",\"rememberUsage\":true}".utf8),
            forKey: "launcher.settings.v1"
        )

        let searches = SettingsStore(defaults: defaults).settings.webSearches

        XCTAssertEqual(
            searches.map(\.keyword),
            ["google", "bing", "ddg", "wiki", "youtube", "maps", "translate"]
        )
        XCTAssertTrue(searches.allSatisfy { !$0.isCustom && $0.isEnabled })
    }

    func testSettingsRejectBlankDuplicateAndReservedKeywords() throws {
        let name = "WebSearchTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)

        for keyword in ["", "two words", "Google", "open"] {
            let custom = WebSearchDefinition(
                id: "custom.\(UUID())",
                keyword: keyword,
                title: "Custom",
                urlTemplate: "https://example.com/search?q={query}"
            )
            let changed = LauncherSettings(
                hotKey: .optionSpace,
                searchDirectories: [],
                searchEngine: .google,
                rememberUsage: true,
                webSearches: WebSearchDefinition.builtIns + [custom]
            )

            XCTAssertThrowsError(try store.save(changed)) { error in
                XCTAssertTrue(error.localizedDescription.contains("关键词"))
            }
        }
        XCTAssertEqual(store.settings, .defaults)
    }

    func testSettingsRejectInvalidTitlesAndURLTemplates() throws {
        let name = "WebSearchTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let invalidDefinitions = [
            WebSearchDefinition(id: "custom.file", keyword: "filesearch", title: "File", urlTemplate: "file:///tmp/{query}"),
            WebSearchDefinition(id: "custom.script", keyword: "script", title: "Script", urlTemplate: "javascript:{query}"),
            WebSearchDefinition(id: "custom.credentials", keyword: "credentials", title: "Credentials", urlTemplate: "https://user:pass@example.com/?q={query}"),
            WebSearchDefinition(id: "custom.missing", keyword: "missing", title: "Missing", urlTemplate: "https://example.com/search"),
            WebSearchDefinition(id: "custom.blank", keyword: "blank", title: "", urlTemplate: "https://example.com/?q={query}"),
        ]

        for definition in invalidDefinitions {
            let changed = LauncherSettings(
                hotKey: .optionSpace,
                searchDirectories: [],
                searchEngine: .google,
                rememberUsage: true,
                webSearches: [definition]
            )
            XCTAssertThrowsError(try store.save(changed)) { error in
                XCTAssertTrue(error is WebSearchValidationError)
            }
        }
        XCTAssertEqual(store.settings, .defaults)
    }

    func testSettingsRejectDuplicateIdentifiersAndTooManyCustomSearches() throws {
        let name = "WebSearchTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let first = WebSearchDefinition(
            id: "custom.same", keyword: "one", title: "One", urlTemplate: "https://example.com/?q={query}"
        )
        let second = WebSearchDefinition(
            id: "custom.same", keyword: "two", title: "Two", urlTemplate: "https://example.com/?q={query}"
        )
        let duplicates = LauncherSettings(
            hotKey: .optionSpace, searchDirectories: [], searchEngine: .google,
            rememberUsage: true, webSearches: [first, second]
        )
        XCTAssertThrowsError(try store.save(duplicates))

        let many = (0..<65).map { index in
            WebSearchDefinition(
                id: "custom.\(index)", keyword: "search\(index)", title: "Search \(index)",
                urlTemplate: "https://example.com/?q={query}"
            )
        }
        let excessive = LauncherSettings(
            hotKey: .optionSpace, searchDirectories: [], searchEngine: .google,
            rememberUsage: true, webSearches: many
        )
        XCTAssertThrowsError(try store.save(excessive))
        XCTAssertEqual(store.settings, .defaults)
    }

    func testGitHubAloneRemainsDefaultSearchForExistingBookmarks() {
        XCTAssertEqual(QueryParser.parse("github")?.intent, .applications)
    }
}
