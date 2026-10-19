import Foundation

/// Ranks search results. This is the heart of Pennyworth's "feel" —
/// the single function that decides whether it behaves like Alfred.
enum FuzzyMatcher {
    /// Scores how well `item` matches `query`.
    ///
    /// - Returns: `nil` if no match; otherwise a score where higher ranks first.
    static func score(item: AppItem, query: String) -> Double? {
        // ── MVP placeholder: case-insensitive substring match ──────────────
        // TODO(human): replace with subsequence fuzzy matching + frecency.
        //
        // Target behavior (tests in FuzzyMatcherTests define the spec):
        //   1. Subsequence match: "sfr" should match "Safari" (s-a-f-a-r-i
        //      contains s,f,r in order). Consecutive hits score higher.
        //   2. Frecency: apps launched often *and* recently via Pennyworth
        //      get a boost. Persist launch events (UserDefaults is enough),
        //      weight frequency and recency decay.
        //
        // Design trade-off to think about: a pure fuzzy score is stateless
        // and predictable; frecency makes it learn but can surprise the user
        // when rankings shift. Alfred blends both, with fuzzy dominating for
        // short queries. What should happen when query length is 1?
        guard let range = item.name.range(of: query, options: .caseInsensitive) else {
            return nil
        }
        let position = item.name.distance(from: item.name.startIndex, to: range.lowerBound)
        return 1000 - Double(position)
    }
}
