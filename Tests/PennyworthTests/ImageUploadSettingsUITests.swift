@testable import Pennyworth
import AppKit
import XCTest

final class ImageUploadSettingsUITests: XCTestCase {
    @MainActor func testAddHostViaSheetPersistsSecretOnlyInSecretStoreAndHistoryCopiesClears() throws {
        _ = NSApplication.shared
        defer { AppLocalization.configure(language: .system) }
        AppLocalization.configure(language: .simplifiedChinese)

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

        controller.window?.animationBehavior = .none
        controller.showWindow(nil)
        defer { controller.close() }
        controller.selectPage(L10n.tr("settings.page.image_upload"))
        XCTAssertEqual(controller.selectedPageTitle, L10n.tr("settings.page.image_upload"))

        let content = try XCTUnwrap(controller.window?.contentView)
        let uploadView = try XCTUnwrap(descendants(content).compactMap { $0 as? ImageUploadSettingsView }.first)

        // Open Add Host sheet.
        let addHostButton = try XCTUnwrap(descendants(uploadView).compactMap { $0 as? NSButton }.first {
            $0.title == L10n.tr("image_upload.settings.add_host")
        })
        addHostButton.performClick(nil)

        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let sheetViews = descendants(try XCTUnwrap(sheet.contentView))

        let nameField = try XCTUnwrap(textField(in: sheetViews, label: "image_upload.field.name"))
        let bucketField = try XCTUnwrap(textField(in: sheetViews, label: "image_upload.field.bucket"))
        let endpointField = try XCTUnwrap(textField(in: sheetViews, label: "image_upload.field.endpoint"))
        let accessKeyField = try XCTUnwrap(textField(in: sheetViews, label: "image_upload.field.access_key"))
        let secretKeyField = try XCTUnwrap(textField(in: sheetViews, label: "image_upload.field.secret_key"))
        let domainField = try XCTUnwrap(textField(in: sheetViews, label: "image_upload.field.domain"))

        nameField.stringValue = "Blog R2"
        bucketField.stringValue = "blog-assets"
        endpointField.stringValue = "https://acct.r2.cloudflarestorage.com"
        accessKeyField.stringValue = "AKIA_DEMO"
        domainField.stringValue = "https://cdn.blog.example.com"

        // Saving without secret key must fail inline and not persist host.
        let saveButton = try XCTUnwrap(sheetViews.compactMap { $0 as? NSButton }.first { $0.title == L10n.tr("settings.save") })
        saveButton.performClick(nil)
        XCTAssertTrue(store.settings.imageUpload.hosts.isEmpty)

        // Fill secret key and save.
        let secretValue = "SUPER_SECRET_VALUE_98765"
        secretKeyField.stringValue = secretValue
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

        // History tab copy & clear actions.
        uploadView.selectTab(.history)
        let copyButton = try XCTUnwrap(descendants(uploadView).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == L10n.format("image_upload.row.copy_accessibility", "a.png")
        })
        copyButton.performClick(nil)
        XCTAssertEqual(copiedItem?.id, "h1")

        let clearButton = try XCTUnwrap(descendants(uploadView).compactMap { $0 as? NSButton }.first {
            $0.title == L10n.tr("image_upload.history.clear")
        })
        clearButton.performClick(nil)
        XCTAssertTrue(cleared)

        // Deleting the host removes it immediately and cleans up its secret from the secret store.
        uploadView.selectTab(.hosts)
        let deleteButton = try XCTUnwrap(descendants(uploadView).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == L10n.format("image_upload.row.delete_accessibility", "Blog R2")
        })
        deleteButton.performClick(nil)
        XCTAssertTrue(store.settings.imageUpload.hosts.isEmpty)
        XCTAssertNil(try secretStore.secret(for: savedHost.id))
    }

    @MainActor private func textField(in views: [NSView], label key: String) -> NSTextField? {
        views.compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == L10n.tr(key)
        }
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
