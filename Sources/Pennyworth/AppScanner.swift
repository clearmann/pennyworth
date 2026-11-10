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

    static func scanInstalledApplications(language: AppLanguage = .system) -> [AppItem] {
        scan(directories: defaultDirectories, language: language)
    }

    /// Scans `directories` (and their non-package subdirectories) for `.app` bundles.
    ///
    /// Results are deduplicated by standard URL — so an overlapping or repeated
    /// directory cannot surface an app twice — and sorted by localized name.
    /// Apps sharing a display name at different paths are all kept.
    static func scan(directories: [URL], language: AppLanguage = .system) -> [AppItem] {
        var seenURLs = Set<URL>()
        var items: [AppItem] = []

        for directory in directories {
            for bundleURL in applicationBundles(under: directory.standardizedFileURL) {
                // Key on the resolved path so the same bundle reached through
                // different roots is reported once, while `url` keeps the path
                // it was actually found at.
                let identity = bundleURL.resolvingSymlinksInPath().standardizedFileURL
                guard seenURLs.insert(identity).inserted else { continue }
                items.append(makeItem(for: bundleURL.standardizedFileURL, language: language))
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

    private static func makeItem(for url: URL, language: AppLanguage) -> AppItem {
        let rawName = url.deletingPathExtension().lastPathComponent
        let names = localizedNames(for: url)
        let displayName: String
        if language == .system {
            displayName = FileManager.default.displayName(atPath: url.path)
        } else {
            let infoPlistNames = localizedInfoPlistNames(for: url, language: language)
            displayName = preferredName(in: names, language: language) ?? infoPlistNames?["CFBundleDisplayName"]
                ?? infoPlistNames?["CFBundleName"] ?? rawName
        }
        let localizedName = strippingAppExtension(from: displayName)
        let name = localizedName.isEmpty ? rawName : localizedName
        let aliases = names.keys.sorted().flatMap { names[$0]?.values.sorted() ?? [] }

        return AppItem(name: name, url: url, aliases: [rawName] + aliases)
    }

    /// Reads display names embedded by modern macOS apps. Unlike
    /// `FileManager.displayName`, these remain available when the process was
    /// launched with a different localization environment.
    private static func localizedNames(for url: URL) -> [String: [String: String]] {
        let tableURL = url.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        guard FileManager.default.fileExists(atPath: tableURL.path) else { return [:] }

        do {
            let data = try Data(contentsOf: tableURL)
            let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
            guard let table = propertyList as? [String: Any] else { return [:] }
            return Dictionary(uniqueKeysWithValues: table.compactMap { locale, value in
                guard let values = value as? [String: Any] else { return nil }
                let names = ["CFBundleDisplayName", "CFBundleName"].reduce(into: [String: String]()) { result, key in
                    if let name = values[key] as? String { result[key] = name }
                }
                return names.isEmpty ? nil : (locale, names)
            })
        } catch {
            logger.error(
                "Cannot read localized application names: \(tableURL.path, privacy: .private) — \(error.localizedDescription, privacy: .private)"
            )
            return [:]
        }
    }

    private static func preferredName(in names: [String: [String: String]], language: AppLanguage) -> String? {
        let candidates = language == .simplifiedChinese
            ? ["zh-Hans", "zh-Hans-CN", "zh_CN", "zh-CN", "zh-SG"]
            : ["en", "en-US", "en_US", "en-GB", "en_GB", "Base"]
        for candidate in candidates {
            guard let locale = names.keys.first(where: { $0.lowercased() == candidate.lowercased() }) else { continue }
            if let name = names[locale]?["CFBundleDisplayName"] ?? names[locale]?["CFBundleName"] {
                return name
            }
        }
        return nil
    }

    private static func localizedInfoPlistNames(for url: URL, language: AppLanguage) -> [String: String]? {
        guard let bundle = Bundle(url: url) else { return nil }
        let identifier = language.resolvedIdentifier()
        let candidates = language == .simplifiedChinese ? [identifier, "zh_CN", "zh-CN"] : [identifier, "en-US", "Base"]
        for candidate in candidates {
            guard let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil,
                                         forLocalization: candidate),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let names = plist as? [String: String] else { continue }
            return names
        }
        return nil
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
