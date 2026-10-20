import Foundation

/// Ranks search results. This is the heart of Pennyworth's "feel" —
/// the single function that decides whether it behaves like Alfred.
///
/// Scoring is stateless: it looks only at the item's names and the query.
/// Frecency is applied by the caller as an additive bonus in `0..<1`, so it can
/// reorder near-ties without ever overtaking a stronger match tier.
enum FuzzyMatcher {
    /// Score bands. Each band is 1000 wide and quality rewards stay below 500,
    /// so a weaker tier can never outrank a stronger one.
    private enum Tier {
        static let exact: Double = 5000
        static let prefix: Double = 4000
        static let wordStart: Double = 3000
        static let substring: Double = 2000
        static let subsequence: Double = 1000
        /// Maximum reward added inside a tier.
        static let maxQualityReward: Double = 499
    }

    /// Longest query that is scored. Longer input is not a meaningful app query
    /// and would only burn CPU on a per-keystroke path.
    static let maxQueryLength = 512

    private struct Match {
        /// Base score of the tier this match landed in.
        let base: Double
        /// Tier-specific quality component in `0...1`.
        let quality: Double
    }

    /// Scores how well `item` matches `query`.
    ///
    /// The best of the display name and every alias wins.
    ///
    /// - Returns: `nil` if no match or if the query is empty/whitespace-only;
    ///   otherwise a score where higher ranks first.
    static func score(item: AppItem, query: String) -> Double? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= maxQueryLength else { return nil }

        let best = ([item.name] + item.aliases)
            .compactMap { match(in: $0, query: query) }
            .max { total($0) < total($1) }
        return best.map(total)
    }

    private static func total(_ match: Match) -> Double {
        match.base + min(match.quality, 1) * Tier.maxQualityReward
    }

    private static func match(in text: String, query: String) -> Match? {
        let haystack = Array(text.precomposedStringWithCanonicalMapping)
        let needle = Array(query.precomposedStringWithCanonicalMapping)

        guard let found = bestMatch(in: haystack, needle: needle) else { return nil }

        let reward = quality(of: found, needleCount: needle.count)

        if haystack.count == needle.count {
            return Match(base: Tier.exact, quality: 0)
        }
        if found.isContiguous, found.range.lowerBound == 0 {
            return Match(base: Tier.prefix, quality: reward)
        }
        if found.isContiguous, startsWord(in: haystack, at: found.range.lowerBound) {
            return Match(base: Tier.wordStart, quality: reward)
        }
        if found.isContiguous {
            return Match(base: Tier.substring, quality: reward)
        }
        return Match(base: Tier.subsequence, quality: reward)
    }

    /// Two ingredients, each in `0...1`: how tightly the matched span hugs the
    /// query, and how much of the query arrived in one unbroken run.
    private static func quality(of hit: SubsequenceHit, needleCount: Int) -> Double {
        let span = hit.range.upperBound - hit.range.lowerBound
        let compactness = Double(needleCount) / Double(span)
        let runReward = Double(hit.longestRun) / Double(needleCount)
        return min(1, 0.5 * compactness + 0.5 * runReward)
    }

    // MARK: - Matching

    private struct SubsequenceHit {
        /// Span from the first to the last matched character, inclusive.
        let range: Range<Int>
        /// Longest run of characters that matched back-to-back.
        let longestRun: Int
        /// True when the whole needle matched as one unbroken run.
        var isContiguous: Bool { longestRun == range.count }
    }

    /// Finds `needle` in `haystack` in order, case-insensitively.
    ///
    /// Tries a contiguous span first (best compactness), then falls back to a
    /// greedy subsequence. Returns `nil` when the letters cannot be found in
    /// order.
    private static func bestMatch(in haystack: [Character], needle: [Character]) -> SubsequenceHit? {
        if let range = contiguousRange(in: haystack, needle: needle) {
            return SubsequenceHit(range: range, longestRun: needle.count)
        }
        return greedySubsequence(in: haystack, needle: needle)
    }

    private static func contiguousRange(in haystack: [Character], needle: [Character]) -> Range<Int>? {
        guard needle.count <= haystack.count else { return nil }

        let lastStart = haystack.count - needle.count
        for start in 0...lastStart {
            var matched = true
            for offset in 0..<needle.count where !charactersEqual(haystack[start + offset], needle[offset]) {
                matched = false
                break
            }
            if matched { return start..<(start + needle.count) }
        }
        return nil
    }

    private static func greedySubsequence(in haystack: [Character], needle: [Character]) -> SubsequenceHit? {
        var positions: [Int] = []
        positions.reserveCapacity(needle.count)

        var searchStart = 0
        for needleChar in needle {
            var position = searchStart
            while position < haystack.count, !charactersEqual(haystack[position], needleChar) {
                position += 1
            }
            guard position < haystack.count else { return nil }
            positions.append(position)
            searchStart = position + 1
        }

        guard let first = positions.first, let last = positions.last else { return nil }

        var longestRun = 1
        var currentRun = 1
        for index in 1..<positions.count {
            if positions[index] == positions[index - 1] + 1 {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 1
            }
        }

        return SubsequenceHit(range: first..<(last + 1), longestRun: longestRun)
    }

    private static func charactersEqual(_ lhs: Character, _ rhs: Character) -> Bool {
        String(lhs).compare(String(rhs), options: .caseInsensitive) == .orderedSame
    }

    /// True when `index` is the start of a word: the beginning of the text, a
    /// non-letter/digit boundary, or a camelCase hump.
    private static func startsWord(in text: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }

        let previous = text[index - 1]
        if !previous.isLetter && !previous.isNumber { return true }

        let current = text[index]
        return previous.isLowercase && current.isUppercase
    }
}
