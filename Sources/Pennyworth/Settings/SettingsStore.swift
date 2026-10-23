import Foundation
import Carbon

enum HotKeyPreset: String, Codable, CaseIterable {
    case optionSpace, optionShiftSpace, controlOptionSpace
    case optionCommandC, controlOptionC
    case commandComma

    var title: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .optionShiftSpace: return "⌥ ⇧ Space"
        case .controlOptionSpace: return "⌃ ⌥ Space"
        case .optionCommandC: return "⌥ ⌘ C"
        case .controlOptionC: return "⌃ ⌥ C"
        case .commandComma: return "⌘ ,"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .optionShiftSpace, .controlOptionSpace: return UInt32(kVK_Space)
        case .optionCommandC, .controlOptionC: return UInt32(kVK_ANSI_C)
        case .commandComma: return UInt32(kVK_ANSI_Comma)
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
        }
    }

    static let launcherPresets: [HotKeyPreset] = [.optionSpace, .optionShiftSpace, .controlOptionSpace]
    static let clipboardPresets: [HotKeyPreset] = [.optionCommandC, .controlOptionC]
}

struct LauncherSettings: Codable, Equatable {
    let hotKey: HotKeyPreset
    let searchDirectories: [String]
    let searchEngine: SearchEngine
    let rememberUsage: Bool
    let fallbackOnlyWhenNoResults: Bool
    let clipboardHotKey: HotKeyPreset

    init(hotKey: HotKeyPreset, searchDirectories: [String], searchEngine: SearchEngine,
         rememberUsage: Bool, fallbackOnlyWhenNoResults: Bool = false,
         clipboardHotKey: HotKeyPreset = .optionCommandC) {
        self.hotKey = hotKey
        self.searchDirectories = searchDirectories
        self.searchEngine = searchEngine
        self.rememberUsage = rememberUsage
        self.fallbackOnlyWhenNoResults = fallbackOnlyWhenNoResults
        self.clipboardHotKey = clipboardHotKey
    }

    private enum CodingKeys: String, CodingKey {
        case hotKey, searchDirectories, searchEngine, rememberUsage, fallbackOnlyWhenNoResults, clipboardHotKey
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try values.decode(HotKeyPreset.self, forKey: .hotKey)
        searchDirectories = try values.decode([String].self, forKey: .searchDirectories)
        searchEngine = try values.decode(SearchEngine.self, forKey: .searchEngine)
        rememberUsage = try values.decode(Bool.self, forKey: .rememberUsage)
        fallbackOnlyWhenNoResults = try values.decodeIfPresent(Bool.self, forKey: .fallbackOnlyWhenNoResults) ?? false
        clipboardHotKey = try values.decodeIfPresent(HotKeyPreset.self, forKey: .clipboardHotKey) ?? .optionCommandC
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
                warning = "设置无法读取，已使用默认值。请在设置中重新保存。"
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

    private static func validate(_ value: LauncherSettings) throws {
        guard value.searchDirectories.count <= 32,
              value.searchDirectories.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else {
            throw SettingsError.invalidDirectories
        }
        guard HotKeyPreset.launcherPresets.contains(value.hotKey),
              HotKeyPreset.clipboardPresets.contains(value.clipboardHotKey) else {
            throw SettingsError.invalidHotKeys
        }
    }
}

enum SettingsError: LocalizedError {
    case invalidDirectories, invalidHotKeys
    var errorDescription: String? {
        switch self {
        case .invalidDirectories: return "请选择有效的绝对目录路径（最多 32 个）。"
        case .invalidHotKeys: return "请选择有效的快捷键组合。"
        }
    }
}
