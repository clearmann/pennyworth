@testable import Pennyworth
import XCTest
import Darwin

/// Exercises `AppScanner.scan(directories:)` against throwaway trees so the
/// tests never depend on what is installed on the machine.
final class AppScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func makeApp(_ relativePath: String, in base: URL? = nil) throws -> URL {
        let url = (base ?? root).appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func makeDirectory(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Discovery

    func testFindsTopLevelApps() throws {
        try makeApp("Safari.app")
        try makeApp("Mail.app")

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(Set(items.map(\.name)), ["Safari", "Mail"])
    }

    func testRecursesIntoUtilitiesDirectory() throws {
        try makeApp("Utilities/Activity Monitor.app")

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Activity Monitor"])
        XCTAssertEqual(
            items.first?.url,
            root.appendingPathComponent("Utilities/Activity Monitor.app").standardizedFileURL
        )
    }

    func testRecursesSeveralLevelsDeep() throws {
        try makeApp("Vendor/Suite/Tools/Deep.app", in: root.appendingPathComponent("Utilities"))

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Deep"])
    }

    func testIgnoresFilesAndNonAppBundles() throws {
        try makeApp("Real.app")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Framework.framework"),
            withIntermediateDirectories: true
        )
        try Data("not an app".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Real"])
    }

    func testDoesNotDescendIntoAppBundles() throws {
        // Tools nested inside an .app must not surface as separate launchables.
        try makeApp("Outer.app/Contents/Resources/Inner.app")

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Outer"])
    }

    func testSkipsHiddenEntries() throws {
        try makeApp("Visible.app")
        try makeApp(".Hidden.app")

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Visible"])
    }

    func testDoesNotFollowSymbolicLinks() throws {
        let realDirectory = try makeDirectory("Real")
        try makeApp("Linked.app", in: realDirectory)

        let link = root.appendingPathComponent("Links")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realDirectory)

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Linked"])
    }

    func testFindsAppLinkedFromOutsideSearchRootWithoutWalkingLinkedDirectories() throws {
        let apps = try makeDirectory("Applications")
        let realApp = try makeApp("System/Safari.app")
        let link = apps.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realApp)
        XCTAssertEqual(lchflags(link.path, UInt32(UF_HIDDEN)), 0)
        defer { _ = lchflags(link.path, 0) }
        XCTAssertEqual(try link.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)
        try FileManager.default.createSymbolicLink(at: apps.appendingPathComponent("Loop"), withDestinationURL: apps)
        let items = AppScanner.scan(directories: [apps])
        XCTAssertEqual(items.map(\.name), ["Safari"])
        XCTAssertEqual(items.first?.url.resolvingSymlinksInPath(), realApp.resolvingSymlinksInPath())
        XCTAssertNotNil(items.first.flatMap { FuzzyMatcher.score(item: $0, query: "sfr") })
    }

    func testDeduplicatesSymlinkedBundles() throws {
        let realDirectory = try makeDirectory("Real")
        let realApp = try makeApp("Target.app", in: realDirectory)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Alias.app"),
            withDestinationURL: realApp
        )

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Target"])
    }

    func testBrokenAppLinksAndPlainFilesAreNotApplications() throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Broken.app"),
                                                 withDestinationURL: root.appendingPathComponent("Missing.app"))
        try Data("not a bundle".utf8).write(to: root.appendingPathComponent("Plain.app"))
        XCTAssertTrue(AppScanner.scan(directories: [root]).isEmpty)
    }

    // MARK: - Deduplication

    func testDeduplicatesWhenRootsOverlap() throws {
        let realApp = try makeApp("Safari.app")

        // The same tree reached twice: directly, and through "Nested/..".
        let nested = try makeDirectory("Nested")
        let aliasRoot = nested.appendingPathComponent("..", isDirectory: true)

        let items = AppScanner.scan(directories: [root, aliasRoot])

        XCTAssertEqual(items.map(\.url), [realApp])
    }

    func testDeduplicatesBundleReachedThroughSymlinkedRoot() throws {
        let realApp = try makeApp("Safari.app")
        let link = root.deletingLastPathComponent()
            .appendingPathComponent("AppScannerTests-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: link) }

        let items = AppScanner.scan(directories: [root, link])

        XCTAssertEqual(items.map(\.url), [realApp])
    }

    func testDuplicateDirectoryRootsDoNotDuplicateItems() throws {
        try makeApp("Safari.app")

        let items = AppScanner.scan(directories: [root, root, root.standardizedFileURL])

        XCTAssertEqual(items.count, 1)
    }

    func testSameNameAtDifferentPathsAreBothKept() throws {
        let systemUtilities = try makeDirectory("System/Utilities")
        try makeApp("Utilities.app")
        try makeApp("Utilities.app", in: systemUtilities)

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.name)), ["Utilities"])
        XCTAssertEqual(Set(items.map(\.url)).count, 2)
    }

    // MARK: - Naming and aliases

    func testStripsAppExtensionFromName() throws {
        try makeApp("Visual Studio Code.app")

        let item = try XCTUnwrap(AppScanner.scan(directories: [root]).first)

        XCTAssertEqual(item.name, "Visual Studio Code")
        XCTAssertEqual(item.url.lastPathComponent, "Visual Studio Code.app")
    }

    func testFindsBundlesWithUppercaseExtension() throws {
        try makeApp("Loud.APP")

        let items = AppScanner.scan(directories: [root])

        XCTAssertEqual(items.map(\.name), ["Loud"])
    }

    func testRawFileNameIsExposedAsAliasForLocalizedNames() throws {
        // On an English system the display name equals the file name, so the
        // alias set collapses to empty; on a localized system the raw name is
        // kept so both spellings match.
        try makeApp("Activity Monitor.app")

        let item = try XCTUnwrap(AppScanner.scan(directories: [root]).first)
        let displayName = FileManager.default.displayName(atPath: item.url.path)
            .replacingOccurrences(of: ".app", with: "")

        XCTAssertEqual(item.name, displayName)
        if displayName == "Activity Monitor" {
            XCTAssertEqual(item.aliases, [])
        } else {
            XCTAssertEqual(item.aliases, ["Activity Monitor"])
        }
    }

    // MARK: - Ordering

    func testResultsAreSortedByLocalizedName() throws {
        try makeApp("Zoom.app")
        try makeApp("Activity Monitor.app")
        try makeApp("safari.app")

        let names = AppScanner.scan(directories: [root]).map(\.name)

        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(names.first, "Activity Monitor")
    }

    // MARK: - Missing directories

    func testMissingDirectoryYieldsNoItemsWithoutCrashing() {
        let missing = root.appendingPathComponent("DoesNotExist", isDirectory: true)

        XCTAssertEqual(AppScanner.scan(directories: [missing]), [])
    }

    func testEmptyDirectoryListYieldsNoItems() {
        XCTAssertEqual(AppScanner.scan(directories: []), [])
    }

    func testDefaultDirectoriesCoverSystemAndUserApplications() {
        let paths = AppScanner.defaultDirectories.map(\.path)

        XCTAssertTrue(paths.contains("/Applications"))
        XCTAssertTrue(paths.contains("/System/Applications"))
        XCTAssertTrue(paths.contains("\(NSHomeDirectory())/Applications"))
        XCTAssertEqual(paths.count, 3)
    }
}
