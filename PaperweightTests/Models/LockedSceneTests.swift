import XCTest

final class LockedSceneTests: XCTestCase {

    func test_allThreeStylesArePresentInDisplayOrder() {
        XCTAssertEqual(LockedScene.allCases, [.simple, .diorama, .overgrown])
    }

    func test_everyStyleHasATitleAndBlurb() {
        for scene in LockedScene.allCases {
            XCTAssertFalse(scene.title.isEmpty)
            XCTAssertFalse(scene.blurb.isEmpty)
        }
    }

    /// A config saved before this field existed must still decode, and must land
    /// on Diorama — the design's default — rather than throwing or resetting.
    func test_configWithoutTheKeyDefaultsToDiorama() throws {
        let json = Data(#"{"isEnabled":true,"coolOffDays":2}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.lockedScene, .diorama)
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.coolOffDays, 2)
    }

    func test_aStoredChoiceSurvivesARoundTrip() throws {
        var config = PaperweightConfig()
        config.lockedScene = .overgrown

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PaperweightConfig.self, from: data)

        XCTAssertEqual(decoded.lockedScene, .overgrown)
    }

    /// An unrecognised value — a config written by a newer build — must fall back
    /// rather than throw, since a thrown config decode wipes the user's setup.
    func test_anUnknownStyleFallsBackToDiorama() throws {
        let json = Data(#"{"lockedScene":"bioluminescent"}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.lockedScene, .diorama)
    }

    func test_theDefaultConfigUsesDiorama() {
        XCTAssertEqual(PaperweightConfig().lockedScene, .diorama)
    }
}
