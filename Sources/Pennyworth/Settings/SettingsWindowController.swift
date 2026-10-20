import AppKit

@MainActor final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let usage: UsageStore
    private let apply: (LauncherSettings) throws -> Void
    private let hotKey = NSPopUpButton()
    private let engine = NSPopUpButton()
    private let remember = NSButton(checkboxWithTitle: "记住应用使用频率", target: nil, action: nil)
    private let directories = NSPopUpButton()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var paths: [String] = []

    init(store: SettingsStore, usage: UsageStore, apply: @escaping (LauncherSettings) throws -> Void) {
        self.store = store
        self.usage = usage
        self.apply = apply
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pennyworth 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configure()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        let value = store.settings
        hotKey.selectItem(at: HotKeyPreset.allCases.firstIndex(of: value.hotKey) ?? 0)
        engine.selectItem(at: SearchEngine.allCases.firstIndex(of: value.searchEngine) ?? 0)
        remember.state = value.rememberUsage ? .on : .off
        paths = value.searchDirectories
        reloadDirectories()
        feedback.stringValue = store.warning ?? "文件搜索仅覆盖所选目录的 Spotlight 索引。建议添加文稿、桌面或下载。"
        super.showWindow(sender)
    }

    private func configure() {
        hotKey.addItems(withTitles: HotKeyPreset.allCases.map(\.title))
        engine.addItems(withTitles: SearchEngine.allCases.map(\.title))
        hotKey.setAccessibilityLabel("全局热键")
        engine.setAccessibilityLabel("默认搜索引擎")
        directories.setAccessibilityLabel("文件搜索目录")
        let add = NSButton(title: "添加目录…", target: self, action: #selector(addDirectory))
        let remove = NSButton(title: "移除所选", target: self, action: #selector(removeDirectory))
        let clear = NSButton(title: "清除使用记录", target: self, action: #selector(clearHistory))
        let save = NSButton(title: "保存", target: self, action: #selector(saveSettings))
        save.keyEquivalent = "\r"
        let stack = NSStackView(views: [
            row("全局热键", hotKey), row("默认搜索引擎", engine), remember,
            row("文件搜索目录", directories), NSStackView(views: [add, remove]),
            clear, feedback, save,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .secondaryLabelColor
        window?.contentView?.addSubview(stack)
        if let content = window?.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
                feedback.widthAnchor.constraint(equalTo: stack.widthAnchor),
                directories.widthAnchor.constraint(equalToConstant: 345),
            ])
        }
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        return NSStackView(views: [label, control])
    }

    private func reloadDirectories() {
        directories.removeAllItems()
        directories.addItems(withTitles: paths.isEmpty ? ["未配置（不搜索文件）"] : paths)
    }

    @objc private func addDirectory() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            self.paths = Array(Set(self.paths + panel.urls.map { $0.standardizedFileURL.path })).sorted()
            self.reloadDirectories()
        }
    }

    @objc private func removeDirectory() {
        guard paths.indices.contains(directories.indexOfSelectedItem) else { return }
        paths = paths.enumerated().filter { $0.offset != directories.indexOfSelectedItem }.map(\.element)
        reloadDirectories()
    }

    @objc private func clearHistory() {
        usage.clear()
        feedback.stringValue = "使用记录已清除。"
    }

    @objc private func saveSettings() {
        let value = LauncherSettings(hotKey: HotKeyPreset.allCases[hotKey.indexOfSelectedItem],
                                     searchDirectories: paths,
                                     searchEngine: SearchEngine.allCases[engine.indexOfSelectedItem],
                                     rememberUsage: remember.state == .on)
        do {
            try apply(value)
            feedback.stringValue = "设置已保存。"
        } catch {
            feedback.stringValue = error.localizedDescription
        }
    }
}
