@testable import Pennyworth
import Carbon
import XCTest

final class ImageUploadSettingsTests: XCTestCase {
    func testSettingsRoundTripAndLegacyDefaults() throws {
        let name = "ImageUploadSettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        // Legacy payload without imageUpload key should decode cleanly to defaults.
        defaults.set(
            Data("{\"hotKey\":\"optionSpace\",\"searchDirectories\":[],\"searchEngine\":\"google\",\"rememberUsage\":true}".utf8),
            forKey: "launcher.settings.v1"
        )
        let legacyStore = SettingsStore(defaults: defaults)
        XCTAssertEqual(legacyStore.settings.imageUpload, .defaults)
        XCTAssertNil(legacyStore.warning)

        let host = ImageHostConfig(
            id: "host-r2",
            name: "Cloudflare R2",
            provider: .s3,
            bucket: "assets",
            region: "auto",
            endpoint: "https://acct.r2.cloudflarestorage.com",
            accessKey: "AKIA123456",
            domain: "https://cdn.example.com",
            saveKeyPath: "img/{year}/{month}/{filename}{.suffix}",
            suffix: "?v=1",
            usePathStyle: true
        )
        let uploadSettings = ImageUploadSettings(
            hosts: [host],
            selectedHostID: host.id,
            outputFormat: .markdown,
            compressFactor: 80,
            encodeURL: true,
            uploadClipboardHotKey: .custom(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(cmdKey | shiftKey)),
            uploadFileHotKey: .custom(keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(cmdKey | shiftKey))
        )

        let updated = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            imageUpload: uploadSettings
        )
        try legacyStore.save(updated)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.imageUpload, uploadSettings)
        XCTAssertEqual(reloaded.settings.imageUpload.activeHost, host)
    }

    func testValidationRejectsInvalidHostsAndSettings() {
        XCTAssertThrowsError(try ImageUploadSettings.validate(ImageUploadSettings(compressFactor: 5)))
        XCTAssertThrowsError(try ImageUploadSettings.validate(ImageUploadSettings(compressFactor: 105)))

        let validS3 = ImageHostConfig(
            id: "s3-1",
            name: "R2",
            provider: .s3,
            bucket: "my-bucket",
            region: "auto",
            endpoint: "https://r2.example.com",
            accessKey: "ak"
        )
        XCTAssertNoThrow(try ImageUploadSettings.validate(ImageUploadSettings(hosts: [validS3], selectedHostID: "s3-1")))

        // Missing selected host reference
        XCTAssertThrowsError(try ImageUploadSettings.validate(ImageUploadSettings(hosts: [validS3], selectedHostID: "missing")))

        // Duplicate host IDs
        XCTAssertThrowsError(try ImageUploadSettings.validate(ImageUploadSettings(hosts: [validS3, validS3], selectedHostID: "s3-1")))

        // Qiniu requires domain and custom region requires endpoint
        let qiniuMissingDomain = ImageHostConfig(
            id: "qn-1",
            name: "Qiniu",
            provider: .qiniu,
            bucket: "bucket",
            region: QiniuRegion.z0.rawValue,
            accessKey: "ak",
            domain: ""
        )
        XCTAssertThrowsError(try ImageUploadSettings.validate(ImageUploadSettings(hosts: [qiniuMissingDomain])))

        let qiniuCustomNoEndpoint = ImageHostConfig(
            id: "qn-2",
            name: "Qiniu Custom",
            provider: .qiniu,
            bucket: "bucket",
            region: QiniuRegion.custom.rawValue,
            endpoint: "",
            accessKey: "ak",
            domain: "https://cdn.example.com"
        )
        XCTAssertThrowsError(try ImageUploadSettings.validate(ImageUploadSettings(hosts: [qiniuCustomNoEndpoint])))

        // Invalid domain scheme
        let badDomain = ImageHostConfig(
            id: "s3-bad",
            name: "Bad",
            provider: .s3,
            bucket: "bucket",
            region: "us-east-1",
            accessKey: "ak",
            domain: "ftp://example.com"
        )
        XCTAssertThrowsError(try ImageUploadSettings.validate(ImageUploadSettings(hosts: [badDomain])))
    }

    func testUploadHotKeyConflictValidation() throws {
        let name = "UploadHotKeyConflict.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)

        let conflictWithLauncher = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            imageUpload: ImageUploadSettings(uploadClipboardHotKey: .optionSpace)
        )
        XCTAssertThrowsError(try store.save(conflictWithLauncher))

        let duplicateUploadHotKeys = HotKeyPreset.custom(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(cmdKey | optionKey))
        let conflictWithEachOther = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            imageUpload: ImageUploadSettings(
                uploadClipboardHotKey: duplicateUploadHotKeys,
                uploadFileHotKey: duplicateUploadHotKeys
            )
        )
        XCTAssertThrowsError(try store.save(conflictWithEachOther))

        let conflictWithSettings = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            imageUpload: ImageUploadSettings(uploadFileHotKey: .commandComma)
        )
        XCTAssertThrowsError(try store.save(conflictWithSettings))

        // Unmodified F18 should be allowed per project hotkey design constraints.
        let f18 = HotKeyPreset.custom(keyCode: UInt32(kVK_F18), modifiers: 0)
        let validF18 = LauncherSettings(
            hotKey: .optionSpace,
            searchDirectories: [],
            searchEngine: .google,
            rememberUsage: true,
            imageUpload: ImageUploadSettings(uploadClipboardHotKey: f18)
        )
        XCTAssertNoThrow(try store.save(validF18))
    }
}
