@testable import Pennyworth
import AppKit
import XCTest

final class ApplicationFocusRestorerTests: XCTestCase {
    @MainActor func testRestoresCapturedApplicationOnlyOnce() {
        let previous = FakeRestorableApplication(processIdentifier: 100)
        var frontmost: RestorableApplication? = previous
        let restorer = ApplicationFocusRestorer(frontmostApplication: { frontmost },
                                                currentProcessIdentifier: 200)

        restorer.captureFrontmostApplication()
        frontmost = nil

        XCTAssertTrue(restorer.restorePreviousApplication())
        XCTAssertEqual(previous.focusRestoreCount, 1)
        XCTAssertFalse(restorer.restorePreviousApplication())
        XCTAssertEqual(previous.focusRestoreCount, 1)
    }

    @MainActor func testCapturingOwnApplicationKeepsOriginalApplication() {
        let previous = FakeRestorableApplication(processIdentifier: 100)
        let pennyworth = FakeRestorableApplication(processIdentifier: 200)
        var frontmost: RestorableApplication? = previous
        let restorer = ApplicationFocusRestorer(frontmostApplication: { frontmost },
                                                currentProcessIdentifier: 200)

        restorer.captureFrontmostApplication()
        frontmost = pennyworth
        restorer.captureFrontmostApplication()

        XCTAssertTrue(restorer.restorePreviousApplication())
        XCTAssertEqual(previous.focusRestoreCount, 1)
        XCTAssertEqual(pennyworth.focusRestoreCount, 0)
    }

    @MainActor func testCapturingNoApplicationClearsStaleApplication() {
        let previous = FakeRestorableApplication(processIdentifier: 100)
        var frontmost: RestorableApplication? = previous
        let restorer = ApplicationFocusRestorer(frontmostApplication: { frontmost },
                                                currentProcessIdentifier: 200)

        restorer.captureFrontmostApplication()
        frontmost = nil
        restorer.captureFrontmostApplication()

        XCTAssertFalse(restorer.restorePreviousApplication())
        XCTAssertEqual(previous.focusRestoreCount, 0)
    }
}

private final class FakeRestorableApplication: RestorableApplication {
    let processIdentifier: pid_t
    private(set) var focusRestoreCount = 0

    init(processIdentifier: pid_t) {
        self.processIdentifier = processIdentifier
    }

    func restoreFocus() -> Bool {
        focusRestoreCount += 1
        return true
    }
}
