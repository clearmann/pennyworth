import Foundation

struct AppShortcut: Codable, Equatable {
    let id: String
    let bundleIdentifier: String?
    let appPath: String
    let appName: String
    let hotKey: HotKeyPreset
    let isEnabled: Bool

    init(
        id: String,
        bundleIdentifier: String?,
        appPath: String,
        appName: String,
        hotKey: HotKeyPreset,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.appName = appName
        self.hotKey = hotKey
        self.isEnabled = isEnabled
    }
}

enum AppShortcutValidationError: LocalizedError, Equatable {
    case tooManyShortcuts
    case invalidIdentifier
    case duplicateIdentifier
    case invalidApplication
    case missingHotKey
    case invalidHotKey
    case duplicateHotKey(String)

    var errorDescription: String? {
        switch self {
        case .tooManyShortcuts:
            return L10n.tr("app_shortcuts.error.too_many")
        case .invalidIdentifier:
            return L10n.tr("app_shortcuts.error.invalid_identifier")
        case .duplicateIdentifier:
            return L10n.tr("app_shortcuts.error.duplicate_identifier")
        case .invalidApplication:
            return L10n.tr("app_shortcuts.error.invalid_app")
        case .missingHotKey:
            return L10n.tr("app_shortcuts.error.missing_hotkey")
        case .invalidHotKey:
            return L10n.tr("settings.error.invalid_hotkeys")
        case .duplicateHotKey(let title):
            return L10n.format("app_shortcuts.error.duplicate_hotkey", title)
        }
    }
}

extension AppShortcut {
    static func validate(_ shortcuts: [AppShortcut], reservedHotKeys: [HotKeyPreset]) throws {
        guard shortcuts.count <= 64 else {
            throw AppShortcutValidationError.tooManyShortcuts
        }
        var seenIDs = Set<String>()
        var usedBindings = Set(reservedHotKeys.map(\.trigger))
        for shortcut in shortcuts {
            guard !shortcut.id.isEmpty, shortcut.id.count <= 64 else {
                throw AppShortcutValidationError.invalidIdentifier
            }
            guard seenIDs.insert(shortcut.id).inserted else {
                throw AppShortcutValidationError.duplicateIdentifier
            }
            let trimmedName = shortcut.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty,
                  shortcut.appName.count <= 120,
                  shortcut.appPath.hasPrefix("/"),
                  shortcut.appPath.count <= 1024,
                  !shortcut.appPath.contains("\0"),
                  URL(fileURLWithPath: shortcut.appPath).pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                throw AppShortcutValidationError.invalidApplication
            }
            if let bundleID = shortcut.bundleIdentifier {
                guard !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      bundleID.count <= 256 else {
                    throw AppShortcutValidationError.invalidApplication
                }
            }
            guard SettingsStore.isValidAppShortcutBinding(shortcut.hotKey) else {
                throw AppShortcutValidationError.invalidHotKey
            }
            guard usedBindings.insert(shortcut.hotKey.trigger).inserted else {
                throw AppShortcutValidationError.duplicateHotKey(shortcut.hotKey.title)
            }
        }
    }
}
