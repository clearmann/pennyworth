import CryptoKit
import Foundation

struct AliyunOSSUploader: ImageHostUploading {
    func buildRequest(
        payload: UploadPayload,
        config: ImageHostConfig,
        secretKey: String,
        date: Date
    ) throws -> PreparedUploadRequest {
        let trimmed = config.trimmed
        let encodedKey = UploadPathFormatter.encodePathSegments(payload.objectKey)
        let (requestURL, fallbackBaseURL) = try resolveURL(config: trimmed, encodedKey: encodedKey)

        let dateHeader = Self.httpDateString(from: date)
        let contentMD5 = Data(Insecure.MD5.hash(data: payload.data)).base64EncodedString()
        let canonicalizedResource = "/\(trimmed.bucket)/\(payload.objectKey)"

        let stringToSign = [
            "PUT",
            contentMD5,
            payload.mimeType,
            dateHeader,
            canonicalizedResource,
        ].joined(separator: "\n")

        let key = SymmetricKey(data: Data(secretKey.utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        let signature = Data(mac).base64EncodedString()

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.httpBody = payload.data
        request.timeoutInterval = 60
        request.setValue(UploadResponseHelper.hostHeaderValue(for: requestURL), forHTTPHeaderField: "Host")
        request.setValue(dateHeader, forHTTPHeaderField: "Date")
        request.setValue(payload.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentMD5, forHTTPHeaderField: "Content-MD5")
        request.setValue("OSS \(trimmed.accessKey):\(signature)", forHTTPHeaderField: "Authorization")

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
            let regionHost = normalizedRegionHost(config.region)
            guard !regionHost.isEmpty else {
                throw ImageUploadError.invalidEndpoint(config.region)
            }
            base = "https://\(config.bucket).\(regionHost)"
        }

        guard let url = URL(string: "\(base)/\(encodedKey)") else {
            throw ImageUploadError.invalidEndpoint(base)
        }
        return (url, base)
    }

    private func normalizedRegionHost(_ rawRegion: String) -> String {
        let region = rawRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !region.isEmpty else { return "" }
        if region.contains(".") {
            return region
        }
        let prefixed = region.hasPrefix("oss-") ? region : "oss-\(region)"
        return "\(prefixed).aliyuncs.com"
    }

    static func httpDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}
