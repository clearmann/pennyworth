import AppKit
import XCTest
@testable import Pennyworth

@MainActor
final class ScreenshotPermissionPresentationTests: XCTestCase {
    func testGuidanceShowsPermissionInstructionsAndMapsOpenSettings() async {
        _ = NSApplication.shared
        let presenter = AlertScreenCaptureGuidancePresenter(runModal: { alert in
            XCTAssertEqual(alert.alertStyle, .warning)
            XCTAssertEqual(alert.messageText, L10n.tr("screenshot.permission.title"))
            XCTAssertEqual(alert.informativeText, L10n.tr("screenshot.permission.message"))
            XCTAssertEqual(alert.buttons.map(\.title), [
                L10n.tr("screenshot.permission.open_settings"),
                L10n.tr("screenshot.permission.retry"),
                L10n.tr("screenshot.action.cancel"),
            ])
            return .alertFirstButtonReturn
        })
        let choice = await presenter.presentGuidance()
        guard case .openSettings = choice else { return XCTFail("Expected Open Settings") }
    }

    func testCheckAgainButtonRequestsOnePermissionRecheck() async {
        _ = NSApplication.shared
        let presenter = AlertScreenCaptureGuidancePresenter(runModal: { _ in .alertSecondButtonReturn })
        let choice = await presenter.presentGuidance()
        guard case .retry = choice else { return XCTFail("Expected a permission recheck") }
    }

    func testCancelAndDismissDoNotOpenSettingsOrRetry() async {
        _ = NSApplication.shared
        for response: NSApplication.ModalResponse in [.alertThirdButtonReturn, .abort] {
            let presenter = AlertScreenCaptureGuidancePresenter(runModal: { _ in response })
            let choice = await presenter.presentGuidance()
            guard case .cancel = choice else { return XCTFail("Expected cancellation") }
        }
    }
}
