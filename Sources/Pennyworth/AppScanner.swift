import AppKit
import os

/// Scans the well-known application directories for .app bundles.
///
/// The walk is recursive but bounded: it descends into plain directories such
/// as `Utilities`, and stops at any bundle or package (`.app`, `.framework`,
/// `.bundle`, …) so it never crawls inside an application. App symlinks are
/// resolved as leaves; directory links are never traversed.
enum AppScanner {
    private static let logger = Logger(subsystem: "com.pennyworth.launcher", category: "AppScanner")

    /// Directories scanned by `scanInstalledApplications()`.
    static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
        ]
    }

    static func scanInstalledApplications() -> [AppItem] {
        scan(directories: defaultDirectories)
    }

    /// Scans `directories` (and their non-package subdirectories) for `.app` bundles.
    ///
    /// Results are deduplicated by standard URL — so an overlapping or repeated
    /// directory cannot surface an app twice — and sorted by localized name.
    /// Apps sharing a display name at different paths are all kept.
    static func scan(directories: [URL]) -> [AppItem] {
        var seenURLs = Set<URL>()
        var items: [AppItem] = []

        for directory in directories {
            for bundleURL in applicationBundles(under: directory.standardizedFileURL) {
                // Key on the resolved path so the same bundle reached through
                // different roots is reported once, while `url` keeps the path
                // it was actually found at.
                let identity = bundleURL.resolvingSymlinksInPath().standardizedFileURL
                guard seenURLs.insert(identity).inserted else { continue }
                items.append(makeItem(for: bundleURL.standardizedFileURL))
            }
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Directory walk

    private static func applicationBundles(under directory: URL) -> [URL] {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isHiddenKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            // Surface the failure instead of silently returning "no apps here":
            // a missing permission would otherwise look like an empty folder.
            // Both values stay private — a home-relative path can contain the
            // user's account name.
            logger.error(
                "Cannot read applications directory: \(directory.path, privacy: .private) — \(error.localizedDescription, privacy: .private)"
            )
            return []
        }

        return entries.flatMap { bundles(in: $0) }
    }

    private static func bundles(in entry: URL) -> [URL] {
        let values = try? entry.resourceValues(forKeys: [.isHiddenKey, .isSymbolicLinkKey])
        guard values?.isHidden != true || values?.isSymbolicLink == true else { return [] }
        // macOS exposes Safari through a .app symlink outside these roots.
        // Resolve only app leaves; never recurse through directory links.
        if entry.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  (try? resolved.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return [] }
            return [isSymbolicLink(entry) ? resolved : entry]
        }
        guard !isSymbolicLink(entry) else { return [] }

        let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let isPackage = (try? entry.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
        guard isDirectory, !isPackage else { return [] }

        // Plain directory (e.g. "Utilities"); descend. Packages and plain files
        // are skipped so the walk never crawls inside a bundle.
        return applicationBundles(under: entry)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        // `isSymbolicLink` describes the link itself, so it is also true for a
        // dangling link that cannot be resolved.
        if let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink {
            return isLink
        }
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    // MARK: - Item construction

    private static func makeItem(for url: URL) -> AppItem {
        let displayName = FileManager.default.displayName(atPath: url.path)
        let localizedName = strippingAppExtension(from: displayName)
        let rawName = url.deletingPathExtension().lastPathComponent
        let name = localizedName.isEmpty ? rawName : localizedName

        return AppItem(name: name, url: url, aliases: [rawName] + localizedNames(for: url))
    }

    /// Reads display names embedded by modern macOS apps. Unlike
    /// `FileManager.displayName`, these remain available when the process was
    /// launched with a different localization environment.
    private static func localizedNames(for url: URL) -> [String] {
        let tableURL = url.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        guard FileManager.default.fileExists(atPath: tableURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: tableURL)
            let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
            guard let table = propertyList as? [String: Any] else { return [] }
            return table.keys.sorted().flatMap { locale -> [String] in
                guard let values = table[locale] as? [String: Any] else { return [] }
                return ["CFBundleDisplayName", "CFBundleName"].compactMap { values[$0] as? String }
            }
        } catch {
            logger.error(
                "Cannot read localized application names: \(tableURL.path, privacy: .private) — \(error.localizedDescription, privacy: .private)"
            )
            return []
        }
    }

    /// Strips trailing ".app", case-insensitively. Repeated because
    /// `displayName` appends another ".app" to a bundle whose real extension is
    /// uppercase ("Loud.APP" is reported as "Loud.APP.app").
    private static func strippingAppExtension(from name: String) -> String {
        var result = name
        while result.count > 4,
            String(result.suffix(4)).caseInsensitiveCompare(".app") == .orderedSame
        {
            result = String(result.dropLast(4))
        }
        return result
    }
}
