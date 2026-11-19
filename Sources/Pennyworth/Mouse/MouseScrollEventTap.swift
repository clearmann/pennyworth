import CoreGraphics
import Foundation
import os

protocol MouseScrollEventTapBackend: AnyObject {
    var isRunning: Bool { get }
    func start(callback: @escaping (ScrollWheelEventSnapshot) -> ScrollEventDecision) -> Bool
    func stop()
    func postContinuousScroll(deltaX: Int32, deltaY: Int32, flags: CGEventFlags)
}

protocol ScrollTickScheduling: AnyObject {
    func start(interval: TimeInterval, onTick: @escaping (TimeInterval) -> Void)
    func stop()
}

final class CoreGraphicsMouseScrollTapBackend: MouseScrollEventTapBackend {
    private struct LifecycleState {
        var running = false
        var tap: CFMachPort?
        var runLoop: CFRunLoop?
        var callback: ((ScrollWheelEventSnapshot) -> ScrollEventDecision)?
        var exitSemaphore: DispatchSemaphore?
    }

    private let state = OSAllocatedUnfairLock(initialState: LifecycleState())
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private let logger = Logger(subsystem: "com.clearmann.pennyworth", category: "MouseScroll")

    var isRunning: Bool {
        state.withLock { $0.running }
    }

    func start(callback: @escaping (ScrollWheelEventSnapshot) -> ScrollEventDecision) -> Bool {
        let alreadyRunning = state.withLock { state -> Bool in
            if state.running {
                state.callback = callback
                return true
            }
            return false
        }
        if alreadyRunning { return true }

        let ready = DispatchSemaphore(value: 0)
        let exitSemaphore = DispatchSemaphore(value: 0)
        var started = false

        let thread = Thread { [self] in
            let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.tapCallback,
                userInfo: userInfo
            ) else {
                ready.signal()
                exitSemaphore.signal()
                return
            }

            let runLoop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            state.withLock { state in
                state.running = true
                state.tap = tap
                state.runLoop = runLoop
                state.callback = callback
                state.exitSemaphore = exitSemaphore
            }
            started = true
            ready.signal()

            CFRunLoopRun()

            CGEvent.tapEnable(tap: tap, enable: false)
            if let source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            state.withLock { state in
                state.running = false
                state.tap = nil
                state.runLoop = nil
                state.callback = nil
                state.exitSemaphore = nil
            }
            exitSemaphore.signal()
        }
        thread.name = "com.clearmann.pennyworth.mouse-scroll.tap"
        thread.qualityOfService = .userInteractive
        thread.start()

        ready.wait()
        if !started {
            logger.error("创建鼠标滚轮 CGEventTap 失败")
        }
        return started
    }

    func stop() {
        let teardown: (CFMachPort?, CFRunLoop?, DispatchSemaphore?) = state.withLock { state in
            guard state.running else { return (nil, nil, nil) }
            return (state.tap, state.runLoop, state.exitSemaphore)
        }
        guard let runLoop = teardown.1 else { return }
        if let tap = teardown.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        CFRunLoopStop(runLoop)
        teardown.2?.wait()
    }

    func postContinuousScroll(deltaX: Int32, deltaY: Int32, flags: CGEventFlags) {
        guard deltaX != 0 || deltaY != 0,
              let event = CGEvent(
                scrollWheelEvent2Source: eventSource,
                units: .pixel,
                wheelCount: 2,
                wheel1: deltaY,
                wheel2: deltaX,
                wheel3: 0
              ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: ScrollEventProcessor.syntheticEventTag)
        event.flags = flags
        event.post(tap: .cgSessionEventTap)
    }

    deinit {
        stop()
    }

    private func handleTapEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let tap = state.withLock { $0.tap }
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }
        guard let callback = state.withLock({ $0.callback }) else {
            return Unmanaged.passUnretained(event)
        }

        let snapshot = ScrollWheelEventSnapshot(cgEvent: event, timestamp: ProcessInfo.processInfo.systemUptime)
        switch callback(snapshot) {
        case .passThrough, .passThroughAndCancelAnimation:
            return Unmanaged.passUnretained(event)
        case let .modifyDiscrete(lineDeltaY, lineDeltaX, pointDeltaY, pointDeltaX, fixedDeltaY, fixedDeltaX):
            // CoreGraphics resets point/fixed deltas when line deltas are written,
            // so line deltas must always be written first.
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lineDeltaY)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lineDeltaX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedDeltaY)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedDeltaX)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaX)
            return Unmanaged.passUnretained(event)
        case .consumeForSmooth:
            return nil
        }
    }

    private static let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let backend = Unmanaged<CoreGraphicsMouseScrollTapBackend>.fromOpaque(userInfo).takeUnretainedValue()
        return backend.handleTapEvent(proxy: proxy, type: type, event: event)
    }
}

final class DispatchScrollTickScheduler: ScrollTickScheduling {
    private struct TimerState {
        var timer: DispatchSourceTimer?
        var lastUptimeNanos: UInt64 = 0
        var handler: ((TimeInterval) -> Void)?
    }

    private let queue = DispatchQueue(
        label: "com.clearmann.pennyworth.mouse-scroll.tick",
        qos: .userInteractive
    )
    private let state = OSAllocatedUnfairLock(initialState: TimerState())

    func start(interval: TimeInterval, onTick: @escaping (TimeInterval) -> Void) {
        let clampedInterval = max(1.0 / 240.0, interval)
        state.withLock { state in
            state.handler = onTick
            guard state.timer == nil else { return }
            state.lastUptimeNanos = DispatchTime.now().uptimeNanoseconds
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            let intervalNanos = Int(clampedInterval * 1_000_000_000)
            timer.schedule(
                deadline: .now() + .nanoseconds(intervalNanos),
                repeating: .nanoseconds(intervalNanos),
                leeway: .microseconds(500)
            )
            timer.setEventHandler { [weak self] in
                self?.fireTick(fallbackInterval: clampedInterval)
            }
            state.timer = timer
            timer.resume()
        }
    }

    func stop() {
        let timer = state.withLock { state -> DispatchSourceTimer? in
            let existing = state.timer
            state.timer = nil
            state.handler = nil
            state.lastUptimeNanos = 0
            return existing
        }
        timer?.cancel()
    }

    private func fireTick(fallbackInterval: TimeInterval) {
        let invocation: ((TimeInterval) -> Void, TimeInterval)? = state.withLock { state in
            guard let handler = state.handler else { return nil }
            let now = DispatchTime.now().uptimeNanoseconds
            let dt: TimeInterval
            if state.lastUptimeNanos > 0, now > state.lastUptimeNanos {
                dt = Double(now - state.lastUptimeNanos) / 1_000_000_000.0
            } else {
                dt = fallbackInterval
            }
            state.lastUptimeNanos = now
            return (handler, dt)
        }
        invocation?.0(invocation?.1 ?? fallbackInterval)
    }

    deinit {
        stop()
    }
}
