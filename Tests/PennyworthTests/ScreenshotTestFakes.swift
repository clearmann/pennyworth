import XCTest
@testable import Pennyworth

final class FakeAccess: ScreenCaptureAccessing {
    var results: [Bool]
    var requestResult = false
    private(set) var preflightCount = 0
    private(set) var requestCount = 0

    init(results: [Bool]) { self.results = results }

    func preflight() -> Bool {
        preflightCount += 1
        let index = min(preflightCount - 1, results.count - 1)
        return results[index]
    }

    func request() -> Bool {
        requestCount += 1
        return requestResult
    }
}

@MainActor
final class FakeGuidance: ScreenCaptureGuidancePresenting {
    var choices: [ScreenCaptureGuidanceChoice]
    private(set) var presentations = 0

    init(choices: [ScreenCaptureGuidanceChoice]) { self.choices = choices }

    func presentGuidance() async -> ScreenCaptureGuidanceChoice {
        let index = presentations
        presentations += 1
        // Unexpected extra prompts must fail assertions, not trap a test in a retry loop.
        return choices.indices.contains(index) ? choices[index] : .cancel
    }
}

@MainActor
final class FakeSettingsOpener: ScreenCaptureSettingsOpening {
    private(set) var openCount = 0
    var result = true

    func openScreenCaptureSettings() -> Bool {
        openCount += 1
        return result
    }
}
