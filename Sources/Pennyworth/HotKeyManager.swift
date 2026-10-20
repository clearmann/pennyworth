import AppKit
import Carbon
import os

enum HotKeyError: Error, LocalizedError {
    case registrationFailed(OSStatus)
    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "无法注册热键（OSStatus \(status)）。请尝试其他组合，原热键保持不变。"
        }
    }
}

protocol HotKeyBackend: AnyObject {
    func install(_ callback: @escaping (UInt32) -> Void) throws
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws
    func unregister(id: UInt32)
}

final class HotKeyManager {
    static let shared = HotKeyManager(backend: CarbonHotKeyBackend())
    private let backend: HotKeyBackend
    private var installed = false
    private var nextID: UInt32 = 1
    private var currentID: UInt32?
    private var currentKey: UInt32?
    private(set) var currentModifiers: UInt32?
    var onHotKey: (() -> Void)?

    init(backend: HotKeyBackend) { self.backend = backend }

    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey)) throws {
        if currentID != nil, currentKey == keyCode, currentModifiers == modifiers { return }
        if !installed {
            try backend.install { [weak self] id in
                guard let self, self.currentID == id else { return }
                self.onHotKey?()
            }
            installed = true
        }
        let id = nextID
        try backend.register(keyCode: keyCode, modifiers: modifiers, id: id)
        if let currentID { backend.unregister(id: currentID) }
        currentID = id
        currentKey = keyCode
        currentModifiers = modifiers
        nextID &+= 1
    }

    func unregister() {
        if let currentID { backend.unregister(id: currentID) }
        currentID = nil
        currentKey = nil
        currentModifiers = nil
    }
}

private final class CarbonHotKeyBackend: HotKeyBackend {
    private static let signature: OSType = 0x5057_524F
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var callback: ((UInt32) -> Void)?

    func install(_ callback: @escaping (UInt32) -> Void) throws {
        self.callback = callback
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr, key.signature == CarbonHotKeyBackend.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(context).takeUnretainedValue()
            backend.callback?(key.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw HotKeyError.registrationFailed(status) }
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                        GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotKeyError.registrationFailed(status) }
        registrations = registrations.merging([id: ref]) { _, new in new }
    }

    func unregister(id: UInt32) {
        guard let ref = registrations[id] else { return }
        let status = UnregisterEventHotKey(ref)
        if status != noErr {
            Logger(subsystem: "com.clearmann.pennyworth", category: "HotKey").error("热键注销失败：\(status)")
        }
        registrations = registrations.filter { $0.key != id }
    }

    deinit {
        registrations.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
