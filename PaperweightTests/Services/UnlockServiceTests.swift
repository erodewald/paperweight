import XCTest

#if os(iOS)
final class UnlockServiceTests: XCTestCase {

    var configStore: ConfigStore!
    var nfcService: MockNFCService!
    var restrictionService: RestrictionService!

    @MainActor
    override func setUp() {
        super.setUp()
        configStore = ConfigStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        nfcService = MockNFCService()
        restrictionService = RestrictionService(store: MockManagedSettingsStore())
    }

    @MainActor
    func test_registerTag_savesUID() async throws {
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)
        try await service.registerTag()
        XCTAssertEqual(configStore.load().registeredNFCTagUID, "AABBCCDD")
    }

    @MainActor
    func test_unlock_failsIfNoTagRegistered() async {
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)
        do {
            try await service.unlock()
            XCTFail("Should have thrown")
        } catch UnlockError.noTagRegistered {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func test_unlock_failsIfWrongUID() async throws {
        var config = PaperweightConfig()
        config.registeredNFCTagUID = "11223344"
        try configStore.save(config)

        nfcService.mockUID = "FFEEDDCC"
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)

        do {
            try await service.unlock()
            XCTFail("Should have thrown")
        } catch UnlockError.tagMismatch {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func test_unlock_succeedsWithMatchingUID() async throws {
        var config = PaperweightConfig()
        config.registeredNFCTagUID = "AABBCCDD"
        config.isEnabled = true
        try configStore.save(config)

        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)
        try await service.unlock()

        XCTAssertTrue(service.isUnlocked)
    }
}
#endif
