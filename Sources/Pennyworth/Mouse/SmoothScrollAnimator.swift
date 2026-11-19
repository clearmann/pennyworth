import CoreGraphics
import Foundation

struct SmoothScrollFrame: Equatable {
    let deltaX: Int32
    let deltaY: Int32
    let flags: CGEventFlags
}

final class SmoothScrollAnimator {
    static let basePixelsPerLine: Double = 48.0
    static let rapidScrollWindow: TimeInterval = 0.12
    static let maxAccelerationMultiplier: Double = 2.5

    private static let minDeltaTime: TimeInterval = 1.0 / 240.0
    private static let maxDeltaTime: TimeInterval = 1.0 / 20.0
    private static let stopThreshold: Double = 0.35

    private var remainingX: Double = 0
    private var remainingY: Double = 0
    private var carryX: Double = 0
    private var carryY: Double = 0
    private var activeFlags: CGEventFlags = []
    private var lastImpulseTimestamp: TimeInterval?
    private var lastDirectionY: Double = 0
    private var lastDirectionX: Double = 0
    private var consecutiveRapidTicks: Int = 0

    var isActive: Bool {
        abs(remainingX) >= Self.stopThreshold
            || abs(remainingY) >= Self.stopThreshold
            || abs(carryX) >= 0.5
            || abs(carryY) >= 0.5
    }

    /// Computes a speed multiplier when the user spins the wheel rapidly in the same direction.
    ///
    /// - Parameters:
    ///   - elapsed: Seconds since the previous same-direction wheel tick (`nil` on the first tick
    ///     or immediately after a direction reversal).
    ///   - consecutiveTicks: Number of consecutive rapid ticks accumulated so far (0 for a single tick).
    /// - Returns: Multiplier >= 1.0 (recommended upper bound: `Self.maxAccelerationMultiplier` = 2.5).
    static func accelerationMultiplier(elapsed: TimeInterval?, consecutiveTicks: Int) -> Double {
        guard let elapsed, elapsed >= 0, elapsed < rapidScrollWindow, consecutiveTicks > 0 else {
            return 1.0
        }
        let pace = (rapidScrollWindow - elapsed) / rapidScrollWindow
        let streak = min(Double(consecutiveTicks), 8.0) / 8.0
        // Blend tick cadence with consecutive streak: slow single ticks stay 1:1 while sustained flicks glide smoothly.
        let boost = (0.45 * pace + 0.55 * streak) * (maxAccelerationMultiplier - 1.0)
        return min(maxAccelerationMultiplier, 1.0 + boost)
    }

    func enqueueImpulse(
        deltaX: Double,
        deltaY: Double,
        flags: CGEventFlags,
        timestamp: TimeInterval,
        settings: MouseScrollSettings
    ) {
        let reversedY = (deltaY > 0 && remainingY < 0) || (deltaY < 0 && remainingY > 0)
        let reversedX = (deltaX > 0 && remainingX < 0) || (deltaX < 0 && remainingX > 0)
        if reversedY {
            remainingY = 0
            carryY = 0
        }
        if reversedX {
            remainingX = 0
            carryX = 0
        }

        let sameDirection = !reversedY && !reversedX
            && ((deltaY == 0) || (deltaY * lastDirectionY > 0))
            && ((deltaX == 0) || (deltaX * lastDirectionX > 0))
        let elapsed = sameDirection ? lastImpulseTimestamp.map { max(0, timestamp - $0) } : nil

        if let elapsed, elapsed < Self.rapidScrollWindow {
            consecutiveRapidTicks += 1
        } else {
            consecutiveRapidTicks = 0
        }

        let acceleration = Self.accelerationMultiplier(elapsed: elapsed, consecutiveTicks: consecutiveRapidTicks)
        let scale = Self.basePixelsPerLine * settings.scrollSpeed * acceleration

        remainingX += deltaX * scale
        remainingY += deltaY * scale
        activeFlags = flags
        lastImpulseTimestamp = timestamp
        if deltaY != 0 { lastDirectionY = deltaY > 0 ? 1 : -1 }
        if deltaX != 0 { lastDirectionX = deltaX > 0 ? 1 : -1 }
    }

    func step(dt: TimeInterval, smoothness: ScrollSmoothness) -> SmoothScrollFrame? {
        guard isActive else { return nil }
        let clampedDT = min(max(dt, Self.minDeltaTime), Self.maxDeltaTime)
        let factor = 1.0 - exp(-clampedDT / smoothness.timeConstant)

        let emitX = advanceAxis(remaining: &remainingX, carry: &carryX, factor: factor)
        let emitY = advanceAxis(remaining: &remainingY, carry: &carryY, factor: factor)

        guard emitX != 0 || emitY != 0 else { return nil }
        return SmoothScrollFrame(deltaX: emitX, deltaY: emitY, flags: activeFlags)
    }

    func cancel() {
        remainingX = 0
        remainingY = 0
        carryX = 0
        carryY = 0
        activeFlags = []
        lastImpulseTimestamp = nil
        lastDirectionX = 0
        lastDirectionY = 0
        consecutiveRapidTicks = 0
    }

    private func advanceAxis(remaining: inout Double, carry: inout Double, factor: Double) -> Int32 {
        if abs(remaining) < Self.stopThreshold {
            let finalTotal = remaining + carry
            let emitted = Int32(finalTotal.rounded())
            remaining = 0
            carry = 0
            return emitted
        }
        let step = remaining * factor
        remaining -= step
        let total = step + carry
        let emitted = Int32(total.rounded(.towardZero))
        carry = total - Double(emitted)
        return emitted
    }
}
