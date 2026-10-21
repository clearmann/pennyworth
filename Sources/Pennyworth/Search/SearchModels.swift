import Foundation

enum FileAction: Equatable {
    case open
    case reveal
}

enum QueryIntent: Equatable {
    case applications
    case bookmarks
    case fileSearch(FileAction)
    case calculator
    case web(SearchEngine)
}

struct SearchRequest: Equatable {
    let intent: QueryIntent
    let query: String
    let explicitCalculation: Bool
}

enum SearchAction: Equatable {
    case openApplication(URL)
    case openFile(URL)
    case revealFile(URL)
    case openURL(URL)
    case copyText(String)
}

struct SearchResult: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let action: SearchAction

    var fileURL: URL? {
        switch action {
        case .openApplication(let url), .openFile(let url), .revealFile(let url): return url
        default: return nil
        }
    }
}

struct SearchSnapshot: Equatable {
    let results: [SearchResult]
    let message: String
    let isLoading: Bool

    static let empty = SearchSnapshot(results: [], message: "输入应用名称，或按空格搜索文件", isLoading: false)
}
