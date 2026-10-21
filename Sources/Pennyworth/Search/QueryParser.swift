import Foundation

enum QueryParser {
    static func parse(_ raw: String) -> SearchRequest? {
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
        case "google": return request(.web(.google), value)
        case "bing": return request(.web(.bing), value)
        case "ddg": return request(.web(.duckDuckGo), value)
        default: break
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
