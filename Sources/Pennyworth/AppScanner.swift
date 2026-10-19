import AppKit

/// Scans the well-known application directories for .app bundles.
///
/// Deliberately shallow: only the top level of each directory. Recursive
/// scanning and Spotlight integration come later.
enum AppScanner {
    private static var searchDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
        ]
    }

    static func scanInstalledApplications() -> [AppItem] {
        searchDirectories
            .flatMap(scanDirectory(_:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func scanDirectory(_ directory: URL) -> [AppItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "app" }
            .map { url in
                // displayName is localized (e.g. "活动监视器" for Activity Monitor)
                let displayName = FileManager.default.displayName(atPath: url.path)
                let name = displayName.replacingOccurrences(of: ".app", with: "")
                return AppItem(name: name, url: url)
            }
    }
}
