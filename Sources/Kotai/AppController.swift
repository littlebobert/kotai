import AppKit
import AsyncHTTPClient
import Foundation
import Hummingbird
import NIOPosix
import Observation

@MainActor
@Observable
final class AppController {
    enum RuntimeStatus: Equatable {
        case needsConfiguration
        case starting
        case running
        case failed(String)

        var displayName: String {
            switch self {
            case .needsConfiguration:
                String(localized: "Setup required")
            case .starting:
                String(localized: "Starting")
            case .running:
                String(localized: "Connected")
            case .failed:
                String(localized: "Connection failed")
            }
        }

        var symbolName: String {
            switch self {
            case .needsConfiguration:
                "exclamationmark.triangle"
            case .starting:
                "arrow.trianglehead.2.clockwise.rotate.90"
            case .running:
                "checkmark.circle"
            case .failed:
                "xmark.octagon"
            }
        }
    }

    enum CredentialAvailability: Equatable {
        case complete
        case missing
        case inaccessible(String)

        var requiresSetup: Bool {
            self == .missing
        }
    }

    private static let proxyPort = 18_742

    let autoUpdates = AutoUpdateService()

    private let configuration: ProxyConfiguration
    private let ngrokManager = NgrokManager()
    private let openRouterManagementClient = OpenRouterManagementClient()
    private let openAIAdministrationClient = OpenAIAdministrationClient()
    private let managedAccountProvisioner = ManagedAccountProvisioner()
    private let httpClient: HTTPClient
    private var proxyTask: Task<Void, Never>?
    private var ngrokProcess: Process?

    private(set) var runtimeStatus: RuntimeStatus = .starting
    private(set) var isSetupRequired = false
    private(set) var shouldShowSetupWizard = false

    init() {
        NSApplication.shared.applicationIconImage = KotaiIcon.image
        self.configuration = ProxyConfiguration()
        var httpClientConfiguration = HTTPClient.Configuration()
        httpClientConfiguration.httpVersion = .http1Only
        self.httpClient = HTTPClient(
            eventLoopGroup: MultiThreadedEventLoopGroup.singleton,
            configuration: httpClientConfiguration
        )
        KotaiLogger.shared.info(
            "App initialized; upstreamHTTP=http1; networkBackend=nio-posix"
        )
    }


    var statusDetail: String? {
        if case .failed(let message) = runtimeStatus {
            return message
        }
        return nil
    }

    func start() {
        KotaiLogger.shared.info("App starting")
        autoUpdates.start()
        startProxy()
        Task {
            await refreshRuntime()
        }
    }

    func beginSetupWizard() {
        KotaiLogger.shared.info("Setup wizard requested")
        shouldShowSetupWizard = true
    }

    func completeSetupWizard() {
        shouldShowSetupWizard = false
    }

    static let successfulSetupRuntimeStatus = RuntimeStatus.running

    func recordSuccessfulSetup() {
        isSetupRequired = false
        runtimeStatus = Self.successfulSetupRuntimeStatus
    }


    func managedConnection(for mode: AccountMode) async throws -> ManagedAccountConnection? {
        try await configuration.managedConnection(for: mode)
    }

    func managedCredentialsAvailable(for mode: AccountMode) async throws -> Bool {
        try await configuration.managedCredentials(for: mode) != nil
    }

    func openRouterWorkspaces(managementKey: String) async throws -> [OpenRouterWorkspace] {
        try await openRouterManagementClient.listWorkspaces(managementKey: managementKey)
    }

    func createOpenRouterWorkspace(name: String, managementKey: String) async throws -> OpenRouterWorkspace {
        try await openRouterManagementClient.createWorkspace(name: name, managementKey: managementKey)
    }

    func openAIProjects(adminKey: String) async throws -> [OpenAIProject] {
        try await openAIAdministrationClient.listProjects(adminKey: adminKey)
    }

    func stageManagedAccount(_ draft: ManagedAccountDraft) async throws -> StagedManagedAccount {
        try await managedAccountProvisioner.provision(draft)
    }

    func commitManagedAccounts(_ accounts: [StagedManagedAccount]) async throws {
        do {
            try await configuration.commitManagedAccounts(accounts)
        } catch {
            for account in accounts { await managedAccountProvisioner.cleanup(account) }
            throw error
        }
    }

    func discardManagedAccounts(_ accounts: [StagedManagedAccount]) async {
        for account in accounts { await managedAccountProvisioner.cleanup(account) }
    }

    func managedUsage(for mode: AccountMode, days: Int) async throws -> (connection: ManagedAccountConnection, credits: OpenRouterCredits, usage: WorkspaceUsage, openAICost: Double?) {
        let account = mode == .personal ? "personal" : "work"
        KotaiLogger.shared.info(
            "Usage refresh started; account=\(account) days=\(days)"
        )
        do {
            guard let connection = try await configuration.managedConnection(for: mode),
                  let credentials = try await configuration.managedCredentials(for: mode)
            else {
                throw AdministrationAPIError.forbidden("This setup is not managed yet.")
            }
            async let credits = openRouterManagementClient.credits(managementKey: credentials.managementKey)
            async let usage = openRouterManagementClient.workspaceUsage(
                workspaceID: connection.openRouterWorkspace.id,
                managementKey: credentials.managementKey,
                days: days
            )
            async let openAICost: Double? = {
                guard let projectID = connection.openAIProject?.id,
                      let adminKey = credentials.adminKey,
                      !adminKey.isEmpty else { return nil }
                return try? await openAIAdministrationClient.projectCosts(
                    projectID: projectID,
                    adminKey: adminKey,
                    days: days
                )
            }()
            let result = try await (connection, credits, usage, openAICost)
            KotaiLogger.shared.info(
                "Usage refresh completed; account=\(account) days=\(days) "
                    + "dailyRows=\(result.2.daily.count) modelRows=\(result.2.models.count)"
            )
            return result
        } catch {
            KotaiLogger.shared.error(
                "Usage refresh failed; account=\(account) days=\(days) "
                    + "error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func requiresManagedSetupUpgrade() async -> Bool {
        do {
            let personalKey = try await loadCredential(.personalOpenRouterKey)
            let workKey = try await loadCredential(.workOpenRouterKey)
            let personalConnection = try await configuration.managedConnection(for: .personal)
            let workConnection = try await configuration.managedConnection(for: .work)
            let hasLegacyKeys = !personalKey.isEmpty && !workKey.isEmpty
            let hasManagedAccounts = personalConnection != nil && workConnection != nil
            return hasLegacyKeys && !hasManagedAccounts
        } catch {
            return false
        }
    }

    func loadCredential(
        _ credential: ProxyConfiguration.Credential
    ) async throws -> String {
        try await configuration.credential(credential) ?? ""
    }

    func saveSetupCredentials(
        personalOpenRouterKey: String,
        workOpenRouterKey: String,
        proxyToken: String,
        ngrokAuthtoken: String,
        ngrokStaticURL: String
    ) async throws {
        KotaiLogger.shared.info("Saving verified setup credentials")
        try await configuration.setCredentials([
            .personalOpenRouterKey: personalOpenRouterKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            .workOpenRouterKey: workOpenRouterKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            .proxyToken: proxyToken.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            .ngrokAuthtoken: ngrokAuthtoken.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            .ngrokStaticURL: ngrokStaticURL.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
        ])
    }

    static func credentialAvailability(
        values: [String?],
        error: Error? = nil
    ) -> CredentialAvailability {
        if let error {
            return .inaccessible(error.localizedDescription)
        }
        return values.allSatisfy { !($0 ?? "").isEmpty } ? .complete : .missing
    }

    func updateCredential(
        _ credential: ProxyConfiguration.Credential,
        value: String
    ) async throws -> String {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try await configuration.setCredential(normalizedValue, for: credential)
        return normalizedValue
    }

    func regenerateAndPersistProxyToken() async throws -> String {
        let proxyToken = generateProxyToken()
        try await configuration.setCredential(proxyToken, for: .proxyToken)
        return proxyToken
    }

    func hasCompleteSettingsCredentials() async throws -> Bool {
        let requiredCredentials = try await [
            configuration.credential(.ngrokAuthtoken),
            configuration.credential(.personalOpenRouterKey),
            configuration.credential(.workOpenRouterKey),
            configuration.credential(.proxyToken),
        ]
        return requiredCredentials.allSatisfy { !($0 ?? "").isEmpty }
    }

    func restartWithStaticURL(_ staticURL: String) async throws -> URL {
        let normalizedStaticURL = try NgrokStaticURL(staticURL)
        guard let ngrokAuthtoken = try await configuration.credential(.ngrokAuthtoken),
              !ngrokAuthtoken.isEmpty
        else {
            throw NgrokError.invalidAuthtoken
        }

        runtimeStatus = .starting
        do {
            let publicURL = try await restartNgrok(
                authtoken: ngrokAuthtoken,
                staticURL: normalizedStaticURL.absoluteString,
                progress: { _ in }
            )
            try await configuration.setCredential(
                normalizedStaticURL.absoluteString,
                for: .ngrokStaticURL
            )
            UserDefaults.standard.set(
                normalizedStaticURL.absoluteString,
                forKey: "ngrok-public-url"
            )
            runtimeStatus = .running
            return publicURL
        } catch {
            runtimeStatus = .failed(error.localizedDescription)
            throw error
        }
    }

    func setupNgrok(
        authtoken: String,
        staticURL: String? = nil,
        progress: @MainActor @escaping (NgrokSetupPhase) -> Void
    ) async throws -> (publicURL: URL, proxyToken: String) {
        KotaiLogger.shared.info("ngrok setup started")
        let normalizedStaticURL = try NgrokStaticURL(
            staticURL ?? legacyConfiguredPublicURL()?.absoluteString ?? ""
        )
        let normalizedAuthtoken = authtoken.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let proxyToken = try await setupProxyToken()
        let publicURL = try await restartNgrok(
            authtoken: normalizedAuthtoken,
            staticURL: normalizedStaticURL.absoluteString,
            progress: progress
        )
        KotaiLogger.shared.info(
            "ngrok endpoint verified; host=\(normalizedStaticURL.host)"
        )
        return (publicURL, proxyToken)
    }

    func confirmedStaticURL() async throws -> URL? {
        let selection = StaticURLSelection(
            confirmedValue: try await configuration.credential(.ngrokStaticURL),
            legacyValue: nil
        )
        return selection.confirmedURL
    }

    func setupStaticURLSuggestion() async throws -> URL? {
        let selection = StaticURLSelection(
            confirmedValue: try await configuration.credential(.ngrokStaticURL),
            legacyValue: legacyConfiguredPublicURL()?.absoluteString
        )
        return selection.setupSuggestionURL
    }

    func configuredPublicURL() -> URL? {
        legacyConfiguredPublicURL()
    }

    private func legacyConfiguredPublicURL() -> URL? {
        guard
            let storedURL = UserDefaults.standard.string(forKey: "ngrok-public-url"),
            let normalizedStaticURL = try? NgrokStaticURL(storedURL)
        else {
            return nil
        }
        return normalizedStaticURL.url
    }

    func generateProxyToken() -> String {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            randomBytes.count,
            &randomBytes
        )

        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private func setupProxyToken() async throws -> String {
        if let existingToken = try await configuration.credential(.proxyToken),
           !existingToken.isEmpty
        {
            return existingToken
        }

        return generateProxyToken()
    }

    func quit() {
        KotaiLogger.shared.info("App quitting")
        ngrokProcess?.terminate()
        ngrokProcess = nil
        proxyTask?.cancel()
        proxyTask = nil
        NSApplication.shared.terminate(nil)
    }

    private func startProxy() {
        guard proxyTask == nil else {
            return
        }
        KotaiLogger.shared.info(
            "Starting local proxy on 127.0.0.1:\(Self.proxyPort)"
        )

        let responder = OpenRouterProxy(
            configuration: configuration,
            httpClient: httpClient
        )
        let application = Application(
            responder: responder,
            configuration: .init(
                address: .hostname("127.0.0.1", port: Self.proxyPort),
                serverName: "Kotai"
            )
        )

        proxyTask = Task {
            do {
                try await application.run()
            } catch is CancellationError {
                KotaiLogger.shared.info("Local proxy stopped")
                return
            } catch {
                KotaiLogger.shared.error(
                    "Local proxy failed: \(error.localizedDescription)"
                )
                runtimeStatus = .failed(
                    String(
                        localized: "Local proxy: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    private func refreshRuntime() async {
        KotaiLogger.shared.info("Refreshing runtime")
        ngrokProcess?.terminate()
        ngrokProcess = nil

        do {
            let requiredCredentials = try await [
                configuration.credential(.ngrokAuthtoken),
                configuration.credential(.ngrokStaticURL),
                configuration.credential(.personalOpenRouterKey),
                configuration.credential(.workOpenRouterKey),
                configuration.credential(.proxyToken),
            ]
            guard Self.credentialAvailability(values: requiredCredentials) == .complete,
                  let rawNgrokAuthtoken = requiredCredentials[0],
                  let ngrokStaticURL = requiredCredentials[1],
                  let ngrokAuthtoken = try? NgrokAuthtoken(rawNgrokAuthtoken)
            else {
                KotaiLogger.shared.warning(
                    "Runtime needs configuration; one or more credentials are missing or invalid"
                )
                isSetupRequired = true
                shouldShowSetupWizard = true
                runtimeStatus = .needsConfiguration
                return
            }

            isSetupRequired = false
            runtimeStatus = .starting
            _ = try await restartNgrok(
                authtoken: ngrokAuthtoken.value,
                staticURL: ngrokStaticURL,
                progress: { _ in }
            )
            runtimeStatus = .running
            KotaiLogger.shared.info("Runtime connected")
        } catch NgrokError.invalidAuthtoken {
            KotaiLogger.shared.warning("Runtime needs configuration; the saved ngrok authtoken is invalid")
            isSetupRequired = true
            shouldShowSetupWizard = true
            runtimeStatus = .needsConfiguration
        } catch {
            let availability = Self.credentialAvailability(values: [], error: error)
            KotaiLogger.shared.error(
                "Runtime refresh failed: \(error.localizedDescription)"
            )
            isSetupRequired = availability.requiresSetup
            shouldShowSetupWizard = false
            if case .inaccessible(let message) = availability {
                runtimeStatus = .failed(message)
            } else {
                runtimeStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func restartNgrok(
        authtoken: String,
        staticURL: String,
        progress: @MainActor @escaping (NgrokSetupPhase) -> Void
    ) async throws -> URL {
        KotaiLogger.shared.info("Restarting ngrok")
        ngrokProcess?.terminate()
        ngrokProcess = nil

        let endpoint = try await ngrokManager.start(
            authtoken: authtoken,
            staticURL: staticURL,
            progress: progress
        )
        endpoint.process.terminationHandler = { [weak self] process in
            guard process.terminationStatus != 0 else {
                return
            }
            Task { @MainActor [weak self] in
                guard self?.ngrokProcess === process else {
                    return
                }
                KotaiLogger.shared.error(
                    "ngrok exited with status \(process.terminationStatus)"
                )
                self?.runtimeStatus = .failed(
                    String(
                        localized: "ngrok stopped with status \(process.terminationStatus)."
                    )
                )
            }
        }

        ngrokProcess = endpoint.process
        UserDefaults.standard.set(
            endpoint.publicURL.absoluteString,
            forKey: "ngrok-public-url"
        )
        KotaiLogger.shared.info(
            "ngrok endpoint ready; host=\(endpoint.publicURL.host ?? "unknown")"
        )
        return endpoint.publicURL
    }
}
