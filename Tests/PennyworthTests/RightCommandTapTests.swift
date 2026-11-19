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
        try manager.register(name: "launcher", keyCode: UInt32(kVK_F19), modifiers: 0) { launches += 1 }
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
        try manager.register(name: "launcher", keyCode: UInt32(kVK_F19), modifiers: 0) { launches += 1 }
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

    func testTapTracksOnlyAnActiveBareF19LauncherAndPhysicalF19StillWorks() throws {
        let monitor = FakeRightCommandMonitor()
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor, inputWasQuietSince: { _ in true })
        let f19 = UInt32(kVK_F19)
        var launches = 0
        try manager.register(name: "clipboard", keyCode: f19, modifiers: 0) { XCTFail("Not the launcher") }
        XCTAssertFalse(monitor.isStarted)
        manager.unregister(name: "clipboard")
        try manager.register(name: "launcher", keyCode: f19, modifiers: UInt32(shiftKey)) {}
        XCTAssertFalse(monitor.isStarted)
        try manager.register(name: "launcher", keyCode: f19, modifiers: 0) { launches += 1 }
        backend.emit(id: try XCTUnwrap(backend.active.first?.key))
        XCTAssertEqual(launches, 1)
        monitor.setRightCommand(true, at: 1)
        try manager.register(name: "launcher", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { launches += 1 }
        XCTAssertFalse(monitor.isStarted)
        monitor.setRightCommand(false, at: 1.1)
        XCTAssertEqual(launches, 1)
    }
}
