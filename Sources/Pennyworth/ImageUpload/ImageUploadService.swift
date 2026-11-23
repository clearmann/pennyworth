import Foundation

final class ImageUploadService: @unchecked Sendable {
    private let transport: HTTPTransporting
    private let secretStore: ImageUploadSecretStoring
    private let now: () -> Date
    private let randomProvider: () -> String

    init(
        transport: HTTPTransporting = URLSessionHTTPTransport(),
        secretStore: ImageUploadSecretStoring = KeychainSecretStore(),
        now: @escaping () -> Date = Date.init,
        randomProvider: @escaping () -> String = { UploadPathFormatter.generateRandomToken(length: 6) }
    ) {
        self.transport = transport
        self.secretStore = secretStore
        self.now = now
        self.randomProvider = randomProvider
    }

    static func uploader(for provider: ImageHostProvider) -> ImageHostUploading {
        switch provider {
        case .s3: return S3CompatibleUploader()
        case .aliyunOSS: return AliyunOSSUploader()
        case .tencentCOS: return TencentCOSUploader()
        case .qiniu: return QiniuUploader()
        }
    }

    func upload(
        inputs: [RawUploadInput],
        settings: ImageUploadSettings
    ) async throws -> [UploadResult] {
        guard let host = settings.activeHost else {
            throw ImageUploadError.noHostConfigured
        }
        return try await upload(inputs: inputs, host: host, settings: settings)
    }

    func upload(
        inputs: [RawUploadInput],
        host: ImageHostConfig,
        settings: ImageUploadSettings
    ) async throws -> [UploadResult] {
        let trimmedHost = host.trimmed
        try ImageUploadSettings.validateHost(trimmedHost)
        guard let secretKey = try secretStore.secret(for: trimmedHost.id),
              !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImageUploadError.missingSecretKey(hostName: trimmedHost.name)
        }

        let uploader = Self.uploader(for: trimmedHost.provider)
        var results: [UploadResult] = []
        results.reserveCapacity(inputs.count)

        for input in inputs {
            let compressed = ImageCompressor.compress(
                data: input.data,
                fileExtension: input.fileExtension,
                mimeType: input.mimeType,
                qualityFactor: settings.compressFactor
            )
            let timestamp = now()
            let objectKey = UploadPathFormatter.resolveObjectKey(
                template: trimmedHost.saveKeyPath,
                filenameWithoutExtension: input.filenameWithoutExtension,
                fileExtension: compressed.fileExtension,
                date: timestamp,
                randomProvider: randomProvider
            )
            let finalFilename = compressed.fileExtension.isEmpty
                ? input.filenameWithoutExtension
                : "\(input.filenameWithoutExtension).\(compressed.fileExtension)"
            let payload = UploadPayload(
                data: compressed.data,
                originalFilename: finalFilename,
                fileExtension: compressed.fileExtension,
                mimeType: compressed.mimeType,
                objectKey: objectKey
            )

            let prepared = try uploader.buildRequest(
                payload: payload,
                config: trimmedHost,
                secretKey: secretKey,
                date: timestamp
            )
            let (responseData, httpResponse) = try await transport.send(prepared.request)
            let url = try uploader.parseResponse(
                data: responseData,
                response: httpResponse,
                prepared: prepared,
                config: trimmedHost,
                encodeURL: settings.encodeURL
            )
            let formatted = settings.outputFormat.format(url: url, filename: finalFilename)
            let thumbnail = ImageCompressor.makeThumbnail(from: input.data)

            results.append(UploadResult(
                url: url,
                formattedText: formatted,
                filename: finalFilename,
                hostName: trimmedHost.name,
                provider: trimmedHost.provider,
                fileSize: compressed.data.count,
                thumbnailData: thumbnail
            ))
        }

        return results
    }
}
