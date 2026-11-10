import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var title: String {
        switch self {
        case .system: return AppLocalization.string("language.system")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .simplifiedChinese, .english:
            return rawValue
        case .system:
            for language in preferredLanguages {
                let normalized = language.lowercased()
                if normalized.hasPrefix("zh") { return "zh-Hans" }
                if normalized.hasPrefix("en") { return "en" }
            }
            return "en"
        }
    }
}

enum AppLocalization {
    private static let resourceBundle = loadResourceBundle()
    private(set) static var currentLanguage: AppLanguage = .system
    private static var currentBundle = bundle(for: .system)

    static func configure(language: AppLanguage) {
        currentLanguage = language
        currentBundle = bundle(for: language)
    }

    static func string(_ key: String, language: AppLanguage? = nil,
                       preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let target = language.map { bundle(for: $0, preferredLanguages: preferredLanguages) } ?? currentBundle
        return NSLocalizedString(key, bundle: target, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale(identifier: currentLanguage.resolvedIdentifier()), arguments: arguments)
    }

    private static func bundle(for language: AppLanguage,
                               preferredLanguages: [String] = Locale.preferredLanguages) -> Bundle {
        let identifier = language.resolvedIdentifier(preferredLanguages: preferredLanguages)
        guard let path = resourceBundle.path(forResource: identifier.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resourceBundle
        }
        return bundle
    }

    private static func loadResourceBundle() -> Bundle {
        let name = "Pennyworth_Pennyworth.bundle"
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        for directory in candidates {
            let url = directory.appendingPathComponent(name)
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle.module
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        AppLocalization.string(key)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.format(key, arguments)
    }
}
