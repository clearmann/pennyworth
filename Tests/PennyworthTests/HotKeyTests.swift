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

    func testNamedHotKeysRouteAndUnregisterIndependently() throws {
        let backend = FakeHotKeyBackend()
        let manager = HotKeyManager(backend: backend)
        var events: [String] = []
        try manager.register(name: "launcher", keyCode: 49, modifiers: 1) { events.append("launcher") }
        try manager.register(name: "clipboard", keyCode: 8, modifiers: 3) { events.append("clipboard") }

        try manager.register(name: "settings", keyCode: 2, modifiers: 4) { events.append("settings") }
        backend.emit(id: 1)
        backend.emit(id: 2)
        backend.emit(id: 3)
        manager.unregister(name: "launcher")
        backend.emit(id: 1)
        backend.emit(id: 2)
        backend.emit(id: 3)

        XCTAssertEqual(events, ["launcher", "clipboard", "settings", "clipboard", "settings"])
        XCTAssertEqual(backend.removed, [1])
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
