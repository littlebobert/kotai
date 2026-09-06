import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
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
