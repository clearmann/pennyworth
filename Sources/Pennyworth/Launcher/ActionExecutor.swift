import AppKit

@MainActor protocol ActionExecuting {
    func execute(_ action: SearchAction, completion: @escaping (Result<Void, Error>) -> Void)
}

enum ActionError: LocalizedError {
    case missingFile, invalidURL, clipboardWriteFailed
    var errorDescription: String? {
        switch self {
        case .missingFile: return "文件已移动、删除或暂时不可访问。请刷新搜索后重试。"
        case .invalidURL: return "无法打开此网址。"
        case .clipboardWriteFailed: return "无法写入剪贴板，请重试。"
        }
    }
}

@MainActor final class ActionExecutor: ActionExecuting {
    private let pasteboard: NSPasteboard
    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func execute(_ action: SearchAction, completion: @escaping (Result<Void, Error>) -> Void) {
        switch action {
        case .copyText(let text):
            pasteboard.clearContents()
            completion(pasteboard.setString(text, forType: .string)
                       ? .success(()) : .failure(ActionError.clipboardWriteFailed))
        case .openApplication(let url), .openFile(let url), .revealFile(let url):
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                completion(.failure(ActionError.missingFile)); return
            }
            if case .revealFile = action {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                completion(.success(())) // Finder accepts a request, not a completion acknowledgement.
            } else {
                open(url, application: { if case .openApplication = action { return true }; return false }(), completion: completion)
            }
        case .openURL(let url):
            guard url.scheme == "https", url.host != nil else {
                completion(.failure(ActionError.invalidURL)); return
            }
            open(url, application: false, completion: completion)
        }
    }

    private func open(_ url: URL, application: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let callback: @Sendable (NSRunningApplication?, Error?) -> Void = { _, error in
            Task { @MainActor in
                if let error { completion(.failure(error)) } else { completion(.success(())) }
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        if application {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: callback)
        } else {
            NSWorkspace.shared.open(url, configuration: configuration, completionHandler: callback)
        }
    }
}
