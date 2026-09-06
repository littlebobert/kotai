import Foundation
import Security

enum SecureStoreError: LocalizedError, Equatable {
    enum StatusClassification: Equatable {
        case itemNotFound
        case accessDenied
        case otherFailure
    }

    case invalidStoredValue
    case accessDenied(OSStatus)
    case unexpectedStatus(OSStatus)

    static func classify(_ status: OSStatus) -> StatusClassification {
        switch status {
        case errSecItemNotFound:
            .itemNotFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            .accessDenied
        default:
            .otherFailure
        }
    }

    static func statusError(_ status: OSStatus) -> SecureStoreError {
        switch classify(status) {
        case .accessDenied:
            .accessDenied(status)
        case .itemNotFound, .otherFailure:
            .unexpectedStatus(status)
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            String(localized: "The stored Keychain value is not valid UTF-8.")
        case .accessDenied:
            String(localized: "Kotai could not access its saved credentials. In the Keychain prompt, choose Always Allow, then relaunch Kotai.")
        case .unexpectedStatus(let status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? String(localized: "Keychain returned status \(status).")
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

        switch SecureStoreError.classify(status) {
        case .itemNotFound:
            return nil
        case .accessDenied, .otherFailure:
            guard status == errSecSuccess else {
                throw SecureStoreError.statusError(status)
            }
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
                throw SecureStoreError.statusError(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw SecureStoreError.statusError(updateStatus)
        }
    }

    func delete(account: String) throws {
        let query = mutationQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.statusError(status)
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
