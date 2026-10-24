import AppKit

/// A launchable application on disk. Immutable value type.
struct AppItem: Equatable {
    /// Localized display name, e.g. "活动监视器" on a Chinese system.
    let name: String
    let url: URL
    /// Other names the app is known by: the bundle's raw file name and
    /// localized variants loaded from its resources. Never contains `name` itself.
    let aliases: [String]

    init(name: String, url: URL, aliases: [String] = []) {
        self.name = name
        self.url = url
        self.aliases = AppItem.normalizedAliases(aliases, excluding: name)
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func normalizedAliases(_ aliases: [String], excluding name: String) -> [String] {
        let nameKey = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        var seen = Set<String>()

        return aliases.compactMap { alias in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil
            )
            guard key != nameKey, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }
}
