import Foundation

enum NgrokSetupPhase: String, Sendable {
    case starting = "Starting ngrok…"
    case discoveringEndpoint = "Discovering your static ngrok URL…"
}

struct NgrokEndpoint: Sendable {
    let publicURL: URL
    let process: Process
}

enum NgrokError: LocalizedError {
    case agentExited(String)
    case invalidAuthtoken
    case noHTTPSEndpoint
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .agentExited(let output):
            output.isEmpty
                ? "ngrok stopped before creating an endpoint."
                : "ngrok could not start: \(output)"
        case .invalidAuthtoken:
            "Paste the authtoken from your ngrok dashboard."
        case .noHTTPSEndpoint:
            "ngrok started, but Kotai could not discover its HTTPS endpoint."
        case .notInstalled:
            "Install ngrok with `brew install ngrok`, then try again."
        }
    }
}

@MainActor
struct NgrokManager {
    private static let inspectionAPIURL = URL(
        string: "http://127.0.0.1:4041/api/tunnels"
    )!
    private static let proxyAddress = "http://127.0.0.1:18742"

    func start(
        authtoken rawAuthtoken: String,
        progress: @MainActor @escaping (NgrokSetupPhase) -> Void
    ) async throws -> NgrokEndpoint {
        let authtoken = rawAuthtoken.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !authtoken.isEmpty else {
            throw NgrokError.invalidAuthtoken
        }

        progress(.starting)
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = try executableURL()
        process.arguments = [
            "http",
            Self.proxyAddress,
            "--name",
            "kotai",
            "--web-addr",
            "127.0.0.1:4041",
            "--log",
            "stdout",
            "--log-format",
            "json",
        ]
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
            let publicURL = try await discoverPublicURL(for: process)
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
            return NgrokEndpoint(publicURL: publicURL, process: process)
        } catch {
            process.terminate()
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

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

    private func discoverPublicURL(for process: Process) async throws -> URL {
        for _ in 0..<40 {
            guard process.isRunning else {
                throw NgrokError.agentExited("")
            }

            if let publicURL = try? await fetchPublicURL() {
                return publicURL
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        throw NgrokError.noHTTPSEndpoint
    }

    private func fetchPublicURL() async throws -> URL {
        let (data, response) = try await URLSession.shared.data(
            from: Self.inspectionAPIURL
        )
        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw NgrokError.noHTTPSEndpoint
        }

        let tunnelList = try JSONDecoder().decode(
            NgrokTunnelList.self,
            from: data
        )
        guard
            let publicURLString = tunnelList.tunnels
                .first(where: { $0.proto == "https" })?
                .publicURL,
            let publicURL = URL(string: publicURLString),
            publicURL.scheme == "https"
        else {
            throw NgrokError.noHTTPSEndpoint
        }

        return publicURL
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
