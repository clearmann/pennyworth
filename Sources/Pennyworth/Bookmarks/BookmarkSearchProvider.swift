import Foundation

enum BookmarkSearchProvider {
    static func results(entries: [BookmarkEntry], query: String, preferences: BookmarkPreferences,
                        limit: Int = 50) -> [SearchResult] {
        guard limit > 0 else { return [] }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = Dictionary(grouping: entries.filter { ActionExecutor.isAllowedWebURL($0.url) }, by: { $0.url.absoluteString })
        let ranked: [(BookmarkEntry, Double, [BookmarkEntry])] = groups.values.compactMap { group in
            let scored = group.compactMap { entry -> (BookmarkEntry, Double)? in
                if query.isEmpty { return (entry, 0) }
                let fields: [(Bool, String, Double)] = [
                    (preferences.matchTitle, entry.title, 20_000),
                    (preferences.matchURL, entry.url.absoluteString, 10_000),
                    (preferences.matchFolders, entry.folderPath, 0)
                ]
                for (enabled, text, bonus) in fields where enabled {
                    if let score = FuzzyMatcher.score(item: AppItem(name: text, url: entry.url), query: query) {
                        return (entry, bonus + score)
                    }
                }
                return nil
            }.sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.title.localizedStandardCompare(rhs.0.title) == .orderedAscending : lhs.1 > rhs.1
            }
            guard let best = scored.first else { return nil }
            return (best.0, best.1, group)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            let comparison = lhs.0.title.localizedStandardCompare(rhs.0.title)
            return comparison == .orderedSame ? lhs.0.url.absoluteString < rhs.0.url.absoluteString : comparison == .orderedAscending
        }.prefix(limit).map { entry, _, group in
            let sources = Set(group.map { "Chrome／" + $0.sourceName + ($0.folderPath.isEmpty ? "" : " · " + $0.folderPath) }).sorted()
            return SearchResult(id: "bookmark:" + entry.url.absoluteString, title: entry.title,
                                subtitle: ([entry.url.host ?? entry.url.absoluteString] + sources).joined(separator: " · "),
                                symbol: "bookmark", action: .openURL(entry.url))
        }
    }
}
