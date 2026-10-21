@testable import Pennyworth
import XCTest

final class BookmarkCoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeBookmarks(_ profile: URL, name: String = "Bookmarks", title: String = "GitHub") throws {
        let object: [String: Any] = ["roots": ["bookmark_bar": ["type": "folder", "name": "开发", "children": [
            ["type": "url", "id": "1", "name": title, "url": "https://github.com"],
            ["type": "url", "id": "2", "name": "Unsafe", "url": "javascript:alert(1)"]
        ]]]]
        try JSONSerialization.data(withJSONObject: object).write(to: profile.appendingPathComponent(name))
    }

    @MainActor func testImportRefreshPersistenceAndSelection() async throws {
        let root = try temporaryDirectory()
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try writeBookmarks(profile)
        try writeBookmarks(profile, name: "AccountBookmarks", title: "Account")
        let file = root.appendingPathComponent("state/bookmarks.json")
        let store = BookmarkStore(fileURL: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try await store.discoverProfiles(root: root)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertFalse(store.profiles[0].selected)
        try store.setSelected(true, profileID: profile.path)
        try store.updatePreferences(BookmarkPreferences(enabled: true))
        try await store.refreshSelected()
        XCTAssertEqual(store.searchableEntries.count, 2)
        XCTAssertEqual(store.snapshots[profile.path]?.skippedCount, 2)
        XCTAssertEqual(store.searchableEntries[0].folderPath, "开发")
        try await store.refreshSelected()
        XCTAssertEqual(store.searchableEntries.count, 2)
        let restored = BookmarkStore(fileURL: file)
        XCTAssertEqual(restored.searchableEntries.count, 2)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try store.setSelected(false, profileID: profile.path)
        XCTAssertTrue(store.searchableEntries.isEmpty)
        try store.clearImportedData()
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path))
    }

    @MainActor func testCorruptRefreshPreservesLastSnapshotAndEncryptedIsNotEmptySuccess() async throws {
        let root = try temporaryDirectory()
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try writeBookmarks(profile)
        let store = BookmarkStore(fileURL: root.appendingPathComponent("state.json"))
        try await store.discoverProfiles(root: root)
        try store.setSelected(true, profileID: profile.path)
        try await store.refreshSelected()
        try Data(#"{"roots":{}}"#.utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        do { try await store.refreshSelected(); XCTFail("Malformed roots must fail") } catch { }
        XCTAssertEqual(store.snapshots[profile.path]?.entries.count, 1)
        try FileManager.default.removeItem(at: profile.appendingPathComponent("Bookmarks"))
        try Data().write(to: profile.appendingPathComponent("EncryptedBookmarks2"))
        do { try await store.refreshSelected(); XCTFail("Encrypted sources must fail") } catch { }
        XCTAssertEqual(store.snapshots[profile.path]?.entries.count, 1)
    }

    @MainActor func testPersistenceFailureDoesNotChangeMemory() throws {
        let root = try temporaryDirectory()
        let obstruction = root.appendingPathComponent("file")
        try Data().write(to: obstruction)
        let store = BookmarkStore(fileURL: obstruction.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try store.updatePreferences(BookmarkPreferences(enabled: true)))
        XCTAssertFalse(store.preferences.enabled)
    }

    @MainActor func testDiscoveryRetainsSelectionAndRejectsEscapingSymlink() async throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Profile 1"), withDestinationURL: outside)
        let store = BookmarkStore(fileURL: root.appendingPathComponent("state.json"))
        try await store.discoverProfiles(root: root)
        XCTAssertEqual(store.profiles.count, 1)
        try store.setSelected(true, profileID: profile.path)
        try await store.discoverProfiles(root: root)
        XCTAssertTrue(store.profiles[0].selected)
    }

    func testSearchFieldPriorityDedupAndBounds() {
        let entries = [
            BookmarkEntry(id: "1", title: "GitHub", url: URL(string: "https://example.com")!, folderPath: "开发", sourceID: "a", sourceName: "个人"),
            BookmarkEntry(id: "2", title: "Other", url: URL(string: "https://github.com")!, folderPath: "Work", sourceID: "b", sourceName: "工作"),
            BookmarkEntry(id: "3", title: "Duplicate", url: URL(string: "https://example.com")!, folderPath: "Shared", sourceID: "b", sourceName: "工作")
        ]
        let results = BookmarkSearchProvider.results(entries: entries, query: "github", preferences: BookmarkPreferences())
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.title, "GitHub")
        XCTAssertTrue(results[0].subtitle.contains("Shared"))
        XCTAssertTrue(results[0].subtitle.contains("个人"))
        XCTAssertEqual(BookmarkSearchProvider.results(entries: entries, query: "", preferences: BookmarkPreferences(), limit: 1).count, 1)
        XCTAssertTrue(BookmarkSearchProvider.results(entries: entries, query: "", preferences: BookmarkPreferences(), limit: 0).isEmpty)
        var prefs = BookmarkPreferences()
        prefs.matchTitle = false; prefs.matchURL = false; prefs.matchFolders = true
        XCTAssertEqual(BookmarkSearchProvider.results(entries: entries, query: "开发", preferences: prefs).count, 1)
    }
}
