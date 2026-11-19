@testable import Pennyworth
import CoreGraphics
import XCTest

final class MouseScrollEngineTests: XCTestCase {
    private func discreteEvent(
        lineY: Int64 = -1,
        lineX: Int64 = 0,
        pointY: Int64 = -10,
        pointX: Int64 = 0,
        fixedY: Double = -1.0,
        fixedX: Double = 0.0,
        flags: CGEventFlags = [],
        timestamp: TimeInterval = 1.0
    ) -> ScrollWheelEventSnapshot {
        ScrollWheelEventSnapshot(
            lineDeltaY: lineY,
            lineDeltaX: lineX,
            pointDeltaY: pointY,
            pointDeltaX: pointX,
            fixedDeltaY: fixedY,
            fixedDeltaX: fixedX,
            isContinuous: false,
            hasGesturePhase: false,
            userData: 0,
            flags: flags,
            timestamp: timestamp
        )
    }

    // MARK: - Event Processing

    func testSyntheticSelfEventsAlwaysPassThroughWithoutCancelingAnimation() {
        let processor = ScrollEventProcessor()
        let synthetic = ScrollWheelEventSnapshot(
            lineDeltaY: 0,
            lineDeltaX: 0,
            pointDeltaY: 12,
            pointDeltaX: 0,
            fixedDeltaY: 1.2,
            fixedDeltaX: 0,
            isContinuous: true,
            hasGesturePhase: false,
            userData: ScrollEventProcessor.syntheticEventTag,
            flags: [],
            timestamp: 1.0
        )
        let settings = MouseScrollSettings(reverseScrollDirection: true, smoothScrolling: true, scrollSpeed: 2.0)

        XCTAssertEqual(processor.process(synthetic, settings: settings), .passThrough)
    }

    func testTrackpadContinuousAndGestureEventsPassThroughAndCancelMouseAnimation() {
        let processor = ScrollEventProcessor()
        let settings = MouseScrollSettings(reverseScrollDirection: true, smoothScrolling: true)

        let continuous = ScrollWheelEventSnapshot(
            lineDeltaY: 0, lineDeltaX: 0, pointDeltaY: -8, pointDeltaX: 0,
            fixedDeltaY: -0.8, fixedDeltaX: 0,
            isContinuous: true, hasGesturePhase: false, userData: 0, flags: [], timestamp: 1.0
        )
        XCTAssertEqual(processor.process(continuous, settings: settings), .passThroughAndCancelAnimation)

        let phased = ScrollWheelEventSnapshot(
            lineDeltaY: -1, lineDeltaX: 0, pointDeltaY: -10, pointDeltaX: 0,
            fixedDeltaY: -1.0, fixedDeltaX: 0,
            isContinuous: false, hasGesturePhase: true, userData: 0, flags: [], timestamp: 1.1
        )
        XCTAssertEqual(processor.process(phased, settings: settings), .passThroughAndCancelAnimation)
    }

    func testCommandAndControlZoomScrollBypassEnhancementAndCancelAnimation() {
        let processor = ScrollEventProcessor()
        let settings = MouseScrollSettings(reverseScrollDirection: true, smoothScrolling: true, scrollSpeed: 2.0)

        XCTAssertEqual(
            processor.process(discreteEvent(flags: .maskCommand), settings: settings),
            .passThroughAndCancelAnimation
        )
        XCTAssertEqual(
            processor.process(discreteEvent(flags: .maskControl), settings: settings),
            .passThroughAndCancelAnimation
        )
    }

    func testReverseOnlyFlipsBothVerticalAndHorizontalDiscreteDeltas() {
        let processor = ScrollEventProcessor()
        let settings = MouseScrollSettings(reverseScrollDirection: true, smoothScrolling: false, scrollSpeed: 1.0)
        let event = discreteEvent(lineY: -2, lineX: 1, pointY: -20, pointX: 10, fixedY: -2.0, fixedX: 1.0)

        XCTAssertEqual(
            processor.process(event, settings: settings),
            .modifyDiscrete(lineDeltaY: 2, lineDeltaX: -1, pointDeltaY: 20, pointDeltaX: -10, fixedDeltaY: 2.0, fixedDeltaX: -1.0)
        )
    }

    func testDiscreteSpeedScalingUsesFractionalAccumulationForLines() {
        let processor = ScrollEventProcessor()
        let settings = MouseScrollSettings(reverseScrollDirection: false, smoothScrolling: false, scrollSpeed: 1.5)

        let first = processor.process(discreteEvent(lineY: 1, pointY: 10, fixedY: 1.0), settings: settings)
        let second = processor.process(discreteEvent(lineY: 1, pointY: 10, fixedY: 1.0), settings: settings)

        guard case .modifyDiscrete(let line1, _, let point1, _, let fixed1, _) = first,
              case .modifyDiscrete(let line2, _, let point2, _, let fixed2, _) = second else {
            return XCTFail("Expected modifyDiscrete decisions")
        }
        XCTAssertEqual(line1 + line2, 3)
        XCTAssertEqual(point1, 15)
        XCTAssertEqual(point2, 15)
        XCTAssertEqual(fixed1, 1.5, accuracy: 0.001)
        XCTAssertEqual(fixed2, 1.5, accuracy: 0.001)
    }

    func testSmoothModeConsumesDiscreteEventAndRespectsDirectionAndShiftFlag() {
        let processor = ScrollEventProcessor()
        let reversed = MouseScrollSettings(reverseScrollDirection: true, smoothScrolling: true, scrollSpeed: 1.0)
        let event = discreteEvent(lineY: -1, lineX: 0, flags: .maskShift, timestamp: 2.5)

        let decision = processor.process(event, settings: reversed)
        XCTAssertEqual(decision, .consumeForSmooth(impulseX: 0.0, impulseY: 1.0, flags: .maskShift, timestamp: 2.5))
    }

    // MARK: - Smooth Scroll Animator

    func testAnimatorConservesTotalPixelDisplacementWithoutLoss() {
        let animator = SmoothScrollAnimator()
        let settings = MouseScrollSettings(smoothScrolling: true, scrollSpeed: 1.0, smoothness: .balanced)

        animator.enqueueImpulse(deltaX: 0, deltaY: 1.0, flags: [], timestamp: 1.0, settings: settings)
        XCTAssertTrue(animator.isActive)

        var emittedY: Int32 = 0
        var ticks = 0
        while animator.isActive && ticks < 200 {
            if let frame = animator.step(dt: 1.0 / 120.0, smoothness: .balanced) {
                emittedY += frame.deltaY
            }
            ticks += 1
        }

        XCTAssertFalse(animator.isActive)
        XCTAssertEqual(Double(emittedY), SmoothScrollAnimator.basePixelsPerLine, accuracy: 1.0)
    }

    func testAnimatorIsFrameRateIndependentBetween60HzAnd120Hz() {
        let settings = MouseScrollSettings(smoothScrolling: true, scrollSpeed: 1.5, smoothness: .balanced)
        let anim60 = SmoothScrollAnimator()
        let anim120 = SmoothScrollAnimator()
        anim60.enqueueImpulse(deltaX: 0, deltaY: -2.0, flags: [], timestamp: 1.0, settings: settings)
        anim120.enqueueImpulse(deltaX: 0, deltaY: -2.0, flags: [], timestamp: 1.0, settings: settings)

        // Compare displacement after 100ms elapsed.
        var total60: Int32 = 0
        for _ in 0..<6 {
            total60 += anim60.step(dt: 1.0 / 60.0, smoothness: .balanced)?.deltaY ?? 0
        }
        var total120: Int32 = 0
        for _ in 0..<12 {
            total120 += anim120.step(dt: 1.0 / 120.0, smoothness: .balanced)?.deltaY ?? 0
        }

        XCTAssertEqual(Double(total60), Double(total120), accuracy: 2.0)
    }

    func testReversingDirectionImmediatelyCancelsOpposingResidualInertia() {
        let animator = SmoothScrollAnimator()
        let settings = MouseScrollSettings(smoothScrolling: true, scrollSpeed: 1.0, smoothness: .silky)

        animator.enqueueImpulse(deltaX: 0, deltaY: 3.0, flags: [], timestamp: 1.0, settings: settings)
        _ = animator.step(dt: 1.0 / 60.0, smoothness: .silky)

        // Immediately scroll in opposite direction.
        animator.enqueueImpulse(deltaX: 0, deltaY: -1.0, flags: [], timestamp: 1.05, settings: settings)
        let nextFrame = animator.step(dt: 1.0 / 60.0, smoothness: .silky)

        XCTAssertLessThan(nextFrame?.deltaY ?? 0, 0)
    }

    func testCrispSettlesFasterThanBalancedAndSilky() {
        func ticksToSettle(_ smoothness: ScrollSmoothness) -> Int {
            let animator = SmoothScrollAnimator()
            let settings = MouseScrollSettings(smoothScrolling: true, scrollSpeed: 1.0, smoothness: smoothness)
            animator.enqueueImpulse(deltaX: 0, deltaY: 2.0, flags: [], timestamp: 1.0, settings: settings)
            var count = 0
            while animator.isActive && count < 400 {
                _ = animator.step(dt: 1.0 / 120.0, smoothness: smoothness)
                count += 1
            }
            return count
        }

        let crisp = ticksToSettle(.crisp)
        let balanced = ticksToSettle(.balanced)
        let silky = ticksToSettle(.silky)

        XCTAssertLessThan(crisp, balanced)
        XCTAssertLessThan(balanced, silky)
    }

    func testRapidConsecutiveScrollTicksReceiveBoundedAccelerationBoost() {
        let single = SmoothScrollAnimator.accelerationMultiplier(elapsed: nil, consecutiveTicks: 0)
        let slow = SmoothScrollAnimator.accelerationMultiplier(elapsed: 0.4, consecutiveTicks: 1)
        let rapid = SmoothScrollAnimator.accelerationMultiplier(elapsed: 0.03, consecutiveTicks: 5)
        let extreme = SmoothScrollAnimator.accelerationMultiplier(elapsed: 0.01, consecutiveTicks: 50)

        XCTAssertEqual(single, 1.0, accuracy: 0.0001)
        XCTAssertEqual(slow, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(rapid, 1.2)
        XCTAssertLessThanOrEqual(extreme, 2.5)
    }
}
