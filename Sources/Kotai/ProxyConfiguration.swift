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

    private(set) var accountMode: AccountMode
    private let secureStore: SecureStore
    private var credentialCache: [Credential: String]?

    init(
        accountMode: AccountMode = .personal,
        secureStore: SecureStore = SecureStore(),
        initialCredentials: [Credential: String]? = nil
    ) {
        self.accountMode = accountMode
        self.secureStore = secureStore
        self.credentialCache = initialCredentials
        if let initialCredentials {
            for value in initialCredentials.values {
                KotaiLogger.shared.registerSensitiveValue(value)
            }
        }
    }

    func setAccountMode(_ accountMode: AccountMode) {
        self.accountMode = accountMode
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

        if let storedVault = try secureStore.read(account: Self.vaultAccount) {
            let data = Data(storedVault.utf8)
            let storedCredentials = try JSONDecoder().decode(
                [String: String].self,
                from: data
            )
            let credentials = Dictionary(
                uniqueKeysWithValues: storedCredentials.compactMap {
                    key,
                    value in
                    Credential(rawValue: key).map { ($0, value) }
                }
            )
            registerSensitiveValues(in: credentials)
            credentialCache = credentials
            return credentials
        }

        var credentials: [Credential: String] = [:]
        for credential in Credential.allCases {
            credentials[credential] = try secureStore.read(
                account: credential.rawValue
            )
        }

        if !credentials.isEmpty {
            try saveCredentialVault(credentials)
            for credential in Credential.allCases {
                try secureStore.delete(account: credential.rawValue)
            }
        }

        registerSensitiveValues(in: credentials)
        credentialCache = credentials
        return credentials
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
