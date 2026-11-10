import Foundation

enum WebSearchValidationError: LocalizedError {
    case invalidKeyword
    case reservedKeyword
    case duplicateKeyword
    case invalidTitle
    case invalidURLTemplate
    case invalidIdentifier
    case duplicateIdentifier
    case tooManyCustomSearches

    var errorDescription: String? {
        switch self {
        case .invalidKeyword:
            return L10n.tr("web_search.error.invalid_keyword")
        case .reservedKeyword:
            return L10n.tr("web_search.error.reserved_keyword")
        case .duplicateKeyword:
            return L10n.tr("web_search.error.duplicate_keyword")
        case .invalidTitle:
            return L10n.tr("web_search.error.invalid_title")
        case .invalidURLTemplate:
            return L10n.tr("web_search.error.invalid_url")
        case .invalidIdentifier:
            return L10n.tr("web_search.error.invalid_identifier")
        case .duplicateIdentifier:
            return L10n.tr("web_search.error.duplicate_identifier")
        case .tooManyCustomSearches:
            return L10n.tr("web_search.error.too_many")
        }
    }
}

extension WebSearchDefinition {
    static func validate(_ definitions: [WebSearchDefinition]) throws {
        guard definitions.filter(\.isCustom).count <= 64, definitions.count <= 128 else {
            throw WebSearchValidationError.tooManyCustomSearches
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let reserved: Set<String> = ["bm", "open", "find"]
        var keywords: Set<String> = []
        var identifiers: Set<String> = []
        for definition in definitions {
            guard !definition.id.isEmpty, definition.id.count <= 64 else {
                throw WebSearchValidationError.invalidIdentifier
            }
            guard identifiers.insert(definition.id).inserted else {
                throw WebSearchValidationError.duplicateIdentifier
            }
            let keyword = definition.keyword.lowercased()
            guard !keyword.isEmpty, keyword.count <= 32,
                  keyword.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw WebSearchValidationError.invalidKeyword
            }
            guard !reserved.contains(keyword) else { throw WebSearchValidationError.reservedKeyword }
            guard keywords.insert(keyword).inserted else { throw WebSearchValidationError.duplicateKeyword }
            guard !definition.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  definition.title.count <= 80 else { throw WebSearchValidationError.invalidTitle }
            guard definition.urlTemplate.count <= 2048,
                  WebSearchProvider.url(for: "validation", definition: definition) != nil else {
                throw WebSearchValidationError.invalidURLTemplate
            }
        }
    }
}
