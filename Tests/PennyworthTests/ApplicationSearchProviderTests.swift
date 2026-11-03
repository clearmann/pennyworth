@testable import Pennyworth
import XCTest

final class ApplicationSearchProviderTests: XCTestCase {
    func testShortQueryRanksExactAliasAndWordInitialsLikeAlfred() throws {
        let items = [
            AppItem(name: "Google Chrome Canary", url: URL(fileURLWithPath: "/Applications/Google Chrome Canary.app")),
            AppItem(name: "Stocks", url: URL(fileURLWithPath: "/System/Applications/Stocks.app")),
            AppItem(name: "Adobe Acrobat", url: URL(fileURLWithPath: "/Applications/Adobe Acrobat.app")),
            AppItem(
                name: "Artificial Analysis",
                url: URL(fileURLWithPath: "/Applications/Artificial Analysis.app"),
                aliases: ["aa"]
            ),
            AppItem(name: "Clock", url: URL(fileURLWithPath: "/System/Applications/Clock.app")),
        ]
        let suiteName = "ApplicationSearchProviderTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let results = ApplicationSearchProvider.results(
            items: items,
            query: "aa",
            usage: UsageStore(defaults: defaults),
            enabled: false
        )

        XCTAssertEqual(
            results.map(\.title),
            ["Artificial Analysis", "Adobe Acrobat", "Google Chrome Canary"]
        )
    }
}
