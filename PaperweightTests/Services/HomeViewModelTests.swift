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

    /// The unlock service and the monitor extension write to the same persisted
    /// config through their own stores. On foreground the view model must read
    /// what they wrote before deciding what the shield and the DeviceActivity
    /// registrations should be — otherwise a live unlock is re-shielded early
    /// and its expiry activity is dropped.
    @MainActor
    func test_refresh_picksUpAnUnlockGrantedThroughAnotherStore() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        try configStore.save(config)
        let shield = MockManagedSettingsStore()
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: RestrictionService(store: shield), widgetStore: widgetStore)

        // Another instance — as UnlockService has — grants a timed unlock.
        var onDisk = configStore.load()
        onDisk.unlockExpiresAt = Date().addingTimeInterval(600)
        try configStore.save(onDisk)

        vm.refresh()

        XCTAssertNotNil(vm.config.unlockExpiresAt)
        XCTAssertTrue(shield.shieldWasCleared)
        XCTAssertFalse(shield.shieldApplicationsWasSet, "a live unlock must not be re-shielded on foreground")
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

    /// An open-all-day exception over an all-quiet week must lift the shield —
    /// the old `!schedule.isEmpty` guard would have kept it applied.
    @MainActor
    func test_syncRestrictions_liftsForADayOffOverAnEmptySchedule() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        config.schedule = PaperweightSchedule()
        config.dayExceptions = [DayException(firstDay: .today(), lastDay: .today(), treatment: .openAllDay)]
        try configStore.save(config)
        let shield = MockManagedSettingsStore()
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: RestrictionService(store: shield), widgetStore: widgetStore)

        vm.syncRestrictions()

        XCTAssertTrue(shield.shieldWasCleared)
        XCTAssertFalse(shield.shieldApplicationsWasSet)
    }

    @MainActor
    func test_addDayException_persistsAndResyncs() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        try configStore.save(config)
        let shield = MockManagedSettingsStore()
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: RestrictionService(store: shield), widgetStore: widgetStore)

        let tomorrow = DayKey.today().next()
        try vm.addDayException(DayException(firstDay: tomorrow, lastDay: tomorrow, treatment: .openAllDay))

        XCTAssertEqual(configStore.load().dayExceptions.count, 1)
        XCTAssertTrue(shield.shieldApplicationsWasSet || shield.shieldWasCleared, "the shield was re-evaluated")
    }

    @MainActor
    func test_removeDayException_persistsTheResult() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        let tomorrow = DayKey.today().next()
        let e = DayException(firstDay: tomorrow, lastDay: tomorrow, treatment: .openAllDay)
        config.dayExceptions = [e]
        try configStore.save(config)
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: restrictionService, widgetStore: widgetStore)

        XCTAssertEqual(vm.removeDayException(id: e.id), .removed)
        XCTAssertTrue(configStore.load().dayExceptions.isEmpty)
    }

    /// A removal that only truncates leaves the day in force until midnight;
    /// the view model remembers which ones so the list can say why.
    @MainActor
    func test_removeDayException_remembersATruncation() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        config.schedule = .weekdayEvenings()
        let today = DayKey.today()
        if today.weekdayIndex() == 0 || today.weekdayIndex() == 6 {
            config.schedule = .alwaysFree()
        }
        // Quiet all day over a weekday evening: removing it would open tonight, so it truncates.
        let e = DayException(firstDay: today, lastDay: today.next(), treatment: .quietAllDay)
        config.dayExceptions = [e]
        try configStore.save(config)
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: restrictionService, widgetStore: widgetStore)

        XCTAssertEqual(vm.removeDayException(id: e.id), .truncatedToToday)
        XCTAssertTrue(vm.truncatedDayExceptionIDs.contains(e.id))
    }
}
#endif
