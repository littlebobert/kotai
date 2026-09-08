import AppKit
import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import SwiftUI
import Testing
@testable import Kotai

struct ProxyConfigurationTests {
    @Test
    func healthEndpointIsAvailableWithoutCredentials() async throws {
        let (application, httpClient) = makeApplication()

        try await application.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == #"{"status":"ok"}"#)
            }
        }
        try await httpClient.shutdown()
    }

    @Test
    func unknownEndpointIsNotExposed() async throws {
        let (application, httpClient) = makeApplication()

        try await application.test(.router) { client in
            try await client.execute(uri: "/mode", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
        try await httpClient.shutdown()
    }

    @Test
    func malformedPrefixedModelReturnsBadRequestBeforeUpstream() async throws {
        let (application, httpClient) = makeApplication(
            credentials: [.proxyToken: "test-proxy-token"]
        )
        let headers: HTTPFields = [
            .authorization: "Bearer test-proxy-token",
            .contentType: "application/json",
        ]
        let body = ByteBuffer(
            string: #"{"model":"kotai/unknown/openai/gpt-5"}"#
        )

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: headers,
                body: body
            ) { response in
                #expect(response.status == .badRequest)
                #expect(
                    String(buffer: response.body)
                        == #"{"error":"Malformed Kotai model routing"}"#
                )
            }
        }
        try await httpClient.shutdown()
    }

    @Test
    func unprefixedModelReturnsBadRequestWithGuidance() async throws {
        let (application, httpClient) = makeApplication(
            credentials: [.proxyToken: "test-proxy-token"]
        )
        let headers: HTTPFields = [
            .authorization: "Bearer test-proxy-token",
            .contentType: "application/json",
        ]
        let body = ByteBuffer(string: #"{"model":"openai/gpt-5"}"#)

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: headers,
                body: body
            ) { response in
                #expect(response.status == .badRequest)
                let responseObject = try JSONSerialization.jsonObject(
                    with: Data(response.body.readableBytesView)
                ) as? [String: String]
                #expect(
                    responseObject?["error"]
                        == "Prefix the model with kotai/personal/ or kotai/work/"
                )
            }
        }
        try await httpClient.shutdown()
    }

    @Test
    func missingRoutedAccountKeyReturnsServiceUnavailable() async throws {
        let (application, httpClient) = makeApplication(
            credentials: [
                .proxyToken: "test-proxy-token",
                .personalOpenRouterKey: "personal-test-key",
            ]
        )
        let headers: HTTPFields = [
            .authorization: "Bearer test-proxy-token",
            .contentType: "application/json",
        ]
        let body = ByteBuffer(
            string: #"{"model":"kotai/work/anthropic/claude"}"#
        )

        try await application.test(.router) { client in
            try await client.execute(
                uri: "/v1/chat/completions",
                method: .post,
                headers: headers,
                body: body
            ) { response in
                #expect(response.status == .serviceUnavailable)
                #expect(
                    String(buffer: response.body)
                        == #"{"error":"The work OpenRouter key is not configured"}"#
                )
            }
        }
        try await httpClient.shutdown()
    }

    @Test
    func cursorRouteUsesCursorSpecificOpenRouterEndpoint() {
        let upstreamURL = OpenRouterRoute.upstreamURL(
            path: "/cursor/v1/chat/completions",
            query: "trace=true"
        )

        #expect(
            upstreamURL?.absoluteString
                == "https://openrouter.ai/api/v1/cursor/chat/completions?trace=true"
        )
    }

    @Test
    func genericRouteUsesStandardOpenRouterEndpoint() {
        let upstreamURL = OpenRouterRoute.upstreamURL(
            path: "/v1/models",
            query: nil
        )

        #expect(
            upstreamURL?.absoluteString
                == "https://openrouter.ai/api/v1/models"
        )
    }

    @Test
    func lookalikeRoutePrefixIsRejected() {
        #expect(
            OpenRouterRoute.upstreamURL(
                path: "/v10/models",
                query: nil
            ) == nil
        )
    }


    @Test @MainActor
    func nativeLogViewerHandlesRapidShrinkingTextUpdates() {
        var followsLatestEntry = false
        let followsLatestEntryBinding = Binding(
            get: { followsLatestEntry },
            set: { followsLatestEntry = $0 }
        )
        let scrollView = NSScrollView()
        let textView = NSTextView()
        scrollView.documentView = textView
        let coordinator = NativeLogTextView.Coordinator(
            followsLatestEntry: followsLatestEntryBinding
        )
        coordinator.connect(scrollView: scrollView, textView: textView)
        defer { coordinator.disconnect() }

        coordinator.update(
            text: "a long diagnostic line with a selected suffix",
            followsLatestEntry: false,
            scrollToLatestRequest: 0
        )
        textView.setSelectedRange(NSRange(location: 36, length: 8))

        for text in ["warning", "w", "", "error"] {
            coordinator.update(
                text: text,
                followsLatestEntry: false,
                scrollToLatestRequest: 0
            )
            #expect(textView.string == text)
        }
    }

    @Test
    func diagnosticLogFilterIncludesSelectedLevelsAndUnclassifiedText() {
        let logText = """
        heading
        2026-01-01T00:00:00Z [INFO] connected
        2026-01-01T00:00:01Z [WARN] delayed
        2026-01-01T00:00:02Z [ERRO] stopped
        """

        let filteredText = DiagnosticLogFilter.filteredText(
            logText,
            selectedLevels: [.warning]
        )

        #expect(filteredText.contains("heading"))
        #expect(filteredText.contains("[WARN] delayed"))
        #expect(!filteredText.contains("[INFO] connected"))
        #expect(!filteredText.contains("[ERRO] stopped"))
    }

    @Test
    func diagnosticLogFilterMatchesTextCaseInsensitively() {
        let logText = """
        2026-01-01T00:00:00Z [INFO] Connected to OpenRouter
        2026-01-01T00:00:01Z [WARN] Slow response
        2026-01-01T00:00:02Z [ERRO] Connection stopped
        """

        let filteredText = DiagnosticLogFilter.filteredText(
            logText,
            selectedLevels: [.info, .warning],
            query: "CONnect"
        )

        #expect(filteredText.contains("[INFO] Connected"))
        #expect(!filteredText.contains("[WARN] Slow"))
        #expect(!filteredText.contains("[ERRO] Connection"))
    }

    @Test
    func diagnosticLogFilterReturnsOriginalTextWhenAllLevelsSelected() {
        let logText = "2026-01-01T00:00:00Z [DEBG] payload"

        #expect(
            DiagnosticLogFilter.filteredText(
                logText,
                selectedLevels: Set(DiagnosticLogLevel.allCases)
            ) == logText
        )
    }

    @Test
    func diagnosticLogLevelPrefixesUseFourCharacters() {
        let prefixes = KotaiLogger.Level.allCases.map(\.rawValue)

        #expect(prefixes == ["DEBG", "ERRO", "INFO", "WARN"])
        #expect(prefixes.allSatisfy { $0.count == 4 })
    }

    @Test
    func diagnosticRedactionRemovesCredentialsFromCommonLogFormats() {
        let secrets = [
            "sk-or-v1-openrouterSecret123",
            "proxy-client-secret-456",
            "ngrok-authtoken-789",
            "query-secret-012",
            "json-secret-345",
        ]
        let logText = """
        Authorization: Bearer \(secrets[0])
        proxy_token=\(secrets[1])
        authtoken=\(secrets[2])
        https://example.com/path?api_key=\(secrets[3])&mode=test
        {"apiKey":"\(secrets[4])","model":"test"}
        """

        let redactedText = KotaiLogger.redactingSensitivePatterns(in: logText)

        for secret in secrets {
            #expect(!redactedText.contains(secret))
        }
        #expect(redactedText.contains("Authorization: [REDACTED]"))
        #expect(redactedText.contains("proxy_token=[REDACTED]"))
        #expect(redactedText.contains("api_key=[REDACTED]"))
        #expect(redactedText.contains(#""apiKey":"[REDACTED]""#))
    }

    @Test
    func diagnosticRedactionPreservesNonSensitiveContext() {
        let logText = "Proxy request failed for model=anthropic/claude with status=401"

        let redactedText = KotaiLogger.redactingSensitivePatterns(in: logText)

        #expect(redactedText == logText)
    }

    private func makeApplication(
        credentials: [ProxyConfiguration.Credential: String]? = nil
    ) -> (
        application: Application<OpenRouterProxy>,
        httpClient: HTTPClient
    ) {
        let configuration = ProxyConfiguration(
            initialCredentials: credentials
        )
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let responder = OpenRouterProxy(
            configuration: configuration,
            httpClient: httpClient
        )

        return (Application(responder: responder), httpClient)
    }
}

struct ProxyConfigurationMigrationTests {
    @Test
    func legacyVaultMigratesAsOneCompleteWriteAndRemainsForRollback() async throws {
        let legacyVault = #"{"personal-openrouter-key":"personal","work-openrouter-key":"work","ngrok-authtoken":"ngrok","proxy-token":"proxy"}"#
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.legacyVaultService: ["credential-vault-v1": legacyVault],
        ])
        let configuration = ProxyConfiguration(secureStore: SecureStore(backend: backend))

        #expect(try await configuration.credential(.personalOpenRouterKey) == "personal")
        #expect(backend.writes.count == 1)
        #expect(backend.writes[0].account == "credential-vault-v1")
        #expect(backend.writes[0].serviceName == SecureStore.productionService)
        #expect(backend.deleteCount == 0)
        #expect(backend.items(serviceName: SecureStore.legacyVaultService)["credential-vault-v1"] == legacyVault)
        #expect(try await configuration.credential(.workOpenRouterKey) == "work")
        #expect(backend.reads.count == 2)
    }

    @Test
    func deniedLegacyAccessThrowsWithoutWritingOrDeleting() async {
        let denial = SecureStoreError.accessDenied(errSecUserCanceled)
        let backend = FakeSecureStoreBackend(readErrorByService: [
            SecureStore.legacyVaultService: denial,
        ])
        let configuration = ProxyConfiguration(secureStore: SecureStore(backend: backend))

        do {
            _ = try await configuration.credential(.proxyToken)
            Issue.record("Expected denied legacy access to throw")
        } catch let error as SecureStoreError {
            #expect(error == denial)
        } catch {
            Issue.record("Unexpected error: \\(error)")
        }
        #expect(backend.writes.isEmpty)
        #expect(backend.deleteCount == 0)
    }

    @Test
    func denialDuringHistoricalFallbackDoesNotWritePartialVault() async {
        let denial = SecureStoreError.accessDenied(errSecInteractionNotAllowed)
        let backend = FakeSecureStoreBackend(
            itemsByService: [
                SecureStore.priorLegacyService: [
                    "ngrok-authtoken": "ngrok",
                    "personal-openrouter-key": "personal",
                    "work-openrouter-key": "work",
                ],
            ],
            readErrorByServiceAndAccount: [
                SecureStore.priorLegacyService: ["proxy-token": denial],
            ]
        )
        let configuration = ProxyConfiguration(
            secureStore: SecureStore(backend: backend)
        )

        do {
            _ = try await configuration.credential(.personalOpenRouterKey)
            Issue.record("Expected denied historical access to throw")
        } catch let error as SecureStoreError {
            #expect(error == denial)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(backend.writes.isEmpty)
        #expect(backend.deleteCount == 0)
        #expect(
            backend.items(serviceName: SecureStore.productionService).isEmpty
        )
        #expect(
            backend.items(serviceName: SecureStore.priorLegacyService)[
                "personal-openrouter-key"
            ] == "personal"
        )
    }

    @Test
    func invalidLegacyVaultDoesNotPartiallyOverwriteCurrentVault() async {
        let invalidVault = #"{"personal-openrouter-key":1}"#
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.legacyVaultService: ["credential-vault-v1": invalidVault],
        ])
        let configuration = ProxyConfiguration(secureStore: SecureStore(backend: backend))

        await #expect(throws: DecodingError.self) {
            _ = try await configuration.credential(.personalOpenRouterKey)
        }
        #expect(backend.writes.isEmpty)
        #expect(backend.items(serviceName: SecureStore.productionService).isEmpty)
    }

    @Test
    func updatingMigratedCredentialsWritesCompleteVaultWithoutRequerying() async throws {
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.priorLegacyService: [
                "personal-openrouter-key": "personal",
                "work-openrouter-key": "work",
                "proxy-token": "old-proxy",
            ],
        ])
        let configuration = ProxyConfiguration(secureStore: SecureStore(backend: backend))

        #expect(try await configuration.credential(.workOpenRouterKey) == "work")
        try await configuration.setCredential("new-proxy", for: .proxyToken)

        #expect(backend.writes.count == 2)
        let updatedData = try #require(backend.writes.last?.value.data(using: .utf8))
        let updatedVault = try JSONDecoder().decode([String: String].self, from: updatedData)
        #expect(updatedVault["personal-openrouter-key"] == "personal")
        #expect(updatedVault["work-openrouter-key"] == "work")
        #expect(updatedVault["proxy-token"] == "new-proxy")
        #expect(backend.reads.map(\.serviceName) == [
            SecureStore.productionService,
            SecureStore.legacyVaultService,
            SecureStore.priorLegacyService,
            SecureStore.priorLegacyService,
        ])
    }
}
