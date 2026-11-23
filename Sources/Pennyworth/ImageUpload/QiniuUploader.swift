import CryptoKit
import Foundation

struct QiniuUploader: ImageHostUploading {
    private static let tokenTTLSeconds: Int64 = 3600

    func buildRequest(
        payload: UploadPayload,
        config: ImageHostConfig,
        secretKey: String,
        date: Date
    ) throws -> PreparedUploadRequest {
        let trimmed = config.trimmed
        let uploadURL = try resolveUploadURL(config: trimmed)
        let deadline = Int64(date.timeIntervalSince1970) + Self.tokenTTLSeconds
        let token = try Self.makeUploadToken(
            accessKey: trimmed.accessKey,
            secretKey: secretKey,
            bucket: trimmed.bucket,
            objectKey: payload.objectKey,
            deadline: deadline
        )

        let boundary = "PennyworthBoundary-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let body = buildMultipartBody(
            boundary: boundary,
            token: token,
            objectKey: payload.objectKey,
            filename: payload.originalFilename,
            mimeType: payload.mimeType,
            fileData: payload.data
        )

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")

        return PreparedUploadRequest(
            request: request,
            objectKey: payload.objectKey,
            fallbackBaseURL: trimmed.domain
        )
    }

    func parseResponse(
        data: Data,
        response: HTTPURLResponse,
        prepared: PreparedUploadRequest,
        config: ImageHostConfig,
        encodeURL: Bool
    ) throws -> String {
        guard (200..<300).contains(response.statusCode) else {
            throw ImageUploadError.serverError(
                statusCode: response.statusCode,
                message: UploadResponseHelper.extractErrorMessage(from: data, statusCode: response.statusCode)
            )
        }

        let trimmed = config.trimmed
        var finalKey = prepared.objectKey
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let returnedKey = json["key"] as? String,
           !returnedKey.isEmpty {
            finalKey = returnedKey
        }

        return UploadPathFormatter.buildPublicURL(
            baseDomain: trimmed.domain,
            objectKey: finalKey,
            suffix: trimmed.suffix,
            percentEncode: encodeURL
        )
    }

    static func makeUploadToken(
        accessKey: String,
        secretKey: String,
        bucket: String,
        objectKey: String,
        deadline: Int64
    ) throws -> String {
        let policy: [String: Any] = [
            "scope": "\(bucket):\(objectKey)",
            "deadline": deadline,
        ]
        let policyData = try JSONSerialization.data(
            withJSONObject: policy,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let encodedPolicy = urlSafeBase64(policyData)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(encodedPolicy.utf8),
            using: SymmetricKey(data: Data(secretKey.utf8))
        )
        let encodedSign = urlSafeBase64(Data(mac))
        return "\(accessKey):\(encodedSign):\(encodedPolicy)"
    }

    static func urlSafeBase64(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private func resolveUploadURL(config: ImageHostConfig) throws -> URL {
        let region = QiniuRegion(rawValue: config.region) ?? .custom
        let rawEndpoint = region.uploadEndpoint ?? config.endpoint
        guard !rawEndpoint.isEmpty, let url = URL(string: rawEndpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw ImageUploadError.invalidEndpoint(rawEndpoint)
        }
        return url
    }

    private func buildMultipartBody(
        boundary: String,
        token: String,
        objectKey: String,
        filename: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        let safeFilename = filename
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"token\"\r\n\r\n")
        append("\(token)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"key\"\r\n\r\n")
        append("\(objectKey)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}
