import Foundation

enum SearchEngine: String, Codable, CaseIterable {
    case google, bing, duckDuckGo

    var title: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckDuckGo: return "DuckDuckGo"
        }
    }

    var baseURL: String {
        switch self {
        case .google: return "https://www.google.com/search"
        case .bing: return "https://www.bing.com/search"
        case .duckDuckGo: return "https://duckduckgo.com/"
        }
    }
}

enum WebSearchProvider {
    static func result(for query: String, engine: SearchEngine) -> SearchResult? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query.count <= 512,
              var components = URLComponents(string: engine.baseURL) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // '+' is otherwise interpreted as a space by form-style search servers.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return nil }
        return SearchResult(
            id: "web:\(engine.rawValue):\(query)",
            title: "Search \(engine.title) for \(query)",
            subtitle: "回车在默认浏览器中搜索", symbol: "globe", action: .openURL(url)
        )
    }
}
