import AppKit

/// A launchable application on disk. Immutable value type.
struct AppItem: Equatable {
    let name: String
    let url: URL

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
