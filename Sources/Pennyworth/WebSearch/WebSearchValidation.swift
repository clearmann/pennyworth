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
            return "网页搜索关键词需为 1–32 个字母、数字、汉字、连字符或下划线，且不能包含空格。"
        case .reservedKeyword:
            return "该关键词已被 bm、open 或 find 命令保留，请更换关键词。"
        case .duplicateKeyword:
            return "网页搜索关键词不能重复，请更换关键词。"
        case .invalidTitle:
            return "网页搜索显示名称不能为空，且最多 80 个字符。"
        case .invalidURLTemplate:
            return "搜索网址必须是有效的 HTTP/HTTPS 地址，包含 {query}，且不能包含账号密码。"
        case .invalidIdentifier:
            return "网页搜索标识无效，请删除后重新添加。"
        case .duplicateIdentifier:
            return "网页搜索标识不能重复，请删除重复项后重新添加。"
        case .tooManyCustomSearches:
            return "自定义网页搜索最多 64 项。"
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
