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

    private static let proxyPort = 18_742
    private static var hasInstalledApplicationIcon = false

    let autoUpdates = AutoUpdateService()

    private let configuration: ProxyConfiguration
    private let ngrokManager = NgrokManager()
    private let httpClient: HTTPClient
    private var proxyTask: Task<Void, Never>?
    private var ngrokProcess: Process?

    private(set) var accountMode: AccountMode
    private(set) var runtimeStatus: RuntimeStatus = .starting
    private(set) var isSetupRequired = false
    private(set) var shouldShowSetupWizard = false

    init() {
        Self.installApplicationIcon()

        let storedMode = UserDefaults.standard.string(forKey: "account-mode")
            .flatMap(AccountMode.init(rawValue:))
            ?? .personal
        let configuration = ProxyConfiguration(accountMode: storedMode)

        self.accountMode = storedMode
        self.configuration = configuration
        var httpClientConfiguration = HTTPClient.Configuration()
        httpClientConfiguration.httpVersion = .http1Only
        self.httpClient = HTTPClient(
            eventLoopGroup: MultiThreadedEventLoopGroup.singleton,
            configuration: httpClientConfiguration
        )
        KotaiLogger.shared.info(
            "App initialized; account=\(storedMode.rawValue); " +
                "upstreamHTTP=http1; networkBackend=nio-posix"
        )
    }

    private static func installApplicationIcon() {
        guard !hasInstalledApplicationIcon else {
            return
        }
        hasInstalledApplicationIcon = true

        let applicationIcon = NSImage(named: "KotaiIcon") ?? Bundle.main
            .url(forResource: "Kotai", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))

        guard let applicationIcon else {
            KotaiLogger.shared.warning("Packaged application icon could not be loaded")
            return
        }

        NSApplication.shared.applicationIconImage = applicationIcon
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

    func selectAccountMode(_ accountMode: AccountMode) {
        self.accountMode = accountMode
        UserDefaults.standard.set(accountMode.rawValue, forKey: "account-mode")
        KotaiLogger.shared.info(
            "Default account changed to \(accountMode.rawValue)"
        )

        Task {
            await configuration.setAccountMode(accountMode)
        }
    }

    func beginSetupWizard() {
        KotaiLogger.shared.info("Setup wizard requested")
        shouldShowSetupWizard = true
    }

    func completeSetupWizard() {
        shouldShowSetupWizard = false
    }

    func loadCredential(
        _ credential: ProxyConfiguration.Credential
    ) async throws -> String {
        try await configuration.credential(credential) ?? ""
    }

    func saveCredentials(
        personalOpenRouterKey: String,
        workOpenRouterKey: String,
        proxyToken: String
    ) async throws {
        KotaiLogger.shared.info("Saving credentials")
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
        ])
        await refreshRuntime()
    }

    func saveSettings(
        personalOpenRouterKey: String,
        workOpenRouterKey: String,
        proxyToken: String,
        staticURL: String
    ) async throws -> URL {
        KotaiLogger.shared.info("Saving settings")
        let normalizedStaticURL = try NgrokStaticURL(staticURL)
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
            .ngrokStaticURL: normalizedStaticURL.absoluteString,
        ])
        UserDefaults.standard.set(
            normalizedStaticURL.absoluteString,
            forKey: "ngrok-public-url"
        )
        await refreshRuntime()
        return normalizedStaticURL.url
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
        let proxyToken = try await ensureProxyToken()
        let publicURL = try await restartNgrok(
            authtoken: normalizedAuthtoken,
            staticURL: normalizedStaticURL.absoluteString,
            progress: progress
        )
        try await configuration.setCredentials([
            .ngrokAuthtoken: normalizedAuthtoken,
            .ngrokStaticURL: normalizedStaticURL.absoluteString,
        ])
        UserDefaults.standard.set(
            normalizedStaticURL.absoluteString,
            forKey: "ngrok-public-url"
        )
        KotaiLogger.shared.info(
            "ngrok setup completed; host=\(normalizedStaticURL.host)"
        )
        return (publicURL, proxyToken)
    }

    func configuredStaticURL() async throws -> URL? {
        if let storedStaticURL = try await configuration.credential(.ngrokStaticURL),
           let normalizedStaticURL = try? NgrokStaticURL(storedStaticURL)
        {
            return normalizedStaticURL.url
        }
        return legacyConfiguredPublicURL()
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

    private func ensureProxyToken() async throws -> String {
        if let existingToken = try await configuration.credential(.proxyToken),
           !existingToken.isEmpty
        {
            return existingToken
        }

        let proxyToken = generateProxyToken()
        try await configuration.setCredential(
            proxyToken,
            for: .proxyToken
        )
        return proxyToken
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
            guard requiredCredentials.allSatisfy({ !($0 ?? "").isEmpty }) else {
                KotaiLogger.shared.warning(
                    "Runtime needs configuration; one or more credentials are missing"
                )
                isSetupRequired = true
                shouldShowSetupWizard = true
                runtimeStatus = .needsConfiguration
                return
            }

            guard
                let ngrokAuthtoken = requiredCredentials[0],
                let ngrokStaticURL = requiredCredentials[1]
            else {
                isSetupRequired = true
                runtimeStatus = .needsConfiguration
                return
            }

            isSetupRequired = false
            runtimeStatus = .starting
            _ = try await restartNgrok(
                authtoken: ngrokAuthtoken,
                staticURL: ngrokStaticURL,
                progress: { _ in }
            )
            runtimeStatus = .running
            KotaiLogger.shared.info("Runtime connected")
        } catch {
            KotaiLogger.shared.error(
                "Runtime refresh failed: \(error.localizedDescription)"
            )
            runtimeStatus = .failed(error.localizedDescription)
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
