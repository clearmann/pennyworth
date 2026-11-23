import Foundation
import Security

protocol ImageUploadSecretStoring: AnyObject, Sendable {
    func secret(for hostID: String) throws -> String?
    func setSecret(_ secret: String, for hostID: String) throws
    func deleteSecret(for hostID: String) throws
}

final class KeychainSecretStore: ImageUploadSecretStoring, @unchecked Sendable {
    private let service: String

    init(service: String = "com.clearmann.pennyworth.image-upload") {
        self.service = service
    }

    func secret(for hostID: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ImageUploadError.keychainFailure(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func setSecret(_ secret: String, for hostID: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteSecret(for: hostID)
            return
        }
        let encoded = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = encoded
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ImageUploadError.keychainFailure(addStatus)
            }
            return
        }
        throw ImageUploadError.keychainFailure(updateStatus)
    }

    func deleteSecret(for hostID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ImageUploadError.keychainFailure(status)
        }
    }
}

final class InMemorySecretStore: ImageUploadSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]

    init(initial: [String: String] = [:]) {
        self.storage = initial
    }

    func secret(for hostID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[hostID]
    }

    func setSecret(_ secret: String, for hostID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            storage.removeValue(forKey: hostID)
        } else {
            storage[hostID] = trimmed
        }
    }

    func deleteSecret(for hostID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: hostID)
    }
}
