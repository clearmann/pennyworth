import Foundation
import os

@MainActor final class LauncherModel {
    typealias FileSearch = (String, [URL]) async -> FileSearchOutcome
    private let settings: SettingsStore
    private let usage: UsageStore
    private let executor: ActionExecuting
    private let fileSearch: FileSearch
    private let bookmarks: BookmarkStore?
    private var searchTask: Task<Void, Never>?
    private var generation = UUID()
    private var session = UUID()
    private var active = false
    private var items: [AppItem] = []
    private(set) var query = ""
    private(set) var snapshot = SearchSnapshot.empty
    private(set) var selectedID: String?
    private(set) var isExecuting = false
    var onChange: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onExecutionError: (() -> Void)?

    init(settings: SettingsStore, usage: UsageStore, executor: ActionExecuting, bookmarks: BookmarkStore? = nil,
         fileSearch: @escaping FileSearch = { query, scopes in
             await FileSearchProvider().search(query: query, scopes: scopes)
         }) {
        self.settings = settings
        self.usage = usage
        self.executor = executor
        self.fileSearch = fileSearch
        self.bookmarks = bookmarks
    }

    func beginSession() {
        session = UUID()
        active = true
        isExecuting = false
        updateQuery("")
    }

    func endSession() {
        active = false
        session = UUID()
        generation = UUID()
        searchTask?.cancel()
        searchTask = nil
        isExecuting = false
    }

    func setApplications(_ items: [AppItem]) {
        self.items = items
        if active && !isExecuting { updateQuery(query) }
    }

    func updateQuery(_ raw: String) {
        guard !isExecuting else { return }
        query = raw
        generation = UUID()
        searchTask?.cancel()
        searchTask = nil
        selectedID = nil
        guard let request = QueryParser.parse(raw) else {
            publish([], message: "输入过长，最多 512 个字符"); return
        }
        switch request.intent {
        case .applications:
            var results = ApplicationSearchProvider.results(items: items, query: request.query,
                                                           usage: usage, enabled: settings.settings.rememberUsage)
            if !request.query.isEmpty, bookmarks?.preferences.includeInDefaultResults == true {
                results += bookmarkResults(request.query)
            }
            let fallback = settings.settings.fallbackOnlyWhenNoResults && !results.isEmpty ? [] : webResults(request.query)
            publish(results + fallback, message: "↑↓ 选择 · ↵ 打开 · bm 搜书签 · 空格搜文件 · ⌘, 设置")
        case .bookmarks:
            guard let bookmarks, bookmarks.preferences.enabled else {
                publish([], message: "书签搜索未启用，请在设置的网页书签中启用并导入"); return
            }
            let results = bookmarkResults(request.query)
            publish(results, message: results.isEmpty ? "没有匹配书签，请检查来源选择或在设置中导入 / 刷新" : "最多显示 50 项 · ↵ 使用默认浏览器打开")
        case .calculator:
            do {
                publish(try CalculatorProvider.result(for: request).map { [$0] } ?? [], message: "↵ 复制计算结果")
            } catch {
                publish(request.explicitCalculation ? [] : webResults(request.query),
                        message: request.explicitCalculation ? error.localizedDescription : "继续输入算式，或回车网页搜索")
            }
        case .web(let engine):
            publish(WebSearchProvider.result(for: request.query, engine: engine).map { [$0] } ?? [],
                    message: "输入关键词，回车后才会打开浏览器")
        case .fileSearch(let action):
            searchFiles(request.query, action: action)
        }
    }

    private func webResults(_ query: String) -> [SearchResult] {
        WebSearchProvider.result(for: query, engine: settings.settings.searchEngine).map { [$0] } ?? []
    }

    private func bookmarkResults(_ query: String) -> [SearchResult] {
        guard let bookmarks else { return [] }
        return BookmarkSearchProvider.results(entries: bookmarks.searchableEntries, query: query,
                                              preferences: bookmarks.preferences)
    }

    func refreshPreferences() {
        if active && !isExecuting { updateQuery(query) }
    }

    private func searchFiles(_ query: String, action: FileAction) {
        let scopes = settings.settings.searchDirectories.map { URL(fileURLWithPath: $0) }
        guard !scopes.isEmpty else {
            publish([], message: "尚未选择搜索目录，请按 ⌘, 打开设置添加目录"); return
        }
        guard !query.isEmpty else { publish([], message: "请输入文件名"); return }
        publish([], message: "正在搜索文件…", loading: true)
        let token = generation
        searchTask = Task { [weak self, fileSearch] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            let outcome = await fileSearch(query, scopes)
            guard let self, self.active, self.generation == token, !Task.isCancelled else { return }
            switch outcome {
            case .results(let hits):
                self.publish(hits.map { $0.searchResult(action: action) },
                             message: hits.isEmpty ? "没有匹配；请检查目录与 Spotlight 索引" : "最多显示 50 项 · ↵ \(action == .open ? "打开" : "在 Finder 显示")")
            case .notConfigured: self.publish([], message: "请在设置中添加搜索目录")
            case .emptyQuery: self.publish([], message: "请输入文件名")
            case .cancelled: self.publish([], message: "搜索已取消")
            case .failed(let message): self.publish([], message: message)
            }
        }
    }

    func select(_ id: String?) {
        guard !isExecuting else { return }
        selectedID = snapshot.results.first(where: { $0.id == id })?.id
    }

    func moveSelection(by delta: Int) {
        guard !isExecuting, !snapshot.results.isEmpty else { return }
        let index = snapshot.results.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = snapshot.results[min(max(index + delta, 0), snapshot.results.count - 1)].id
        onChange?()
    }

    func executeSelected() {
        guard active, !isExecuting,
              let result = snapshot.results.first(where: { $0.id == selectedID }) else { return }
        isExecuting = true
        let token = session
        onChange?()
        executor.execute(result.action) { [weak self] outcome in
            guard let self, self.active, self.session == token else { return }
            self.isExecuting = false
            switch outcome {
            case .success:
                if case .openApplication(let url) = result.action, self.settings.settings.rememberUsage {
                    do { try self.usage.record(url) } catch {
                        Logger(subsystem: "com.clearmann.pennyworth", category: "Usage").error("无法保存使用记录")
                    }
                }
                self.endSession()
                self.onDismiss?()
            case .failure(let error):
                self.publish(self.snapshot.results, message: error.localizedDescription)
                self.onExecutionError?()
            }
        }
    }

    private func publish(_ results: [SearchResult], message: String, loading: Bool = false) {
        snapshot = SearchSnapshot(results: results, message: message, isLoading: loading)
        if !results.contains(where: { $0.id == selectedID }) { selectedID = results.first?.id }
        onChange?()
    }
}
