import Foundation
import Carbon

enum HotKeyPreset: String, Codable, CaseIterable {
    case optionSpace, optionShiftSpace, controlOptionSpace

    var title: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .optionShiftSpace: return "⌥ ⇧ Space"
        case .controlOptionSpace: return "⌃ ⌥ Space"
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .optionShiftSpace: return UInt32(optionKey | shiftKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        }
    }
}

struct LauncherSettings: Codable, Equatable {
    let hotKey: HotKeyPreset
    let searchDirectories: [String]
    let searchEngine: SearchEngine
    let rememberUsage: Bool

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
    }
}

enum SettingsError: LocalizedError {
    case invalidDirectories
    var errorDescription: String? { "请选择有效的绝对目录路径（最多 32 个）。" }
}
