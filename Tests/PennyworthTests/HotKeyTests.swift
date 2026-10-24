@testable import Pennyworth
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
}

final class FakeHotKeyBackend: HotKeyBackend {
    var fail = false
    var registrations = 0
    var removed: [UInt32] = []
    private var callback: ((UInt32) -> Void)?
    func install(_ callback: @escaping (UInt32) -> Void) throws { self.callback = callback }
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
        if fail { throw HotKeyError.registrationFailed(-1) }
        registrations += 1
    }
    func unregister(id: UInt32) { removed = removed + [id] }
    func emit(id: UInt32) { callback?(id) }
}
