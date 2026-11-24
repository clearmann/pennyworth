@testable import Pennyworth
import AppKit
import Carbon
import XCTest

final class HotKeyTests: XCTestCase {
    func testFailedReplacementKeepsExistingRegistration() throws {
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend)
        try manager.register(keyCode: 49, modifiers: 1)
        backend.fail = true
        XCTAssertThrowsError(try manager.register(keyCode: 49, modifiers: 2))
        XCTAssertEqual(manager.currentModifiers, 1)
        XCTAssertTrue(backend.removed.isEmpty)
        backend.fail = false
        try manager.register(keyCode: 49, modifiers: 2)
        XCTAssertEqual(manager.currentModifiers, 2)
        XCTAssertEqual(backend.removed, [1])
        try manager.register(keyCode: 49, modifiers: 2)
        XCTAssertEqual(backend.registrations, 2)
        manager.unregister()
        XCTAssertNil(manager.currentModifiers)
    }

    func testCustomHotKeyRoundTripsAndFormatsTitle() throws {
        let binding = HotKeyPreset.custom(keyCode: 35, modifiers: 256 | 4096)
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotKeyPreset.self, from: data)

        XCTAssertEqual(decoded, binding)
        XCTAssertEqual(binding.title, "⌘⌃P")
    }

    func testExtendedFunctionKeyTitles() {
        let functionKeys: [(keyCode: UInt32, name: String)] = [
            (105, "F13"), (107, "F14"), (113, "F15"), (106, "F16"),
            (64, "F17"), (79, "F18"), (80, "F19"), (90, "F20"),
        ]

        for key in functionKeys {
            XCTAssertEqual(HotKeyPreset.custom(keyCode: key.keyCode, modifiers: 0).title, key.name)
        }
    }

    @MainActor func testRecorderAcceptsModifiedKeyAndCancelRestoresPreviousBinding() {
        let recorder = HotKeyRecorderView(binding: .optionSpace)
        recorder.beginRecording()

        XCTAssertTrue(recorder.processKey(keyCode: 35, modifiers: 256 | 4096))
        XCTAssertEqual(recorder.binding, .custom(keyCode: 35, modifiers: 256 | 4096))

        recorder.beginRecording()
        XCTAssertTrue(recorder.processKey(keyCode: 53, modifiers: 0))
        XCTAssertEqual(recorder.binding, .custom(keyCode: 35, modifiers: 256 | 4096))
    }

    @MainActor func testRecorderAcceptsUnmodifiedExtendedFunctionKeys() {
        let functionKeys: [(keyCode: UInt32, name: String)] = [
            (105, "F13"), (107, "F14"), (113, "F15"), (106, "F16"),
            (64, "F17"), (79, "F18"), (80, "F19"), (90, "F20"),
        ]

        for key in functionKeys {
            let recorder = HotKeyRecorderView(binding: .optionSpace)
            recorder.beginRecording()

            XCTAssertTrue(recorder.processKey(keyCode: key.keyCode, modifiers: 0), key.name)
            XCTAssertEqual(recorder.binding, .custom(keyCode: key.keyCode, modifiers: 0), key.name)
        }
    }

    @MainActor func testRecorderRejectsUnmodifiedKeyAndCanClearBinding() {
        let recorder = HotKeyRecorderView(binding: .optionSpace)
        recorder.beginRecording()

        XCTAssertFalse(recorder.processKey(keyCode: 35, modifiers: 0))
        XCTAssertEqual(recorder.binding, .optionSpace)
        XCTAssertTrue(recorder.processKey(keyCode: 51, modifiers: 0))
        XCTAssertNil(recorder.binding)
    }

    func testRightCommandModifierDetectionDistinguishesLeftAndRightCommand() {
        let leftFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x08)
        let rightFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
        let bothFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x08 | 0x10)
        let genericFlags = NSEvent.ModifierFlags.command

        XCTAssertFalse(HotKeyModifiers.isRightCommandOnly(leftFlags))
        XCTAssertTrue(HotKeyModifiers.isRightCommandOnly(rightFlags))
        XCTAssertFalse(HotKeyModifiers.isRightCommandOnly(bothFlags))
        XCTAssertFalse(HotKeyModifiers.isRightCommandOnly(genericFlags))

        XCTAssertEqual(HotKeyRecorderView.carbonModifiers(leftFlags), 256)
        XCTAssertEqual(HotKeyRecorderView.carbonModifiers(rightFlags), HotKeyModifiers.rightCommand)
        XCTAssertEqual(
            HotKeyRecorderView.carbonModifiers(NSEvent.ModifierFlags(rawValue: rightFlags.rawValue | NSEvent.ModifierFlags.shift.rawValue)),
            HotKeyModifiers.rightCommand | 512
        )
    }

    func testRightCommandAndStandardKeyTitlesFormatCleanly() {
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)
        XCTAssertEqual(HotKeyPreset.custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand).title, "右⌘W")
        XCTAssertEqual(HotKeyPreset.custom(keyCode: 13, modifiers: 256).title, "⌘W")
        XCTAssertEqual(HotKeyPreset.custom(keyCode: 17, modifiers: HotKeyModifiers.rightCommand | 512).title, "右⌘⇧T")

        AppLocalization.configure(language: .english)
        XCTAssertEqual(HotKeyPreset.custom(keyCode: 13, modifiers: HotKeyModifiers.rightCommand).title, "Right ⌘W")
    }

    func testDynamicRightCommandHotKeyRegistersOnlyWhileRightCommandHeld() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor)
        var wechatTriggered = 0

        try manager.register(name: "app.wechat", keyCode: 13, modifiers: HotKeyModifiers.rightCommand) {
            wechatTriggered += 1
        }
        XCTAssertTrue(monitor.isStarted)
        XCTAssertTrue(backend.active.isEmpty, "Right Command shortcut must not stay registered while Right Command is up")

        monitor.setRightCommand(true)
        XCTAssertEqual(backend.active.count, 1)
        let activeEntry = try XCTUnwrap(backend.active.first)
        XCTAssertEqual(activeEntry.value.keyCode, 13)
        XCTAssertEqual(activeEntry.value.modifiers, 256)

        backend.emit(id: activeEntry.key)
        XCTAssertEqual(wechatTriggered, 1)

        monitor.setRightCommand(false)
        XCTAssertTrue(backend.active.isEmpty, "Releasing Right Command must immediately unregister Carbon hotkey")

        manager.unregister()
        XCTAssertFalse(monitor.isStarted)
    }

    func testRightCommandTapTriggersOnlyForShortTap() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor, inputWasQuietSince: { _ in true })
        var launcherTriggered = 0

        try manager.register(name: "launcher", preset: .rightCommandTap) { launcherTriggered += 1 }
        XCTAssertTrue(monitor.isStarted, "A registered Right Command tap hotkey should enable monitoring")

        monitor.setRightCommand(true, at: 1.0)
        XCTAssertEqual(launcherTriggered, 0, "Wait for release so the next key can still form a chord")
        monitor.setRightCommand(false, at: 1.12)
        XCTAssertEqual(launcherTriggered, 1)

        monitor.setRightCommand(true, at: 2.0)
        monitor.setRightCommand(false, at: 2.5)
        XCTAssertEqual(launcherTriggered, 1, "A long Right Command hold must not trigger on release")
    }

    func testRightCommandChordSuppressesTapOnlyForThatHold() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor, inputWasQuietSince: { _ in true })
        var launcherTriggered = 0
        var wechatTriggered = 0

        try manager.register(name: "launcher", preset: .rightCommandTap) { launcherTriggered += 1 }
        try manager.register(name: "app.wechat", keyCode: 13, modifiers: HotKeyModifiers.rightCommand) {
            wechatTriggered += 1
        }

        monitor.setRightCommand(true, at: 3)
        let wechatSlotID = try XCTUnwrap(backend.active.first { $0.value.keyCode == 13 }?.key)
        backend.emit(id: wechatSlotID)
        monitor.setRightCommand(false, at: 3.08)
        XCTAssertEqual(wechatTriggered, 1)
        XCTAssertEqual(launcherTriggered, 0, "Releasing Right Command after Right ⌘W must not also open the launcher")

        monitor.setRightCommand(true, at: 4)
        monitor.setRightCommand(false, at: 4.08)
        XCTAssertEqual(launcherTriggered, 1, "A later independent tap should still trigger the launcher")
    }

    func testLeftAndRightCommandShareCarbonSlotAndDispatchIndependently() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor)
        var leftCount = 0
        var rightCount = 0

        try manager.register(name: "settings", keyCode: 43, modifiers: 256) { leftCount += 1 }
        try manager.register(name: "app.sysprefs", keyCode: 43, modifiers: HotKeyModifiers.rightCommand) { rightCount += 1 }
        XCTAssertEqual(backend.active.count, 1)

        let slotID = try XCTUnwrap(backend.active.first?.key)
        backend.emit(id: slotID)
        XCTAssertEqual(leftCount, 1)
        XCTAssertEqual(rightCount, 0)

        monitor.setRightCommand(true)
        XCTAssertEqual(backend.active.count, 1)
        backend.emit(id: slotID)
        XCTAssertEqual(leftCount, 1)
        XCTAssertEqual(rightCount, 1)

        monitor.setRightCommand(false)
        XCTAssertEqual(backend.active.count, 1, "Left Command registration keeps slot active after Right Command release")
        backend.emit(id: slotID)
        XCTAssertEqual(leftCount, 2)
        XCTAssertEqual(rightCount, 1)
    }

    func testSuspendingHotKeyManagerTemporarilyUnregistersAndRestoresSlots() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor)

        try manager.register(name: "launcher", keyCode: 49, modifiers: 2048) {}
        try manager.register(name: "app.wechat", keyCode: 13, modifiers: HotKeyModifiers.rightCommand) {}
        monitor.setRightCommand(true)
        XCTAssertEqual(backend.active.count, 2)

        manager.setSuspended(true)
        XCTAssertTrue(backend.active.isEmpty)

        manager.setSuspended(false)
        XCTAssertEqual(backend.active.count, 2)
    }

    func testSystemRightCommandMonitorTracksFlagsAndAutoReleasesStuckState() {
        let rightFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
        var simulatedFlags: NSEvent.ModifierFlags = []
        let monitor = SystemRightCommandMonitor(flagsProvider: { simulatedFlags })
        var states: [Bool] = []
        let releasedExpectation = expectation(description: "Release watch timer clears stuck Right Command")

        monitor.start { change in
            states.append(change.isActive)
            if case .synchronized(false) = change { releasedExpectation.fulfill() }
        }
        defer { monitor.stop() }

        simulatedFlags = rightFlags
        monitor.processModifierFlags(rightFlags, keyCode: UInt16(kVK_RightCommand), timestamp: 1)
        XCTAssertEqual(states, [true])

        simulatedFlags = []
        wait(for: [releasedExpectation], timeout: 1.0)
        XCTAssertEqual(states, [true, false])
    }

    func testDuplicateBindingUnderDifferentNamesThrowsConflict() throws {
        let backend = FakeHotKeyBackend()
        let monitor = FakeRightCommandMonitor()
        let manager = HotKeyManager(backend: backend, modifierMonitor: monitor)

        try manager.register(name: "first", keyCode: 13, modifiers: HotKeyModifiers.rightCommand) {}
        XCTAssertThrowsError(try manager.register(name: "second", keyCode: 13, modifiers: HotKeyModifiers.rightCommand) {})
        manager.unregister(name: "first")
        try manager.register(name: "second", keyCode: 13, modifiers: HotKeyModifiers.rightCommand) {}
    }

    @MainActor func testRecorderClearResignAndDisabledStates() {
        let recorder = HotKeyRecorderView(binding: .optionSpace)
        var changes: [HotKeyPreset?] = []
        recorder.onChange = { changes.append($0) }

        recorder.beginRecording()
        recorder.isEnabled = false
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.binding, .optionSpace)

        recorder.isEnabled = true
        recorder.beginRecording()
        XCTAssertTrue(recorder.resignFirstResponder())
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.binding, .optionSpace)

        recorder.clearBinding()
        XCTAssertNil(recorder.binding)
        XCTAssertEqual(changes, [nil])
    }

    func testModifierTapPresetsRoundTripAndFormatLocalizedTitles() throws {
        defer { AppLocalization.configure(language: .system) }
        let presets: [HotKeyPreset] = [
            .rightCommandTap,
            .doubleTap(.command),
            .doubleTap(.option),
            .doubleTap(.control),
            .doubleTap(.shift),
        ]
        for preset in presets {
            let data = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(HotKeyPreset.self, from: data)
            XCTAssertEqual(decoded, preset)
        }

        AppLocalization.configure(language: .simplifiedChinese)
        XCTAssertEqual(HotKeyPreset.rightCommandTap.title, "轻按右 ⌘")
        XCTAssertEqual(HotKeyPreset.doubleTap(.command).title, "双击 ⌘")
        XCTAssertEqual(HotKeyPreset.doubleTap(.option).title, "双击 ⌥")
        XCTAssertEqual(HotKeyPreset.doubleTap(.control).title, "双击 ⌃")
        XCTAssertEqual(HotKeyPreset.doubleTap(.shift).title, "双击 ⇧")

        AppLocalization.configure(language: .english)
        XCTAssertEqual(HotKeyPreset.rightCommandTap.title, "Right ⌘ Tap")
        XCTAssertEqual(HotKeyPreset.doubleTap(.command).title, "⌘ Double Tap")
        XCTAssertEqual(HotKeyPreset.doubleTap(.option).title, "⌥ Double Tap")
        XCTAssertEqual(HotKeyPreset.doubleTap(.control).title, "⌃ Double Tap")
        XCTAssertEqual(HotKeyPreset.doubleTap(.shift).title, "⇧ Double Tap")
    }

    @MainActor func testRecorderRecordsDoubleTapModifiersDirectly() {
        let leftFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x08)
        let rightFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)

        let cases: [(ModifierTapKey, UInt16, NSEvent.ModifierFlags)] = [
            (.command, UInt16(kVK_Command), leftFlags),
            (.command, UInt16(kVK_RightCommand), rightFlags),
            (.option, UInt16(kVK_Option), .option),
            (.control, UInt16(kVK_Control), .control),
            (.shift, UInt16(kVK_Shift), .shift),
        ]

        for (key, keyCode, flags) in cases {
            let recorder = HotKeyRecorderView(binding: .optionSpace, allowsClearing: false, allowsModifierTap: true)
            var changes: [HotKeyPreset?] = []
            recorder.onChange = { changes.append($0) }

            recorder.beginRecording()
            recorder.processModifierFlags(flags, keyCode: keyCode, timestamp: 1.0)
            recorder.processModifierFlags([], keyCode: keyCode, timestamp: 1.06)
            XCTAssertTrue(recorder.isRecording)
            recorder.processModifierFlags(flags, keyCode: keyCode, timestamp: 1.18)
            recorder.processModifierFlags([], keyCode: keyCode, timestamp: 1.24)

            XCTAssertFalse(recorder.isRecording)
            XCTAssertEqual(recorder.binding, .doubleTap(key))
            XCTAssertEqual(changes, [.doubleTap(key)])
        }

        // Standard combo cancels pending tap immediately.
        let comboRecorder = HotKeyRecorderView(binding: .optionSpace, allowsClearing: false, allowsModifierTap: true)
        comboRecorder.beginRecording()
        comboRecorder.processModifierFlags(rightFlags, keyCode: UInt16(kVK_RightCommand), timestamp: 2.0)
        XCTAssertTrue(comboRecorder.processKey(keyCode: UInt32(kVK_ANSI_W), modifiers: HotKeyModifiers.rightCommand))
        XCTAssertFalse(comboRecorder.isRecording)
        XCTAssertEqual(comboRecorder.binding, .custom(keyCode: UInt32(kVK_ANSI_W), modifiers: HotKeyModifiers.rightCommand))

        // Recorders with allowsModifierTap == false ignore modifier-only taps.
        let standardRecorder = HotKeyRecorderView(binding: .optionSpace, allowsClearing: true, allowsModifierTap: false)
        standardRecorder.beginRecording()
        standardRecorder.processModifierFlags(leftFlags, keyCode: UInt16(kVK_Command), timestamp: 3.0)
        standardRecorder.processModifierFlags([], keyCode: UInt16(kVK_Command), timestamp: 3.05)
        standardRecorder.processModifierFlags(leftFlags, keyCode: UInt16(kVK_Command), timestamp: 3.15)
        standardRecorder.processModifierFlags([], keyCode: UInt16(kVK_Command), timestamp: 3.2)
        XCTAssertTrue(standardRecorder.isRecording)
        XCTAssertEqual(standardRecorder.binding, .optionSpace)
    }

    @MainActor func testRecorderRecordsSingleRightCommandTapAfterGraceWindowAndCancelsOnEscape() {
        let rightFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
        let leftFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x08)

        let recorder = HotKeyRecorderView(binding: .optionSpace, allowsClearing: false, allowsModifierTap: true)
        recorder.modifierTapCommitDelay = 0.02
        let committed = expectation(description: "Single Right Command tap commits after grace window")
        var changes: [HotKeyPreset?] = []
        recorder.onChange = { binding in
            changes.append(binding)
            if binding == .rightCommandTap { committed.fulfill() }
        }

        recorder.beginRecording()
        recorder.processModifierFlags(rightFlags, keyCode: UInt16(kVK_RightCommand), timestamp: 1.0)
        recorder.processModifierFlags([], keyCode: UInt16(kVK_RightCommand), timestamp: 1.06)
        wait(for: [committed], timeout: 1.0)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.binding, .rightCommandTap)
        XCTAssertEqual(changes, [.rightCommandTap])

        // Escape during grace window cancels and restores original binding.
        let escapeRecorder = HotKeyRecorderView(binding: .optionSpace, allowsClearing: false, allowsModifierTap: true)
        escapeRecorder.modifierTapCommitDelay = 0.05
        escapeRecorder.beginRecording()
        escapeRecorder.processModifierFlags(rightFlags, keyCode: UInt16(kVK_RightCommand), timestamp: 2.0)
        escapeRecorder.processModifierFlags([], keyCode: UInt16(kVK_RightCommand), timestamp: 2.05)
        XCTAssertTrue(escapeRecorder.processKey(keyCode: UInt32(kVK_Escape), modifiers: 0))
        XCTAssertFalse(escapeRecorder.isRecording)
        XCTAssertEqual(escapeRecorder.binding, .optionSpace)

        // Single Left Command tap expires without committing.
        let leftRecorder = HotKeyRecorderView(binding: .optionSpace, allowsClearing: false, allowsModifierTap: true)
        leftRecorder.modifierTapCommitDelay = 0.02
        leftRecorder.beginRecording()
        leftRecorder.processModifierFlags(leftFlags, keyCode: UInt16(kVK_Command), timestamp: 3.0)
        leftRecorder.processModifierFlags([], keyCode: UInt16(kVK_Command), timestamp: 3.05)
        let expired = expectation(description: "Single Left Command tap expires while staying in recording state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { expired.fulfill() }
        wait(for: [expired], timeout: 1.0)
        XCTAssertTrue(leftRecorder.isRecording)
        XCTAssertEqual(leftRecorder.binding, .optionSpace)
    }
}

final class FakeHotKeyBackend: HotKeyBackend {
    struct Entry: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    var fail = false
    var failOnKeyCode: UInt32?
    var registrations = 0
    var removed: [UInt32] = []
    var active: [UInt32: Entry] = [:]
    private var callback: ((UInt32) -> Void)?
    func install(_ callback: @escaping (UInt32) -> Void) throws { self.callback = callback }
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
        if fail || failOnKeyCode == keyCode { throw HotKeyError.registrationFailed(-1) }
        registrations += 1
        active[id] = Entry(keyCode: keyCode, modifiers: modifiers)
    }
    func unregister(id: UInt32) {
        removed = removed + [id]
        active.removeValue(forKey: id)
    }
    func emit(id: UInt32) { callback?(id) }
}

final class FakeRightCommandMonitor: RightCommandMonitoring {
    private(set) var isStarted = false
    private var currentState = false
    private var handler: ((RightCommandChange) -> Void)?

    func start(_ handler: @escaping (RightCommandChange) -> Void) {
        isStarted = true
        self.handler = handler
    }

    func stop() {
        isStarted = false
        handler = nil
    }

    func currentRightCommandState() -> Bool { currentState }

    func send(_ change: RightCommandChange) {
        currentState = change.isActive
        handler?(change)
    }

    func setRightCommand(_ active: Bool, at timestamp: TimeInterval = 0) {
        let right = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
        send(.flagsChanged(keyCode: UInt16(kVK_RightCommand), flags: active ? right : [], timestamp: timestamp))
    }
}
