import Foundation

@MainActor final class ClipboardHistoryModel {
    private(set) var items: [ClipboardItem]
    private(set) var query = ""
    private(set) var selectedID: UUID?

    init(items: [ClipboardItem]) {
        self.items = items
        selectedID = items.first?.id
    }

    var visibleItems: [ClipboardItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.displayTitle.localizedCaseInsensitiveContains(query)
                || item.displaySubtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedItem: ClipboardItem? {
        visibleItems.first { $0.id == selectedID }
    }

    var message: String {
        if items.isEmpty { return "暂无剪贴板历史" }
        if visibleItems.isEmpty { return "没有匹配的剪贴板记录" }
        return "↑↓ 选择 · ↵ 恢复到剪贴板 · Esc 关闭"
    }

    func updateQuery(_ value: String) {
        query = value
        if !visibleItems.contains(where: { $0.id == selectedID }) {
            selectedID = visibleItems.first?.id
        }
    }

    func moveSelection(by delta: Int) {
        let values = visibleItems
        guard !values.isEmpty else { return }
        let index = values.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = values[min(max(index + delta, 0), values.count - 1)].id
    }

    func select(_ id: UUID?) {
        selectedID = visibleItems.first(where: { $0.id == id })?.id
    }

    func updateItems(_ values: [ClipboardItem]) {
        items = values
        if !visibleItems.contains(where: { $0.id == selectedID }) {
            selectedID = visibleItems.first?.id
        }
    }
}
