import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotCommandTests: XCTestCase {
    // MARK: - QueryParser

    func testCaptureKeywordsRouteToScreenshotIntent() {
        for keyword in ["shot", "screenshot", "截图", "SHOT", "Screenshot"] {
            let request = QueryParser.parse(keyword)
            XCTAssertEqual(request?.intent, .screenshot(.capture), "keyword \(keyword)")
        }
    }

    func testPinKeywordsRouteToPinClipboardIntent() {
        for keyword in ["pin", "贴图", "PIN"] {
            XCTAssertEqual(QueryParser.parse(keyword)?.intent, .screenshot(.pinClipboard), "keyword \(keyword)")
        }
    }

    func testSimilarKeywordsDoNotHijackApplicationSearch() {
        for query in ["shotgun", "pinto", "spin", "截图工具箱"] {
            if case .screenshot = QueryParser.parse(query)?.intent {
                XCTFail("query \(query) must not route to screenshot")
            }
        }
    }

    // MARK: - LauncherModel

    func testScreenshotIntentPublishesCommandResult() {
        let model = LauncherModel(settings: SettingsStore(defaults: makeDefaults()), usage: UsageStore(),
                                  executor: ActionExecutor())
        model.updateQuery("shot")
        XCTAssertEqual(model.snapshot.results.map(\.id), ["screenshot.capture"])
        XCTAssertEqual(model.snapshot.results.first?.action, .startScreenshot)
        model.updateQuery("pin")
        XCTAssertEqual(model.snapshot.results.map(\.id), ["screenshot.pin_clipboard"])
        XCTAssertEqual(model.snapshot.results.first?.action, .pinClipboardImage)
    }

    // MARK: - ActionExecutor

    func testStartScreenshotActionInvokesSession() {
        let actions = FakeScreenshotActions()
        let executor = ActionExecutor(pasteboard: NSPasteboard.withUniqueName(), screenshotActions: actions)
        let expectation = expectation(description: "completion")
        executor.execute(.startScreenshot) { result in
            switch result {
            case .success: break
            case .failure(let error): XCTFail("unexpected error: \(error)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(actions.startCount, 1)
    }

    func testPinClipboardActionInvokesSession() {
        let actions = FakeScreenshotActions()
        let executor = ActionExecutor(pasteboard: NSPasteboard.withUniqueName(), screenshotActions: actions)
        let expectation = expectation(description: "completion")
        executor.execute(.pinClipboardImage) { _ in expectation.fulfill() }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(actions.pinCount, 1)
    }

    func testMissingScreenshotDependencyFails() {
        let executor = ActionExecutor(pasteboard: NSPasteboard.withUniqueName())
        let expectation = expectation(description: "completion")
        executor.execute(.startScreenshot) { result in
            if case .failure(let error) = result, let actionError = error as? ActionError,
               case .screenshotUnavailable = actionError {} else {
                XCTFail("expected screenshotUnavailable")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testSessionErrorPropagatesAsActionFailure() {
        let actions = FakeScreenshotActions()
        actions.error = ScreenshotError.clipboardImageMissing
        let executor = ActionExecutor(pasteboard: NSPasteboard.withUniqueName(), screenshotActions: actions)
        let expectation = expectation(description: "completion")
        executor.execute(.pinClipboardImage) { result in
            if case .failure = result {} else { XCTFail("expected failure") }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ScreenshotCommandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
final class FakeScreenshotActions: ScreenshotActionHandling {
    var error: Error?
    private(set) var startCount = 0
    private(set) var pinCount = 0

    func startScreenshot() throws {
        if let error { throw error }
        startCount += 1
    }

    func pinClipboardImage() throws {
        if let error { throw error }
        pinCount += 1
    }
}
