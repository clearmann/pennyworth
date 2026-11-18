import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotPermissionTests: XCTestCase {
    private func makeCoordinator(results: [Bool], choices: [ScreenCaptureGuidanceChoice] = [.cancel])
        -> (ScreenCapturePermissionCoordinator, FakeAccess, FakeGuidance, FakeSettingsOpener) {
        let access = FakeAccess(results: results)
        let guidance = FakeGuidance(choices: choices)
        let opener = FakeSettingsOpener()
        let coordinator = ScreenCapturePermissionCoordinator(access: access, guidance: guidance, settingsOpener: opener)
        return (coordinator, access, guidance, opener)
    }

    func testAlreadyAuthorizedSkipsRequestAndGuidance() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [true])
        let authorized = try await coordinator.ensureAuthorized()
        XCTAssertTrue(authorized)
        XCTAssertEqual(access.preflightCount, 1)
        XCTAssertEqual(access.requestCount, 0)
        XCTAssertEqual(guidance.presentations, 0)
    }

    func testRequestGrantsAccessWithoutGuidance() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [false, true])
        let authorized = try await coordinator.ensureAuthorized()
        XCTAssertTrue(authorized)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(guidance.presentations, 0)
    }

    func testSuccessfulRequestDoesNotRequirePreflightToRefreshImmediately() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [false])
        access.requestResult = true
        let authorized = try await coordinator.ensureAuthorized()
        XCTAssertTrue(authorized)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(guidance.presentations, 0)
    }

    func testDeniedSystemRequestDefersGuidanceToNextAttempt() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [false], choices: [.cancel])
        let authorized = try await coordinator.ensureAuthorized()
        XCTAssertFalse(authorized)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(guidance.presentations, 0)
    }

    func testOpenSettingsEndsAttemptWithoutReopeningGuidance() async throws {
        let (coordinator, access, guidance, opener) = makeCoordinator(results: [false],
                                                                       choices: [.openSettings])
        let firstAttempt = try await coordinator.ensureAuthorized()
        let secondAttempt = try await coordinator.ensureAuthorized()
        XCTAssertFalse(firstAttempt)
        XCTAssertFalse(secondAttempt)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(opener.openCount, 1)
        XCTAssertEqual(guidance.presentations, 1)
    }

    func testRepeatedDeniedAttemptsDoNotRequestSystemAccessAgain() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [false])
        for _ in 0..<3 {
            let authorized = try await coordinator.ensureAuthorized()
            XCTAssertFalse(authorized)
        }
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(guidance.presentations, 2)
    }

    func testGrantAfterOpeningSettingsIsDetectedOnNextAttempt() async throws {
        let (coordinator, access, guidance, opener) = makeCoordinator(results: [false], choices: [.openSettings])
        _ = try await coordinator.ensureAuthorized()
        _ = try await coordinator.ensureAuthorized()
        access.results = [true]
        let authorized = try await coordinator.ensureAuthorized()
        XCTAssertTrue(authorized)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(opener.openCount, 1)
        XCTAssertEqual(guidance.presentations, 1)
    }

    func testRetryDetectsPermissionGrantedWhileGuidanceWasVisible() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [false, false, false, true],
                                                                 choices: [.retry])
        let firstAttempt = try await coordinator.ensureAuthorized()
        let retry = try await coordinator.ensureAuthorized()
        XCTAssertFalse(firstAttempt)
        XCTAssertTrue(retry)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(guidance.presentations, 1)
    }

    func testPreviouslyGrantedPermissionIsRecheckedAfterRevocation() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [true])
        let firstAttempt = try await coordinator.ensureAuthorized()
        access.results = [false]
        let afterRevocation = try await coordinator.ensureAuthorized()
        XCTAssertTrue(firstAttempt)
        XCTAssertFalse(afterRevocation)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(guidance.presentations, 0)
    }

    func testSettingsOpenFailureIsReportedInsteadOfSilentlyEnding() async throws {
        let (coordinator, _, _, opener) = makeCoordinator(results: [false], choices: [.openSettings])
        opener.result = false
        _ = try await coordinator.ensureAuthorized()
        do {
            _ = try await coordinator.ensureAuthorized()
            XCTFail("Opening Settings failed, but the permission attempt did not report the error")
        } catch {
            XCTAssertEqual(error.localizedDescription, L10n.tr("screenshot.permission.settings_failed"))
        }
    }

    func testRetryFailureEndsAttemptWithoutReopeningGuidance() async throws {
        let (coordinator, access, guidance, _) = makeCoordinator(results: [false], choices: [.retry])
        let firstAttempt = try await coordinator.ensureAuthorized()
        let secondAttempt = try await coordinator.ensureAuthorized()
        XCTAssertFalse(firstAttempt)
        XCTAssertFalse(secondAttempt)
        XCTAssertEqual(guidance.presentations, 1)
        XCTAssertEqual(access.requestCount, 1)
    }
}
