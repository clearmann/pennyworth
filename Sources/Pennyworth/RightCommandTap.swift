import AppKit
import Carbon

enum RightCommandChange {
    case flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags, timestamp: TimeInterval)
    case synchronized(Bool)

    var isActive: Bool {
        switch self {
        case .flagsChanged(_, let flags, _): return HotKeyModifiers.isRightCommandOnly(flags)
        case .synchronized(let active): return active
        }
    }
}

/// Only a pair of actual right-Command edges can form a tap. State repairs and
/// other modifier changes may cancel an edge, but must never manufacture one.
final class RightCommandTap {
    private static let maximumDuration: TimeInterval = 0.3
    private static let otherModifiers: NSEvent.ModifierFlags = [.option, .control, .shift, .function]
    private let inputWasQuietSince: (TimeInterval) -> Bool
    private var pressedAt: TimeInterval?

    init(inputWasQuietSince: @escaping (TimeInterval) -> Bool) {
        self.inputWasQuietSince = inputWasQuietSince
    }

    func cancel() { pressedAt = nil }

    func completesTap(_ change: RightCommandChange, wasActive: Bool) -> Bool {
        let start = pressedAt
        cancel()
        guard case let .flagsChanged(key, flags, time) = change,
              key == UInt16(kVK_RightCommand), flags.isDisjoint(with: Self.otherModifiers) else { return false }
        if !wasActive && change.isActive {
            pressedAt = time
            return false
        }
        guard wasActive, !flags.contains(.command), let start,
              (0...Self.maximumDuration).contains(time - start) else { return false }
        return inputWasQuietSince(start)
    }

    // Ask only about elapsed time, not which keys were pressed. Use the real down
    // event's uptime so an unbound chord still cancels if the main queue was busy.
    static func sessionInputWasQuiet(since press: TimeInterval) -> Bool {
        guard !IsSecureEventInputEnabled(), NSEvent.pressedMouseButtons == 0 else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - press
        let interruptingEvents: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown,
                                                  .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel]
        return elapsed >= 0 && interruptingEvents.allSatisfy {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) > elapsed
        }
    }
}

/// Detects Alfred-style double-taps on a single modifier key (⌘, ⌥, ⌃, ⇧).
/// Fires only on the second clean release so fast chords (e.g., ⌘ then ⌘C) never false-trigger.
final class ModifierDoubleTapDetector {
    private static let maximumTapDuration: TimeInterval = 0.3
    private static let maximumInterval: TimeInterval = 0.35

    private struct ActivePress {
        let key: ModifierTapKey
        let keyCode: UInt16
        let pressedAt: TimeInterval
    }

    private struct CompletedTap {
        let key: ModifierTapKey
        let releasedAt: TimeInterval
    }

    private let inputWasQuietSince: (TimeInterval) -> Bool
    private var activePress: ActivePress?
    private var lastCompletedTap: CompletedTap?

    init(inputWasQuietSince: @escaping (TimeInterval) -> Bool) {
        self.inputWasQuietSince = inputWasQuietSince
    }

    func cancel() {
        activePress = nil
        lastCompletedTap = nil
    }

    func completedDoubleTap(_ change: RightCommandChange) -> ModifierTapKey? {
        guard case let .flagsChanged(keyCode, flags, timestamp) = change else {
            cancel()
            return nil
        }
        guard let key = ModifierTapKey.from(keyCode: keyCode) else {
            cancel()
            return nil
        }
        let relevant = flags.intersection(ModifierTapKey.trackedModifierFlags)

        if relevant == key.flag && activePress == nil {
            if key == .command && HotKeyModifiers.hasBothCommandKeys(flags) {
                cancel()
                return nil
            }
            if let prev = lastCompletedTap,
               prev.key != key || !(0...Self.maximumInterval).contains(timestamp - prev.releasedAt) {
                lastCompletedTap = nil
            }
            activePress = ActivePress(key: key, keyCode: keyCode, pressedAt: timestamp)
            return nil
        }

        if relevant.isEmpty, let press = activePress {
            activePress = nil
            guard press.key == key, press.keyCode == keyCode,
                  (0...Self.maximumTapDuration).contains(timestamp - press.pressedAt),
                  inputWasQuietSince(press.pressedAt) else {
                lastCompletedTap = nil
                return nil
            }
            if let prev = lastCompletedTap,
               prev.key == key,
               (0...Self.maximumInterval).contains(press.pressedAt - prev.releasedAt),
               inputWasQuietSince(prev.releasedAt) {
                lastCompletedTap = nil
                return key
            }
            lastCompletedTap = CompletedTap(key: key, releasedAt: timestamp)
            return nil
        }

        cancel()
        return nil
    }
}
