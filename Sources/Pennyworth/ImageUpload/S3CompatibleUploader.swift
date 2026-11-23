import CryptoKit
import Foundation

struct S3CompatibleUploader: ImageHostUploading {
    func buildRequest(
        payload: UploadPayload,
        config: ImageHostConfig,
        secretKey: String,
        date: Date
    ) throws -> PreparedUploadRequest {
        let trimmed = config.trimmed
        let region = trimmed.region.isEmpty ? "us-east-1" : trimmed.region
        let encodedKey = UploadPathFormatter.encodePathSegments(payload.objectKey)

        let (requestURL, canonicalURI, fallbackBaseURL) = try resolveURLs(
            config: trimmed,
            region: region,
            encodedKey: encodedKey
        )

        let hostHeader = UploadResponseHelper.hostHeaderValue(for: requestURL)
        let amzDate = Self.amzDateString(from: date)
        let dateStamp = String(amzDate.prefix(8))
        let payloadHash = UploadResponseHelper.hexString(SHA256.hash(data: payload.data))

        let canonicalHeaders =
            "content-type:\(payload.mimeType)\n" +
            "host:\(hostHeader)\n" +
            "x-amz-content-sha256:\(payloadHash)\n" +
            "x-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = [
            "PUT",
            canonicalURI,
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let canonicalRequestHash = UploadResponseHelper.hexString(SHA256.hash(data: Data(canonicalRequest.utf8)))
        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash,
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secretKey: secretKey, dateStamp: dateStamp, region: region, service: "s3")
        let signature = UploadResponseHelper.hexString(
            HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: signingKey)
        )
        let authorization =
            "AWS4-HMAC-SHA256 Credential=\(trimmed.accessKey)/\(credentialScope), " +
            "SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.httpBody = payload.data
        request.timeoutInterval = 60
        request.setValue(hostHeader, forHTTPHeaderField: "Host")
        request.setValue(payload.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
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

    private func resolveURLs(
        config: ImageHostConfig,
        region: String,
        encodedKey: String
    ) throws -> (url: URL, canonicalURI: String, fallbackBaseURL: String) {
        let encodedBucket = UploadPathFormatter.encodeRFC3986(config.bucket)

        if config.endpoint.isEmpty {
            let base: String
            let canonicalURI: String
            if config.usePathStyle {
                base = "https://s3.\(region).amazonaws.com/\(encodedBucket)"
                canonicalURI = "/\(encodedBucket)/\(encodedKey)"
            } else {
                base = "https://\(config.bucket).s3.\(region).amazonaws.com"
                canonicalURI = "/\(encodedKey)"
            }
            guard let url = URL(string: "\(base)/\(encodedKey)") else {
                throw ImageUploadError.invalidEndpoint(base)
            }
            return (url, canonicalURI, base)
        }

        guard let components = URLComponents(string: config.endpoint),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            throw ImageUploadError.invalidEndpoint(config.endpoint)
        }

        let portPart = components.port.map { ":\($0)" } ?? ""
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }

        let base: String
        let canonicalURI: String
        if config.usePathStyle {
            base = "\(scheme)://\(host)\(portPart)\(basePath)/\(encodedBucket)"
            canonicalURI = "\(basePath)/\(encodedBucket)/\(encodedKey)"
        } else {
            let virtualHost = host.hasPrefix("\(config.bucket).") ? host : "\(config.bucket).\(host)"
            base = "\(scheme)://\(virtualHost)\(portPart)\(basePath)"
            canonicalURI = "\(basePath)/\(encodedKey)"
        }
        guard let url = URL(string: "\(base)/\(encodedKey)") else {
            throw ImageUploadError.invalidEndpoint(base)
        }
        return (url, canonicalURI, base)
    }

    private func deriveSigningKey(
        secretKey: String,
        dateStamp: String,
        region: String,
        service: String
    ) -> SymmetricKey {
        let kSecret = SymmetricKey(data: Data("AWS4\(secretKey)".utf8))
        let kDate = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(dateStamp.utf8), using: kSecret)))
        let kRegion = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(region.utf8), using: kDate)))
        let kService = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(service.utf8), using: kRegion)))
        return SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: kService)))
    }

    static func amzDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
