import AppKit

protocol RightCommandMonitoring: AnyObject {
    func start(_ handler: @escaping (RightCommandChange) -> Void)
    func stop()
    func currentRightCommandState() -> Bool
}

final class SystemRightCommandMonitor: RightCommandMonitoring {
    private let flagsProvider: () -> NSEvent.ModifierFlags
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var releaseWatchTimer: Timer?
    private var handler: ((RightCommandChange) -> Void)?
    private var lastReportedState = false

    init(flagsProvider: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }) {
        self.flagsProvider = flagsProvider
    }

    func start(_ handler: @escaping (RightCommandChange) -> Void) {
        self.handler = handler
        guard globalMonitor == nil, localMonitor == nil else { return }
        lastReportedState = currentRightCommandState()
        let process: (NSEvent) -> Void = { [weak self] event in
            self?.processModifierFlags(event.modifierFlags, keyCode: event.keyCode, timestamp: event.timestamp)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: process)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            process(event)
            return event
        }
        installLifecycleObservers()
        updateReleaseWatchTimer(active: lastReportedState)
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        removeLifecycleObservers()
        releaseWatchTimer?.invalidate()
        releaseWatchTimer = nil
        lastReportedState = false
        handler = nil
    }

    func currentRightCommandState() -> Bool {
        HotKeyModifiers.isRightCommandOnly(flagsProvider())
    }

    func processModifierFlags(_ flags: NSEvent.ModifierFlags, keyCode: UInt16, timestamp: TimeInterval) {
        report(.flagsChanged(keyCode: keyCode, flags: flags, timestamp: timestamp))
    }

    private func synchronize() {
        report(.synchronized(currentRightCommandState()))
    }

    private func report(_ change: RightCommandChange) {
        let active = change.isActive
        if lastReportedState != active {
            lastReportedState = active
            updateReleaseWatchTimer(active: active)
        }
        handler?(change)
    }

    private func updateReleaseWatchTimer(active: Bool) {
        releaseWatchTimer?.invalidate()
        releaseWatchTimer = nil
        guard active else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, !self.currentRightCommandState() else { return }
            self.report(.synchronized(false))
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatchTimer = timer
    }

    private func installLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default
        let workspaceNotifications: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        let appNotifications: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
        ]
        let workspaceTokens = workspaceNotifications.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.synchronize()
            }
        }
        let appTokens = appNotifications.map { name in
            appCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.synchronize()
            }
        }
        observers = workspaceTokens + appTokens
    }

    private func removeLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default
        for token in observers {
            workspaceCenter.removeObserver(token)
            appCenter.removeObserver(token)
        }
        observers = []
    }

    deinit {
        stop()
    }
}
