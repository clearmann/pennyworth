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
        guard let request = QueryParser.parse(raw, webSearches: settings.settings.webSearches) else {
            publish([], message: L10n.tr("search.error.too_long")); return
        }
        switch request.intent {
        case .applications:
            guard !request.query.isEmpty else {
                publish([], message: SearchSnapshot.empty.message)
                return
            }
            var results = ApplicationSearchProvider.results(items: items, query: request.query,
                                                           usage: usage, enabled: settings.settings.rememberUsage)
            if bookmarks?.preferences.includeInDefaultResults == true {
                results += bookmarkResults(request.query)
            }
            let fallback = settings.settings.fallbackOnlyWhenNoResults && !results.isEmpty ? [] : webResults(request.query)
            publish(results + fallback, message: L10n.tr("launcher.help"))
        case .bookmarks:
            guard let bookmarks, bookmarks.preferences.enabled else {
                publish([], message: L10n.tr("launcher.bookmarks_disabled")); return
            }
            let results = bookmarkResults(request.query)
            publish(results, message: results.isEmpty ? L10n.tr("launcher.bookmarks_empty") : L10n.tr("launcher.bookmarks_help"))
        case .calculator:
            do {
                publish(try CalculatorProvider.result(for: request).map { [$0] } ?? [], message: L10n.tr("launcher.calculator_help"))
            } catch {
                publish(request.explicitCalculation ? [] : webResults(request.query),
                        message: request.explicitCalculation ? error.localizedDescription : L10n.tr("launcher.calculator_incomplete"))
            }
        case .web(let definition):
            publish(WebSearchProvider.result(for: request.query, definition: definition).map { [$0] } ?? [],
                    message: L10n.tr("launcher.web_search_help"))
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
            publish([], message: L10n.tr("launcher.files_not_configured")); return
        }
        guard !query.isEmpty else { publish([], message: L10n.tr("launcher.file_query_empty")); return }
        publish([], message: L10n.tr("launcher.files_searching"), loading: true)
        let token = generation
        searchTask = Task { [weak self, fileSearch] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            let outcome = await fileSearch(query, scopes)
            guard let self, self.active, self.generation == token, !Task.isCancelled else { return }
            switch outcome {
            case .results(let hits):
                let actionTitle = L10n.tr(action == .open ? "launcher.action.open" : "launcher.action.reveal")
                self.publish(hits.map { $0.searchResult(action: action) },
                             message: hits.isEmpty ? L10n.tr("launcher.files_empty") : L10n.format("launcher.files_help", actionTitle))
            case .notConfigured: self.publish([], message: L10n.tr("launcher.files_add_directories"))
            case .emptyQuery: self.publish([], message: L10n.tr("launcher.file_query_empty"))
            case .cancelled: self.publish([], message: L10n.tr("launcher.search_cancelled"))
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
