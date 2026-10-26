import Foundation

struct WebSearchDefinition: Codable, Equatable {
    let id: String
    let keyword: String
    let title: String
    let urlTemplate: String
    let isEnabled: Bool
    let isCustom: Bool

    init(id: String, keyword: String, title: String, urlTemplate: String,
         isEnabled: Bool = true, isCustom: Bool = true) {
        self.id = id
        self.keyword = keyword
        self.title = title
        self.urlTemplate = urlTemplate
        self.isEnabled = isEnabled
        self.isCustom = isCustom
    }

    static let google = WebSearchDefinition(
        id: "builtIn.google", keyword: "google", title: "Google",
        urlTemplate: "https://www.google.com/search?q={query}", isCustom: false
    )
    static let bing = WebSearchDefinition(
        id: "builtIn.bing", keyword: "bing", title: "Bing",
        urlTemplate: "https://www.bing.com/search?q={query}", isCustom: false
    )
    static let duckDuckGo = WebSearchDefinition(
        id: "builtIn.duckDuckGo", keyword: "ddg", title: "DuckDuckGo",
        urlTemplate: "https://duckduckgo.com/?q={query}", isCustom: false
    )
    static let wikipedia = WebSearchDefinition(
        id: "builtIn.wikipedia", keyword: "wiki", title: "Wikipedia",
        urlTemplate: "https://en.wikipedia.org/w/index.php?search={query}", isCustom: false
    )
    static let youtube = WebSearchDefinition(
        id: "builtIn.youtube", keyword: "youtube", title: "YouTube",
        urlTemplate: "https://www.youtube.com/results?search_query={query}", isCustom: false
    )
    static let maps = WebSearchDefinition(
        id: "builtIn.maps", keyword: "maps", title: "Google Maps",
        urlTemplate: "https://www.google.com/maps/search/{query}", isCustom: false
    )
    static let translate = WebSearchDefinition(
        id: "builtIn.translate", keyword: "translate", title: "Google Translate",
        urlTemplate: "https://translate.google.com/?sl=auto&text={query}", isCustom: false
    )
    static let builtIns = [google, bing, duckDuckGo, wikipedia, youtube, maps, translate]
}
