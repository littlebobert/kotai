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
}
