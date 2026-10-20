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

    // MARK: - Subsequence matching

    func testSubsequenceFuzzyMatch() throws {
        XCTAssertNotNil(FuzzyMatcher.score(item: safari, query: "sfr"))
        XCTAssertNotNil(FuzzyMatcher.score(item: activityMonitor, query: "amt"))
    }

    func testConsecutiveHitsBeatScatteredOnes() throws {
        // Compare two hypothetical items where both contain the subsequence.
        let consecutive = AppItem(name: "Safari", url: URL(fileURLWithPath: "/a.app"))
        let scattered = AppItem(name: "S_a_f_ari", url: URL(fileURLWithPath: "/b.app"))
        let consecutiveScore = try XCTUnwrap(FuzzyMatcher.score(item: consecutive, query: "saf"))
        let scatteredScore = try XCTUnwrap(FuzzyMatcher.score(item: scattered, query: "saf"))
        XCTAssertGreaterThan(consecutiveScore, scatteredScore)
    }

    func testSubsequenceMustPreserveOrder() {
        XCTAssertNil(FuzzyMatcher.score(item: safari, query: "fsr"))
    }

    // MARK: - Tier ordering

    func testExactBeatsPrefix() throws {
        let exact = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Mail", url: URL(fileURLWithPath: "/a.app")), query: "mail"))
        let prefix = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Mailbox", url: URL(fileURLWithPath: "/b.app")), query: "mail"))
        XCTAssertGreaterThan(exact, prefix)
    }

    func testPrefixBeatsWordStart() throws {
        let prefix = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Safari", url: URL(fileURLWithPath: "/a.app")), query: "saf"))
        let wordStart = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Activity Safari", url: URL(fileURLWithPath: "/b.app")), query: "saf"))
        XCTAssertGreaterThan(prefix, wordStart)
    }

    func testWordStartBeatsMidWordSubstring() throws {
        let wordStart = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Activity Monitor", url: URL(fileURLWithPath: "/a.app")), query: "mon"))
        let midWord = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Xmonitor", url: URL(fileURLWithPath: "/b.app")), query: "mon"))
        XCTAssertGreaterThan(wordStart, midWord)
    }

    func testSubstringBeatsScatteredSubsequence() throws {
        let substring = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "XMonitor", url: URL(fileURLWithPath: "/a.app")), query: "mon"))
        let subsequence = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "M_x_o_n", url: URL(fileURLWithPath: "/b.app")), query: "mon"))
        XCTAssertGreaterThan(substring, subsequence)
    }

    func testTierBandsMatchDocumentedScores() throws {
        let exact = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Mail", url: URL(fileURLWithPath: "/a.app")), query: "Mail"))
        XCTAssertEqual(exact, 5000)

        let prefix = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Mailbox", url: URL(fileURLWithPath: "/b.app")), query: "Mail"))
        XCTAssertGreaterThanOrEqual(prefix, 4000)
        XCTAssertLessThan(prefix, 4500)

        let wordStart = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Activity Monitor", url: URL(fileURLWithPath: "/c.app")), query: "Monitor"))
        XCTAssertGreaterThanOrEqual(wordStart, 3000)
        XCTAssertLessThan(wordStart, 3500)

        let substring = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "XMonitor", url: URL(fileURLWithPath: "/d.app")), query: "Monitor"))
        XCTAssertGreaterThanOrEqual(substring, 2000)
        XCTAssertLessThan(substring, 2500)

        let subsequence = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "M_x_o_n_i_t_o_r", url: URL(fileURLWithPath: "/e.app")), query: "Monitor"))
        XCTAssertGreaterThanOrEqual(subsequence, 1000)
        XCTAssertLessThan(subsequence, 1500)
    }

    func testQualityRewardNeverBreaksTierFloor() throws {
        // Worst possible quality in a stronger tier must still beat the best
        // possible quality in the next tier down.
        let worstSubstring = try XCTUnwrap(
            FuzzyMatcher.score(item: AppItem(name: String(repeating: "x", count: 100) + "mon" + String(repeating: "y", count: 100), url: URL(fileURLWithPath: "/a.app")), query: "mon")
        )
        let bestSubsequence = try XCTUnwrap(
            FuzzyMatcher.score(item: AppItem(name: "m-o-n" + String(repeating: "z", count: 1), url: URL(fileURLWithPath: "/b.app")), query: "mon")
        )
        XCTAssertGreaterThan(worstSubstring, bestSubsequence)
    }

    func testCallerFrecencyBonusCannotCrossTiers() throws {
        // The caller adds 0..<1; verify the gap between tiers exceeds that.
        let prefix = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Safari", url: URL(fileURLWithPath: "/a.app")), query: "saf"))
        let wordStart = try XCTUnwrap(FuzzyMatcher.score(item: AppItem(name: "Activity Safari", url: URL(fileURLWithPath: "/b.app")), query: "saf"))
        XCTAssertGreaterThan(prefix, wordStart + 1)
    }

    // MARK: - Aliases

    func testAliasMatchesWhenDisplayNameDoesNot() throws {
        let localized = AppItem(
            name: "活动监视器",
            url: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
            aliases: ["Activity Monitor"]
        )
        XCTAssertNotNil(FuzzyMatcher.score(item: localized, query: "activity"))
        XCTAssertNotNil(FuzzyMatcher.score(item: localized, query: "活动"))
    }

    func testAliasDuplicateOfNameIsIgnored() {
        let item = AppItem(name: "Safari", url: URL(fileURLWithPath: "/a.app"), aliases: ["safari", "  ", "Safari"])
        XCTAssertEqual(item.aliases, [])
    }

    func testAliasesAreDeduplicated() {
        let item = AppItem(name: "Name", url: URL(fileURLWithPath: "/a.app"), aliases: ["Raw", "raw", "Other"])
        XCTAssertEqual(item.aliases, ["Raw", "Other"])
    }

    // MARK: - Input hygiene

    func testEmptyAndWhitespaceQueriesReturnNil() {
        XCTAssertNil(FuzzyMatcher.score(item: safari, query: ""))
        XCTAssertNil(FuzzyMatcher.score(item: safari, query: "   "))
        XCTAssertNil(FuzzyMatcher.score(item: safari, query: "\n\t"))
    }

    func testQueryLongerThanLimitReturnsNil() {
        let longQuery = String(repeating: "a", count: FuzzyMatcher.maxQueryLength + 1)
        XCTAssertNil(FuzzyMatcher.score(item: safari, query: longQuery))
    }

    func testQueryAtLimitIsScored() {
        let query = String(repeating: "a", count: FuzzyMatcher.maxQueryLength)
        XCTAssertNil(FuzzyMatcher.score(item: safari, query: query))

        let matchingItem = AppItem(name: query, url: URL(fileURLWithPath: "/a.app"))
        XCTAssertEqual(FuzzyMatcher.score(item: matchingItem, query: query), 5000)
    }

    func testUnicodeQueriesAreHandledSafely() {
        let item = AppItem(name: "微信", url: URL(fileURLWithPath: "/Applications/WeChat.app"))
        XCTAssertNotNil(FuzzyMatcher.score(item: item, query: "微信"))
        XCTAssertNil(FuzzyMatcher.score(item: item, query: "微博"))

        // Composed vs decomposed forms of "é" must compare equal.
        let decomposed = "We\u{0301}Chat"
        let composedItem = AppItem(name: decomposed, url: URL(fileURLWithPath: "/a.app"))
        XCTAssertEqual(FuzzyMatcher.score(item: composedItem, query: "WéChat"), 5000)
    }

    func testEmojiAndCombiningMarksDoNotCrash() {
        let item = AppItem(name: "💬 Messages 👨‍👩‍👧", url: URL(fileURLWithPath: "/a.app"))
        XCTAssertNotNil(FuzzyMatcher.score(item: item, query: "msg"))
    }

    // Frecency is deliberately NOT scored here: the caller adds a 0..<1 bonus on
    // top of this stateless text score. Real coverage lives in UsageStoreTests.
    // The old placeholder test asserted nothing and was removed so it could not
    // pass vacuously.
}
