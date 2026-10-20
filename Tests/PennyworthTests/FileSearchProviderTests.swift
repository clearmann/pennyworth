@testable import Pennyworth
import XCTest

final class FileSearchProviderTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/example")
    private let documents = URL(fileURLWithPath: "/Users/example/Documents")

    func testRealMetadataQueryCompletesOrReportsBoundedFailure() async {
        let provider = FileSearchProvider()
        let outcome = await provider.search(query: "pennyworth-no-match-\(UUID())", scopes: [FileManager.default.temporaryDirectory])
        switch outcome {
        case .results(let hits): XCTAssertTrue(hits.isEmpty)
        case .failed(let message): XCTAssertFalse(message.isEmpty)
        default: XCTFail("Expected results or explicit system failure")
        }
    }

    func testRealMetadataQueryCancellationDoesNotHang() async throws {
        let query = SystemMetadataQuery(predicate: NSPredicate(format: "kMDItemFSName == %@", "pennyworth-no-match-\(UUID())"),
                                        scopes: [FileManager.default.temporaryDirectory])
        let task = Task { try await query.execute() }
        try await Task.sleep(nanoseconds: 50_000_000)
        query.cancel()
        do { _ = try await task.value } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testRealMetadataQueryCancelledBeforeStartFinishes() async {
        let query = SystemMetadataQuery(predicate: NSPredicate(value: true), scopes: [FileManager.default.temporaryDirectory])
        query.cancel()
        do { _ = try await query.execute(); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    // MARK: - Scope gating

    func testEmptyScopesReturnNotConfiguredWithoutStartingQuery() async {
        let factory = FakeQueryFactory()
        let provider = FileSearchProvider(factory: factory)

        let outcome = await provider.search(query: "report", scopes: [])

        XCTAssertEqual(outcome, .notConfigured)
        XCTAssertTrue(factory.madeQueries.isEmpty)
    }

    func testNonFileScopesAreDiscardedAndNeverStartQuery() async {
        let factory = FakeQueryFactory()
        let provider = FileSearchProvider(factory: factory)

        let outcome = await provider.search(
            query: "report",
            scopes: [URL(string: "https://example.com/files")!]
        )

        XCTAssertEqual(outcome, .notConfigured)
        XCTAssertTrue(factory.madeQueries.isEmpty)
    }

    func testScopesAreStandardizedAndDeduplicated() {
        let scopes = FileSearchProvider.normalizedScopes([
            documents,
            URL(fileURLWithPath: "/Users/example/Documents/"),
            home,
            URL(string: "https://example.com")!,
        ])

        XCTAssertEqual(scopes.map(\.path), [documents.path, home.path])
    }

    func testBlankQueryDoesNotStartQuery() async {
        let factory = FakeQueryFactory()
        let provider = FileSearchProvider(factory: factory)

        let outcome = await provider.search(query: "   \n", scopes: [documents])

        XCTAssertEqual(outcome, .emptyQuery)
        XCTAssertTrue(factory.madeQueries.isEmpty)
    }

    func testOversizedQueryDoesNotStartQuery() async {
        let factory = FakeQueryFactory()
        let provider = FileSearchProvider(factory: factory)
        let outcome = await provider.search(query: String(repeating: "a", count: 513), scopes: [documents])
        guard case .failed = outcome else { return XCTFail("Expected input limit failure") }
        XCTAssertTrue(factory.madeQueries.isEmpty)
    }

    // MARK: - Filename-only predicate

    func testPredicateTargetsFilenameAttributeOnly() throws {
        let predicate = try XCTUnwrap(FileSearchProvider.predicate(for: "report"))

        XCTAssertTrue(predicate.predicateFormat.contains("kMDItemFSName"))
        XCTAssertFalse(predicate.predicateFormat.contains("kMDItemTextContent"))
        XCTAssertFalse(predicate.predicateFormat.contains("kMDItemContent"))
    }

    func testPredicateTrimsWhitespace() throws {
        let predicate = try XCTUnwrap(FileSearchProvider.predicate(for: "  notes  "))

        XCTAssertTrue(predicate.predicateFormat.contains("\"*notes*\""))
    }

    func testPredicateEscapesLikeWildcards() throws {
        let pattern = try XCTUnwrap(FileSearchProvider.filenamePattern(for: "a*b?c\\d"))

        XCTAssertEqual(pattern, #"*a\*b\?c\\d*"#)
    }

    func testPredicateIsNilForBlankInput() {
        XCTAssertNil(FileSearchProvider.predicate(for: ""))
        XCTAssertNil(FileSearchProvider.predicate(for: " \t "))
    }

    func testFactoryReceivesNormalizedScopesAndPredicate() async {
        let factory = FakeQueryFactory()
        let provider = FileSearchProvider(factory: factory)

        _ = await provider.search(query: "report", scopes: [documents, documents])

        XCTAssertEqual(factory.madeQueries.count, 1)
        XCTAssertEqual(factory.madeQueries.first?.scopes.map(\.path), [documents.path])
        XCTAssertTrue(factory.madeQueries.first?.predicate.predicateFormat.contains("report") == true)
    }

    // MARK: - Result handling

    func testResultsAreFilteredToScopesDeduplicatedSortedAndLimited() async {
        let factory = FakeQueryFactory()
        factory.query.hits = [
            FileSearchHit(url: documents.appendingPathComponent("zeta-report.txt"), displayName: "zeta-report.txt"),
            FileSearchHit(url: documents.appendingPathComponent("alpha-report.txt"), displayName: "alpha-report.txt"),
            FileSearchHit(url: documents.appendingPathComponent("alpha-report.txt"), displayName: "alpha-report.txt"),
            FileSearchHit(url: home.appendingPathComponent("outside-report.txt"), displayName: "outside-report.txt"),
            FileSearchHit(url: URL(string: "https://example.com/report")!, displayName: "report"),
        ]
        let provider = FileSearchProvider(factory: factory, maxResults: 1)

        let outcome = await provider.search(query: "report", scopes: [documents])

        XCTAssertEqual(outcome, .results([
            FileSearchHit(url: documents.appendingPathComponent("alpha-report.txt"), displayName: "alpha-report.txt")
        ]))
    }

    func testRootScopeContainsEveryAbsoluteFileURL() {
        let root = URL(fileURLWithPath: "/")
        let url = URL(fileURLWithPath: "/tmp/report.txt")

        XCTAssertTrue(FileSearchProvider.isContained(url, in: [root]))
    }

    func testSiblingDirectoryIsNotConsideredContained() {
        let scope = URL(fileURLWithPath: "/Users/example/Doc")
        let sibling = URL(fileURLWithPath: "/Users/example/Documents/report.txt")

        XCTAssertFalse(FileSearchProvider.isContained(sibling, in: [scope]))
    }

    func testCancellationOutcome() async {
        let factory = FakeQueryFactory()
        factory.query.error = CancellationError()
        let provider = FileSearchProvider(factory: factory)

        let outcome = await provider.search(query: "report", scopes: [documents])

        XCTAssertEqual(outcome, .cancelled)
    }

    func testFailureOutcome() async {
        struct Boom: LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let factory = FakeQueryFactory()
        factory.query.error = Boom()
        let provider = FileSearchProvider(factory: factory)

        let outcome = await provider.search(query: "report", scopes: [documents])

        XCTAssertEqual(outcome, .failed("boom"))
    }

    // MARK: - Shared result mapping

    func testHitMapsToOpenFileResult() {
        let url = documents.appendingPathComponent("report.txt")
        let result = FileSearchHit(url: url, displayName: "report.txt").searchResult(action: .open)

        XCTAssertEqual(result.id, url.path)
        XCTAssertEqual(result.title, "report.txt")
        XCTAssertEqual(result.subtitle, documents.path)
        XCTAssertEqual(result.action, .openFile(url))
        XCTAssertEqual(result.fileURL, url)
    }

    func testHitMapsToRevealFileResult() {
        let url = documents.appendingPathComponent("report.txt")
        let result = FileSearchHit(url: url, displayName: "report.txt").searchResult(action: .reveal)

        XCTAssertEqual(result.action, .revealFile(url))
    }

    func testUnavailableFactoryReturnsFailure() async {
        let factory = FakeQueryFactory()
        factory.returnsNil = true
        let provider = FileSearchProvider(factory: factory)

        let outcome = await provider.search(query: "report", scopes: [documents])

        guard case .failed = outcome else {
            return XCTFail("Expected failed outcome, got \(outcome)")
        }
    }
}

// MARK: - Doubles

private final class FakeMetadataQuery: FileMetadataQuerying {
    var hits: [FileSearchHit] = []
    var error: Error?
    private(set) var executeCount = 0
    private(set) var cancelCount = 0

    func execute() async throws -> [FileSearchHit] {
        executeCount += 1
        if let error { throw error }
        return hits
    }

    func cancel() {
        cancelCount += 1
    }
}

private final class FakeQueryFactory: FileMetadataQueryMaking {
    private(set) var madeQueries: [(predicate: NSPredicate, scopes: [URL])] = []
    var query = FakeMetadataQuery()
    var returnsNil = false

    func makeQuery(predicate: NSPredicate, scopes: [URL]) -> FileMetadataQuerying? {
        madeQueries.append((predicate, scopes))
        return returnsNil ? nil : query
    }
}
