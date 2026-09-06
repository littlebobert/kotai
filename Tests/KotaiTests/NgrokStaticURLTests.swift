import Foundation
import Testing
@testable import Kotai

struct NgrokStaticURLTests {
    @Test
    func normalizesWhitespaceAndURLCase() throws {
        let staticURL = try NgrokStaticURL("  HTTPS://EXAMPLE.NGROK.APP  ")

        #expect(staticURL.absoluteString == "https://example.ngrok.app")
    }

    @Test
    func normalizesRootSlash() throws {
        let staticURL = try NgrokStaticURL("https://example.ngrok.app/")

        #expect(staticURL.absoluteString == "https://example.ngrok.app")
    }

    @Test
    func acceptsCustomDomain() throws {
        let staticURL = try NgrokStaticURL("https://proxy.example.com")

        #expect(staticURL.absoluteString == "https://proxy.example.com")
    }

    @Test(arguments: [
        "http://example.ngrok.app",
        "example.ngrok.app",
        "https:///",
        "https://example.ngrok.app/proxy",
        "https://example.ngrok.app?token=value",
        "https://example.ngrok.app#fragment",
        "https://user@example.ngrok.app",
        "https://user:password@example.ngrok.app",
    ])
    func rejectsInvalidStaticURL(rawValue: String) {
        #expect(throws: NgrokError.self) {
            try NgrokStaticURL(rawValue)
        }
    }

    @Test @MainActor
    func verifiedEndpointReturnsConfiguredCanonicalURL() throws {
        let configuredURL = try NgrokStaticURL("https://EXAMPLE.ngrok.app/")

        let verifiedURL = try NgrokManager.verifiedPublicURL(
            discoveredURL: "https://example.ngrok.app",
            configuredURL: configuredURL
        )

        #expect(verifiedURL.absoluteString == "https://example.ngrok.app")
    }

    @Test @MainActor
    func verifiedEndpointRejectsMismatch() throws {
        let configuredURL = try NgrokStaticURL("https://expected.ngrok.app")

        #expect(throws: NgrokError.configuredEndpointMismatch) {
            try NgrokManager.verifiedPublicURL(
                discoveredURL: "https://unexpected.ngrok.app",
                configuredURL: configuredURL
            )
        }
    }

    @Test @MainActor
    func argumentsIncludeCanonicalStaticURLAndExistingOptions() throws {
        let staticURL = try NgrokStaticURL(" https://EXAMPLE.ngrok.app/ ")

        let arguments = NgrokManager.arguments(staticURL: staticURL)

        #expect(Array(arguments.prefix(4)) == [
            "http",
            "http://127.0.0.1:18742",
            "--url",
            "https://example.ngrok.app",
        ])
        #expect(arguments.contains("--config"))
        #expect(arguments.contains("--name"))
        #expect(arguments.contains("kotai"))
        #expect(arguments.contains("--log"))
        #expect(arguments.contains("stdout"))
        #expect(arguments.contains("--log-format"))
        #expect(arguments.contains("json"))
    }

    @Test
    func updatingStaticURLPreservesAuthtoken() async throws {
        let configuration = ProxyConfiguration(
            initialCredentials: [
                .ngrokAuthtoken: "existing-token",
                .ngrokStaticURL: "https://old.ngrok.app",
            ]
        )

        try await configuration.setCredential(
            "https://new.ngrok.app",
            for: .ngrokStaticURL
        )

        let storedAuthtoken = try await configuration.credential(.ngrokAuthtoken)
        let storedStaticURL = try await configuration.credential(.ngrokStaticURL)
        #expect(storedAuthtoken == "existing-token")
        #expect(storedStaticURL == "https://new.ngrok.app")
    }

    @Test
    func initialCredentialsIncludeStaticURL() async throws {
        let configuration = ProxyConfiguration(
            initialCredentials: [
                .ngrokStaticURL: "https://example.ngrok.app",
            ]
        )

        let storedURL = try await configuration.credential(.ngrokStaticURL)

        #expect(storedURL == "https://example.ngrok.app")
        #expect(
            ProxyConfiguration.Credential.ngrokStaticURL.rawValue
                == "ngrok-static-url"
        )
    }

    @Test
    func confirmedURLWinsOverLegacySuggestion() {
        let selection = StaticURLSelection(
            confirmedValue: " HTTPS://CONFIRMED.NGROK.APP/ ",
            legacyValue: "https://legacy.ngrok.app"
        )

        #expect(selection.confirmedURL?.absoluteString == "https://confirmed.ngrok.app")
        #expect(selection.setupSuggestionURL == selection.confirmedURL)
    }

    @Test
    func legacyURLIsSuggestionWithoutConfirmation() {
        let selection = StaticURLSelection(
            confirmedValue: nil,
            legacyValue: " HTTPS://LEGACY.NGROK.APP/ "
        )

        #expect(selection.confirmedURL == nil)
        #expect(selection.setupSuggestionURL?.absoluteString == "https://legacy.ngrok.app")
    }

    @Test
    func invalidConfirmedURLFallsBackOnlyAsSuggestion() {
        let selection = StaticURLSelection(
            confirmedValue: "http://invalid.ngrok.app",
            legacyValue: "https://legacy.ngrok.app"
        )

        #expect(selection.confirmedURL == nil)
        #expect(selection.setupSuggestionURL?.absoluteString == "https://legacy.ngrok.app")
    }

    @Test
    func invalidStoredURLsProduceNoSelection() {
        let selection = StaticURLSelection(
            confirmedValue: "not a URL",
            legacyValue: "http://legacy.ngrok.app"
        )

        #expect(selection.confirmedURL == nil)
        #expect(selection.setupSuggestionURL == nil)
    }

    @Test @MainActor
    func runningRuntimeWithSameURLDoesNotRestart() {
        #expect(!AppController.shouldRestartNgrok(
            staticURLChanged: false,
            runtimeStatus: .running,
            hasCompleteCredentials: true
        ))
    }

    @Test @MainActor
    func runningRuntimeWithChangedURLRestarts() {
        #expect(AppController.shouldRestartNgrok(
            staticURLChanged: true,
            runtimeStatus: .running,
            hasCompleteCredentials: true
        ))
    }

    @Test @MainActor
    func failedRuntimeWithCompleteCredentialsRestarts() {
        #expect(AppController.shouldRestartNgrok(
            staticURLChanged: false,
            runtimeStatus: .failed("Unavailable"),
            hasCompleteCredentials: true
        ))
    }

    @Test @MainActor
    func failedRuntimeWithIncompleteCredentialsDoesNotRestart() {
        #expect(!AppController.shouldRestartNgrok(
            staticURLChanged: false,
            runtimeStatus: .failed("Unavailable"),
            hasCompleteCredentials: false
        ))
    }

    @Test @MainActor
    func needsConfigurationRuntimeWithCompleteCredentialsRestarts() {
        #expect(AppController.shouldRestartNgrok(
            staticURLChanged: false,
            runtimeStatus: .needsConfiguration,
            hasCompleteCredentials: true
        ))
    }

    @Test @MainActor
    func needsConfigurationRuntimeWithIncompleteCredentialsDoesNotRestart() {
        #expect(!AppController.shouldRestartNgrok(
            staticURLChanged: false,
            runtimeStatus: .needsConfiguration,
            hasCompleteCredentials: false
        ))
    }

    @Test @MainActor
    func startingRuntimeWithCompleteCredentialsRestarts() {
        #expect(AppController.shouldRestartNgrok(
            staticURLChanged: false,
            runtimeStatus: .starting,
            hasCompleteCredentials: true
        ))
    }

    @Test @MainActor
    func startingRuntimeWithIncompleteCredentialsDoesNotRestart() {
        #expect(!AppController.shouldRestartNgrok(
            staticURLChanged: false,
            runtimeStatus: .starting,
            hasCompleteCredentials: false
        ))
    }

    @Test @MainActor
    func canonicallyEquivalentStaticURLIsUnchanged() throws {
        let proposedURL = try NgrokStaticURL("HTTPS://X/")

        #expect(!AppController.hasStaticURLChanged(
            proposedURL: proposedURL,
            confirmedValue: "https://x"
        ))
    }
}
