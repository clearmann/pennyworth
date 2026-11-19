import AppKit
import Carbon
import os

enum HotKeyError: Error, LocalizedError {
    case registrationFailed(OSStatus)
    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return L10n.format("hotkey.error.registration", status)
        }
    }
}

protocol HotKeyBackend: AnyObject {
    func install(_ callback: @escaping (UInt32) -> Void) throws
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws
    func unregister(id: UInt32)
}

final class HotKeyManager {
    static let shared = HotKeyManager(
        backend: CarbonHotKeyBackend(),
        modifierMonitor: SystemRightCommandMonitor()
    )

    private struct CarbonSlot: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private struct Registration {
        let keyCode: UInt32
        let modifiers: UInt32
        let callback: () -> Void

        var usesRightCommand: Bool {
            HotKeyModifiers.usesRightCommand(modifiers)
        }

        var carbonSlot: CarbonSlot {
            CarbonSlot(
                keyCode: keyCode,
                modifiers: HotKeyModifiers.carbonModifiers(for: modifiers)
            )
        }
    }

    private let backend: HotKeyBackend
    private let modifierMonitor: RightCommandMonitoring
    private let rightCommandTap: RightCommandTap
    private let legacyName = "default"
    private let logger = Logger(subsystem: "com.clearmann.pennyworth", category: "HotKey")
    private var installed = false
    private var nextID: UInt32 = 1
    private var registrations: [String: Registration] = [:]
    private var activeSlots: [CarbonSlot: UInt32] = [:]
    private var isRightCommandActive = false
    private var isMonitoringRightCommand = false
    private var isSuspended = false

    private(set) var currentID: UInt32?
    private(set) var currentKey: UInt32?
    private(set) var currentModifiers: UInt32?
    var onHotKey: (() -> Void)?

    init(backend: HotKeyBackend, modifierMonitor: RightCommandMonitoring = SystemRightCommandMonitor(),
         inputWasQuietSince: @escaping (TimeInterval) -> Bool = RightCommandTap.sessionInputWasQuiet) {
        self.backend = backend
        self.modifierMonitor = modifierMonitor
        self.rightCommandTap = RightCommandTap(inputWasQuietSince: inputWasQuietSince)
    }

    private var f19Launcher: Registration? {
        guard let launcher = registrations["launcher"], launcher.keyCode == UInt32(kVK_F19),
              launcher.modifiers == 0 else { return nil }
        return launcher
    }

    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey)) throws {
        try register(name: legacyName, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.onHotKey?()
        }
    }

    func register(name: String, keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) throws {
        if let current = registrations[name], current.keyCode == keyCode, current.modifiers == modifiers {
            registrations = registrations.merging([name: Registration(keyCode: keyCode, modifiers: modifiers, callback: callback)]) { _, new in new }
            return
        }
        let hasDuplicate = registrations.contains { otherName, existing in
            otherName != name && existing.keyCode == keyCode && existing.modifiers == modifiers
        }
        guard !hasDuplicate else {
            throw HotKeyError.registrationFailed(OSStatus(eventHotKeyExistsErr))
        }
        if !installed {
            try backend.install { [weak self] id in self?.handle(id: id) }
            installed = true
        }
        let candidate = Registration(keyCode: keyCode, modifiers: modifiers, callback: callback)
        if candidate.usesRightCommand && !isMonitoringRightCommand {
            isRightCommandActive = modifierMonitor.currentRightCommandState()
        }
        try prepareSlotForRegistration(candidate)
        let previous = registrations[name]
        registrations = registrations.merging([name: candidate]) { _, new in new }
        if let previous, !shouldKeepSlotActive(previous.carbonSlot) {
            unregisterSlot(previous.carbonSlot)
        }
        syncModifierMonitoring()
        updateLegacyState()
    }

    func unregister(name: String) {
        guard registrations[name] != nil else { return }
        registrations = registrations.filter { $0.key != name }
        reconcileActiveSlots()
        syncModifierMonitoring()
        updateLegacyState()
    }

    func unregister() {
        for id in activeSlots.values { backend.unregister(id: id) }
        activeSlots = [:]
        registrations = [:]
        stopModifierMonitoring()
        updateLegacyState()
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        rightCommandTap.cancel()
        if !suspended && isMonitoringRightCommand {
            isRightCommandActive = modifierMonitor.currentRightCommandState()
        }
        reconcileActiveSlots()
    }

    private func prepareSlotForRegistration(_ candidate: Registration) throws {
        let slot = candidate.carbonSlot
        guard activeSlots[slot] == nil else { return }
        let needsActiveNow = !isSuspended && (!candidate.usesRightCommand || isRightCommandActive)
        let id = allocateID()
        try backend.register(keyCode: slot.keyCode, modifiers: slot.modifiers, id: id)
        if needsActiveNow {
            activeSlots = activeSlots.merging([slot: id]) { _, new in new }
        } else {
            backend.unregister(id: id)
        }
    }

    private func handleRightCommandChange(_ change: RightCommandChange) {
        let wasActive = isRightCommandActive
        if wasActive != change.isActive {
            isRightCommandActive = change.isActive
            reconcileActiveSlots()
        }
        guard !isSuspended, let launcher = f19Launcher, activeSlots[launcher.carbonSlot] != nil else {
            rightCommandTap.cancel()
            return
        }
        if rightCommandTap.completesTap(change, wasActive: wasActive) { launcher.callback() }
    }

    private func reconcileActiveSlots() {
        for slot in Array(activeSlots.keys) where !shouldKeepSlotActive(slot) {
            unregisterSlot(slot)
        }
        guard !isSuspended else { return }
        for registration in registrations.values {
            let slot = registration.carbonSlot
            guard shouldKeepSlotActive(slot), activeSlots[slot] == nil else { continue }
            let id = allocateID()
            do {
                try backend.register(keyCode: slot.keyCode, modifiers: slot.modifiers, id: id)
                activeSlots = activeSlots.merging([slot: id]) { _, new in new }
            } catch {
                logger.error("动态热键挂载失败（keyCode=\(slot.keyCode)）：\(error.localizedDescription)")
            }
        }
        updateLegacyState()
    }

    private func shouldKeepSlotActive(_ slot: CarbonSlot) -> Bool {
        guard !isSuspended else { return false }
        return registrations.values.contains { registration in
            registration.carbonSlot == slot && (!registration.usesRightCommand || isRightCommandActive)
        }
    }

    private func unregisterSlot(_ slot: CarbonSlot) {
        guard let id = activeSlots[slot] else { return }
        backend.unregister(id: id)
        activeSlots = activeSlots.filter { $0.key != slot }
    }

    private func syncModifierMonitoring() {
        rightCommandTap.cancel()
        let needsMonitoring = f19Launcher != nil || registrations.values.contains { $0.usesRightCommand }
        if needsMonitoring && !isMonitoringRightCommand {
            isMonitoringRightCommand = true
            isRightCommandActive = modifierMonitor.currentRightCommandState()
            modifierMonitor.start { [weak self] change in self?.handleRightCommandChange(change) }
            reconcileActiveSlots()
        } else if !needsMonitoring && isMonitoringRightCommand {
            stopModifierMonitoring()
        }
    }

    private func stopModifierMonitoring() {
        guard isMonitoringRightCommand else { return }
        modifierMonitor.stop()
        isMonitoringRightCommand = false
        isRightCommandActive = false
    }

    private func allocateID() -> UInt32 {
        defer { nextID &+= 1 }
        return nextID
    }

    private func handle(id: UInt32) {
        guard !isSuspended,
              let slot = activeSlots.first(where: { $0.value == id })?.key else { return }
        rightCommandTap.cancel()
        let rightMatch = registrations.values.first { $0.carbonSlot == slot && $0.usesRightCommand }
        let standardMatch = registrations.values.first { $0.carbonSlot == slot && !$0.usesRightCommand }
        if isRightCommandActive {
            (rightMatch ?? standardMatch)?.callback()
        } else {
            standardMatch?.callback()
        }
    }

    private func updateLegacyState() {
        guard let registration = registrations[legacyName] else {
            currentID = nil
            currentKey = nil
            currentModifiers = nil
            return
        }
        currentID = activeSlots[registration.carbonSlot]
        currentKey = registration.keyCode
        currentModifiers = registration.modifiers
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
