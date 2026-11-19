import AppKit
import os

@MainActor protocol AppShortcutLaunching {
    @discardableResult
    func launch(_ shortcut: AppShortcut) -> Bool
}

@MainActor final class AppShortcutLauncher: AppShortcutLaunching {
    nonisolated private static let logger = Logger(subsystem: "com.clearmann.pennyworth", category: "AppShortcuts")
    private let fileExists: (String) -> Bool
    private let resolveBundleURL: (String) -> URL?
    private let openApplication: (URL) -> Void

    init(
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        resolveBundleURL: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        openApplication: @escaping (URL) -> Void = AppShortcutLauncher.defaultOpenApplication
    ) {
        self.fileExists = fileExists
        self.resolveBundleURL = resolveBundleURL
        self.openApplication = openApplication
    }

    @discardableResult
    func launch(_ shortcut: AppShortcut) -> Bool {
        guard let targetURL = resolveApplicationURL(for: shortcut) else {
            Self.logger.error("未找到快捷启动目标应用：\(shortcut.appName, privacy: .public)")
            return false
        }
        openApplication(targetURL)
        return true
    }

    private func resolveApplicationURL(for shortcut: AppShortcut) -> URL? {
        if fileExists(shortcut.appPath) {
            return URL(fileURLWithPath: shortcut.appPath)
        }
        if let bundleID = shortcut.bundleIdentifier, let resolved = resolveBundleURL(bundleID) {
            return resolved
        }
        return nil
    }

    nonisolated private static func defaultOpenApplication(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                logger.error("启动快捷应用失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
