import Foundation

struct BookmarkPreferences: Codable, Equatable {
    var enabled = false
    var includeInDefaultResults = true
    var matchTitle = true
    var matchURL = true
    var matchFolders = true
}

struct ChromeProfile: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    var selected: Bool
}

struct BookmarkEntry: Codable, Equatable {
    let id: String
    let title: String
    let url: URL
    let folderPath: String
    let sourceID: String
    let sourceName: String
}

struct BookmarkSnapshot: Codable {
    let entries: [BookmarkEntry]
    let importedAt: Date
    let skippedCount: Int
}

enum BookmarkError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum ChromeBookmarkReader {
    static let maxBytes = 32 * 1024 * 1024
    static let maxNodes = 100_000
    static let maxDepth = 64

    static func readData(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw BookmarkError.invalid("书签文件超过 32 MB 限制。") }
        return data
    }

    static func discover(root: URL) throws -> [ChromeProfile] {
        // Keep the user's path spelling for stable profile IDs; resolve only
        // when checking containment so /var and /private/var remain equivalent.
        let root = root.standardizedFileURL
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var names: [String: String] = [:]
        let state = root.appendingPathComponent("Local State")
        if FileManager.default.fileExists(atPath: state.path), isContained(state, in: root),
           let data = try? readData(state),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let profile = json["profile"] as? [String: Any],
           let info = profile["info_cache"] as? [String: [String: Any]] {
            for (key, value) in info { names[key] = value["name"] as? String }
        }
        return urls.filter { url in
            let name = url.lastPathComponent
            guard name == "Default" || name.hasPrefix("Profile ") else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let type = attrs?[.type] as? FileAttributeType
            return type != .typeSymbolicLink && isContained(url, in: root)
        }.map {
            let stableID = root.appendingPathComponent($0.lastPathComponent, isDirectory: true).standardizedFileURL.path
            return ChromeProfile(id: stableID, name: names[$0.lastPathComponent] ?? $0.lastPathComponent, selected: false)
        }
            .sorted { $0.id < $1.id }
    }

    static func isContained(_ url: URL, in directory: URL) -> Bool {
        url.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/")
    }

    static func snapshot(profile: ChromeProfile) throws -> BookmarkSnapshot {
        let directory = URL(fileURLWithPath: profile.id, isDirectory: true).standardizedFileURL
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw BookmarkError.invalid("个人资料路径已变为符号链接，请重新选择。")
        }
        let fm = FileManager.default
        let encrypted = ["EncryptedBookmarks2", "EncryptedAccountBookmarks2"].contains {
            fm.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        guard !encrypted else { throw BookmarkError.invalid("检测到 Chrome 加密书签，当前不支持读取；保留上次导入的数据。") }
        let files = ["Bookmarks", "AccountBookmarks"].map { directory.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { throw BookmarkError.invalid("未找到 Chrome 书签文件。") }
        var entries: [BookmarkEntry] = []
        var skipped = 0
        var nodes = 0
        for file in files {
            guard isContained(file, in: directory) else { throw BookmarkError.invalid("书签文件不能指向个人资料目录之外。") }
            let json = try JSONSerialization.jsonObject(with: readData(file))
            guard let object = json as? [String: Any], let roots = object["roots"] as? [String: Any],
                  roots["bookmark_bar"] != nil else { throw BookmarkError.invalid("Chrome 书签结构无效。") }
            for key in ["bookmark_bar", "other", "synced"] {
                guard let root = roots[key] else { continue }
                guard let root = root as? [String: Any], root["type"] as? String == "folder" else {
                    throw BookmarkError.invalid("Chrome 书签根文件夹无效。")
                }
                try visit(root, folders: [], depth: 0, identity: file.lastPathComponent + "/" + key,
                          profile: profile, entries: &entries, skipped: &skipped, nodes: &nodes)
            }
        }
        return BookmarkSnapshot(entries: entries, importedAt: Date(), skippedCount: skipped)
    }

    private static func visit(_ node: [String: Any], folders: [String], depth: Int, identity: String,
                              profile: ChromeProfile, entries: inout [BookmarkEntry], skipped: inout Int,
                              nodes: inout Int) throws {
        nodes += 1
        guard depth <= maxDepth, nodes <= maxNodes else { throw BookmarkError.invalid("书签层级或数量超过安全限制。") }
        guard let type = node["type"] as? String, let name = node["name"] as? String else {
            throw BookmarkError.invalid("Chrome 书签条目结构无效。")
        }
        switch type {
        case "folder":
            guard let children = node["children"] as? [[String: Any]] else { throw BookmarkError.invalid("书签文件夹缺少有效内容。") }
            let path = name.isEmpty ? folders : folders + [name]
            for (index, child) in children.enumerated() {
                try visit(child, folders: path, depth: depth + 1, identity: identity + "/\(index)",
                          profile: profile, entries: &entries, skipped: &skipped, nodes: &nodes)
            }
        case "url":
            guard let text = node["url"] as? String else { throw BookmarkError.invalid("书签缺少网址。") }
            guard let url = URL(string: text), ActionExecutor.isAllowedWebURL(url) else { skipped += 1; return }
            entries.append(BookmarkEntry(id: profile.id + "/" + identity, title: name.isEmpty ? (url.host ?? text) : name,
                                         url: url, folderPath: folders.joined(separator: " / "),
                                         sourceID: profile.id, sourceName: profile.name))
        default: throw BookmarkError.invalid("书签包含不支持的条目结构。")
        }
    }
}
