@testable import Pennyworth
import CoreGraphics
import XCTest

private final class FakeAccessibilityAccess: AccessibilityAccessing {
    var trusted: Bool
    var trustAfterRequest: Bool?
    private(set) var requestCount = 0

    init(trusted: Bool, trustAfterRequest: Bool? = nil) {
        self.trusted = trusted
        self.trustAfterRequest = trustAfterRequest
    }

    func isTrusted() -> Bool { trusted }

    func requestTrust() -> Bool {
        requestCount += 1
        if let trustAfterRequest { trusted = trustAfterRequest }
        return trusted
    }
}

@MainActor private final class FakeAccessibilitySettingsOpener: AccessibilitySettingsOpening {
    var openResult = true
    private(set) var openCount = 0

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        openCount += 1
        return openResult
    }
}

private final class FakeMouseScrollTapBackend: MouseScrollEventTapBackend {
    var startResult = true
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var postedScrolls: [(deltaX: Int32, deltaY: Int32, flags: CGEventFlags)] = []
    private var callback: ((ScrollWheelEventSnapshot) -> ScrollEventDecision)?

    func start(callback: @escaping (ScrollWheelEventSnapshot) -> ScrollEventDecision) -> Bool {
        startCount += 1
        guard startResult else {
            isRunning = false
            return false
        }
        self.callback = callback
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        stopCount += 1
        isRunning = false
        callback = nil
    }

    func postContinuousScroll(deltaX: Int32, deltaY: Int32, flags: CGEventFlags) {
        postedScrolls.append((deltaX, deltaY, flags))
    }

    func simulate(_ event: ScrollWheelEventSnapshot) -> ScrollEventDecision {
        callback?(event) ?? .passThrough
    }
}

private final class FakeScrollTickScheduler: ScrollTickScheduling {
    private(set) var isRunning = false
    private(set) var stopCount = 0
    private var handler: ((TimeInterval) -> Void)?

    func start(interval: TimeInterval, onTick: @escaping (TimeInterval) -> Void) {
        isRunning = true
        handler = onTick
    }

    func stop() {
        guard isRunning else { return }
        stopCount += 1
        isRunning = false
        handler = nil
    }

    func tick(dt: TimeInterval = 1.0 / 120.0) {
        handler?(dt)
    }
}

final class MouseScrollControllerTests: XCTestCase {
    @MainActor func testInactiveSettingsNeverPromptOrStartTap() {
        let access = FakeAccessibilityAccess(trusted: false)
        let backend = FakeMouseScrollTapBackend()
        let scheduler = FakeScrollTickScheduler()
        let controller = MouseScrollController(
            access: access,
            settingsOpener: FakeAccessibilitySettingsOpener(),
            backend: backend,
            tickScheduler: scheduler,
            pollInterval: nil
        )

        controller.apply(.defaults, promptForPermission: true)

        XCTAssertEqual(controller.status, .inactive)
        XCTAssertEqual(access.requestCount, 0)
        XCTAssertEqual(backend.startCount, 0)
    }

    @MainActor func testActiveSettingsWithoutPermissionWaitAndAutoActivateWhenGranted() {
        let access = FakeAccessibilityAccess(trusted: false)
        let backend = FakeMouseScrollTapBackend()
        let scheduler = FakeScrollTickScheduler()
        let controller = MouseScrollController(
            access: access,
            settingsOpener: FakeAccessibilitySettingsOpener(),
            backend: backend,
            tickScheduler: scheduler,
            pollInterval: nil
        )

        controller.apply(MouseScrollSettings(reverseScrollDirection: true), promptForPermission: false)
        XCTAssertEqual(controller.status, .awaitingAccessibilityPermission)
        XCTAssertEqual(access.requestCount, 0)
        XCTAssertEqual(backend.startCount, 0)

        controller.apply(MouseScrollSettings(reverseScrollDirection: true), promptForPermission: true)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(controller.status, .awaitingAccessibilityPermission)

        // Subsequent refresh once user flips the switch in System Settings activates the tap.
        access.trusted = true
        controller.refreshPermissionStatus()
        XCTAssertEqual(controller.status, .active)
        XCTAssertTrue(backend.isRunning)
    }

    @MainActor func testTapCreationFailureReportsTapFailed() {
        let access = FakeAccessibilityAccess(trusted: true)
        let backend = FakeMouseScrollTapBackend()
        backend.startResult = false
        let controller = MouseScrollController(
            access: access,
            settingsOpener: FakeAccessibilitySettingsOpener(),
            backend: backend,
            tickScheduler: FakeScrollTickScheduler(),
            pollInterval: nil
        )

        controller.apply(MouseScrollSettings(smoothScrolling: true))

        XCTAssertEqual(controller.status, .tapFailed)
        XCTAssertFalse(backend.isRunning)
    }

    @MainActor func testSmoothScrollEndToEndEmitsContinuousPixelsAndStopsIdleScheduler() {
        let access = FakeAccessibilityAccess(trusted: true)
        let backend = FakeMouseScrollTapBackend()
        let scheduler = FakeScrollTickScheduler()
        let controller = MouseScrollController(
            access: access,
            settingsOpener: FakeAccessibilitySettingsOpener(),
            backend: backend,
            tickScheduler: scheduler,
            pollInterval: nil
        )

        controller.apply(MouseScrollSettings(reverseScrollDirection: true, smoothScrolling: true, scrollSpeed: 1.0, smoothness: .crisp))
        XCTAssertEqual(controller.status, .active)

        let event = ScrollWheelEventSnapshot(
            lineDeltaY: -1, lineDeltaX: 0, pointDeltaY: -10, pointDeltaX: 0,
            fixedDeltaY: -1.0, fixedDeltaX: 0, isContinuous: false, hasGesturePhase: false,
            userData: 0, flags: [], timestamp: 1.0
        )
        let decision = backend.simulate(event)
        XCTAssertEqual(decision, .consumeForSmooth(impulseX: 0, impulseY: 1.0, flags: [], timestamp: 1.0))
        XCTAssertTrue(scheduler.isRunning)

        for _ in 0..<200 where scheduler.isRunning {
            scheduler.tick(dt: 1.0 / 120.0)
        }

        XCTAssertFalse(scheduler.isRunning)
        let totalY = backend.postedScrolls.reduce(Int32(0)) { $0 + $1.deltaY }
        XCTAssertEqual(Double(totalY), SmoothScrollAnimator.basePixelsPerLine, accuracy: 1.0)
    }

    @MainActor func testTrackpadEventCancelsInFlightSmoothScrollImmediately() {
        let access = FakeAccessibilityAccess(trusted: true)
        let backend = FakeMouseScrollTapBackend()
        let scheduler = FakeScrollTickScheduler()
        let controller = MouseScrollController(
            access: access,
            settingsOpener: FakeAccessibilitySettingsOpener(),
            backend: backend,
            tickScheduler: scheduler,
            pollInterval: nil
        )
        controller.apply(MouseScrollSettings(smoothScrolling: true, smoothness: .silky))

        let mouseTick = ScrollWheelEventSnapshot(
            lineDeltaY: 2, lineDeltaX: 0, pointDeltaY: 20, pointDeltaX: 0,
            fixedDeltaY: 2.0, fixedDeltaX: 0, isContinuous: false, hasGesturePhase: false,
            userData: 0, flags: [], timestamp: 1.0
        )
        _ = backend.simulate(mouseTick)
        XCTAssertTrue(scheduler.isRunning)

        let trackpad = ScrollWheelEventSnapshot(
            lineDeltaY: 0, lineDeltaX: 0, pointDeltaY: -5, pointDeltaX: 0,
            fixedDeltaY: -0.5, fixedDeltaX: 0, isContinuous: true, hasGesturePhase: false,
            userData: 0, flags: [], timestamp: 1.02
        )
        XCTAssertEqual(backend.simulate(trackpad), .passThroughAndCancelAnimation)
        XCTAssertFalse(scheduler.isRunning)
    }

    @MainActor func testDisablingSettingsStopsTapAndScheduler() {
        let access = FakeAccessibilityAccess(trusted: true)
        let backend = FakeMouseScrollTapBackend()
        let scheduler = FakeScrollTickScheduler()
        let controller = MouseScrollController(
            access: access,
            settingsOpener: FakeAccessibilitySettingsOpener(),
            backend: backend,
            tickScheduler: scheduler,
            pollInterval: nil
        )

        controller.apply(MouseScrollSettings(smoothScrolling: true))
        XCTAssertTrue(backend.isRunning)

        controller.apply(.defaults)
        XCTAssertEqual(controller.status, .inactive)
        XCTAssertFalse(backend.isRunning)
        XCTAssertFalse(scheduler.isRunning)
    }
}
