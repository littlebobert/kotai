import Foundation
import Security

enum SecureStoreError: LocalizedError, Equatable {
    enum StatusClassification: Equatable {
        case success
        case itemNotFound
        case duplicateItem
        case accessDenied
        case otherFailure
    }

    case invalidStoredValue
    case accessDenied(OSStatus)
    case unexpectedStatus(OSStatus)

    static func classify(_ status: OSStatus) -> StatusClassification {
        switch status {
        case errSecSuccess: .success
        case errSecItemNotFound: .itemNotFound
        case errSecDuplicateItem: .duplicateItem
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed: .accessDenied
        default: .otherFailure
        }
    }

    static func statusError(_ status: OSStatus) -> SecureStoreError {
        switch classify(status) {
        case .accessDenied: .accessDenied(status)
        case .success, .itemNotFound, .duplicateItem, .otherFailure: .unexpectedStatus(status)
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            String(localized: "The stored Keychain value is not valid UTF-8.")
        case .accessDenied:
            String(localized: "Kotai could not access its saved credentials. Allow Keychain access, then refresh or relaunch Kotai.")
        case .unexpectedStatus(let status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? String(localized: "Keychain returned status \(status).")
        }
    }
}

protocol SecureStoreBackend: Sendable {
    func readItems(service: SecureStore.Service) throws -> [String: String]
    func write(_ value: String, account: String, service: SecureStore.Service) throws
    func delete(account: String, service: SecureStore.Service) throws
}

struct SecureStore: Sendable {
    struct Service: Equatable, Sendable {
        let name: String
    }

    static let productionService = "com.justin.Kotai.credentials.v3"
    static let legacyVaultService = "com.justin.Kotai.credentials.v2"
    static let priorLegacyService = "com.kotai.credentials"
    static let production = Service(name: productionService)
    static let migrationServices = [
        Service(name: legacyVaultService),
        Service(name: priorLegacyService),
    ]

    private let backend: any SecureStoreBackend
    private let service: Service
    private let legacyServices: [Service]

    init(
        backend: any SecureStoreBackend = SecurityKeychainBackend(),
        service: Service = Self.production,
        legacyServices: [Service] = Self.migrationServices
    ) {
        self.backend = backend
        self.service = service
        self.legacyServices = legacyServices
    }

    func readAllCandidates() throws -> [(service: Service, items: [String: String])] {
        var candidates = [(service: service, items: try backend.readItems(service: service))]
        if !candidates[0].items.isEmpty { return candidates }
        for legacyService in legacyServices {
            let items = try backend.readItems(service: legacyService)
            candidates.append((legacyService, items))
            if !items.isEmpty { return candidates }
        }
        return candidates
    }

    func write(_ value: String, account: String) throws {
        try backend.write(value, account: account, service: service)
    }

    func delete(account: String) throws {
        try backend.delete(account: account, service: service)
    }

    func readQuery(service: Service? = nil) -> [String: Any] {
        var query = baseQuery(service: service ?? self.service)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        return query
    }

    func mutationQuery(account: String, service: Service? = nil) -> [String: Any] {
        var query = baseQuery(service: service ?? self.service)
        query[kSecAttrAccount as String] = account
        return query
    }

    private func baseQuery(service: Service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.name,
        ]
    }
}

struct SecurityKeychainBackend: SecureStoreBackend {
    func readItems(service: SecureStore.Service) throws -> [String: String] {
        let query = SecureStore(service: service).readQuery()
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else { throw SecureStoreError.statusError(status) }
        guard let itemDictionaries = result as? [[String: Any]] else { throw SecureStoreError.invalidStoredValue }
        var items: [String: String] = [:]
        for itemDictionary in itemDictionaries {
            guard
                let account = itemDictionary[kSecAttrAccount as String] as? String,
                let data = itemDictionary[kSecValueData as String] as? Data,
                let value = String(data: data, encoding: .utf8)
            else { throw SecureStoreError.invalidStoredValue }
            items[account] = value
        }
        return items
    }

    func write(_ value: String, account: String, service: SecureStore.Service) throws {
        let query = SecureStore(service: service).mutationQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw SecureStoreError.statusError(updateStatus) }
        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let duplicateUpdateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard duplicateUpdateStatus == errSecSuccess else { throw SecureStoreError.statusError(duplicateUpdateStatus) }
            return
        }
        guard addStatus == errSecSuccess else { throw SecureStoreError.statusError(addStatus) }
    }

    func delete(account: String, service: SecureStore.Service) throws {
        let query = SecureStore(service: service).mutationQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStoreError.statusError(status) }
    }
}
