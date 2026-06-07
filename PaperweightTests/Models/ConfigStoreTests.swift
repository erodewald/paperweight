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
}
