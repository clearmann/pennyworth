import CryptoKit
import Foundation

struct TencentCOSUploader: ImageHostUploading {
    private static let signTTLSeconds: Int64 = 3600

    func buildRequest(
        payload: UploadPayload,
        config: ImageHostConfig,
        secretKey: String,
        date: Date
    ) throws -> PreparedUploadRequest {
        let trimmed = config.trimmed
        let encodedKey = UploadPathFormatter.encodePathSegments(payload.objectKey)
        let (requestURL, fallbackBaseURL) = try resolveURL(config: trimmed, encodedKey: encodedKey)

        let start = Int64(date.timeIntervalSince1970)
        let end = start + Self.signTTLSeconds
        let keyTime = "\(start);\(end)"

        let signKeyMAC = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(keyTime.utf8),
            using: SymmetricKey(data: Data(secretKey.utf8))
        )
        let signKey = UploadResponseHelper.hexString(signKeyMAC)

        let hostHeader = UploadResponseHelper.hostHeaderValue(for: requestURL)
        let lowerHost = hostHeader.lowercased()
        let encodedHostValue = UploadPathFormatter.encodeRFC3986(lowerHost)
        let uriPathname = "/\(payload.objectKey)"

        let httpString = "put\n\(uriPathname)\n\nhost=\(encodedHostValue)\n"
        let sha1HttpString = UploadResponseHelper.hexString(Insecure.SHA1.hash(data: Data(httpString.utf8)))
        let stringToSign = "sha1\n\(keyTime)\n\(sha1HttpString)\n"

        let signatureMAC = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: Data(signKey.utf8))
        )
        let signature = UploadResponseHelper.hexString(signatureMAC)

        let authorization = [
            "q-sign-algorithm=sha1",
            "q-ak=\(trimmed.accessKey)",
            "q-sign-time=\(keyTime)",
            "q-key-time=\(keyTime)",
            "q-header-list=host",
            "q-url-param-list=",
            "q-signature=\(signature)",
        ].joined(separator: "&")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.httpBody = payload.data
        request.timeoutInterval = 60
        request.setValue(hostHeader, forHTTPHeaderField: "Host")
        request.setValue(payload.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        return PreparedUploadRequest(
            request: request,
            objectKey: payload.objectKey,
            fallbackBaseURL: fallbackBaseURL
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
        let baseDomain = trimmed.domain.isEmpty ? prepared.fallbackBaseURL : trimmed.domain
        return UploadPathFormatter.buildPublicURL(
            baseDomain: baseDomain,
            objectKey: prepared.objectKey,
            suffix: trimmed.suffix,
            percentEncode: encodeURL
        )
    }

    private func resolveURL(config: ImageHostConfig, encodedKey: String) throws -> (URL, String) {
        let base: String
        if !config.endpoint.isEmpty {
            guard let components = URLComponents(string: config.endpoint),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = components.host,
                  !host.isEmpty else {
                throw ImageUploadError.invalidEndpoint(config.endpoint)
            }
            let portPart = components.port.map { ":\($0)" } ?? ""
            let bucketHost = host.hasPrefix("\(config.bucket).") ? host : "\(config.bucket).\(host)"
            base = "\(scheme)://\(bucketHost)\(portPart)"
        } else {
            let region = config.region.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !region.isEmpty else {
                throw ImageUploadError.invalidEndpoint(config.region)
            }
            base = "https://\(config.bucket).cos.\(region).myqcloud.com"
        }

        guard let url = URL(string: "\(base)/\(encodedKey)") else {
            throw ImageUploadError.invalidEndpoint(base)
        }
        return (url, base)
    }
}
