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
                preset: shortcut.hotKey
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
        onScreenshot: @escaping () -> Void = {},
        onUploadClipboard: @escaping () -> Void = {},
        onUploadFile: @escaping () -> Void = {},
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
                onScreenshot: onScreenshot,
                onUploadClipboard: onUploadClipboard,
                onUploadFile: onUploadFile,
                onAppShortcut: onAppShortcut
            )
        } catch {
            restore(
                previous,
                afterUnregistering: next,
                in: manager,
                onLauncher: onLauncher,
                onClipboard: onClipboard,
                onScreenshot: onScreenshot,
                onUploadClipboard: onUploadClipboard,
                onUploadFile: onUploadFile,
                onAppShortcut: onAppShortcut
            )
            throw error
        }
    }

    static func restore(
        _ previous: LauncherSettings,
        afterUnregistering failed: LauncherSettings,
        in manager: HotKeyManager,
        onLauncher: @escaping () -> Void,
        onClipboard: @escaping () -> Void,
        onScreenshot: @escaping () -> Void = {},
        onUploadClipboard: @escaping () -> Void = {},
        onUploadFile: @escaping () -> Void = {},
        onAppShortcut: @escaping (AppShortcut) -> Void
    ) {
        unregisterManagedBindings(from: failed, in: manager)
        restoreManagedBindings(
            from: previous,
            in: manager,
            onLauncher: onLauncher,
            onClipboard: onClipboard,
            onScreenshot: onScreenshot,
            onUploadClipboard: onUploadClipboard,
            onUploadFile: onUploadFile,
            onAppShortcut: onAppShortcut
        )
    }

    private static func unregisterManagedBindings(from settings: LauncherSettings, in manager: HotKeyManager) {
        manager.unregister(name: "launcher")
        manager.unregister(name: "clipboard")
        manager.unregister(name: "screenshot")
        manager.unregister(name: "uploadClipboard")
        manager.unregister(name: "uploadFile")
        for shortcut in settings.appShortcuts {
            manager.unregister(name: registrationName(for: shortcut.id))
        }
    }

    private static func registerManagedBindings(
        from settings: LauncherSettings,
        in manager: HotKeyManager,
        onLauncher: @escaping () -> Void,
        onClipboard: @escaping () -> Void,
        onScreenshot: @escaping () -> Void,
        onUploadClipboard: @escaping () -> Void,
        onUploadFile: @escaping () -> Void,
        onAppShortcut: @escaping (AppShortcut) -> Void
    ) throws {
        try manager.register(name: "launcher", preset: settings.hotKey, callback: onLauncher)
        try manager.register(name: "clipboard", preset: settings.clipboardHotKey, callback: onClipboard)
        if let screenshot = settings.screenshotHotKey {
            try manager.register(name: "screenshot", preset: screenshot, callback: onScreenshot)
        }
        if let uploadClipboard = settings.imageUpload.uploadClipboardHotKey {
            try manager.register(name: "uploadClipboard", preset: uploadClipboard, callback: onUploadClipboard)
        }
        if let uploadFile = settings.imageUpload.uploadFileHotKey {
            try manager.register(name: "uploadFile", preset: uploadFile, callback: onUploadFile)
        }
        for shortcut in settings.appShortcuts where shortcut.isEnabled {
            try manager.register(name: registrationName(for: shortcut.id), preset: shortcut.hotKey) {
                onAppShortcut(shortcut)
            }
        }
    }

    private static func restoreManagedBindings(
        from settings: LauncherSettings,
        in manager: HotKeyManager,
        onLauncher: @escaping () -> Void,
        onClipboard: @escaping () -> Void,
        onScreenshot: @escaping () -> Void,
        onUploadClipboard: @escaping () -> Void,
        onUploadFile: @escaping () -> Void,
        onAppShortcut: @escaping (AppShortcut) -> Void
    ) {
        try? manager.register(name: "launcher", preset: settings.hotKey, callback: onLauncher)
        try? manager.register(name: "clipboard", preset: settings.clipboardHotKey, callback: onClipboard)
        if let screenshot = settings.screenshotHotKey {
            try? manager.register(name: "screenshot", preset: screenshot, callback: onScreenshot)
        }
        if let uploadClipboard = settings.imageUpload.uploadClipboardHotKey {
            try? manager.register(name: "uploadClipboard", preset: uploadClipboard, callback: onUploadClipboard)
        }
        if let uploadFile = settings.imageUpload.uploadFileHotKey {
            try? manager.register(name: "uploadFile", preset: uploadFile, callback: onUploadFile)
        }
        for shortcut in settings.appShortcuts where shortcut.isEnabled {
            try? manager.register(name: registrationName(for: shortcut.id), preset: shortcut.hotKey) {
                onAppShortcut(shortcut)
            }
        }
    }
}
