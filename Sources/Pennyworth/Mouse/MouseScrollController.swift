import AppKit
import CoreGraphics
import Foundation
import os

private final class ScrollPipeline {
    private struct EngineState {
        var settings: MouseScrollSettings = .defaults
        let processor = ScrollEventProcessor()
        let animator = SmoothScrollAnimator()
        var isTicking = false
    }

    private let backend: MouseScrollEventTapBackend
    private let tickScheduler: ScrollTickScheduling
    private let engine = OSAllocatedUnfairLock(initialState: EngineState())

    var isRunning: Bool {
        backend.isRunning
    }

    init(backend: MouseScrollEventTapBackend, tickScheduler: ScrollTickScheduling) {
        self.backend = backend
        self.tickScheduler = tickScheduler
    }

    func updateSettings(_ settings: MouseScrollSettings) {
        let shouldStopTick = engine.withLock { state -> Bool in
            state.settings = settings
            state.processor.reset()
            if !settings.smoothScrolling || !settings.isActive {
                state.animator.cancel()
                let wasTicking = state.isTicking
                state.isTicking = false
                return wasTicking
            }
            return false
        }
        if shouldStopTick {
            tickScheduler.stop()
        }
    }

    func startIfNeeded() -> Bool {
        if backend.isRunning { return true }
        return backend.start { [weak self] snapshot in
            self?.handleEvent(snapshot) ?? .passThrough
        }
    }

    func stop() {
        engine.withLock { state in
            state.processor.reset()
            state.animator.cancel()
            state.isTicking = false
        }
        tickScheduler.stop()
        backend.stop()
    }

    private func handleEvent(_ snapshot: ScrollWheelEventSnapshot) -> ScrollEventDecision {
        enum SideEffect {
            case none
            case startTick
            case stopTick
        }

        let (decision, effect): (ScrollEventDecision, SideEffect) = engine.withLock { state in
            let decision = state.processor.process(snapshot, settings: state.settings)
            switch decision {
            case .passThrough, .modifyDiscrete:
                return (decision, .none)
            case .passThroughAndCancelAnimation:
                state.animator.cancel()
                let wasTicking = state.isTicking
                state.isTicking = false
                return (decision, wasTicking ? .stopTick : .none)
            case let .consumeForSmooth(impulseX, impulseY, flags, timestamp):
                state.animator.enqueueImpulse(
                    deltaX: impulseX,
                    deltaY: impulseY,
                    flags: flags,
                    timestamp: timestamp,
                    settings: state.settings
                )
                if state.animator.isActive && !state.isTicking {
                    state.isTicking = true
                    return (decision, .startTick)
                }
                return (decision, .none)
            }
        }

        switch effect {
        case .none:
            break
        case .startTick:
            tickScheduler.start(interval: Self.preferredTickInterval()) { [weak self] dt in
                self?.handleTick(dt: dt)
            }
        case .stopTick:
            tickScheduler.stop()
        }
        return decision
    }

    private func handleTick(dt: TimeInterval) {
        let (frame, shouldStop): (SmoothScrollFrame?, Bool) = engine.withLock { state in
            guard state.settings.smoothScrolling, state.animator.isActive else {
                let wasTicking = state.isTicking
                state.isTicking = false
                return (nil, wasTicking)
            }
            let frame = state.animator.step(dt: dt, smoothness: state.settings.smoothness)
            if !state.animator.isActive {
                state.isTicking = false
                return (frame, true)
            }
            return (frame, false)
        }

        if let frame {
            backend.postContinuousScroll(deltaX: frame.deltaX, deltaY: frame.deltaY, flags: frame.flags)
        }
        if shouldStop {
            tickScheduler.stop()
        }
    }

    private static func preferredTickInterval() -> TimeInterval {
        // 120Hz matches ProMotion displays while remaining smooth on 60Hz monitors.
        1.0 / 120.0
    }
}

@MainActor final class MouseScrollController {
    enum RuntimeStatus: Equatable {
        case inactive
        case active
        case awaitingAccessibilityPermission
        case tapFailed
    }

    private let access: AccessibilityAccessing
    private let settingsOpener: AccessibilitySettingsOpening
    private let pipeline: ScrollPipeline
    private let pollInterval: TimeInterval?
    private var currentSettings: MouseScrollSettings = .defaults
    private var permissionPollTimer: Timer?

    private(set) var status: RuntimeStatus = .inactive {
        didSet {
            if status != oldValue {
                onStatusChange?(status)
            }
        }
    }

    var onStatusChange: ((RuntimeStatus) -> Void)?

    var isAccessibilityTrusted: Bool {
        access.isTrusted()
    }

    init(
        access: AccessibilityAccessing = SystemAccessibilityAccess(),
        settingsOpener: AccessibilitySettingsOpening? = nil,
        backend: MouseScrollEventTapBackend = CoreGraphicsMouseScrollTapBackend(),
        tickScheduler: ScrollTickScheduling = DispatchScrollTickScheduler(),
        pollInterval: TimeInterval? = 1.5
    ) {
        self.access = access
        self.settingsOpener = settingsOpener ?? SystemAccessibilitySettingsOpener()
        self.pipeline = ScrollPipeline(backend: backend, tickScheduler: tickScheduler)
        self.pollInterval = pollInterval
    }

    func apply(_ settings: MouseScrollSettings, promptForPermission: Bool = false) {
        currentSettings = settings
        pipeline.updateSettings(settings)

        guard settings.isActive else {
            stopPermissionPolling()
            pipeline.stop()
            status = .inactive
            return
        }

        let trusted = access.isTrusted() || (promptForPermission && access.requestTrust())
        guard trusted else {
            pipeline.stop()
            status = .awaitingAccessibilityPermission
            startPermissionPolling()
            return
        }

        stopPermissionPolling()
        status = pipeline.startIfNeeded() ? .active : .tapFailed
    }

    func refreshPermissionStatus() {
        apply(currentSettings, promptForPermission: false)
    }

    func requestPermission() {
        let trusted = access.isTrusted() || access.requestTrust()
        if trusted {
            apply(currentSettings, promptForPermission: false)
        } else if currentSettings.isActive {
            status = .awaitingAccessibilityPermission
            startPermissionPolling()
        }
    }

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        settingsOpener.openAccessibilitySettings()
    }

    func stop() {
        stopPermissionPolling()
        pipeline.stop()
        status = .inactive
    }

    private func startPermissionPolling() {
        guard permissionPollTimer == nil, let pollInterval else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.status == .awaitingAccessibilityPermission else { return }
                if self.access.isTrusted() {
                    self.refreshPermissionStatus()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
}
