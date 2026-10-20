@testable import Pennyworth
import AppKit
import XCTest

final class ActionExecutorTests: XCTestCase {
    @MainActor func testCopiesToIsolatedPasteboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var succeeded = false
        ActionExecutor(pasteboard: pasteboard).execute(.copyText("391")) {
            if case .success = $0 { succeeded = true }
        }
        XCTAssertTrue(succeeded)
        XCTAssertEqual(pasteboard.string(forType: .string), "391")
    }

    @MainActor func testMissingFileAndUnsafeURLFailWithoutOpeningAnything() {
        let executor = ActionExecutor()
        let actions: [SearchAction] = [
            .openFile(URL(fileURLWithPath: "/missing-\(UUID())")),
            .openApplication(URL(fileURLWithPath: "/missing-\(UUID()).app")),
            .revealFile(URL(fileURLWithPath: "/missing-\(UUID())")),
            .openURL(URL(string: "file:///etc/passwd")!),
        ]
        for action in actions {
            var failed = false
            executor.execute(action) { if case .failure = $0 { failed = true } }
            XCTAssertTrue(failed)
        }
    }
}
