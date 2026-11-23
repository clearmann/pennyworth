import Foundation

protocol HTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionHTTPTransport: HTTPTransporting {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ImageUploadError.invalidResponse("Non-HTTP response")
        }
        return (data, http)
    }
}

protocol ImageHostUploading: Sendable {
    func buildRequest(
        payload: UploadPayload,
        config: ImageHostConfig,
        secretKey: String,
        date: Date
    ) throws -> PreparedUploadRequest

    func parseResponse(
        data: Data,
        response: HTTPURLResponse,
        prepared: PreparedUploadRequest,
        config: ImageHostConfig,
        encodeURL: Bool
    ) throws -> String
}

enum UploadResponseHelper {
    static func extractErrorMessage(from data: Data, statusCode: Int) -> String {
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            // Try XML <Message>...</Message> (S3 / OSS / COS)
            if let message = extractXMLTag("Message", from: raw), !message.isEmpty {
                return message
            }
            // Try JSON {"error": "..."} (Qiniu) or {"message": "..."}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errorText = json["error"] as? String, !errorText.isEmpty {
                    return errorText
                }
                if let messageText = json["message"] as? String, !messageText.isEmpty {
                    return messageText
                }
            }
            return String(raw.prefix(200))
        }
        return HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }

    static func hostHeaderValue(for url: URL) -> String {
        guard let host = url.host else { return "" }
        if let port = url.port {
            let isDefaultHTTP = url.scheme?.lowercased() == "http" && port == 80
            let isDefaultHTTPS = url.scheme?.lowercased() == "https" && port == 443
            if !isDefaultHTTP && !isDefaultHTTPS {
                return "\(host):\(port)"
            }
        }
        return host
    }

    static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func extractXMLTag(_ tag: String, from xml: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let startRange = xml.range(of: open),
              let endRange = xml.range(of: close, range: startRange.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
