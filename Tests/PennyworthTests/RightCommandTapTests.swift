@testable import Pennyworth
import AppKit
import Carbon
import XCTest

final class RightCommandTapTests: XCTestCase {
    private let right = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
    private let left = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x08)

    func testUnregisteredChordDoesNotCountAsTapAndDoesNotStealCopy() throws {
        let monitor = FakeRightCommandMonitor()
        let backend = FakeHotKeyBackend()
        // An unregistered C went to the front app at 1.05; no Carbon callback arrives.
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor, inputWasQuietSince: { $0 > 1.05 })
        var launches = 0
        try manager.register(name: "launcher", preset: .rightCommandTap) { launches += 1 }
        XCTAssertTrue(backend.active.isEmpty, "Right Command tap does not need a Carbon slot")
        monitor.setRightCommand(true, at: 1)
        XCTAssertFalse(backend.active.values.contains { $0.keyCode == UInt32(kVK_ANSI_C) })
        monitor.setRightCommand(false, at: 1.1)
        XCTAssertEqual(launches, 0)
        monitor.setRightCommand(true, at: 2)
        monitor.setRightCommand(false, at: 2.1)
        XCTAssertEqual(launches, 1)
    }

    func testOtherModifiersResyncAndRecordingCannotCompleteATap() throws {
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: FakeHotKeyBackend(), modifierMonitor: monitor, inputWasQuietSince: { _ in true })
        var launches = 0
        try manager.register(name: "launcher", preset: .rightCommandTap) { launches += 1 }
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 1))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 1.1))
        monitor.setRightCommand(true, at: 2)
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Shift), flags: right.union(.shift), timestamp: 2.03))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Shift), flags: right, timestamp: 2.06))
        monitor.setRightCommand(false, at: 2.1)
        monitor.setRightCommand(true, at: 3)
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: right.union(left), timestamp: 3.03))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: right, timestamp: 3.06))
        monitor.setRightCommand(false, at: 3.1)
        monitor.setRightCommand(true, at: 4)
        monitor.send(.synchronized(false)) // Watchdog noticed a lost key-up; not a tap.
        monitor.setRightCommand(false, at: 4.1)
        monitor.setRightCommand(true, at: 5)
        manager.setSuspended(true)
        manager.setSuspended(false)
        monitor.setRightCommand(false, at: 5.1)
        XCTAssertEqual(launches, 0)
        monitor.setRightCommand(true, at: 6)
        monitor.setRightCommand(false, at: 6.1)
        XCTAssertEqual(launches, 1)
    }

    func testPhysicalF19WorksStandaloneWithoutImplicitRightCommandTap() throws {
        let monitor = FakeRightCommandMonitor()
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor, inputWasQuietSince: { _ in true })
        let f19 = UInt32(kVK_F19)
        var launches = 0
        try manager.register(name: "launcher", keyCode: f19, modifiers: 0) { launches += 1 }
        XCTAssertFalse(monitor.isStarted, "Bare F19 should not implicitly hook Right Command tap")
        backend.emit(id: try XCTUnwrap(backend.active.first?.key))
        XCTAssertEqual(launches, 1)

        try manager.register(name: "launcher", preset: .rightCommandTap) { launches += 1 }
        XCTAssertTrue(monitor.isStarted)
        XCTAssertTrue(backend.active.isEmpty)
        monitor.setRightCommand(true, at: 1)
        try manager.register(name: "launcher", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { launches += 1 }
        XCTAssertFalse(monitor.isStarted)
        monitor.setRightCommand(false, at: 1.1)
        XCTAssertEqual(launches, 1)
    }

    func testDoubleTapModifierTriggersForCommandOptionControlAndShift() throws {
        let cases: [(ModifierTapKey, UInt16, NSEvent.ModifierFlags)] = [
            (.command, UInt16(kVK_Command), left),
            (.command, UInt16(kVK_RightCommand), right),
            (.option, UInt16(kVK_Option), .option),
            (.control, UInt16(kVK_Control), .control),
            (.shift, UInt16(kVK_Shift), .shift),
        ]

        for (key, keyCode, flags) in cases {
            let monitor = FakeRightCommandMonitor()
            let backend = FakeHotKeyBackend()
            let manager = HotKeyManager(backend: backend, modifierMonitor: monitor, inputWasQuietSince: { _ in true })
            var launches = 0

            try manager.register(name: "launcher", preset: .doubleTap(key)) { launches += 1 }
            XCTAssertTrue(monitor.isStarted, "Monitor should run for \(key)")
            XCTAssertTrue(backend.active.isEmpty, "Double-tap should not occupy a Carbon slot")

            // First tap alone does not trigger.
            monitor.send(.flagsChanged(keyCode: keyCode, flags: flags, timestamp: 1.0))
            monitor.send(.flagsChanged(keyCode: keyCode, flags: [], timestamp: 1.08))
            XCTAssertEqual(launches, 0)

            // Second tap within window triggers on release.
            monitor.send(.flagsChanged(keyCode: keyCode, flags: flags, timestamp: 1.2))
            XCTAssertEqual(launches, 0, "Should wait for second release so chords cannot false-trigger")
            monitor.send(.flagsChanged(keyCode: keyCode, flags: [], timestamp: 1.28))
            XCTAssertEqual(launches, 1, "Double-tap should fire for \(key)")

            // Immediate third tap starts a fresh sequence rather than firing a second time.
            monitor.send(.flagsChanged(keyCode: keyCode, flags: flags, timestamp: 1.4))
            monitor.send(.flagsChanged(keyCode: keyCode, flags: [], timestamp: 1.48))
            XCTAssertEqual(launches, 1)
        }
    }

    func testDoubleTapRejectsChordsInterruptingInputLongHoldAndSlowInterval() throws {
        var lastInterrupt: TimeInterval = 0
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(
            backend: FakeHotKeyBackend(),
            modifierMonitor: monitor,
            inputWasQuietSince: { since in since > lastInterrupt }
        )
        var launches = 0
        try manager.register(name: "launcher", preset: .doubleTap(.command)) { launches += 1 }

        // 1. Key pressed between first and second tap cancels double-tap.
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 1.0))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 1.05))
        lastInterrupt = 1.1
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 1.15))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 1.2))
        XCTAssertEqual(launches, 0)

        // 2. Second tap chorded with another key (e.g., ⌘C) cancels double-tap.
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 2.0))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 2.05))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 2.15))
        lastInterrupt = 2.18
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 2.22))
        XCTAssertEqual(launches, 0)

        // 3. Long hold (> 0.3s) is not a tap.
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 3.0))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 3.45))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 3.55))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 3.6))
        XCTAssertEqual(launches, 0)

        // 4. Slow gap (> 0.35s) does not double-tap.
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 4.0))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 4.05))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 4.5))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 4.55))
        XCTAssertEqual(launches, 0)

        // 5. Suspended manager cancels pending sequence.
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 5.0))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 5.05))
        manager.setSuspended(true)
        manager.setSuspended(false)
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 5.15))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 5.2))
        XCTAssertEqual(launches, 0)

        // 6. Clean double-tap succeeds.
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 6.0))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 6.05))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 6.18))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 6.24))
        XCTAssertEqual(launches, 1)
    }

    func testRightCommandTapAndDoubleTapCommandCoexistWithoutCrossTriggering() throws {
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: FakeHotKeyBackend(), modifierMonitor: monitor, inputWasQuietSince: { _ in true })
        var launcherCount = 0
        var clipboardCount = 0

        try manager.register(name: "launcher", preset: .rightCommandTap) { launcherCount += 1 }
        try manager.register(name: "clipboard", preset: .doubleTap(.command)) { clipboardCount += 1 }

        // Two rapid Right Command taps toggle launcher twice without firing double-tap Command clipboard.
        monitor.setRightCommand(true, at: 1.0)
        monitor.setRightCommand(false, at: 1.05)
        monitor.setRightCommand(true, at: 1.15)
        monitor.setRightCommand(false, at: 1.20)
        XCTAssertEqual(launcherCount, 2)
        XCTAssertEqual(clipboardCount, 0)

        // Double-tapping Left Command triggers clipboard without firing launcher.
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 2.0))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 2.05))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: left, timestamp: 2.15))
        monitor.send(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [], timestamp: 2.20))
        XCTAssertEqual(launcherCount, 2)
        XCTAssertEqual(clipboardCount, 1)
    }

    func testDuplicateModifierTapRegistrationThrowsConflict() throws {
        let manager = HotKeyManager(backend: FakeHotKeyBackend(), modifierMonitor: FakeRightCommandMonitor())
        try manager.register(name: "launcher", preset: .rightCommandTap) {}
        XCTAssertThrowsError(try manager.register(name: "clipboard", preset: .rightCommandTap) {})
        try manager.register(name: "clipboard", preset: .doubleTap(.option)) {}
        XCTAssertThrowsError(try manager.register(name: "other", preset: .doubleTap(.option)) {})
    }
}
