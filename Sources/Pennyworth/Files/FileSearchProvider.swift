import Foundation

/// A file matched by filename inside one of the configured scopes.
struct FileSearchHit: Equatable {
    let url: URL
    let displayName: String

    /// Maps a hit onto the shared result model used by the launcher.
    func searchResult(action: FileAction) -> SearchResult {
        let parent = url.deletingLastPathComponent().path
        return SearchResult(
            id: url.standardizedFileURL.path,
            title: displayName,
            subtitle: parent,
            symbol: "doc",
            action: action == .reveal ? .revealFile(url) : .openFile(url)
        )
    }
}

/// Result of one file search request.
///
/// `notConfigured` is the explicit answer for empty or non-file scopes: callers
/// should surface "configure search locations" instead of showing "no results".
enum FileSearchOutcome: Equatable {
    case notConfigured
    case emptyQuery
    case results([FileSearchHit])
    case cancelled
    case failed(String)
}

/// One executable metadata query. Abstracted so the provider can be tested
/// without touching Spotlight.
protocol FileMetadataQuerying: AnyObject {
    func execute() async throws -> [FileSearchHit]
    func cancel()
}

/// Creates metadata queries. Returning `nil` means Spotlight cannot answer
/// right now (for example, the service is unavailable).
protocol FileMetadataQueryMaking {
    func makeQuery(predicate: NSPredicate, scopes: [URL]) -> FileMetadataQuerying?
}

/// Filename-only Spotlight search across an explicit set of file scopes.
///
/// The provider owns three decisions and nothing else:
///   1. Empty / non-file scopes never start a query (`notConfigured`).
///   2. Only filenames are matched, never full text content.
///   3. Results are contained in the requested scopes, deduplicated, sorted and
///      bounded before being returned.
///
/// Spotlight generation, indexing freshness and live updates are deliberately
/// not modelled here; the caller decides when to search again.
final class FileSearchProvider {
    private let factory: FileMetadataQueryMaking
    private let maxResults: Int

    init(factory: FileMetadataQueryMaking = SystemMetadataQueryFactory(), maxResults: Int = 50) {
        self.factory = factory
        self.maxResults = max(1, maxResults)
    }

    func search(query: String, scopes: [URL]) async -> FileSearchOutcome {
        guard query.count <= 512 else { return .failed("输入过长，最多 512 个字符") }
        let scopes = Self.normalizedScopes(scopes)
        guard !scopes.isEmpty else { return .notConfigured }
        guard let predicate = Self.predicate(for: query) else { return .emptyQuery }
        guard let metadataQuery = factory.makeQuery(predicate: predicate, scopes: scopes) else {
            return .failed("Spotlight is unavailable")
        }

        do {
            let hits = try await withTaskCancellationHandler {
                try await metadataQuery.execute()
            } onCancel: {
                metadataQuery.cancel()
            }
            return .results(
                Self.refine(hits, scopes: scopes, limit: maxResults)
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled { return .cancelled }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed(message)
        }
    }

    // MARK: - Pure helpers

    /// Keeps only file URLs, standardizes them and removes duplicates while
    /// preserving first-seen order.
    static func normalizedScopes(_ scopes: [URL]) -> [URL] {
        var seen = Set<String>()
        return scopes.compactMap { scope in
            let url = scope.standardizedFileURL
            guard url.isFileURL, seen.insert(url.path).inserted else { return nil }
            return url
        }
    }

    /// Builds a filename-only predicate. Returns `nil` for a blank query so no
    /// query is started.
    static func predicate(for query: String) -> NSPredicate? {
        guard let pattern = filenamePattern(for: query) else { return nil }
        return NSPredicate(format: "kMDItemFSName LIKE[cd] %@", pattern)
    }

    /// The `LIKE` pattern for a filename match, or `nil` when the query is blank.
    ///
    /// Spotlight wildcards are escaped so a user typing `*` searches for a
    /// literal asterisk instead of matching every file.
    static func filenamePattern(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
        return "*\(escaped)*"
    }

    /// True when `url` lives directly in, or below, one of `scopes`.
    static func isContained(_ url: URL, in scopes: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return scopes.contains { scope in
            let root = scope.standardizedFileURL.path
            if root == "/" { return path.hasPrefix("/") }
            return path == root || path.hasPrefix(root + "/")
        }
    }

    static func refine(_ hits: [FileSearchHit], scopes: [URL], limit: Int) -> [FileSearchHit] {
        var seen = Set<String>()
        let contained = hits.filter { hit in
            guard hit.url.isFileURL, isContained(hit.url, in: scopes) else { return false }
            return seen.insert(hit.url.standardizedFileURL.path).inserted
        }
        return contained
            .sorted { lhs, rhs in
                let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if order == .orderedSame {
                    return lhs.url.path < rhs.url.path
                }
                return order == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Spotlight

/// Creates real `NSMetadataQuery` instances.
struct SystemMetadataQueryFactory: FileMetadataQueryMaking {
    func makeQuery(predicate: NSPredicate, scopes: [URL]) -> FileMetadataQuerying? {
        SystemMetadataQuery(predicate: predicate, scopes: scopes)
    }
}

/// Wraps `NSMetadataQuery` in a one-shot async call.
///
/// `NSMetadataQuery` only makes progress while a run loop is spinning, so the
/// query is started on the main queue; the caller merely awaits its result.
final class SystemMetadataQuery: FileMetadataQuerying, @unchecked Sendable {
    private let query = NSMetadataQuery()
    private let lock = NSLock()
    private var didResolve = false
    private var cancellationRequested = false
    private var observers: [NSObjectProtocol] = []
    private var timeout: DispatchWorkItem?
    private var pendingContinuation: CheckedContinuation<[FileSearchHit], Error>?

    init(predicate: NSPredicate, scopes: [URL]) {
        query.predicate = predicate
        query.searchScopes = scopes
        query.notificationBatchingInterval = 0.1
    }

    func execute() async throws -> [FileSearchHit] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.start(continuation)
            }
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        DispatchQueue.main.async { self.finish(throwing: CancellationError()) }
    }

    private func start(_ continuation: CheckedContinuation<[FileSearchHit], Error>) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                self?.finishWithCurrentResults()
            },
            center.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { [weak self] _ in
                self?.finishWithCurrentResults()
            },
        ]

        lock.lock()
        let cancelled = cancellationRequested
        pendingContinuation = continuation
        lock.unlock()
        guard !cancelled else {
            removeObservers()
            lock.lock()
            pendingContinuation = nil
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        guard query.start() else {
            finish(throwing: NSError(domain: "Pennyworth.Spotlight", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Spotlight 查询无法启动，请稍后重试。"])); return
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(throwing: NSError(domain: "Pennyworth.Spotlight", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "Spotlight 搜索超时，请缩小目录范围或检查索引。"]))
        }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
    }

    private func finishWithCurrentResults() {
        query.disableUpdates()
        let hits = (0..<min(query.resultCount, 5000)).compactMap { index -> FileSearchHit? in
            guard let item = query.result(at: index) as? NSMetadataItem else { return nil }
            return Self.hit(from: item)
        }
        query.enableUpdates()
        finish(returning: hits)
    }

    private func finish(returning hits: [FileSearchHit]) {
        query.stop()
        removeObservers()
        lock.lock()
        guard !didResolve, let continuation = pendingContinuation else {
            lock.unlock()
            return
        }
        didResolve = true
        pendingContinuation = nil
        lock.unlock()
        continuation.resume(returning: hits)
    }

    private func finish(throwing error: Error) {
        query.stop()
        removeObservers()
        lock.lock()
        guard !didResolve, let continuation = pendingContinuation else {
            lock.unlock()
            return
        }
        didResolve = true
        pendingContinuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }

    private func removeObservers() {
        timeout?.cancel()
        timeout = nil
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private static func hit(from item: NSMetadataItem) -> FileSearchHit? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
            return nil
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.isFileURL else { return nil }
        let name = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String)
            ?? url.lastPathComponent
        return FileSearchHit(url: url, displayName: name)
    }
}
