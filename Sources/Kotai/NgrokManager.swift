import Foundation

struct NgrokStaticURL: Equatable, Sendable {
    let url: URL

    var absoluteString: String {
        url.absoluteString
    }

    var host: String {
        url.host ?? ""
    }

    init(_ rawValue: String) throws {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmedValue),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else {
            throw NgrokError.invalidStaticURL
        }

        components.scheme = "https"
        components.host = host.lowercased()
        components.path = ""
        guard let canonicalURL = components.url else {
            throw NgrokError.invalidStaticURL
        }
        self.url = canonicalURL
    }
}

enum NgrokSetupPhase: Sendable {
    case starting
    case discoveringEndpoint

    var displayName: String {
        switch self {
        case .starting:
            String(localized: "Starting ngrok…")
        case .discoveringEndpoint:
            String(localized: "Discovering your static ngrok URL…")
        }
    }
}

struct NgrokEndpoint: Sendable {
    let publicURL: URL
    let process: Process
}

enum NgrokError: LocalizedError, Equatable {
    case agentExited(String)
    case configuredEndpointMismatch
    case invalidAuthtoken
    case invalidStaticURL
    case noHTTPSEndpoint
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .agentExited(let output):
            output.isEmpty
                ? String(localized: "ngrok stopped before creating an endpoint.")
                : String(localized: "ngrok could not start: \(output)")
        case .configuredEndpointMismatch:
            String(localized: "ngrok started with a different endpoint than the configured static URL.")
        case .invalidAuthtoken:
            String(localized: "Paste the authtoken from your ngrok dashboard.")
        case .invalidStaticURL:
            String(localized: "Enter a valid HTTPS ngrok static URL without a path, query, or fragment.")
        case .noHTTPSEndpoint:
            String(localized: "ngrok started, but Kotai could not discover its HTTPS endpoint.")
        case .notInstalled:
            String(localized: "Install ngrok with `brew install ngrok`, then try again.")
        }
    }
}

@MainActor
struct NgrokManager {
    private static let inspectionAPIURL = URL(string: "http://127.0.0.1:4041/api/tunnels")!
    private static let proxyAddress = "http://127.0.0.1:18742"
    private static let configurationURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kotai", isDirectory: true)
            .appendingPathComponent("ngrok.yml")
    }()

    static func arguments(staticURL: NgrokStaticURL) -> [String] {
        [
            "http",
            Self.proxyAddress,
            "--url",
            staticURL.absoluteString,
            "--config",
            Self.configurationURL.path,
            "--name",
            "kotai",
            "--log",
            "stdout",
            "--log-format",
            "json",
        ]
    }

    static func verifiedPublicURL(
        discoveredURL rawDiscoveredURL: String,
        configuredURL: NgrokStaticURL
    ) throws -> URL {
        let discoveredURL = try NgrokStaticURL(rawDiscoveredURL)
        guard discoveredURL == configuredURL else {
            throw NgrokError.configuredEndpointMismatch
        }
        return configuredURL.url
    }

    func start(
        authtoken rawAuthtoken: String,
        staticURL rawStaticURL: String,
        progress: @MainActor @escaping (NgrokSetupPhase) -> Void
    ) async throws -> NgrokEndpoint {
        let authtoken = rawAuthtoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authtoken.isEmpty else {
            throw NgrokError.invalidAuthtoken
        }
        let staticURL = try NgrokStaticURL(rawStaticURL)

        progress(.starting)
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = try executableURL()
        try writeConfiguration()
        process.arguments = Self.arguments(staticURL: staticURL)
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["NGROK_AUTHTOKEN": authtoken]
        ) { _, kotaiValue in
            kotaiValue
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        progress(.discoveringEndpoint)

        do {
            let publicURL = try await discoverPublicURL(
                for: process,
                configuredURL: staticURL
            )
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
            return NgrokEndpoint(publicURL: publicURL, process: process)
        } catch {
            process.terminate()
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if case NgrokError.configuredEndpointMismatch = error {
                throw NgrokError.configuredEndpointMismatch
            }
            if !process.isRunning {
                throw NgrokError.agentExited(outputText)
            }
            throw error
        }
    }

    func executableURL() throws -> URL {
        let executableURL = [
            "/opt/homebrew/bin/ngrok",
            "/usr/local/bin/ngrok",
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }

        guard let executableURL else {
            throw NgrokError.notInstalled
        }
        return executableURL
    }

    private func writeConfiguration() throws {
        let directoryURL = Self.configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let configuration = """
        version: 3
        agent:
          web_addr: 127.0.0.1:4041
          update_check: false
        """
        try configuration.write(
            to: Self.configurationURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private func discoverPublicURL(
        for process: Process,
        configuredURL: NgrokStaticURL
    ) async throws -> URL {
        for _ in 0..<40 {
            guard process.isRunning else {
                throw NgrokError.agentExited("")
            }

            do {
                let publicURL = try await fetchPublicURL(configuredURL: configuredURL)
                return publicURL
            } catch NgrokError.configuredEndpointMismatch {
                throw NgrokError.configuredEndpointMismatch
            } catch {
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        throw NgrokError.noHTTPSEndpoint
    }

    private func fetchPublicURL(configuredURL: NgrokStaticURL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: Self.inspectionAPIURL)
        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw NgrokError.noHTTPSEndpoint
        }

        let tunnelList = try JSONDecoder().decode(NgrokTunnelList.self, from: data)
        guard let publicURLString = tunnelList.tunnels
            .first(where: { $0.proto == "https" })?
            .publicURL
        else {
            throw NgrokError.noHTTPSEndpoint
        }

        return try Self.verifiedPublicURL(
            discoveredURL: publicURLString,
            configuredURL: configuredURL
        )
    }
}

private struct NgrokTunnelList: Decodable {
    let tunnels: [NgrokTunnel]
}

private struct NgrokTunnel: Decodable {
    let proto: String
    let publicURL: String

    private enum CodingKeys: String, CodingKey {
        case proto
        case publicURL = "public_url"
    }
}
