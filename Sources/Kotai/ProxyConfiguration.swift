import Foundation

actor ProxyConfiguration {
    enum Credential: String, CaseIterable {
        case ngrokAuthtoken = "ngrok-authtoken"
        case ngrokStaticURL = "ngrok-static-url"
        case personalOpenRouterKey = "personal-openrouter-key"
        case proxyToken = "proxy-token"
        case workOpenRouterKey = "work-openrouter-key"
    }

    private static let vaultAccount = "credential-vault-v1"

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

    private func loadCredentialVault() throws -> [Credential: String] {
        if let credentialCache {
            return credentialCache
        }

        let candidates = try secureStore.readAllCandidates()
        guard let storedCandidate = candidates.last, !storedCandidate.items.isEmpty else {
            credentialCache = [:]
            return [:]
        }

        let credentials = try decodeCredentials(from: storedCandidate.items)
        if storedCandidate.service != SecureStore.production {
            try saveCredentialVault(credentials)
        }

        registerSensitiveValues(in: credentials)
        credentialCache = credentials
        return credentials
    }

    private func decodeCredentials(
        from items: [String: String]
    ) throws -> [Credential: String] {
        if let storedVault = items[Self.vaultAccount] {
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
        try secureStore.write(value, account: Self.vaultAccount)
    }
}
