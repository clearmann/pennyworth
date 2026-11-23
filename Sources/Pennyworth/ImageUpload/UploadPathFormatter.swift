import Foundation

enum UploadPathFormatter {
    private static let randomAlphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// RFC 3986 unreserved characters allowed verbatim in AWS SigV4 / S3 / OSS / COS URI paths.
    static let rfc3986Unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return set
    }()

    static func resolveObjectKey(
        template: String,
        filenameWithoutExtension: String,
        fileExtension: String,
        date: Date = Date(),
        randomProvider: () -> String = { generateRandomToken(length: 6) },
        timeZone: TimeZone = .current
    ) -> String {
        let effectiveTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ImageHostConfig.defaultSaveKeyPath
            : template.trimmingCharacters(in: .whitespacesAndNewlines)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = String(format: "%04d", comps.year ?? 1970)
        let month = String(format: "%02d", comps.month ?? 1)
        let day = String(format: "%02d", comps.day ?? 1)
        let hour = String(format: "%02d", comps.hour ?? 0)
        let minute = String(format: "%02d", comps.minute ?? 0)
        let second = String(format: "%02d", comps.second ?? 0)
        let sinceSecond = String(Int64(date.timeIntervalSince1970))
        let sinceMillisecond = String(Int64((date.timeIntervalSince1970 * 1000.0).rounded()))

        let cleanedBase = sanitizeFilename(filenameWithoutExtension)
        let fallbackName = "\(year)\(month)\(day)-\(hour)\(minute)\(second)"
        let safeFilename = cleanedBase.isEmpty ? fallbackName : cleanedBase

        let cleanedExt = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
            .replacingOccurrences(of: "/", with: "")
        let dotSuffix = cleanedExt.isEmpty ? "" : ".\(cleanedExt)"

        var result = effectiveTemplate
        if result.contains("{random}") {
            result = result.replacingOccurrences(of: "{random}", with: randomProvider())
        }
        let replacements: [(String, String)] = [
            ("{year}", year),
            ("{month}", month),
            ("{day}", day),
            ("{hour}", hour),
            ("{minute}", minute),
            ("{second}", second),
            ("{since_second}", sinceSecond),
            ("{since_millisecond}", sinceMillisecond),
            ("{filename}", safeFilename),
            ("{.suffix}", dotSuffix),
            ("{suffix}", cleanedExt),
        ]
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }

        let normalizedSegments = result
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }

        if normalizedSegments.isEmpty {
            return safeFilename + dotSuffix
        }
        return normalizedSegments.joined(separator: "/")
    }

    static func encodePathSegments(_ objectKey: String) -> String {
        objectKey
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { encodeRFC3986(String($0)) }
            .joined(separator: "/")
    }

    static func encodeRFC3986(_ value: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if isRFC3986Unreserved(byte) {
                encoded.append(Character(UnicodeScalar(byte)))
            } else {
                encoded.append(String(format: "%%%02X", byte))
            }
        }
        return encoded
    }

    static func buildPublicURL(
        baseDomain: String,
        objectKey: String,
        suffix: String = "",
        percentEncode: Bool = true
    ) -> String {
        var normalizedBase = baseDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedBase.hasSuffix("/") {
            normalizedBase.removeLast()
        }
        var normalizedKey = objectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedKey.hasPrefix("/") {
            normalizedKey.removeFirst()
        }
        let renderedKey = percentEncode ? encodePathSegments(normalizedKey) : normalizedKey
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedBase)/\(renderedKey)\(trimmedSuffix)"
    }

    static func generateRandomToken(length: Int) -> String {
        guard length > 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status == errSecSuccess {
            return String(bytes.map { randomAlphabet[Int($0) % randomAlphabet.count] })
        }
        return String((0..<length).map { _ in randomAlphabet.randomElement()! })
    }

    private static func sanitizeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let disallowed = CharacterSet(charactersIn: "/\\:*?\"<>|\0\r\n\t")
        let scalars = trimmed.unicodeScalars.map { disallowed.contains($0) ? "_" : String($0) }
        return scalars.joined().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func isRFC3986Unreserved(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) // A-Z
            || (byte >= 0x61 && byte <= 0x7A) // a-z
            || (byte >= 0x30 && byte <= 0x39) // 0-9
            || byte == 0x2D // -
            || byte == 0x2E // .
            || byte == 0x5F // _
            || byte == 0x7E // ~
    }
}
