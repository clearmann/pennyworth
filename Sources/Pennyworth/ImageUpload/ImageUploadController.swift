import AppKit
import Foundation

@MainActor final class ImageUploadController {
    enum VisualState: Equatable {
        case idle
        case dragHover
        case uploading(count: Int)
        case succeeded
    }

    private let settingsProvider: () -> ImageUploadSettings
    private let service: ImageUploadService
    private let historyStore: UploadHistoryStore
    private let pasteboard: NSPasteboard
    private let onFeedback: (String, String?, UploadStatusToast.Style) -> Void
    private var activeTaskCount = 0
    private var isDragHovering = false
    private var successResetWorkItem: DispatchWorkItem?

    var onStateChanged: ((VisualState) -> Void)?
    var onHistoryChanged: (() -> Void)?

    private(set) var visualState: VisualState = .idle {
        didSet {
            if oldValue != visualState {
                onStateChanged?(visualState)
            }
        }
    }

    init(
        settingsProvider: @escaping () -> ImageUploadSettings,
        service: ImageUploadService,
        historyStore: UploadHistoryStore,
        pasteboard: NSPasteboard = .general,
        onFeedback: @escaping (String, String?, UploadStatusToast.Style) -> Void
    ) {
        self.settingsProvider = settingsProvider
        self.service = service
        self.historyStore = historyStore
        self.pasteboard = pasteboard
        self.onFeedback = onFeedback
    }

    func setDragHovering(_ hovering: Bool) {
        isDragHovering = hovering
        refreshVisualState()
    }

    func uploadClipboard() {
        do {
            let inputs = try UploadInputLoader.loadFromPasteboard(pasteboard)
            startUpload(inputs: inputs)
        } catch {
            onFeedback(L10n.tr("image_upload.toast.failed_title"), error.localizedDescription, .error)
        }
    }

    func uploadFiles(_ urls: [URL]) {
        do {
            let inputs = try UploadInputLoader.loadFromFileURLs(urls)
            startUpload(inputs: inputs)
        } catch {
            onFeedback(L10n.tr("image_upload.toast.failed_title"), error.localizedDescription, .error)
        }
    }

    func selectFilesAndUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.tr("image_upload.action.upload")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        uploadFiles(panel.urls)
    }

    func copyHistoryItem(_ item: UploadHistoryItem, format: UploadOutputFormat? = nil) {
        let effectiveFormat = format ?? settingsProvider().outputFormat
        let formatted = effectiveFormat.format(url: item.url, filename: item.filename)
        writeToPasteboard(formatted)
        onFeedback(L10n.tr("image_upload.toast.copied_title"), formatted, .info)
    }

    func clearHistory() {
        historyStore.clear()
        onHistoryChanged?()
    }

    @discardableResult
    func uploadInputsForTesting(_ inputs: [RawUploadInput]) async -> [UploadResult]? {
        await performUpload(inputs: inputs)
    }

    private func startUpload(inputs: [RawUploadInput]) {
        Task { [weak self] in
            await self?.performUpload(inputs: inputs)
        }
    }

    @discardableResult
    private func performUpload(inputs: [RawUploadInput]) async -> [UploadResult]? {
        let uploadSettings = settingsProvider()
        guard uploadSettings.activeHost != nil else {
            onFeedback(
                L10n.tr("image_upload.toast.failed_title"),
                ImageUploadError.noHostConfigured.localizedDescription,
                .error
            )
            return nil
        }

        successResetWorkItem?.cancel()
        activeTaskCount += 1
        refreshVisualState()

        do {
            let results = try await service.upload(inputs: inputs, settings: uploadSettings)
            activeTaskCount = max(0, activeTaskCount - 1)

            let combined = results.map(\.formattedText).joined(separator: "\n")
            writeToPasteboard(combined)

            for result in results {
                historyStore.add(UploadHistoryItem(
                    url: result.url,
                    filename: result.filename,
                    hostName: result.hostName,
                    provider: result.provider,
                    fileSize: result.fileSize,
                    thumbnailData: result.thumbnailData
                ))
            }
            onHistoryChanged?()

            if results.count == 1, let first = results.first {
                onFeedback(L10n.tr("image_upload.toast.success_title"), first.formattedText, .success)
            } else {
                onFeedback(
                    L10n.format("image_upload.toast.success_batch_title", results.count),
                    results.first?.formattedText,
                    .success
                )
            }
            showTransientSuccessState()
            return results
        } catch {
            activeTaskCount = max(0, activeTaskCount - 1)
            refreshVisualState()
            onFeedback(L10n.tr("image_upload.toast.failed_title"), error.localizedDescription, .error)
            return nil
        }
    }

    private func writeToPasteboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func showTransientSuccessState() {
        guard activeTaskCount == 0 else {
            refreshVisualState()
            return
        }
        visualState = .succeeded
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshVisualState()
            }
        }
        successResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func refreshVisualState() {
        if activeTaskCount > 0 {
            visualState = .uploading(count: activeTaskCount)
        } else if isDragHovering {
            visualState = .dragHover
        } else {
            visualState = .idle
        }
    }
}
