import XCTest

#if os(iOS)
final class HomeViewModelTests: XCTestCase {

    var configStore: ConfigStore!
    var familyService: MockFamilyControlsService!
    var restrictionService: RestrictionService!
    var widgetStore: WidgetSnapshotStore!

    @MainActor
    override func setUp() {
        super.setUp()
        configStore = ConfigStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        familyService = MockFamilyControlsService()
        restrictionService = RestrictionService(store: MockManagedSettingsStore())
        // Isolated suite: the default store writes to the real App Group, which
        // would leak widget state between tests and into the installed app.
        widgetStore = WidgetSnapshotStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    @MainActor
    func test_enable_requestsAuthorizationIfNeeded() async {
        familyService.isAuthorized = false
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)

        await vm.setEnabled(true)

        XCTAssertEqual(familyService.authorizationCallCount, 1)
    }

    @MainActor
    func test_enable_doesNotRequestAuth_ifAlreadyAuthorized() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)

        await vm.setEnabled(true)

        XCTAssertEqual(familyService.authorizationCallCount, 0)
    }

    @MainActor
    func test_enable_savesConfig() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)

        await vm.setEnabled(true)

        XCTAssertTrue(configStore.load().isEnabled)
    }

    @MainActor
    func test_disable_savesConfig() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)
        await vm.setEnabled(true)
        await vm.setEnabled(false)

        XCTAssertFalse(configStore.load().isEnabled)
    }

    @MainActor
    func test_hasUnlockMethod_falseWithNoTokenOrCodes() {
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)
        XCTAssertFalse(vm.hasUnlockMethod)
    }

    @MainActor
    func test_hasUnlockMethod_trueWithRegisteredToken() {
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)
        vm.config.registeredNFCTagUID = "04A29F1C"
        XCTAssertTrue(vm.hasUnlockMethod)
    }

    @MainActor
    func test_hasUnlockMethod_trueWithUnusedRecoveryCode() {
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)
        vm.config.recoveryCodes = [RecoveryCode(id: UUID(), codeHash: "abc", isUsed: false)]
        XCTAssertTrue(vm.hasUnlockMethod)
    }

    @MainActor
    func test_hasAppsSelected_falseWhenSelectionEmpty() {
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)
        XCTAssertFalse(vm.hasAppsSelected)
    }

    @MainActor
    func test_hasUnlockMethod_falseWhenAllCodesUsed() {
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)
        vm.config.recoveryCodes = [RecoveryCode(id: UUID(), codeHash: "abc", isUsed: true)]
        XCTAssertFalse(vm.hasUnlockMethod)
    }

    /// Regression test: `saveScheduleEdit` must promote a due pending schedule
    /// before applying the new edit. If it applies against the stale active
    /// schedule instead, the intersection in `applyScheduleEdit` drops the
    /// half-hour the pending schedule had already opened, silently discarding
    /// a loosening the user waited a day for.
    @MainActor
    func test_saveScheduleEdit_promotesADueChangeBeforeApplying() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService, widgetStore: widgetStore)
        await vm.setEnabled(true)

        // A slot that's already free today, a slot only the (still-pending)
        // loosening opened, and a slot the further edit opens on top of that.
        let alreadyFreeSlot = PaperweightSchedule.slot(day: 0, halfHour: 0)
        let pendingOnlySlot = PaperweightSchedule.slot(day: 0, halfHour: 5)
        let furtherEditSlot = PaperweightSchedule.slot(day: 0, halfHour: 10)

        // State after the app sat open past midnight: a loosening is due but
        // hasn't been promoted onto the active schedule yet.
        vm.config.schedule = PaperweightSchedule(freeSlots: [alreadyFreeSlot])
        vm.config.pendingSchedule = PaperweightSchedule(freeSlots: [alreadyFreeSlot, pendingOnlySlot])
        vm.config.pendingScheduleEffectiveAt = Date(timeIntervalSinceNow: -3600)

        // A further edit that still leaves the pending slot open.
        let edit = PaperweightSchedule(freeSlots: [alreadyFreeSlot, pendingOnlySlot, furtherEditSlot])
        vm.saveScheduleEdit(edit)

        XCTAssertTrue(
            vm.config.schedule?.freeSlots.contains(pendingOnlySlot) ?? false,
            "the already-due pending loosening should have been promoted before the new edit was applied"
        )
    }
}
#endif
