import Foundation
import Darwin

@MainActor
final class BookmarkStore {
    private struct State: Codable {
        var preferences = BookmarkPreferences()
        var profiles: [ChromeProfile] = []
        var snapshots: [String: BookmarkSnapshot] = [:]
    }

    private var state = State()
    private let fileURL: URL
    private var refreshGeneration = 0
    private(set) var warning: String?
    var onChange: (() -> Void)?

    var preferences: BookmarkPreferences { state.preferences }
    var profiles: [ChromeProfile] { state.profiles }
    var snapshots: [String: BookmarkSnapshot] { state.snapshots }
    var searchableEntries: [BookmarkEntry] {
        guard preferences.enabled else { return [] }
        return profiles.filter(\.selected).flatMap { snapshots[$0.id]?.entries ?? [] }
    }

    static var defaultChromeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pennyworth/bookmarks.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode(State.self, from: ChromeBookmarkReader.readData(self.fileURL))
            guard Set(saved.profiles.map(\.id)).count == saved.profiles.count,
                  saved.profiles.allSatisfy({ $0.id.hasPrefix("/") && !$0.id.contains("\0") }),
                  saved.snapshots.values.allSatisfy({ $0.entries.allSatisfy { ActionExecutor.isAllowedWebURL($0.url) } }) else {
                throw BookmarkError.invalid("书签缓存内容无效。")
            }
            state = saved
        } catch {
            warning = "本地书签数据无法读取，未载入缓存：\(error.localizedDescription)"
        }
    }

    func updatePreferences(_ value: BookmarkPreferences) throws {
        var next = state
        next.preferences = value
        try commit(next)
    }

    func setSelected(_ selected: Bool, profileID: String) throws {
        guard let index = state.profiles.firstIndex(where: {
            $0.id == profileID || URL(fileURLWithPath: $0.id).resolvingSymlinksInPath().path
                == URL(fileURLWithPath: profileID).resolvingSymlinksInPath().path
        }) else {
            throw BookmarkError.invalid("未找到该 Chrome 个人资料，请重新检测。")
        }
        var next = state
        next.profiles[index].selected = selected
        try commit(next)
    }

    func discoverProfiles(root: URL) async throws {
        do {
            let discovered = try await Task.detached(priority: .userInitiated) {
                try ChromeBookmarkReader.discover(root: root)
            }.value
            guard !discovered.isEmpty else { throw BookmarkError.invalid("此目录没有可用的 Chrome 个人资料。请选择 Chrome 数据目录。") }
            var next = state
            for profile in discovered {
                if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) {
                    next.profiles[index] = ChromeProfile(id: profile.id, name: profile.name, selected: next.profiles[index].selected)
                } else {
                    next.profiles.append(profile)
                }
            }
            try commit(next)
        } catch {
            warning = error.localizedDescription
            onChange?()
            throw error
        }
    }

    func refreshSelected() async throws {
        let selected = profiles.filter(\.selected)
        guard !selected.isEmpty else { throw BookmarkError.invalid("请先选择要导入的 Chrome 个人资料。") }
        refreshGeneration += 1
        let generation = refreshGeneration
        let outcomes = await Task.detached(priority: .userInitiated) {
            selected.map { profile -> (String, BookmarkSnapshot?, String?) in
                do { return (profile.id, try ChromeBookmarkReader.snapshot(profile: profile), nil) }
                catch { return (profile.id, nil, "\(profile.name)：\(error.localizedDescription)") }
            }
        }.value
        // A clear or newer refresh wins over an older background read.
        guard generation == refreshGeneration else { return }
        var next = state
        var failures: [String] = []
        var succeeded = false
        for (id, snapshot, error) in outcomes {
            if let snapshot { next.snapshots[id] = snapshot; succeeded = true }
            if let error { failures.append(error) }
        }
        do {
            if succeeded { try commit(next) }
        } catch {
            warning = "无法保存书签，保留上次数据：\(error.localizedDescription)"
            onChange?()
            throw error
        }
        if !failures.isEmpty {
            warning = failures.joined(separator: "\n")
            onChange?()
            throw BookmarkError.invalid(warning!)
        }
    }

    func clearImportedData() throws {
        var next = state
        next.snapshots = [:]
        try commit(next)
        refreshGeneration += 1
    }

    private func commit(_ next: State) throws {
        let data = try JSONEncoder().encode(next)
        guard data.count <= ChromeBookmarkReader.maxBytes else { throw BookmarkError.invalid("书签缓存超过 32 MB 限制。") }
        let fm = FileManager.default
        let parent = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let temporary = parent.appendingPathComponent(".bookmarks-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw BookmarkError.invalid("无法创建私有书签缓存文件。")
        }
        defer { try? fm.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        let result = temporary.path.withCString { source in
            fileURL.path.withCString { destination in Darwin.rename(source, destination) }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        state = next
        warning = nil
        onChange?()
    }
}
