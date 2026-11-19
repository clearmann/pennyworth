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
