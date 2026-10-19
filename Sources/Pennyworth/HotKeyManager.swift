import AppKit
import Carbon

/// Why registration can fail: Carbon hotkeys are exclusive — first app to
/// claim a shortcut owns it. If Alfred already holds ⌥Space, we get an error.
enum HotKeyError: Error, LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Global hotkey registration failed (OSStatus \(status)). Another app likely owns this shortcut."
        }
    }
}

/// Registers a system-wide hotkey using the Carbon `RegisterEventHotKey` API.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerInstalled = false

    private static let signature: OSType = 0x5057_524F
    private static let hotKeyID: UInt32 = 1

    private init() {}

    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey)) throws {
        unregister()
        installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            throw HotKeyError.registrationFailed(status)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyManager.shared.onHotKey?() }
            return noErr
        }, 1, &eventSpec, nil, nil)
        eventHandlerInstalled = true
    }
}
