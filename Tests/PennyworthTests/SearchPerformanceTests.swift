@testable import Pennyworth
import XCTest

final class SearchPerformanceTests: XCTestCase {
    func testThousandApplicationCandidates() throws {
        let name = "PerformanceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let usage = UsageStore(defaults: defaults)
        let items = (0..<1000).map {
            AppItem(name: "Application Number \($0)", url: URL(fileURLWithPath: "/Applications/Test\($0).app"))
        }
        measure {
            let results = ApplicationSearchProvider.results(items: items, query: "apn", usage: usage, enabled: false)
            XCTAssertEqual(results.count, 49)
        }
    }
}
