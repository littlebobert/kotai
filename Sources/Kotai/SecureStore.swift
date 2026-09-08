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
            String(
                format: String(localized: "Keychain error: %@ (status %lld)."),
                locale: .current,
                SecCopyErrorMessageString(status, nil) as String?
                    ?? String(localized: "Unknown Keychain error"),
                Int64(status)
            )
        }
    }
}

protocol SecureStoreBackend: Sendable {
    func readItems(
        accounts: [SecureStore.Account],
        service: SecureStore.Service
    ) throws -> [String: String]
    func write(_ value: String, account: String, service: SecureStore.Service) throws
    func delete(account: String, service: SecureStore.Service) throws
}

struct SecureStore: Sendable {
    struct Service: Equatable, Sendable {
        enum Role: String, Sendable {
            case production = "production-v3"
            case retainedRollback = "retained-v2"
            case priorLegacy = "prior-legacy"
            case custom
        }

        let name: String
        let role: Role

        init(name: String, role: Role = .custom) {
            self.name = name
            self.role = role
        }
    }

    struct Account: Equatable, Sendable {
        let name: String
        let role: String

        static let vault = Account(
            name: "credential-vault-v1",
            role: "credential-vault"
        )
        static let ngrokAuthtoken = Account(
            name: "ngrok-authtoken",
            role: "prior-ngrok-authtoken"
        )
        static let ngrokStaticURL = Account(
            name: "ngrok-static-url",
            role: "prior-ngrok-static-url"
        )
        static let personalOpenRouterKey = Account(
            name: "personal-openrouter-key",
            role: "prior-personal-openrouter-key"
        )
        static let personalOpenRouterManagementKey = Account(name: "personal-openrouter-management-key", role: "managed")
        static let personalOpenAIAdminKey = Account(name: "personal-openai-admin-key", role: "managed")
        static let personalManagedConnection = Account(name: "personal-managed-connection", role: "metadata")
        static let workOpenRouterManagementKey = Account(name: "work-openrouter-management-key", role: "managed")
        static let workOpenAIAdminKey = Account(name: "work-openai-admin-key", role: "managed")
        static let workManagedConnection = Account(name: "work-managed-connection", role: "metadata")
        static let proxyToken = Account(
            name: "proxy-token",
            role: "prior-proxy-token"
        )
        static let workOpenRouterKey = Account(
            name: "work-openrouter-key",
            role: "prior-work-openrouter-key"
        )
        static let priorCredentials = [
            ngrokAuthtoken,
            ngrokStaticURL,
            personalOpenRouterKey,
            proxyToken,
            workOpenRouterKey,
        ]
    }

    static let productionService = "com.justin.Kotai.credentials.v3"
    static let legacyVaultService = "com.justin.Kotai.credentials.v2"
    static let priorLegacyService = "com.kotai.credentials"
    static let production = Service(
        name: productionService,
        role: .production
    )
    static let migrationServices = [
        Service(name: legacyVaultService, role: .retainedRollback),
        Service(name: priorLegacyService, role: .priorLegacy),
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
        var candidates = [(service: service, items: try readItems(service: service))]
        if !candidates[0].items.isEmpty { return candidates }
        for legacyService in legacyServices {
            let items = try readItems(service: legacyService)
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

    func readQuery(
        account: Account,
        service: Service? = nil
    ) -> [String: Any] {
        var query = mutationQuery(
            account: account.name,
            service: service
        )
        query[kSecMatchLimit as String] = kSecMatchLimitOne
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

    private func readItems(service: Service) throws -> [String: String] {
        let vaultItems = try backend.readItems(
            accounts: [.vault],
            service: service
        )
        guard
            vaultItems.isEmpty,
            service.role == .priorLegacy
        else {
            return vaultItems
        }
        return try backend.readItems(
            accounts: Account.priorCredentials,
            service: service
        )
    }
}

struct SecurityKeychainBackend: SecureStoreBackend {
    func readItems(
        accounts: [SecureStore.Account],
        service: SecureStore.Service
    ) throws -> [String: String] {
        var items: [String: String] = [:]
        for account in accounts {
            let query = SecureStore(service: service).readQuery(account: account)
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { continue }
            guard status == errSecSuccess else {
                try throwStatus(
                    status,
                    operation: "read",
                    service: service,
                    accountRole: account.role
                )
            }
            guard
                let data = result as? Data,
                let value = String(data: data, encoding: .utf8)
            else {
                KotaiLogger.shared.error(
                    "Keychain read returned invalid data "
                        + "serviceRole=\(service.role.rawValue) "
                        + "accountRole=\(account.role) status=\(status)"
                )
                throw SecureStoreError.invalidStoredValue
            }
            items[account.name] = value
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
        guard updateStatus == errSecItemNotFound else {
            try throwStatus(
                updateStatus,
                operation: "update",
                service: service,
                accountRole: accountRole(for: account)
            )
        }
        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let duplicateUpdateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard duplicateUpdateStatus == errSecSuccess else {
                try throwStatus(
                    duplicateUpdateStatus,
                    operation: "duplicate-update",
                    service: service,
                    accountRole: accountRole(for: account)
                )
            }
            return
        }
        guard addStatus == errSecSuccess else {
            try throwStatus(
                addStatus,
                operation: "add",
                service: service,
                accountRole: accountRole(for: account)
            )
        }
    }

    func delete(account: String, service: SecureStore.Service) throws {
        let query = SecureStore(service: service).mutationQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            try throwStatus(
                status,
                operation: "delete",
                service: service,
                accountRole: accountRole(for: account)
            )
        }
    }

    private func accountRole(for account: String) -> String {
        if account == SecureStore.Account.vault.name {
            return SecureStore.Account.vault.role
        }
        return SecureStore.Account.priorCredentials.first {
            $0.name == account
        }?.role ?? "custom"
    }

    private func throwStatus(
        _ status: OSStatus,
        operation: String,
        service: SecureStore.Service,
        accountRole: String
    ) throws -> Never {
        KotaiLogger.shared.error(
            "Keychain \(operation) failed "
                + "serviceRole=\(service.role.rawValue) "
                + "accountRole=\(accountRole) status=\(status)"
        )
        throw SecureStoreError.statusError(status)
    }
}
