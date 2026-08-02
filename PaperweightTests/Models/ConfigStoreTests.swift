import XCTest

final class ConfigStoreTests: XCTestCase {

    var store: ConfigStore!

    override func setUp() {
        super.setUp()
        // Use a unique in-memory UserDefaults suite per test run
        store = ConfigStore(defaults: UserDefaults(suiteName: "test.paperweight.\(UUID().uuidString)")!)
    }

    func test_save_andLoad_roundtrips() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        config.unlockDuration = 300

        try store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.isEnabled, true)
        XCTAssertEqual(loaded.unlockDuration, 300)
    }

    func test_load_returnsDefault_whenEmpty() {
        let config = store.load()
        XCTAssertFalse(config.isEnabled)
    }

    func test_save_overwritesPrevious() throws {
        var config = PaperweightConfig()
        config.unlockDuration = 300
        try store.save(config)

        config.unlockDuration = 600
        try store.save(config)

        XCTAssertEqual(store.load().unlockDuration, 600)
    }

    /// The whole feature hinges on this: a pending loosening whose effective
    /// date has already passed must come into force the moment anything —
    /// app, widget, or monitor extension — calls load(), not just when the
    /// view model happens to sync.
    func test_load_promotesPendingSchedule_whenEffectiveDateHasPassed() throws {
        var config = PaperweightConfig()
        let active = PaperweightSchedule(freeSlots: [0])
        let pending = PaperweightSchedule(freeSlots: [0, 1])
        config.schedule = active
        config.pendingSchedule = pending
        config.pendingScheduleEffectiveAt = Date().addingTimeInterval(-3600)
        try store.save(config)

        let loaded = store.load()

        XCTAssertEqual(loaded.schedule, pending)
        XCTAssertNil(loaded.pendingSchedule)
        XCTAssertNil(loaded.pendingScheduleEffectiveAt)

        // The promotion must be persisted, not just returned in memory —
        // otherwise every other reader (widget, monitor extension) would see
        // the stale, still-pending schedule on their own next load().
        XCTAssertEqual(store.load().schedule, pending)
    }
}
