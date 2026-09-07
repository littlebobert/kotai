import Foundation
import Security
import Testing
@testable import Kotai

struct SecureStoreTests {
    @Test
    func productionQueriesUseLegacyMacOSKeychain() {
        let secureStore = SecureStore()
        let readQuery = secureStore.readQuery()
        let mutationQuery = secureStore.mutationQuery(account: "test-account")

        #expect(SecureStore.productionService == "com.justin.Kotai.credentials.v3")
        #expect(readQuery[kSecAttrService as String] as? String == SecureStore.productionService)
        #expect(readQuery[kSecAttrAccessGroup as String] == nil)
        #expect(readQuery[kSecUseDataProtectionKeychain as String] == nil)
        #expect(readQuery[kSecMatchLimit as String] as? String == kSecMatchLimitAll as String)
        #expect(readQuery[kSecReturnAttributes as String] as? Bool == true)
        #expect(readQuery[kSecReturnData as String] as? Bool == true)
        #expect(mutationQuery[kSecAttrAccount as String] as? String == "test-account")
        #expect(mutationQuery[kSecAttrAccessGroup as String] == nil)
        #expect(mutationQuery[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test
    func migrationQueriesUseLegacyMacOSKeychain() {
        let secureStore = SecureStore()
        let legacyService = SecureStore.migrationServices[0]
        let readQuery = secureStore.readQuery(service: legacyService)

        #expect(readQuery[kSecAttrService as String] as? String == SecureStore.legacyVaultService)
        #expect(readQuery[kSecAttrAccessGroup as String] == nil)
        #expect(readQuery[kSecUseDataProtectionKeychain as String] == nil)
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
    func commonStatusesHaveDistinctClassifications() {
        #expect(SecureStoreError.classify(errSecSuccess) == .success)
        #expect(SecureStoreError.classify(errSecItemNotFound) == .itemNotFound)
        #expect(SecureStoreError.classify(errSecDuplicateItem) == .duplicateItem)
        #expect(SecureStoreError.classify(errSecParam) == .otherFailure)
    }

    @Test
    func candidateLookupStopsAfterFirstPopulatedService() throws {
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.legacyVaultService: ["credential-vault-v1": "{}"],
            SecureStore.priorLegacyService: ["unused": "unused"],
        ])
        let secureStore = SecureStore(backend: backend)

        let candidates = try secureStore.readAllCandidates()

        #expect(candidates.map(\.service.name) == [
            SecureStore.productionService,
            SecureStore.legacyVaultService,
        ])
        #expect(backend.readServices == [
            SecureStore.productionService,
            SecureStore.legacyVaultService,
        ])
    }

    @Test
    func currentVaultWinsWithoutLegacyQueries() throws {
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.productionService: ["credential-vault-v1": "{}"],
        ])
        let secureStore = SecureStore(backend: backend)

        _ = try secureStore.readAllCandidates()

        #expect(backend.readServices == [SecureStore.productionService])
    }

    @Test @MainActor
    func missingCredentialsRequireSetup() {
        let availability = AppController.credentialAvailability(values: ["token", nil, "key"])
        #expect(availability == .missing)
        #expect(availability.requiresSetup)
    }

    @Test @MainActor
    func deniedCredentialAccessDoesNotRequireSetup() {
        let error = SecureStoreError.accessDenied(errSecUserCanceled)
        let availability = AppController.credentialAvailability(values: [], error: error)

        #expect(!availability.requiresSetup)
        guard case .inaccessible(let message) = availability else {
            Issue.record("Expected inaccessible credential state")
            return
        }
        #expect(message.contains("Allow Keychain access"))
    }

    @Test
    func testHostDoesNotStartRuntimeServices() {
        #expect(!ApplicationLaunchEnvironment.shouldStartRuntime(environment: ["KOTAI_RUNNING_TESTS": "1"]))
        #expect(ApplicationLaunchEnvironment.shouldStartRuntime(environment: [:]))
    }
}

final class FakeSecureStoreBackend: SecureStoreBackend, @unchecked Sendable {
    struct Write: Equatable {
        let value: String
        let account: String
        let serviceName: String
    }

    private let lock = NSLock()
    private var storedItemsByService: [String: [String: String]]
    private var readErrorByService: [String: SecureStoreError]
    private var storedReadServices: [String] = []
    private var storedWrites: [Write] = []
    private var storedDeletes: [(account: String, serviceName: String)] = []

    init(
        itemsByService: [String: [String: String]] = [:],
        readErrorByService: [String: SecureStoreError] = [:]
    ) {
        self.storedItemsByService = itemsByService
        self.readErrorByService = readErrorByService
    }

    var readServices: [String] { lock.withLock { storedReadServices } }
    var writes: [Write] { lock.withLock { storedWrites } }
    var deleteCount: Int { lock.withLock { storedDeletes.count } }

    func items(serviceName: String) -> [String: String] {
        lock.withLock { storedItemsByService[serviceName] ?? [:] }
    }

    func readItems(service: SecureStore.Service) throws -> [String: String] {
        try lock.withLock {
            storedReadServices.append(service.name)
            if let error = readErrorByService[service.name] { throw error }
            return storedItemsByService[service.name] ?? [:]
        }
    }

    func write(_ value: String, account: String, service: SecureStore.Service) throws {
        lock.withLock {
            storedWrites.append(Write(value: value, account: account, serviceName: service.name))
            storedItemsByService[service.name, default: [:]][account] = value
        }
    }

    func delete(account: String, service: SecureStore.Service) throws {
        lock.withLock {
            storedDeletes.append((account, service.name))
            storedItemsByService[service.name]?[account] = nil
        }
    }
}
