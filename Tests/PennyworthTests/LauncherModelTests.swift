@testable import Pennyworth
import XCTest

final class LauncherModelTests: XCTestCase {
    @MainActor func testFailurePreservesSelectionAndNewSessionIgnoresOldCompletion() throws {
        let name = "LauncherTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let executor = TestExecutor()
        let model = LauncherModel(settings: SettingsStore(defaults: defaults), usage: UsageStore(defaults: defaults), executor: executor)
        model.beginSession()
        model.updateQuery("=1+2")
        let selected = model.selectedID
        model.executeSelected()
        executor.finish?(.failure(ActionError.clipboardWriteFailed))
        XCTAssertEqual(model.selectedID, selected)
        XCTAssertFalse(model.isExecuting)
        XCTAssertTrue(model.snapshot.message.contains("剪贴板"))
        model.executeSelected()
        let oldFinish = executor.finish
        model.endSession()
        model.beginSession()
        model.updateQuery("=5+6")
        var dismissed = false
        model.onDismiss = { dismissed = true }
        oldFinish?(.success(()))
        XCTAssertFalse(dismissed)
        XCTAssertEqual(model.snapshot.results.first?.title, "11")
    }

    @MainActor func testLateFileResultsCannotReplaceNewQuery() async throws {
        let name = "LauncherTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        try store.save(LauncherSettings(hotKey: .optionSpace, searchDirectories: ["/tmp"], searchEngine: .google, rememberUsage: false))
        var pending: CheckedContinuation<FileSearchOutcome, Never>?
        let started = expectation(description: "file query started")
        let model = LauncherModel(settings: store, usage: UsageStore(defaults: defaults), executor: TestExecutor(), fileSearch: { _, _ in
            await withCheckedContinuation { pending = $0; started.fulfill() }
        })
        model.beginSession()
        model.updateQuery("open report")
        await fulfillment(of: [started], timeout: 2)
        model.updateQuery("=7*8")
        pending?.resume(returning: .results([FileSearchHit(url: URL(fileURLWithPath: "/tmp/report"), displayName: "report")]))
        await Task.yield()
        XCTAssertEqual(model.snapshot.results.first?.title, "56")
        XCTAssertFalse(model.snapshot.isLoading)
    }

    @MainActor func testQueryModesEmptyResultsAndSelection() throws {
        let name = "LauncherTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let executor = TestExecutor()
        let model = LauncherModel(settings: SettingsStore(defaults: defaults), usage: UsageStore(defaults: defaults), executor: executor)
        model.beginSession()
        model.setApplications([AppItem(name: "Safari", url: URL(fileURLWithPath: "/Safari.app"))])
        model.updateQuery("sfr")
        XCTAssertEqual(model.snapshot.results.first?.title, "Safari")
        model.moveSelection(by: 99)
        XCTAssertEqual(model.selectedID, model.snapshot.results.last?.id)
        model.moveSelection(by: -99)
        XCTAssertEqual(model.selectedID, model.snapshot.results.first?.id)
        model.updateQuery("open report")
        XCTAssertTrue(model.snapshot.message.contains("目录"))
        model.executeSelected()
        XCTAssertTrue(executor.actions.isEmpty)
        model.updateQuery("=1/0")
        XCTAssertTrue(model.snapshot.results.isEmpty)
        XCTAssertTrue(model.snapshot.message.contains("零"))
        model.updateQuery("1+")
        XCTAssertFalse(model.snapshot.results.isEmpty)
        model.updateQuery("ddg 中文")
        XCTAssertTrue(model.snapshot.results.first?.title.contains("DuckDuckGo") == true)
        model.updateQuery(String(repeating: "x", count: 513))
        XCTAssertTrue(model.snapshot.results.isEmpty)
        XCTAssertTrue(model.snapshot.message.contains("512"))
        model.endSession()
    }

    @MainActor func testFileOutcomesAndApplicationSuccess() async throws {
        let name = "LauncherTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        try settings.save(LauncherSettings(hotKey: .optionSpace, searchDirectories: ["/tmp"], searchEngine: .google, rememberUsage: true))
        let outcomes: [FileSearchOutcome] = [.results([]), .notConfigured, .emptyQuery, .cancelled, .failed("Unavailable"),
            .results([FileSearchHit(url: URL(fileURLWithPath: "/tmp/report"), displayName: "report")])]
        for outcome in outcomes {
            let finished = expectation(description: "file outcome")
            let model = LauncherModel(settings: settings, usage: UsageStore(defaults: defaults), executor: TestExecutor(), fileSearch: { _, _ in outcome })
            model.beginSession()
            model.onChange = { if !model.snapshot.isLoading { finished.fulfill() } }
            model.updateQuery("find report")
            await fulfillment(of: [finished], timeout: 2)
            XCTAssertFalse(model.snapshot.isLoading)
            if case .results(let hits) = outcome, !hits.isEmpty {
                XCTAssertEqual(model.snapshot.results.first?.action, .revealFile(hits[0].url))
            }
            model.onChange = nil
            model.endSession()
        }
        let executor = TestExecutor()
        let usage = UsageStore(defaults: defaults)
        let model = LauncherModel(settings: settings, usage: usage, executor: executor)
        model.beginSession()
        model.updateQuery("open")
        XCTAssertTrue(model.snapshot.message.contains("文件名"))
        let url = URL(fileURLWithPath: "/Safari.app")
        model.setApplications([AppItem(name: "Safari", url: url)])
        model.updateQuery("Safari")
        model.select(model.snapshot.results.first?.id)
        model.executeSelected()
        model.updateQuery("ignored")
        XCTAssertEqual(model.query, "Safari")
        executor.finish?(.success(()))
        XCTAssertGreaterThan(usage.bonus(for: url), 0)
    }

    @MainActor func testCalculatorExecutesOnceAndClosesOnSuccess() async throws {
        let name = "LauncherTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let executor = TestExecutor()
        let model = LauncherModel(settings: SettingsStore(defaults: defaults),
                                  usage: UsageStore(defaults: defaults), executor: executor)
        model.beginSession()
        model.updateQuery("23*17")
        XCTAssertEqual(model.snapshot.results.first?.title, "391")
        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.executeSelected()
        model.executeSelected()
        await Task.yield()
        XCTAssertEqual(executor.actions, [.copyText("391")])
        executor.finish?(.success(()))
        XCTAssertTrue(dismissed)
    }
}

@MainActor final class TestExecutor: ActionExecuting {
    var actions: [SearchAction] = []
    var finish: ((Result<Void, Error>) -> Void)?
    func execute(_ action: SearchAction, completion: @escaping (Result<Void, Error>) -> Void) {
        actions = actions + [action]
        finish = completion
    }
}
