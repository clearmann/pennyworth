@testable import Pennyworth
import XCTest

final class FuzzyMatcherTests: XCTestCase {
    private let safari = AppItem(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))
    private let activityMonitor = AppItem(
        name: "Activity Monitor",
        url: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
    )

    // MARK: - Placeholder behavior (must keep passing)

    func testExactNameMatches() {
        XCTAssertNotNil(FuzzyMatcher.score(item: safari, query: "Safari"))
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.score(item: safari, query: "safari"))
        XCTAssertNotNil(FuzzyMatcher.score(item: safari, query: "SAFARI"))
    }

    func testNonMatchingQueryReturnsNil() {
        XCTAssertNil(FuzzyMatcher.score(item: safari, query: "xyzzy"))
    }

    func testEarlierMatchRanksHigher() throws {
        // "a" appears at position 0 in "Activity Monitor" but position 1 in "Safari".
        let activityScore = try XCTUnwrap(FuzzyMatcher.score(item: activityMonitor, query: "a"))
        let safariScore = try XCTUnwrap(FuzzyMatcher.score(item: safari, query: "a"))
        XCTAssertGreaterThan(activityScore, safariScore)
    }

    // MARK: - Target behavior for the human-implemented version
    //
    // These tests are the *spec* for the TODO in FuzzyMatcher.swift.
    // Remove the XCTSkip line → watch them fail (RED) → implement (GREEN).

    func testSubsequenceFuzzyMatch() throws {
        throw XCTSkip("TODO(human): subsequence matching not implemented yet")
        XCTAssertNotNil(FuzzyMatcher.score(item: safari, query: "sfr"))
        XCTAssertNotNil(FuzzyMatcher.score(item: activityMonitor, query: "amt"))
    }

    func testConsecutiveHitsBeatScatteredOnes() throws {
        throw XCTSkip("TODO(human): consecutive-hit bonus not implemented yet")
        // "saf" is consecutive in "Safari"; in "Activity Monitor" the letters s,a,f don't even exist — so
        // instead: compare two hypothetical items where both contain the subsequence.
        let consecutive = AppItem(name: "Safari", url: URL(fileURLWithPath: "/a.app"))
        let scattered = AppItem(name: "S_a_f_ari", url: URL(fileURLWithPath: "/b.app"))
        let consecutiveScore = try XCTUnwrap(FuzzyMatcher.score(item: consecutive, query: "saf"))
        let scatteredScore = try XCTUnwrap(FuzzyMatcher.score(item: scattered, query: "saf"))
        XCTAssertGreaterThan(consecutiveScore, scatteredScore)
    }

    func testFrecencyBoostsFrequentlyLaunchedApps() throws {
        throw XCTSkip("TODO(human): frecency boost not implemented yet")
    }
}
