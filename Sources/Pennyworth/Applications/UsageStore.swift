import Foundation
import os

final class UsageStore {
    private struct Entry: Codable {
        let count: Int
        let lastUsed: Date
    }
    private static let key = "launcher.usage.v1"
    private let defaults: UserDefaults
    private let now: () -> Date
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        do {
            entries = try defaults.data(forKey: Self.key).map {
                try JSONDecoder().decode([String: Entry].self, from: $0)
            } ?? [:]
        } catch {
            entries = [:]
            Logger(subsystem: "com.clearmann.pennyworth", category: "Usage").error("使用记录损坏，已忽略")
        }
    }

    func record(_ url: URL) throws {
        let key = url.standardizedFileURL.path
        let count = min(entries[key]?.count ?? 0, 9999) + 1
        let updated = entries.merging([key: Entry(count: count, lastUsed: now())]) { _, new in new }
        defaults.set(try JSONEncoder().encode(updated), forKey: Self.key)
        entries = updated
    }

    func bonus(for url: URL) -> Double {
        guard let entry = entries[url.standardizedFileURL.path], entry.count > 0 else { return 0 }
        let days = max(0, now().timeIntervalSince(entry.lastUsed) / 86400)
        return min(0.99, Double(entry.count) / Double(entry.count + 5) * 0.6 + 0.39 / (1 + days))
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
        entries = [:]
    }
}

enum ApplicationSearchProvider {
    static func results(items: [AppItem], query: String, usage: UsageStore, enabled: Bool) -> [SearchResult] {
        items.compactMap { item -> (AppItem, Double)? in
            guard let score = query.isEmpty ? 0 : FuzzyMatcher.score(item: item, query: query) else { return nil }
            return (item, score + (enabled ? usage.bonus(for: item.url) : 0))
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let order = $0.0.name.localizedStandardCompare($1.0.name)
            return order == .orderedSame ? $0.0.url.path < $1.0.url.path : order == .orderedAscending
        }.prefix(49).map { item, _ in
            SearchResult(id: "app:\(item.url.path)", title: item.name, subtitle: item.url.path,
                         symbol: "app", action: .openApplication(item.url))
        }
    }
}
