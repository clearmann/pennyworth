import Foundation

enum QueryParser {
    static func parse(_ raw: String, webSearches: [WebSearchDefinition] = WebSearchDefinition.builtIns) -> SearchRequest? {
        guard raw.count <= 512 else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix(" ") || raw.hasPrefix("'") {
            return request(.fileSearch(.open), String(raw.dropFirst()))
        }
        if trimmed.hasPrefix("=") {
            return SearchRequest(intent: .calculator,
                                 query: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces),
                                 explicitCalculation: true)
        }
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let keyword = parts.first.map(String.init)?.lowercased() ?? ""
        let value = parts.count > 1 ? String(parts[1]) : ""
        switch keyword {
        case "bm": return request(.bookmarks, value)
        case "open": return request(.fileSearch(.open), value)
        case "find": return request(.fileSearch(.reveal), value)
        default: break
        }
        if let definition = webSearches.first(where: { $0.isEnabled && $0.keyword.lowercased() == keyword }) {
            return request(.web(definition), value)
        }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() \t\n")
        let isArithmetic = !trimmed.isEmpty
            && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
            && trimmed.contains(where: { "+-*/".contains($0) })
        return request(isArithmetic ? .calculator : .applications, trimmed)
    }

    private static func request(_ intent: QueryIntent, _ query: String) -> SearchRequest {
        SearchRequest(intent: intent, query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                      explicitCalculation: false)
    }
}
