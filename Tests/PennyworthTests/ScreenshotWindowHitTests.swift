import CoreGraphics
import XCTest
@testable import Pennyworth

final class ScreenshotWindowHitTests: XCTestCase {
    private let display = DisplayDescriptor(id: 1, quartzFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                                            cocoaFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000))

    private func window(id: CGWindowID = 1, pid: pid_t = 42, layer: Int = 0,
                        bounds: CGRect = CGRect(x: 100, y: 100, width: 200, height: 200),
                        alpha: Double = 1, onscreen: Bool = true, sharing: Int = 1) -> WindowDescriptor {
        WindowDescriptor(id: id, ownerPID: pid, layer: layer, quartzBounds: bounds,
                         alpha: alpha, isOnscreen: onscreen, sharingState: sharing)
    }

    private func tester() -> WindowHitTester { WindowHitTester(ownPID: 999) }

    func testHitReturnsFrontmostEligibleWindow() {
        let back = window(id: 1)
        let front = window(id: 2)
        let hit = tester().hit(atLocalPoint: CGPoint(x: 150, y: 750), display: display,
                               windows: [front, back], mainDisplayHeight: 1000)
        XCTAssertEqual(hit?.windowID, 2)
        XCTAssertEqual(hit?.localBounds, CGRect(x: 100, y: 700, width: 200, height: 200))
    }

    func testOwnProcessWindowIsSkipped() {
        let own = window(id: 1, pid: 999)
        let other = window(id: 2)
        let hit = tester().hit(atLocalPoint: CGPoint(x: 150, y: 750), display: display,
                               windows: [own, other], mainDisplayHeight: 1000)
        XCTAssertEqual(hit?.windowID, 2)
    }

    func testNonZeroLayerWindowsAreSkipped() {
        let dock = window(id: 1, layer: 25)
        XCTAssertNil(tester().hit(atLocalPoint: CGPoint(x: 150, y: 750), display: display,
                                  windows: [dock], mainDisplayHeight: 1000))
    }

    func testInvisibleTransparentTinyAndSharingNoneWindowsAreSkipped() {
        let candidates = [
            window(id: 1, onscreen: false),
            window(id: 2, alpha: 0),
            window(id: 3, bounds: CGRect(x: 100, y: 100, width: 10, height: 10)),
            window(id: 4, sharing: 0),
        ]
        for candidate in candidates {
            XCTAssertFalse(tester().eligible(candidate), "window \(candidate.id) should be ineligible")
            XCTAssertNil(tester().hit(atLocalPoint: CGPoint(x: 150, y: 750), display: display,
                                      windows: [candidate], mainDisplayHeight: 1000))
        }
    }

    func testPointOutsideAllWindowsReturnsNil() {
        XCTAssertNil(tester().hit(atLocalPoint: CGPoint(x: 900, y: 50), display: display,
                                  windows: [window()], mainDisplayHeight: 1000))
    }

    func testWindowOnNegativeOriginDisplayUsesLocalCoordinates() {
        let secondary = DisplayDescriptor(id: 2, quartzFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                          cocoaFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        // Quartz y is measured from the main display top; main display is 1000pt tall.
        let win = window(bounds: CGRect(x: -1900, y: 100, width: 200, height: 200))
        let hit = tester().hit(atLocalPoint: CGPoint(x: 50, y: 750), display: secondary,
                               windows: [win], mainDisplayHeight: 1000)
        XCTAssertEqual(hit?.windowID, 1)
        XCTAssertEqual(hit?.localBounds, CGRect(x: 20, y: 700, width: 200, height: 200))
    }

    func testWindowSpanningDisplaysKeepsFullLocalBounds() {
        let win = window(bounds: CGRect(x: 900, y: 100, width: 400, height: 200))
        let hit = tester().hit(atLocalPoint: CGPoint(x: 950, y: 750), display: display,
                               windows: [win], mainDisplayHeight: 1000)
        // Not clipped to the display; SelectionModel clamps the chosen rect later.
        XCTAssertEqual(hit?.localBounds, CGRect(x: 900, y: 700, width: 400, height: 200))
    }
}
