import XCTest

#if os(iOS)
final class HomeViewModelTests: XCTestCase {

    var configStore: ConfigStore!
    var familyService: MockFamilyControlsService!
    var restrictionService: RestrictionService!

    @MainActor
    override func setUp() {
        super.setUp()
        configStore = ConfigStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        familyService = MockFamilyControlsService()
        restrictionService = RestrictionService(store: MockManagedSettingsStore())
    }

    @MainActor
    func test_enable_requestsAuthorizationIfNeeded() async {
        familyService.isAuthorized = false
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)

        await vm.setEnabled(true)

        XCTAssertEqual(familyService.authorizationCallCount, 1)
    }

    @MainActor
    func test_enable_doesNotRequestAuth_ifAlreadyAuthorized() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)

        await vm.setEnabled(true)

        XCTAssertEqual(familyService.authorizationCallCount, 0)
    }

    @MainActor
    func test_enable_savesConfig() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)

        await vm.setEnabled(true)

        XCTAssertTrue(configStore.load().isEnabled)
    }

    @MainActor
    func test_disable_savesConfig() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)
        await vm.setEnabled(true)
        await vm.setEnabled(false)

        XCTAssertFalse(configStore.load().isEnabled)
    }
}
#endif
