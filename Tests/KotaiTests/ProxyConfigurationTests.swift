import AsyncHTTPClient
import Hummingbird
import HummingbirdTesting
import Testing
@testable import Kotai

struct ProxyConfigurationTests {
    @Test
    func accountModeCanBeChanged() async {
        let configuration = ProxyConfiguration(accountMode: .personal)

        await configuration.setAccountMode(.work)

        let accountMode = await configuration.accountMode
        #expect(accountMode == .work)
    }

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

    private func makeApplication() -> (
        application: Application<OpenRouterProxy>,
        httpClient: HTTPClient
    ) {
        let configuration = ProxyConfiguration()
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let responder = OpenRouterProxy(
            configuration: configuration,
            httpClient: httpClient
        )

        return (Application(responder: responder), httpClient)
    }
}
