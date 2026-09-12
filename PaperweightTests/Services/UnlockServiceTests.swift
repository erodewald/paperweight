import XCTest

#if os(iOS)
final class UnlockServiceTests: XCTestCase {

    var configStore: ConfigStore!
    var nfcService: MockNFCService!
    var restrictionService: RestrictionService!
    var widgetStore: WidgetSnapshotStore!
    var scheduleService: ScheduleService!

    @MainActor
    override func setUp() {
        super.setUp()
        configStore = ConfigStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        nfcService = MockNFCService()
        restrictionService = RestrictionService(store: MockManagedSettingsStore())
        // Isolated suite: the default store writes to the real App Group, which
        // would leak widget state between tests and into the installed app.
        widgetStore = WidgetSnapshotStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        // Never the shared instance: that talks to the real DeviceActivityCenter.
        scheduleService = ScheduleService(center: MockDeviceActivityCenter())
    }

    /// The in-process relock timer dies with the app, and the app is suspended
    /// seconds after the user leaves it to use the unlocked apps. The monitor
    /// extension has to be told to re-shield at the expiry.
    @MainActor
    func test_grantUnlock_registersTheExpiryWithDeviceActivity() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        try configStore.save(config)
        let center = MockDeviceActivityCenter()
        let service = UnlockService(configStore: configStore, nfcService: nfcService,
                                    restrictionService: restrictionService, widgetStore: widgetStore,
                                    scheduleService: ScheduleService(center: center))

        service.grantUnlock(duration: 15 * 60)

        XCTAssertNotNil(center.schedule(named: "\(Paperweight.activityName).unlockExpiry"))
    }

    @MainActor
    func test_relock_dropsTheExpiryFromDeviceActivity() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        try configStore.save(config)
        let center = MockDeviceActivityCenter()
        let service = UnlockService(configStore: configStore, nfcService: nfcService,
                                    restrictionService: restrictionService, widgetStore: widgetStore,
                                    scheduleService: ScheduleService(center: center))

        service.grantUnlock(duration: 15 * 60)
        service.relock()

        XCTAssertNil(center.schedule(named: "\(Paperweight.activityName).unlockExpiry"))
        XCTAssertTrue(center.names.contains { $0.hasPrefix("\(Paperweight.activityName).heartbeat") },
                      "relock re-registers the ordinary schedule, it doesn't stop monitoring")
    }

    @MainActor
    func test_registerTag_savesUID() async throws {
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService, widgetStore: widgetStore, scheduleService: scheduleService)
        try await service.registerTag()
        XCTAssertEqual(configStore.load().registeredNFCTagUID, "AABBCCDD")
    }

    @MainActor
    func test_unlock_failsIfNoTagRegistered() async {
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService, widgetStore: widgetStore, scheduleService: scheduleService)
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
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService, widgetStore: widgetStore, scheduleService: scheduleService)

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

        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService, widgetStore: widgetStore, scheduleService: scheduleService)
        try await service.unlock()

        XCTAssertTrue(service.isUnlocked)
    }

    /// After a relock, the shield follows the resolver: a day off keeps it lifted.
    @MainActor
    func test_relock_keepsTheShieldLiftedOnADayOff() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        config.dayExceptions = [DayException(firstDay: .today(), lastDay: .today(), treatment: .openAllDay)]
        try configStore.save(config)
        let shield = MockManagedSettingsStore()
        let service = UnlockService(configStore: configStore, nfcService: nfcService,
                                    restrictionService: RestrictionService(store: shield),
                                    widgetStore: widgetStore, scheduleService: scheduleService)

        service.relock()

        XCTAssertFalse(shield.shieldApplicationsWasSet)
    }
}
#endif
