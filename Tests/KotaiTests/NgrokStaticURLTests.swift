import Foundation
import Testing
@testable import Kotai

struct NgrokStaticURLTests {
    @Test
    func normalizesWhitespaceAndURLCase() throws {
        let staticURL = try NgrokStaticURL("  HTTPS://EXAMPLE.NGROK.APP  ")

        #expect(staticURL.absoluteString == "https://example.ngrok.app")
    }

    @Test(arguments: [
        "kaycee-example.ngrok-free.dev",
        "  KAYCEE-EXAMPLE.NGROK-FREE.DEV/  ",
    ])
    func normalizesBareDomain(rawValue: String) throws {
        let staticURL = try NgrokStaticURL(rawValue)

        #expect(staticURL.absoluteString == "https://kaycee-example.ngrok-free.dev")
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
        "",
        "http://example.ngrok.app",
        "ftp://example.ngrok.app",
        "HTTP://example.ngrok.app",
        "https:///",
        "https://example",
        "https://example.ngrok.app/proxy",
        "example.ngrok.app/proxy",
        "https://example.ngrok.app?token=value",
        "example.ngrok.app?token=value",
        "https://example.ngrok.app#fragment",
        "example.ngrok.app#fragment",
        "https://user@example.ngrok.app",
        "user@example.ngrok.app",
        "https://user:password@example.ngrok.app",
        "https://example .ngrok.app",
        "example .ngrok.app",
        "https://example..ngrok.app",
        "https://-example.ngrok.app",
        "https://example-.ngrok.app",
        ".ngrok.app",
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
        let backend = FakeSecureStoreBackend()
        let configuration = ProxyConfiguration(
            secureStore: SecureStore(backend: backend),
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
    func sameCanonicalURLDoesNotEnableRestartWhileRunning() {
        let draft = SettingsConnectionDraft(
            rawValue: " HTTPS://EXAMPLE.NGROK.APP/ ",
            confirmedURL: URL(string: "https://example.ngrok.app"),
            runtimeStatus: .running,
            hasCompleteCredentials: true
        )

        #expect(!draft.isCanonicalURLChanged)
        #expect(!draft.canRestartNgrok)
    }

    @Test @MainActor
    func changedCanonicalURLEnablesRestart() {
        let draft = SettingsConnectionDraft(
            rawValue: "https://new.ngrok.app",
            confirmedURL: URL(string: "https://old.ngrok.app"),
            runtimeStatus: .running,
            hasCompleteCredentials: true
        )

        #expect(draft.isCanonicalURLChanged)
        #expect(draft.canRestartNgrok)
    }

    @Test @MainActor
    func stoppedRuntimeWithConfiguredURLEnablesRestart() {
        let draft = SettingsConnectionDraft(
            rawValue: "https://example.ngrok.app",
            confirmedURL: URL(string: "https://example.ngrok.app"),
            runtimeStatus: .failed("Unavailable"),
            hasCompleteCredentials: true
        )

        #expect(draft.canRestartNgrok)
    }

    @Test @MainActor
    func invalidDraftShowsValidationAndDisablesRestart() {
        let draft = SettingsConnectionDraft(
            rawValue: "http://example.ngrok.app/path",
            confirmedURL: URL(string: "https://example.ngrok.app"),
            runtimeStatus: .failed("Unavailable"),
            hasCompleteCredentials: true
        )

        #expect(draft.normalizedURL == nil)
        #expect(draft.validationError != nil)
        #expect(!draft.canRestartNgrok)
    }

    @Test @MainActor
    func incompleteCredentialsDisableRestart() {
        let draft = SettingsConnectionDraft(
            rawValue: "https://new.ngrok.app",
            confirmedURL: URL(string: "https://old.ngrok.app"),
            runtimeStatus: .running,
            hasCompleteCredentials: false
        )

        #expect(!draft.canRestartNgrok)
    }

}
