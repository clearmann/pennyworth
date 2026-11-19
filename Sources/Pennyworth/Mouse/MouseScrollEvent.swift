import CoreGraphics
import Foundation

struct ScrollWheelEventSnapshot: Equatable {
    let lineDeltaY: Int64
    let lineDeltaX: Int64
    let pointDeltaY: Int64
    let pointDeltaX: Int64
    let fixedDeltaY: Double
    let fixedDeltaX: Double
    let isContinuous: Bool
    let hasGesturePhase: Bool
    let userData: Int64
    let flags: CGEventFlags
    let timestamp: TimeInterval

    init(
        lineDeltaY: Int64,
        lineDeltaX: Int64,
        pointDeltaY: Int64,
        pointDeltaX: Int64,
        fixedDeltaY: Double,
        fixedDeltaX: Double,
        isContinuous: Bool,
        hasGesturePhase: Bool,
        userData: Int64,
        flags: CGEventFlags,
        timestamp: TimeInterval
    ) {
        self.lineDeltaY = lineDeltaY
        self.lineDeltaX = lineDeltaX
        self.pointDeltaY = pointDeltaY
        self.pointDeltaX = pointDeltaX
        self.fixedDeltaY = fixedDeltaY
        self.fixedDeltaX = fixedDeltaX
        self.isContinuous = isContinuous
        self.hasGesturePhase = hasGesturePhase
        self.userData = userData
        self.flags = flags
        self.timestamp = timestamp
    }

    init(cgEvent: CGEvent, timestamp: TimeInterval) {
        self.lineDeltaY = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        self.lineDeltaX = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        self.pointDeltaY = cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        self.pointDeltaX = cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        self.fixedDeltaY = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        self.fixedDeltaX = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        self.isContinuous = cgEvent.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let scrollPhase = cgEvent.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = cgEvent.getIntegerValueField(.scrollWheelEventMomentumPhase)
        self.hasGesturePhase = scrollPhase != 0 || momentumPhase != 0
        self.userData = cgEvent.getIntegerValueField(.eventSourceUserData)
        self.flags = cgEvent.flags
        self.timestamp = timestamp
    }
}

enum ScrollEventDecision: Equatable {
    case passThrough
    case passThroughAndCancelAnimation
    case modifyDiscrete(
        lineDeltaY: Int64,
        lineDeltaX: Int64,
        pointDeltaY: Int64,
        pointDeltaX: Int64,
        fixedDeltaY: Double,
        fixedDeltaX: Double
    )
    case consumeForSmooth(
        impulseX: Double,
        impulseY: Double,
        flags: CGEventFlags,
        timestamp: TimeInterval
    )
}

final class ScrollEventProcessor {
    /// Custom marker placed in `eventSourceUserData` on synthetic smooth-scroll events
    /// so our own `CGEventTap` passes them straight through without recursion.
    static let syntheticEventTag: Int64 = 0x5057_4D53_4352
    private static let bypassModifiers: CGEventFlags = [.maskCommand, .maskControl]
    private static let forwardedModifiers: CGEventFlags = [.maskShift, .maskAlternate]

    private var carryLineY: Double = 0
    private var carryLineX: Double = 0

    func reset() {
        carryLineY = 0
        carryLineX = 0
    }

    func process(_ event: ScrollWheelEventSnapshot, settings: MouseScrollSettings) -> ScrollEventDecision {
        if event.userData == Self.syntheticEventTag {
            return .passThrough
        }
        if event.isContinuous || event.hasGesturePhase {
            reset()
            return .passThroughAndCancelAnimation
        }
        if !event.flags.isDisjoint(with: Self.bypassModifiers) {
            reset()
            return .passThroughAndCancelAnimation
        }
        guard settings.isActive else {
            return .passThrough
        }

        let direction: Double = settings.reverseScrollDirection ? -1.0 : 1.0
        if settings.smoothScrolling {
            let impulseY = normalizedLineDelta(
                line: event.lineDeltaY,
                fixed: event.fixedDeltaY,
                point: event.pointDeltaY
            ) * direction
            let impulseX = normalizedLineDelta(
                line: event.lineDeltaX,
                fixed: event.fixedDeltaX,
                point: event.pointDeltaX
            ) * direction
            guard impulseX != 0 || impulseY != 0 else { return .passThrough }
            let safeFlags = event.flags.intersection(Self.forwardedModifiers)
            return .consumeForSmooth(
                impulseX: impulseX,
                impulseY: impulseY,
                flags: safeFlags,
                timestamp: event.timestamp
            )
        }

        let scale = direction * settings.scrollSpeed
        let lineY = scaleDiscreteLine(event.lineDeltaY, scale: scale, carry: &carryLineY)
        let lineX = scaleDiscreteLine(event.lineDeltaX, scale: scale, carry: &carryLineX)
        let pointY = Int64((Double(event.pointDeltaY) * scale).rounded())
        let pointX = Int64((Double(event.pointDeltaX) * scale).rounded())
        let fixedY = event.fixedDeltaY * scale
        let fixedX = event.fixedDeltaX * scale
        return .modifyDiscrete(
            lineDeltaY: lineY,
            lineDeltaX: lineX,
            pointDeltaY: pointY,
            pointDeltaX: pointX,
            fixedDeltaY: fixedY,
            fixedDeltaX: fixedX
        )
    }

    private func normalizedLineDelta(line: Int64, fixed: Double, point: Int64) -> Double {
        if line != 0 { return Double(line) }
        if fixed != 0 { return fixed }
        if point != 0 { return Double(point) / 10.0 }
        return 0
    }

    private func scaleDiscreteLine(_ raw: Int64, scale: Double, carry: inout Double) -> Int64 {
        guard raw != 0 else { return 0 }
        let scaled = Double(raw) * scale
        if (scaled > 0 && carry < 0) || (scaled < 0 && carry > 0) {
            carry = 0
        }
        let total = scaled + carry
        let emitted = Int64(total.rounded(.towardZero))
        carry = total - Double(emitted)
        return emitted
    }
}
