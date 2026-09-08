import Foundation

actor ProxyConfiguration {
    enum Credential: CaseIterable {
        case ngrokAuthtoken
        case ngrokStaticURL
        case personalOpenRouterKey
        case personalOpenRouterManagementKey
        case personalOpenAIAdminKey
        case personalManagedConnection
        case proxyToken
        case workOpenRouterKey
        case workOpenRouterManagementKey
        case workOpenAIAdminKey
        case workManagedConnection

        var rawValue: String {
            storageAccount.name
        }

        init?(rawValue: String) {
            guard
                let credential = Self.allCases.first(where: {
                    $0.rawValue == rawValue
                })
            else {
                return nil
            }
            self = credential
        }

        private var storageAccount: SecureStore.Account {
            switch self {
            case .ngrokAuthtoken: .ngrokAuthtoken
            case .ngrokStaticURL: .ngrokStaticURL
            case .personalOpenRouterKey: .personalOpenRouterKey
            case .personalOpenRouterManagementKey: .personalOpenRouterManagementKey
            case .personalOpenAIAdminKey: .personalOpenAIAdminKey
            case .personalManagedConnection: .personalManagedConnection
            case .proxyToken: .proxyToken
            case .workOpenRouterKey: .workOpenRouterKey
            case .workOpenRouterManagementKey: .workOpenRouterManagementKey
            case .workOpenAIAdminKey: .workOpenAIAdminKey
            case .workManagedConnection: .workManagedConnection
            }
        }
    }

    private let secureStore: SecureStore
    private var credentialCache: [Credential: String]?

    init(
        secureStore: SecureStore = SecureStore(),
        initialCredentials: [Credential: String]? = nil
    ) {
        self.secureStore = secureStore
        self.credentialCache = initialCredentials
        if let initialCredentials {
            for value in initialCredentials.values {
                KotaiLogger.shared.registerSensitiveValue(value)
            }
        }
    }

    func credential(_ credential: Credential) throws -> String? {
        try loadCredentialVault()[credential]
    }

    func setCredential(_ value: String, for credential: Credential) throws {
        try setCredentials([credential: value])
    }

    func setCredentials(_ updatedCredentials: [Credential: String]) throws {
        for value in updatedCredentials.values {
            KotaiLogger.shared.registerSensitiveValue(value)
        }
        var credentials = try loadCredentialVault()
        credentials.merge(updatedCredentials) { _, newValue in newValue }
        try saveCredentialVault(credentials)
        credentialCache = credentials
    }

    func openRouterKey(for accountMode: AccountMode) throws -> String? {
        switch accountMode {
        case .personal:
            try credential(.personalOpenRouterKey)
        case .work:
            try credential(.workOpenRouterKey)
        }
    }


    func managedConnection(for accountMode: AccountMode) throws -> ManagedAccountConnection? {
        let credential: Credential = accountMode == .personal
            ? .personalManagedConnection
            : .workManagedConnection
        guard let value = try self.credential(credential),
              let data = value.data(using: .utf8)
        else { return nil }
        return try JSONDecoder().decode(ManagedAccountConnection.self, from: data)
    }

    func managedCredentials(for accountMode: AccountMode) throws -> (managementKey: String, adminKey: String?)? {
        let management: Credential = accountMode == .personal ? .personalOpenRouterManagementKey : .workOpenRouterManagementKey
        let admin: Credential = accountMode == .personal ? .personalOpenAIAdminKey : .workOpenAIAdminKey
        guard let managementKey = try credential(management), !managementKey.isEmpty else { return nil }
        let adminKey = try credential(admin)
        return (managementKey, adminKey?.isEmpty == true ? nil : adminKey)
    }

    func commitManagedAccounts(_ accounts: [StagedManagedAccount]) throws {
        var values: [Credential: String] = [:]
        for stagedAccount in accounts {
            let metadata = try JSONEncoder().encode(stagedAccount.connection)
            guard let metadataString = String(data: metadata, encoding: .utf8) else {
                throw SecureStoreError.invalidStoredValue
            }
            switch stagedAccount.draft.accountMode {
            case .personal:
                values[.personalOpenRouterKey] = stagedAccount.inferenceKey
                values[.personalOpenRouterManagementKey] = stagedAccount.draft.openRouterManagementKey
                values[.personalOpenAIAdminKey] = stagedAccount.draft.openAIAdminKey ?? ""
                values[.personalManagedConnection] = metadataString
            case .work:
                values[.workOpenRouterKey] = stagedAccount.inferenceKey
                values[.workOpenRouterManagementKey] = stagedAccount.draft.openRouterManagementKey
                values[.workOpenAIAdminKey] = stagedAccount.draft.openAIAdminKey ?? ""
                values[.workManagedConnection] = metadataString
            }
        }
        try setCredentials(values)
    }

    private func loadCredentialVault() throws -> [Credential: String] {
        if let credentialCache {
            return credentialCache
        }

        let candidates = try secureStore.readAllCandidates()
        guard candidates.contains(where: { !$0.items.isEmpty }) else {
            credentialCache = [:]
            return [:]
        }

        var credentials: [Credential: String] = [:]
        for candidate in candidates.reversed() where !candidate.items.isEmpty {
            let candidateCredentials = try decodeCredentials(from: candidate.items)
            credentials.merge(candidateCredentials) { _, newerValue in newerValue }
        }

        if candidates.first?.items.isEmpty == true {
            try saveCredentialVault(credentials)
        }

        registerSensitiveValues(in: credentials)
        credentialCache = credentials
        return credentials
    }

    private func decodeCredentials(
        from items: [String: String]
    ) throws -> [Credential: String] {
        if let storedVault = items[SecureStore.Account.vault.name] {
            let data = Data(storedVault.utf8)
            let storedCredentials = try JSONDecoder().decode(
                [String: String].self,
                from: data
            )
            return Dictionary(
                uniqueKeysWithValues: storedCredentials.compactMap { key, value in
                    Credential(rawValue: key).map { ($0, value) }
                }
            )
        }

        return Dictionary(
            uniqueKeysWithValues: Credential.allCases.compactMap { credential in
                items[credential.rawValue].map { (credential, $0) }
            }
        )
    }

    private func registerSensitiveValues(
        in credentials: [Credential: String]
    ) {
        for value in credentials.values {
            KotaiLogger.shared.registerSensitiveValue(value)
        }
    }

    private func saveCredentialVault(
        _ credentials: [Credential: String]
    ) throws {
        let storedCredentials = Dictionary(
            uniqueKeysWithValues: credentials.map {
                ($0.key.rawValue, $0.value)
            }
        )
        let data = try JSONEncoder().encode(storedCredentials)
        guard let value = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.invalidStoredValue
        }
        try secureStore.write(
            value,
            account: SecureStore.Account.vault.name
        )
    }
}
