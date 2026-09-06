import Foundation
import Security

enum SecureStoreError: LocalizedError {
    case invalidStoredValue
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            "The stored Keychain value is not valid UTF-8."
        case .unexpectedStatus(let status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain returned status \(status)."
        }
    }
}

struct SecureStore: Sendable {
    static let productionService = "com.justin.Kotai.credentials.v2"

    let service: String

    init(service: String = Self.productionService) {
        self.service = service
    }

    // Never query earlier service namespaces: their pre-release ACL can trigger a login Keychain password prompt.

    func read(account: String) throws -> String? {
        let query = readQuery(account: account)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureStoreError.unexpectedStatus(status)
        }
        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw SecureStoreError.invalidStoredValue
        }

        return value
    }

    func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = mutationQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var newItem = query
            attributes.forEach { key, value in
                newItem[key] = value
            }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecureStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw SecureStoreError.unexpectedStatus(updateStatus)
        }
    }

    func delete(account: String) throws {
        let query = mutationQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    func readQuery(account: String) -> [String: Any] {
        var query = mutationQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        return query
    }

    func mutationQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
