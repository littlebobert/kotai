import Foundation

actor ProxyConfiguration {
    enum Credential: String {
        case ngrokAuthtoken = "ngrok-authtoken"
        case personalOpenRouterKey = "personal-openrouter-key"
        case proxyToken = "proxy-token"
        case workOpenRouterKey = "work-openrouter-key"
    }

    private(set) var accountMode: AccountMode
    private let secureStore: SecureStore

    init(
        accountMode: AccountMode = .personal,
        secureStore: SecureStore = SecureStore()
    ) {
        self.accountMode = accountMode
        self.secureStore = secureStore
    }

    func setAccountMode(_ accountMode: AccountMode) {
        self.accountMode = accountMode
    }

    func credential(_ credential: Credential) throws -> String? {
        try secureStore.read(account: credential.rawValue)
    }

    func setCredential(_ value: String, for credential: Credential) throws {
        try secureStore.write(value, account: credential.rawValue)
    }

    func activeOpenRouterKey() throws -> String? {
        switch accountMode {
        case .personal:
            try credential(.personalOpenRouterKey)
        case .work:
            try credential(.workOpenRouterKey)
        }
    }
}
