import Foundation

enum ImageHostProvider: String, Codable, CaseIterable, Sendable {
    case s3
    case aliyunOSS
    case tencentCOS
    case qiniu

    var title: String {
        L10n.tr("image_upload.provider.\(rawValue)")
    }
}

enum UploadOutputFormat: String, Codable, CaseIterable, Sendable {
    case url
    case markdown
    case html
    case ubb

    var title: String {
        L10n.tr("image_upload.format.\(rawValue)")
    }

    func format(url: String, filename: String) -> String {
        let safeAlt = filename.replacingOccurrences(of: "\n", with: " ")
        switch self {
        case .url:
            return url
        case .markdown:
            let escapedAlt = safeAlt
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            return "![\(escapedAlt)](\(url))"
        case .html:
            let escapedURL = url.replacingOccurrences(of: "\"", with: "&quot;")
            let escapedAlt = safeAlt
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<img src=\"\(escapedURL)\" alt=\"\(escapedAlt)\"/>"
        case .ubb:
            return "[img]\(url)[/img]"
        }
    }
}

enum QiniuRegion: String, Codable, CaseIterable, Sendable {
    case z0
    case z1
    case z2
    case na0
    case as0
    case cnEast2 = "cn-east-2"
    case custom

    var title: String {
        L10n.tr("image_upload.qiniu_region.\(rawValue)")
    }

    var uploadEndpoint: String? {
        switch self {
        case .z0: return "https://upload.qiniup.com"
        case .z1: return "https://upload-z1.qiniup.com"
        case .z2: return "https://upload-z2.qiniup.com"
        case .na0: return "https://upload-na0.qiniup.com"
        case .as0: return "https://upload-as0.qiniup.com"
        case .cnEast2: return "https://upload-cn-east-2.qiniup.com"
        case .custom: return nil
        }
    }
}

/// Non-secret configuration for an image host. Secret keys live exclusively in Keychain.
struct ImageHostConfig: Codable, Equatable, Identifiable, Sendable {
    static let defaultSaveKeyPath = "uPic/{year}/{month}/{filename}{.suffix}"

    let id: String
    let name: String
    let provider: ImageHostProvider
    let bucket: String
    let region: String
    let endpoint: String
    let accessKey: String
    let domain: String
    let saveKeyPath: String
    let suffix: String
    let usePathStyle: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        provider: ImageHostProvider,
        bucket: String = "",
        region: String = "",
        endpoint: String = "",
        accessKey: String = "",
        domain: String = "",
        saveKeyPath: String = ImageHostConfig.defaultSaveKeyPath,
        suffix: String = "",
        usePathStyle: Bool = true
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.accessKey = accessKey
        self.domain = domain
        self.saveKeyPath = saveKeyPath
        self.suffix = suffix
        self.usePathStyle = usePathStyle
    }

    var trimmed: ImageHostConfig {
        ImageHostConfig(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: provider,
            bucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKey: accessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: domain.trimmingCharacters(in: .whitespacesAndNewlines),
            saveKeyPath: saveKeyPath.trimmingCharacters(in: .whitespacesAndNewlines),
            suffix: suffix.trimmingCharacters(in: .whitespacesAndNewlines),
            usePathStyle: usePathStyle
        )
    }

    static func makeTemplate(for provider: ImageHostProvider, name: String) -> ImageHostConfig {
        switch provider {
        case .s3:
            return ImageHostConfig(name: name, provider: .s3, region: "auto", usePathStyle: true)
        case .aliyunOSS:
            return ImageHostConfig(name: name, provider: .aliyunOSS, region: "oss-cn-hangzhou", usePathStyle: false)
        case .tencentCOS:
            return ImageHostConfig(name: name, provider: .tencentCOS, region: "ap-guangzhou", usePathStyle: false)
        case .qiniu:
            return ImageHostConfig(name: name, provider: .qiniu, region: QiniuRegion.z0.rawValue, usePathStyle: false)
        }
    }
}

struct ImageUploadSettings: Codable, Equatable, Sendable {
    static let maxHosts = 32
    static let compressFactorRange = 10...100

    let hosts: [ImageHostConfig]
    let selectedHostID: String?
    let outputFormat: UploadOutputFormat
    let compressFactor: Int
    let encodeURL: Bool
    let uploadClipboardHotKey: HotKeyPreset?
    let uploadFileHotKey: HotKeyPreset?

    static let defaults = ImageUploadSettings()

    init(
        hosts: [ImageHostConfig] = [],
        selectedHostID: String? = nil,
        outputFormat: UploadOutputFormat = .url,
        compressFactor: Int = 100,
        encodeURL: Bool = true,
        uploadClipboardHotKey: HotKeyPreset? = nil,
        uploadFileHotKey: HotKeyPreset? = nil
    ) {
        self.hosts = hosts
        self.selectedHostID = selectedHostID
        self.outputFormat = outputFormat
        self.compressFactor = compressFactor
        self.encodeURL = encodeURL
        self.uploadClipboardHotKey = uploadClipboardHotKey
        self.uploadFileHotKey = uploadFileHotKey
    }

    var activeHost: ImageHostConfig? {
        if let selectedHostID, let matched = hosts.first(where: { $0.id == selectedHostID }) {
            return matched
        }
        return hosts.first
    }

    func withSelectedHostID(_ hostID: String?) -> ImageUploadSettings {
        ImageUploadSettings(
            hosts: hosts,
            selectedHostID: hostID,
            outputFormat: outputFormat,
            compressFactor: compressFactor,
            encodeURL: encodeURL,
            uploadClipboardHotKey: uploadClipboardHotKey,
            uploadFileHotKey: uploadFileHotKey
        )
    }

    func withOutputFormat(_ format: UploadOutputFormat) -> ImageUploadSettings {
        ImageUploadSettings(
            hosts: hosts,
            selectedHostID: selectedHostID,
            outputFormat: format,
            compressFactor: compressFactor,
            encodeURL: encodeURL,
            uploadClipboardHotKey: uploadClipboardHotKey,
            uploadFileHotKey: uploadFileHotKey
        )
    }

    private enum CodingKeys: String, CodingKey {
        case hosts, selectedHostID, outputFormat, compressFactor, encodeURL
        case uploadClipboardHotKey, uploadFileHotKey
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try values.decodeIfPresent([ImageHostConfig].self, forKey: .hosts) ?? []
        selectedHostID = try values.decodeIfPresent(String.self, forKey: .selectedHostID)
        outputFormat = try values.decodeIfPresent(UploadOutputFormat.self, forKey: .outputFormat) ?? .url
        compressFactor = try values.decodeIfPresent(Int.self, forKey: .compressFactor) ?? 100
        encodeURL = try values.decodeIfPresent(Bool.self, forKey: .encodeURL) ?? true
        uploadClipboardHotKey = try values.decodeIfPresent(HotKeyPreset.self, forKey: .uploadClipboardHotKey)
        uploadFileHotKey = try values.decodeIfPresent(HotKeyPreset.self, forKey: .uploadFileHotKey)
    }

    static func validate(_ value: ImageUploadSettings) throws {
        guard value.hosts.count <= maxHosts else {
            throw ImageUploadError.tooManyHosts
        }
        guard compressFactorRange.contains(value.compressFactor) else {
            throw ImageUploadError.invalidCompressFactor
        }
        var seenIDs = Set<String>()
        for host in value.hosts {
            let trimmed = host.trimmed
            guard !trimmed.id.isEmpty, seenIDs.insert(trimmed.id).inserted else {
                throw ImageUploadError.invalidHostID
            }
            try validateHost(trimmed)
        }
        if let selected = value.selectedHostID, !value.hosts.isEmpty, !seenIDs.contains(selected) {
            throw ImageUploadError.invalidSelectedHost
        }
    }

    static func validateHost(_ host: ImageHostConfig) throws {
        let h = host.trimmed
        guard !h.name.isEmpty else {
            throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.name"), hostName: h.provider.title)
        }
        guard !h.bucket.isEmpty else {
            throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.bucket"), hostName: h.name)
        }
        guard !h.accessKey.isEmpty else {
            throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.access_key"), hostName: h.name)
        }
        if !h.domain.isEmpty, !isValidHTTPURL(h.domain) {
            throw ImageUploadError.invalidURL(field: L10n.tr("image_upload.field.domain"), hostName: h.name)
        }
        if !h.endpoint.isEmpty, !isValidHTTPURL(h.endpoint) {
            throw ImageUploadError.invalidURL(field: L10n.tr("image_upload.field.endpoint"), hostName: h.name)
        }
        switch h.provider {
        case .s3:
            if h.region.isEmpty {
                throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.region"), hostName: h.name)
            }
        case .aliyunOSS:
            if h.region.isEmpty && h.endpoint.isEmpty {
                throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.region"), hostName: h.name)
            }
        case .tencentCOS:
            if h.region.isEmpty && h.endpoint.isEmpty {
                throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.region"), hostName: h.name)
            }
        case .qiniu:
            if h.domain.isEmpty {
                throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.domain"), hostName: h.name)
            }
            let region = QiniuRegion(rawValue: h.region) ?? .custom
            if region == .custom && h.endpoint.isEmpty {
                throw ImageUploadError.missingHostField(field: L10n.tr("image_upload.field.endpoint"), hostName: h.name)
            }
        }
    }

    static func isValidHTTPURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }
}

struct UploadPayload: Equatable, Sendable {
    let data: Data
    let originalFilename: String
    let fileExtension: String
    let mimeType: String
    let objectKey: String
}

struct PreparedUploadRequest: Sendable {
    let request: URLRequest
    let objectKey: String
    let fallbackBaseURL: String
}

struct UploadResult: Equatable, Sendable {
    let url: String
    let formattedText: String
    let filename: String
    let hostName: String
    let provider: ImageHostProvider
    let fileSize: Int
    let thumbnailData: Data?
}

enum ImageUploadError: LocalizedError, Equatable {
    case tooManyHosts
    case invalidCompressFactor
    case invalidHostID
    case invalidSelectedHost
    case missingHostField(field: String, hostName: String)
    case invalidURL(field: String, hostName: String)
    case noHostConfigured
    case missingSecretKey(hostName: String)
    case clipboardEmpty
    case unreadableFile(String)
    case directoryNotSupported(String)
    case fileTooLarge(String, Int)
    case invalidEndpoint(String)
    case serverError(statusCode: Int, message: String)
    case invalidResponse(String)
    case keychainFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .tooManyHosts:
            return L10n.tr("image_upload.error.too_many_hosts")
        case .invalidCompressFactor:
            return L10n.tr("image_upload.error.invalid_compress_factor")
        case .invalidHostID:
            return L10n.tr("image_upload.error.invalid_host_id")
        case .invalidSelectedHost:
            return L10n.tr("image_upload.error.invalid_selected_host")
        case .missingHostField(let field, let hostName):
            return L10n.format("image_upload.error.missing_field", hostName, field)
        case .invalidURL(let field, let hostName):
            return L10n.format("image_upload.error.invalid_url", hostName, field)
        case .noHostConfigured:
            return L10n.tr("image_upload.error.no_host")
        case .missingSecretKey(let hostName):
            return L10n.format("image_upload.error.missing_secret", hostName)
        case .clipboardEmpty:
            return L10n.tr("image_upload.error.clipboard_empty")
        case .unreadableFile(let name):
            return L10n.format("image_upload.error.unreadable_file", name)
        case .directoryNotSupported(let name):
            return L10n.format("image_upload.error.directory_not_supported", name)
        case .fileTooLarge(let name, let limitMB):
            return L10n.format("image_upload.error.file_too_large", name, limitMB)
        case .invalidEndpoint(let value):
            return L10n.format("image_upload.error.invalid_endpoint", value)
        case .serverError(let statusCode, let message):
            return L10n.format("image_upload.error.server_error", statusCode, message)
        case .invalidResponse(let detail):
            return L10n.format("image_upload.error.invalid_response", detail)
        case .keychainFailure(let status):
            return L10n.format("image_upload.error.keychain_failure", Int(status))
        }
    }
}
