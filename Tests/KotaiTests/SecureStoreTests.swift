import Security
import Testing
@testable import Kotai

struct SecureStoreTests {
    @Test
    func productionQueriesUseOnlyTheStableService() {
        let secureStore = SecureStore()
        let account = "test-account"
        let readQuery = secureStore.readQuery(account: account)
        let mutationQuery = secureStore.mutationQuery(account: account)

        #expect(SecureStore.productionService == "com.justin.Kotai.credentials.v2")
        #expect(readQuery[kSecAttrService as String] as? String == SecureStore.productionService)
        #expect(readQuery[kSecAttrAccount as String] as? String == account)
        #expect(readQuery[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(readQuery[kSecReturnData as String] as? Bool == true)
        #expect(mutationQuery[kSecAttrService as String] as? String == SecureStore.productionService)
        #expect(mutationQuery[kSecAttrAccount as String] as? String == account)
        #expect(mutationQuery[kSecReturnData as String] == nil)
    }

    @Test
    func injectedServiceIsUsedByEveryQuery() {
        let injectedService = "com.example.KotaiTests.credentials"
        let secureStore = SecureStore(service: injectedService)

        #expect(
            secureStore.readQuery(account: "read")[kSecAttrService as String] as? String
                == injectedService
        )
        #expect(
            secureStore.mutationQuery(account: "write")[kSecAttrService as String] as? String
                == injectedService
        )
    }

    @Test(arguments: [
        errSecAuthFailed,
        errSecUserCanceled,
        errSecInteractionNotAllowed,
    ])
    func accessStatusesAreClassifiedWithoutKeychainCalls(status: OSStatus) {
        #expect(SecureStoreError.classify(status) == .accessDenied)
        #expect(SecureStoreError.statusError(status) == .accessDenied(status))
    }

    @Test
    func itemNotFoundIsDistinctFromAccessFailure() {
        #expect(SecureStoreError.classify(errSecItemNotFound) == .itemNotFound)
        #expect(SecureStoreError.classify(errSecParam) == .otherFailure)
    }

    @Test @MainActor
    func missingCredentialsRequireSetup() {
        let availability = AppController.credentialAvailability(
            values: ["token", nil, "key"]
        )

        #expect(availability == .missing)
        #expect(availability.requiresSetup)
    }

    @Test @MainActor
    func deniedCredentialAccessDoesNotRequireSetup() {
        let error = SecureStoreError.accessDenied(errSecUserCanceled)
        let availability = AppController.credentialAvailability(
            values: [],
            error: error
        )

        #expect(!availability.requiresSetup)
        guard case .inaccessible(let message) = availability else {
            Issue.record("Expected inaccessible credential state")
            return
        }
        #expect(message.contains("Always Allow"))
    }

    @Test
    func testHostDoesNotStartRuntimeServices() {
        #expect(
            !ApplicationLaunchEnvironment.shouldStartRuntime(
                environment: ["KOTAI_RUNNING_TESTS": "1"]
            )
        )
        #expect(ApplicationLaunchEnvironment.shouldStartRuntime(environment: [:]))
    }
}
