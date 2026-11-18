import Foundation
import Carbon

enum HotKeyPreset: Equatable, Codable {
    case optionSpace, optionShiftSpace, controlOptionSpace
    case optionCommandC, controlOptionC
    case commandComma
    case controlOptionP
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
        case .controlOptionP: return "⌃ ⌥ P"
        case .custom(let keyCode, let modifiers):
            return Self.modifierTitle(modifiers) + Self.keyTitle(keyCode)
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .optionShiftSpace, .controlOptionSpace: return UInt32(kVK_Space)
        case .optionCommandC, .controlOptionC: return UInt32(kVK_ANSI_C)
        case .commandComma: return UInt32(kVK_ANSI_Comma)
        case .controlOptionP: return UInt32(kVK_ANSI_P)
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
        case .controlOptionP: return UInt32(controlKey | optionKey)
        case .custom(_, let modifiers): return modifiers
        }
    }

    static let launcherPresets: [HotKeyPreset] = [.optionSpace, .optionShiftSpace, .controlOptionSpace]
    static let clipboardPresets: [HotKeyPreset] = [.optionCommandC, .controlOptionC]
    private static let extendedFunctionKeys: [UInt32: String] = [
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]

    static func supportsWithoutModifier(_ keyCode: UInt32) -> Bool {
        extendedFunctionKeys[keyCode] != nil
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }
    private enum Fixed: String, Codable {
        case optionSpace, optionShiftSpace, controlOptionSpace, optionCommandC, controlOptionC, commandComma, controlOptionP
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
            case .controlOptionP: self = .controlOptionP
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
        case .controlOptionP: try encodeFixed(.controlOptionP, to: encoder)
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
        if modifiers & UInt32(cmdKey) != 0 { title += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { title += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { title += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { title += "⇧" }
        return title
    }

    private static func keyTitle(_ keyCode: UInt32) -> String {
        if keyCode == UInt32(kVK_Space) { return "Space" }
        if keyCode == UInt32(kVK_ANSI_C) { return "C" }
        if keyCode == UInt32(kVK_ANSI_P) { return "P" }
        if keyCode == UInt32(kVK_ANSI_Comma) { return "," }
        if let functionKey = extendedFunctionKeys[keyCode] { return functionKey }
        return "Key \(keyCode)"
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
    /// nil means the user disabled the screenshot hotkey (Delete in the recorder).
    let screenshotHotKey: HotKeyPreset?

    init(hotKey: HotKeyPreset, searchDirectories: [String], searchEngine: SearchEngine,
         rememberUsage: Bool, webSearches: [WebSearchDefinition] = WebSearchDefinition.builtIns,
         fallbackOnlyWhenNoResults: Bool = false, clipboardHotKey: HotKeyPreset = .optionCommandC,
         language: AppLanguage = .system, screenshotHotKey: HotKeyPreset? = .controlOptionP) {
        self.hotKey = hotKey
        self.searchDirectories = searchDirectories
        self.searchEngine = searchEngine
        self.webSearches = webSearches
        self.rememberUsage = rememberUsage
        self.fallbackOnlyWhenNoResults = fallbackOnlyWhenNoResults
        self.clipboardHotKey = clipboardHotKey
        self.language = language
        self.screenshotHotKey = screenshotHotKey
    }

    private enum CodingKeys: String, CodingKey {
        case hotKey, searchDirectories, searchEngine, webSearches, rememberUsage, fallbackOnlyWhenNoResults, clipboardHotKey, language, screenshotHotKey
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
        if values.contains(.screenshotHotKey) {
            // An explicit JSON null is a deliberate user disable.
            screenshotHotKey = try values.decodeIfPresent(HotKeyPreset.self, forKey: .screenshotHotKey)
        } else {
            // Legacy data: offer the default unless it collides with an existing binding.
            let candidate = HotKeyPreset.controlOptionP
            let collides = [hotKey, clipboardHotKey].contains {
                $0.keyCode == candidate.keyCode && $0.modifiers == candidate.modifiers
            }
            screenshotHotKey = collides ? nil : candidate
        }
    }

    static let defaults = LauncherSettings(hotKey: .optionSpace, searchDirectories: [],
                                           searchEngine: .google, rememberUsage: true)

    /// JSONEncoder omits nil optionals by default; screenshotHotKey must encode an explicit
    /// null so that "user disabled" survives a save/load round trip (absent key = legacy default).
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(hotKey, forKey: .hotKey)
        try values.encode(searchDirectories, forKey: .searchDirectories)
        try values.encode(searchEngine, forKey: .searchEngine)
        try values.encode(webSearches, forKey: .webSearches)
        try values.encode(rememberUsage, forKey: .rememberUsage)
        try values.encode(fallbackOnlyWhenNoResults, forKey: .fallbackOnlyWhenNoResults)
        try values.encode(clipboardHotKey, forKey: .clipboardHotKey)
        try values.encode(language, forKey: .language)
        if let screenshotHotKey {
            try values.encode(screenshotHotKey, forKey: .screenshotHotKey)
        } else {
            try values.encodeNil(forKey: .screenshotHotKey)
        }
    }
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
                if Self.isLegacyMigrationDisable(data: data, value: value) {
                    warning = L10n.tr("settings.warning.screenshot_hotkey_disabled")
                }
            } catch {
                settings = .defaults
                warning = L10n.tr("settings.error.corrupted")
            }
        } else {
            settings = .defaults
        }
    }

    /// Legacy JSON without a screenshotHotKey key whose default collided with an existing
    /// binding is migrated to "disabled" with a warning instead of corrupting all settings.
    private static func isLegacyMigrationDisable(data: Data, value: LauncherSettings) -> Bool {
        guard value.screenshotHotKey == nil,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              raw["screenshotHotKey"] == nil else { return false }
        return true
    }

    func save(_ value: LauncherSettings) throws {
        try Self.validate(value)
        defaults.set(try JSONEncoder().encode(value), forKey: Self.key)
        settings = value
        warning = nil
    }

    private static func validate(_ value: LauncherSettings) throws {
        try WebSearchDefinition.validate(value.webSearches)
        guard value.searchDirectories.count <= 32,
              value.searchDirectories.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else {
            throw SettingsError.invalidDirectories
        }
        guard isValidBinding(value.hotKey, allowed: .launcher),
              isValidBinding(value.clipboardHotKey, allowed: .clipboard),
              !sameBinding(value.hotKey, HotKeyPreset.commandComma),
              !sameBinding(value.clipboardHotKey, HotKeyPreset.commandComma),
              !sameBinding(value.hotKey, value.clipboardHotKey) else {
            throw SettingsError.invalidHotKeys
        }
        if let screenshot = value.screenshotHotKey {
            guard isValidBinding(screenshot, allowed: .screenshot),
                  !sameBinding(screenshot, HotKeyPreset.commandComma),
                  !sameBinding(screenshot, value.hotKey),
                  !sameBinding(screenshot, value.clipboardHotKey) else {
                throw SettingsError.invalidHotKeys
            }
        }
    }

    /// Compares physical key combinations: .optionCommandC and .custom(⌥⌘C) are the same hotkey.
    private static func sameBinding(_ a: HotKeyPreset, _ b: HotKeyPreset) -> Bool {
        a.keyCode == b.keyCode && a.modifiers == b.modifiers
    }

    private enum BindingGroup { case launcher, clipboard, screenshot }

    private static func isValidBinding(_ binding: HotKeyPreset, allowed: BindingGroup) -> Bool {
        if allowed == .launcher && HotKeyPreset.launcherPresets.contains(binding) { return true }
        if allowed == .clipboard && HotKeyPreset.clipboardPresets.contains(binding) { return true }
        if allowed == .screenshot && binding == .controlOptionP { return true }
        guard case .custom(let keyCode, let modifiers) = binding else { return false }
        let allowedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return keyCode <= UInt32(UInt16.max)
            && (modifiers != 0 || HotKeyPreset.supportsWithoutModifier(keyCode))
            && modifiers & ~allowedModifiers == 0
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
