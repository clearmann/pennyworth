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
}

final class FakeHotKeyBackend: HotKeyBackend {
    var fail = false
    var registrations = 0
    var removed: [UInt32] = []
    func install(_ callback: @escaping (UInt32) -> Void) throws {}
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
        if fail { throw HotKeyError.registrationFailed(-1) }
        registrations += 1
    }
    func unregister(id: UInt32) { removed = removed + [id] }
}
