import Foundation
import Carbon

enum HotKeyPreset: Equatable, Codable {
    case optionSpace, optionShiftSpace, controlOptionSpace
    case optionCommandC, controlOptionC
    case commandComma
    case custom(keyCode: UInt32, modifiers: UInt32)

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .optionShiftSpace: return "⌥ ⇧ Space"
        case .controlOptionSpace: return "⌃ ⌥ Space"
        case .optionCommandC: return "⌥ ⌘ C"
        case .controlOptionC: return "⌃ ⌥ C"
        case .commandComma: return "⌘ ,"
        case .custom(let keyCode, let modifiers):
            return Self.modifierTitle(modifiers) + Self.keyTitle(keyCode)
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .optionShiftSpace, .controlOptionSpace: return UInt32(kVK_Space)
        case .optionCommandC, .controlOptionC: return UInt32(kVK_ANSI_C)
        case .commandComma: return UInt32(kVK_ANSI_Comma)
        case .custom(let keyCode, _): return keyCode
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .optionShiftSpace: return UInt32(optionKey | shiftKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .optionCommandC: return UInt32(optionKey | cmdKey)
        case .controlOptionC: return UInt32(controlKey | optionKey)
        case .commandComma: return UInt32(cmdKey)
        case .custom(_, let modifiers): return modifiers
        }
    }

    static let launcherPresets: [HotKeyPreset] = [.optionSpace, .optionShiftSpace, .controlOptionSpace]
    static let clipboardPresets: [HotKeyPreset] = [.optionCommandC, .controlOptionC]

    static func supportsWithoutModifier(_ keyCode: UInt32) -> Bool {
        HotKeyKeyCodeTitles.extendedFunctionKeys[keyCode] != nil
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }
    private enum Fixed: String, Codable {
        case optionSpace, optionShiftSpace, controlOptionSpace, optionCommandC, controlOptionC, commandComma
    }

    init(from decoder: Decoder) throws {
        if let fixed = try? decoder.singleValueContainer().decode(Fixed.self) {
            switch fixed {
            case .optionSpace: self = .optionSpace
            case .optionShiftSpace: self = .optionShiftSpace
            case .controlOptionSpace: self = .controlOptionSpace
            case .optionCommandC: self = .optionCommandC
            case .controlOptionC: self = .controlOptionC
            case .commandComma: self = .commandComma
            }
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self = .custom(keyCode: try values.decode(UInt32.self, forKey: .keyCode),
                       modifiers: try values.decode(UInt32.self, forKey: .modifiers))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .optionSpace: try encodeFixed(.optionSpace, to: encoder)
        case .optionShiftSpace: try encodeFixed(.optionShiftSpace, to: encoder)
        case .controlOptionSpace: try encodeFixed(.controlOptionSpace, to: encoder)
        case .optionCommandC: try encodeFixed(.optionCommandC, to: encoder)
        case .controlOptionC: try encodeFixed(.controlOptionC, to: encoder)
        case .commandComma: try encodeFixed(.commandComma, to: encoder)
        case .custom(let keyCode, let modifiers):
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(keyCode, forKey: .keyCode)
            try values.encode(modifiers, forKey: .modifiers)
        }
    }

    private func encodeFixed(_ value: Fixed, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    private static func modifierTitle(_ modifiers: UInt32) -> String {
        var title = ""
        if HotKeyModifiers.usesRightCommand(modifiers) {
            title += L10n.tr("hotkey.modifier.right_command")
        }
        if modifiers & UInt32(cmdKey) != 0 { title += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { title += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { title += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { title += "⇧" }
        return title
    }

    private static func keyTitle(_ keyCode: UInt32) -> String {
        HotKeyKeyCodeTitles.title(for: keyCode)
    }
}

struct LauncherSettings: Codable, Equatable {
    let hotKey: HotKeyPreset
    let searchDirectories: [String]
    let searchEngine: SearchEngine
    let webSearches: [WebSearchDefinition]
    let rememberUsage: Bool
    let fallbackOnlyWhenNoResults: Bool
    let clipboardHotKey: HotKeyPreset
    let language: AppLanguage
    let appShortcuts: [AppShortcut]

    init(hotKey: HotKeyPreset, searchDirectories: [String], searchEngine: SearchEngine,
         rememberUsage: Bool, webSearches: [WebSearchDefinition] = WebSearchDefinition.builtIns,
         fallbackOnlyWhenNoResults: Bool = false, clipboardHotKey: HotKeyPreset = .optionCommandC,
         language: AppLanguage = .system, appShortcuts: [AppShortcut] = []) {
        self.hotKey = hotKey
        self.searchDirectories = searchDirectories
        self.searchEngine = searchEngine
        self.webSearches = webSearches
        self.rememberUsage = rememberUsage
        self.fallbackOnlyWhenNoResults = fallbackOnlyWhenNoResults
        self.clipboardHotKey = clipboardHotKey
        self.language = language
        self.appShortcuts = appShortcuts
    }

    private enum CodingKeys: String, CodingKey {
        case hotKey, searchDirectories, searchEngine, webSearches, rememberUsage
        case fallbackOnlyWhenNoResults, clipboardHotKey, language, appShortcuts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try values.decode(HotKeyPreset.self, forKey: .hotKey)
        searchDirectories = try values.decode([String].self, forKey: .searchDirectories)
        searchEngine = try values.decode(SearchEngine.self, forKey: .searchEngine)
        webSearches = try values.decodeIfPresent([WebSearchDefinition].self, forKey: .webSearches)
            ?? WebSearchDefinition.builtIns
        rememberUsage = try values.decode(Bool.self, forKey: .rememberUsage)
        fallbackOnlyWhenNoResults = try values.decodeIfPresent(Bool.self, forKey: .fallbackOnlyWhenNoResults) ?? false
        clipboardHotKey = try values.decodeIfPresent(HotKeyPreset.self, forKey: .clipboardHotKey) ?? .optionCommandC
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        appShortcuts = try values.decodeIfPresent([AppShortcut].self, forKey: .appShortcuts) ?? []
    }

    static let defaults = LauncherSettings(hotKey: .optionSpace, searchDirectories: [],
                                           searchEngine: .google, rememberUsage: true)
}

final class SettingsStore {
    private static let key = "launcher.settings.v1"
    private let defaults: UserDefaults
    private(set) var settings: LauncherSettings
    private(set) var warning: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                let value = try JSONDecoder().decode(LauncherSettings.self, from: data)
                try Self.validate(value)
                settings = value
            } catch {
                settings = .defaults
                warning = L10n.tr("settings.error.corrupted")
            }
        } else {
            settings = .defaults
        }
    }

    func save(_ value: LauncherSettings) throws {
        try Self.validate(value)
        defaults.set(try JSONEncoder().encode(value), forKey: Self.key)
        settings = value
        warning = nil
    }

    static func validate(_ value: LauncherSettings) throws {
        try WebSearchDefinition.validate(value.webSearches)
        guard value.searchDirectories.count <= 32,
              value.searchDirectories.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else {
            throw SettingsError.invalidDirectories
        }
        guard isValidBinding(value.hotKey, allowed: .launcher),
              isValidBinding(value.clipboardHotKey, allowed: .clipboard),
              value.hotKey.keyCode != HotKeyPreset.commandComma.keyCode || value.hotKey.modifiers != HotKeyPreset.commandComma.modifiers,
              value.clipboardHotKey.keyCode != HotKeyPreset.commandComma.keyCode || value.clipboardHotKey.modifiers != HotKeyPreset.commandComma.modifiers,
              value.hotKey.keyCode != value.clipboardHotKey.keyCode || value.hotKey.modifiers != value.clipboardHotKey.modifiers else {
            throw SettingsError.invalidHotKeys
        }
        try AppShortcut.validate(
            value.appShortcuts,
            reservedHotKeys: [value.hotKey, value.clipboardHotKey, .commandComma]
        )
    }

    static func isValidAppShortcutBinding(_ binding: HotKeyPreset) -> Bool {
        if HotKeyPreset.launcherPresets.contains(binding) || HotKeyPreset.clipboardPresets.contains(binding) {
            return true
        }
        return isValidCustomBinding(binding)
    }

    private enum BindingGroup { case launcher, clipboard }

    private static func isValidBinding(_ binding: HotKeyPreset, allowed: BindingGroup) -> Bool {
        if allowed == .launcher && HotKeyPreset.launcherPresets.contains(binding) { return true }
        if allowed == .clipboard && HotKeyPreset.clipboardPresets.contains(binding) { return true }
        return isValidCustomBinding(binding)
    }

    private static func isValidCustomBinding(_ binding: HotKeyPreset) -> Bool {
        guard case .custom(let keyCode, let modifiers) = binding else { return false }
        return keyCode <= UInt32(UInt16.max)
            && !HotKeyModifiers.hasConflictingCommandFlags(modifiers)
            && (modifiers != 0 || HotKeyPreset.supportsWithoutModifier(keyCode))
            && modifiers & ~HotKeyModifiers.allowedModifiers == 0
    }
}

enum SettingsError: LocalizedError {
    case invalidDirectories, invalidHotKeys
    var errorDescription: String? {
        switch self {
        case .invalidDirectories: return L10n.tr("settings.error.invalid_directories")
        case .invalidHotKeys: return L10n.tr("settings.error.invalid_hotkeys")
        }
    }
}
