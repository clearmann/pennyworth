@testable import Pennyworth
import AppKit
import XCTest

final class ImageUploadSettingsUITests: XCTestCase {
    @MainActor func testAddHostSavePersistsSettingsAndStoresSecretOnlyInSecretStore() throws {
        _ = NSApplication.shared
        let name = "ImageUploadSettingsUI.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        var historyItems = [
            UploadHistoryItem(
                id: "h1",
                url: "https://cdn.example.com/a.png",
                filename: "a.png",
                hostName: "My R2",
                provider: .s3,
                fileSize: 512
            )
        ]
        var copiedItem: UploadHistoryItem?
        var cleared = false

        let controller = SettingsWindowController(
            store: store,
            usage: UsageStore(defaults: defaults),
            imageUploadSecretStore: secretStore,
            uploadHistoryProvider: { historyItems },
            onCopyUploadHistory: { copiedItem = $0 },
            onClearUploadHistory: {
                cleared = true
                historyItems = []
            }
        ) {
            try store.save($0)
        }

        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage(L10n.tr("settings.page.image_upload"))
        XCTAssertEqual(controller.selectedPageTitle, L10n.tr("settings.page.image_upload"))

        let content = try XCTUnwrap(controller.window?.contentView)
        let allViews = descendants(content)
        let uploadView = try XCTUnwrap(allViews.compactMap { $0 as? ImageUploadSettingsView }.first)
        let views = descendants(uploadView)

        let addHostButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == L10n.tr("image_upload.settings.add_host")
        })
        addHostButton.performClick(nil)

        let nameField = try XCTUnwrap(textField(in: views, label: "image_upload.field.name"))
        let bucketField = try XCTUnwrap(textField(in: views, label: "image_upload.field.bucket"))
        let endpointField = try XCTUnwrap(textField(in: views, label: "image_upload.field.endpoint"))
        let accessKeyField = try XCTUnwrap(textField(in: views, label: "image_upload.field.access_key"))
        let secretKeyField = try XCTUnwrap(textField(in: views, label: "image_upload.field.secret_key"))
        let domainField = try XCTUnwrap(textField(in: views, label: "image_upload.field.domain"))

        setText("Blog R2", on: nameField)
        setText("blog-assets", on: bucketField)
        setText("https://acct.r2.cloudflarestorage.com", on: endpointField)
        setText("AKIA_DEMO", on: accessKeyField)
        setText("https://cdn.blog.example.com", on: domainField)

        // Saving without secret key must fail and not persist host.
        let saveButton = try XCTUnwrap(allViews.compactMap { $0 as? NSButton }.first { $0.title == L10n.tr("settings.save") })
        saveButton.performClick(nil)
        XCTAssertTrue(store.settings.imageUpload.hosts.isEmpty)

        // Fill secret key and save.
        let secretValue = "SUPER_SECRET_VALUE_98765"
        setText(secretValue, on: secretKeyField)
        saveButton.performClick(nil)

        XCTAssertEqual(store.settings.imageUpload.hosts.count, 1)
        let savedHost = try XCTUnwrap(store.settings.imageUpload.hosts.first)
        XCTAssertEqual(savedHost.name, "Blog R2")
        XCTAssertEqual(savedHost.bucket, "blog-assets")
        XCTAssertEqual(try secretStore.secret(for: savedHost.id), secretValue)

        // Verify secret value never appears in plain-text UserDefaults settings JSON.
        let rawJSON = try XCTUnwrap(defaults.data(forKey: "launcher.settings.v1"))
        let jsonString = try XCTUnwrap(String(data: rawJSON, encoding: .utf8))
        XCTAssertFalse(jsonString.contains(secretValue))

        // History copy & clear actions
        let historyTable = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first {
            $0.accessibilityLabel() == L10n.tr("image_upload.history.list_accessibility")
        })
        historyTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let copyButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == L10n.tr("image_upload.history.copy")
        })
        copyButton.performClick(nil)
        XCTAssertEqual(copiedItem?.id, "h1")

        let clearButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == L10n.tr("image_upload.history.clear")
        })
        clearButton.performClick(nil)
        XCTAssertTrue(cleared)

        // Removing the host and saving cleans up the secret in Keychain/store.
        let removeButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == L10n.tr("image_upload.settings.remove_host")
        })
        removeButton.performClick(nil)
        saveButton.performClick(nil)
        XCTAssertTrue(store.settings.imageUpload.hosts.isEmpty)
        XCTAssertNil(try secretStore.secret(for: savedHost.id))
    }

    @MainActor private func textField(in views: [NSView], label key: String) -> NSTextField? {
        views.compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == L10n.tr(key)
        }
    }

    @MainActor private func setText(_ value: String, on field: NSTextField) {
        field.stringValue = value
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
