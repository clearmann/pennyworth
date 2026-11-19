import Foundation

enum HotKeyConfigurationApplier {
    static func registrationName(for shortcutID: String) -> String {
        "appShortcut.\(shortcutID)"
    }

    static func registerStartupAppShortcuts(
        _ shortcuts: [AppShortcut],
        in manager: HotKeyManager,
        onAppShortcut: @escaping (AppShortcut) -> Void
    ) {
        for shortcut in shortcuts where shortcut.isEnabled {
            try? manager.register(
                name: registrationName(for: shortcut.id),
                keyCode: shortcut.hotKey.keyCode,
                modifiers: shortcut.hotKey.modifiers
            ) {
                onAppShortcut(shortcut)
            }
        }
    }

    static func apply(
        next: LauncherSettings,
        previous: LauncherSettings,
        manager: HotKeyManager,
        onLauncher: @escaping () -> Void,
        onClipboard: @escaping () -> Void,
        onAppShortcut: @escaping (AppShortcut) -> Void
    ) throws {
        try SettingsStore.validate(next)
        unregisterManagedBindings(from: previous, in: manager)
        do {
            try registerManagedBindings(
                from: next,
                in: manager,
                onLauncher: onLauncher,
                onClipboard: onClipboard,
                onAppShortcut: onAppShortcut
            )
        } catch {
            unregisterManagedBindings(from: next, in: manager)
            try? registerManagedBindings(
                from: previous,
                in: manager,
                onLauncher: onLauncher,
                onClipboard: onClipboard,
                onAppShortcut: onAppShortcut
            )
            throw error
        }
    }

    private static func unregisterManagedBindings(from settings: LauncherSettings, in manager: HotKeyManager) {
        manager.unregister(name: "launcher")
        manager.unregister(name: "clipboard")
        for shortcut in settings.appShortcuts {
            manager.unregister(name: registrationName(for: shortcut.id))
        }
    }

    private static func registerManagedBindings(
        from settings: LauncherSettings,
        in manager: HotKeyManager,
        onLauncher: @escaping () -> Void,
        onClipboard: @escaping () -> Void,
        onAppShortcut: @escaping (AppShortcut) -> Void
    ) throws {
        try manager.register(
            name: "launcher",
            keyCode: settings.hotKey.keyCode,
            modifiers: settings.hotKey.modifiers,
            callback: onLauncher
        )
        try manager.register(
            name: "clipboard",
            keyCode: settings.clipboardHotKey.keyCode,
            modifiers: settings.clipboardHotKey.modifiers,
            callback: onClipboard
        )
        for shortcut in settings.appShortcuts where shortcut.isEnabled {
            try manager.register(
                name: registrationName(for: shortcut.id),
                keyCode: shortcut.hotKey.keyCode,
                modifiers: shortcut.hotKey.modifiers
            ) {
                onAppShortcut(shortcut)
            }
        }
    }
}
