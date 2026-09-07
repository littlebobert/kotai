import Foundation
import Security
import Testing
@testable import Kotai

struct SecureStoreTests {
    @Test
    func exactAccountReadQueryUsesLegacyMacOSKeychain() {
        let secureStore = SecureStore()
        let readQuery = secureStore.readQuery(account: .vault)
        let mutationQuery = secureStore.mutationQuery(account: "test-account")

        #expect(SecureStore.productionService == "com.justin.Kotai.credentials.v3")
        #expect(readQuery[kSecAttrService as String] as? String == SecureStore.productionService)
        #expect(
            readQuery[kSecAttrAccount as String] as? String
                == SecureStore.Account.vault.name
        )
        #expect(readQuery[kSecAttrAccessGroup as String] == nil)
        #expect(readQuery[kSecUseDataProtectionKeychain as String] == nil)
        #expect(
            readQuery[kSecMatchLimit as String] as? String
                == kSecMatchLimitOne as String
        )
        #expect(readQuery[kSecReturnAttributes as String] == nil)
        #expect(readQuery[kSecReturnData as String] as? Bool == true)
        #expect(mutationQuery[kSecAttrAccount as String] as? String == "test-account")
        #expect(mutationQuery[kSecAttrAccessGroup as String] == nil)
        #expect(mutationQuery[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test
    func migrationQueriesUseLegacyMacOSKeychain() {
        let secureStore = SecureStore()
        let legacyService = SecureStore.migrationServices[0]
        let readQuery = secureStore.readQuery(
            account: .vault,
            service: legacyService
        )

        #expect(readQuery[kSecAttrService as String] as? String == SecureStore.legacyVaultService)
        #expect(
            readQuery[kSecAttrAccount as String] as? String
                == SecureStore.Account.vault.name
        )
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
        #expect(backend.reads == [
            .init(
                accountNames: [SecureStore.Account.vault.name],
                serviceName: SecureStore.productionService
            ),
            .init(
                accountNames: [SecureStore.Account.vault.name],
                serviceName: SecureStore.legacyVaultService
            ),
        ])
    }

    @Test
    func currentVaultWinsWithoutLegacyQueries() throws {
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.productionService: ["credential-vault-v1": "{}"],
        ])
        let secureStore = SecureStore(backend: backend)

        _ = try secureStore.readAllCandidates()

        #expect(backend.reads == [
            .init(
                accountNames: [SecureStore.Account.vault.name],
                serviceName: SecureStore.productionService
            ),
        ])
    }

    @Test
    func productionAndV2ReadOnlyTheVaultAccount() throws {
        let backend = FakeSecureStoreBackend()
        let secureStore = SecureStore(backend: backend)

        _ = try secureStore.readAllCandidates()

        #expect(backend.reads[0].accountNames == [SecureStore.Account.vault.name])
        #expect(backend.reads[0].serviceName == SecureStore.productionService)
        #expect(backend.reads[1].accountNames == [SecureStore.Account.vault.name])
        #expect(backend.reads[1].serviceName == SecureStore.legacyVaultService)
    }

    @Test
    func priorVaultStopsHistoricalAccountFallback() throws {
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.priorLegacyService: [
                SecureStore.Account.vault.name: "{}",
                "proxy-token": "must-not-be-read",
            ],
        ])
        let secureStore = SecureStore(backend: backend)

        let candidates = try secureStore.readAllCandidates()

        #expect(candidates.last?.items == [SecureStore.Account.vault.name: "{}"])
        #expect(backend.reads.count == 3)
        #expect(backend.reads.last?.accountNames == [SecureStore.Account.vault.name])
    }

    @Test
    func priorServiceFallsBackToHistoricalCredentialAccounts() throws {
        let backend = FakeSecureStoreBackend(itemsByService: [
            SecureStore.priorLegacyService: ["proxy-token": "proxy"],
        ])
        let secureStore = SecureStore(backend: backend)

        let candidates = try secureStore.readAllCandidates()

        #expect(candidates.last?.items == ["proxy-token": "proxy"])
        #expect(backend.reads.count == 4)
        #expect(
            backend.reads.last?.accountNames
                == SecureStore.Account.priorCredentials.map(\.name)
        )
    }

    @Test
    func unexpectedReadStatusStopsLookupAndIsNotMissing() {
        let failure = SecureStoreError.unexpectedStatus(errSecParam)
        let backend = FakeSecureStoreBackend(readErrorByService: [
            SecureStore.productionService: failure,
        ])
        let secureStore = SecureStore(backend: backend)

        do {
            _ = try secureStore.readAllCandidates()
            Issue.record("Expected errSecParam to throw")
        } catch let error as SecureStoreError {
            #expect(error == failure)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(backend.reads.count == 1)
        #expect(backend.writes.isEmpty)
    }

    @Test
    func unexpectedStatusDescriptionIncludesMessageAndNumericCode() throws {
        let description = try #require(SecureStoreError
            .unexpectedStatus(errSecParam)
            .errorDescription)
        let systemMessage = try #require(
            SecCopyErrorMessageString(errSecParam, nil) as String?
        )

        #expect(description.contains("-50"))
        #expect(description.contains(systemMessage))
    }

    @Test @MainActor
    func unexpectedStatusDoesNotRequireSetup() {
        let availability = AppController.credentialAvailability(
            values: [],
            error: SecureStoreError.unexpectedStatus(errSecParam)
        )

        #expect(!availability.requiresSetup)
        guard case .inaccessible(let message) = availability else {
            Issue.record("Expected inaccessible credential state")
            return
        }
        #expect(message.contains("-50"))
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
    struct Read: Equatable {
        let accountNames: [String]
        let serviceName: String
    }

    struct Write: Equatable {
        let value: String
        let account: String
        let serviceName: String
    }

    private let lock = NSLock()
    private var storedItemsByService: [String: [String: String]]
    private var readErrorByService: [String: SecureStoreError]
    private var readErrorByServiceAndAccount: [String: [String: SecureStoreError]]
    private var storedReads: [Read] = []
    private var storedWrites: [Write] = []
    private var storedDeletes: [(account: String, serviceName: String)] = []

    init(
        itemsByService: [String: [String: String]] = [:],
        readErrorByService: [String: SecureStoreError] = [:],
        readErrorByServiceAndAccount: [
            String: [String: SecureStoreError]
        ] = [:]
    ) {
        self.storedItemsByService = itemsByService
        self.readErrorByService = readErrorByService
        self.readErrorByServiceAndAccount = readErrorByServiceAndAccount
    }

    var reads: [Read] { lock.withLock { storedReads } }
    var writes: [Write] { lock.withLock { storedWrites } }
    var deleteCount: Int { lock.withLock { storedDeletes.count } }

    func items(serviceName: String) -> [String: String] {
        lock.withLock { storedItemsByService[serviceName] ?? [:] }
    }

    func readItems(
        accounts: [SecureStore.Account],
        service: SecureStore.Service
    ) throws -> [String: String] {
        try lock.withLock {
            storedReads.append(
                Read(
                    accountNames: accounts.map(\.name),
                    serviceName: service.name
                )
            )
            if let error = readErrorByService[service.name] { throw error }
            let storedItems = storedItemsByService[service.name] ?? [:]
            var items: [String: String] = [:]
            for account in accounts {
                if let error = readErrorByServiceAndAccount[
                    service.name
                ]?[account.name] {
                    throw error
                }
                items[account.name] = storedItems[account.name]
            }
            return items
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
