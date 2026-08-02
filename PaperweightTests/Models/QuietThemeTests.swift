import XCTest

final class QuietThemeTests: XCTestCase {

    func test_allThreeStylesArePresentInDisplayOrder() {
        XCTAssertEqual(QuietTheme.allCases, [.simple, .diorama, .overgrown])
    }

    func test_everyStyleHasATitleAndBlurb() {
        for scene in QuietTheme.allCases {
            XCTAssertFalse(scene.title.isEmpty)
            XCTAssertFalse(scene.blurb.isEmpty)
        }
    }

    func test_onlySimpleHasNoArtwork() {
        XCTAssertFalse(QuietTheme.simple.hasArtwork)
        XCTAssertTrue(QuietTheme.diorama.hasArtwork)
        XCTAssertTrue(QuietTheme.overgrown.hasArtwork)
    }

    /// A config saved before this field existed must still decode, and must land
    /// on Diorama — the design's default — rather than throwing or resetting.
    func test_configWithoutTheKeyDefaultsToDiorama() throws {
        let json = Data(#"{"isEnabled":true,"coolOffDays":2}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.quietTheme, .diorama)
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.coolOffDays, 2)
    }

    func test_aStoredChoiceSurvivesARoundTrip() throws {
        var config = PaperweightConfig()
        config.quietTheme = .overgrown

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PaperweightConfig.self, from: data)

        XCTAssertEqual(decoded.quietTheme, .overgrown)
    }

    /// An unrecognised value — a config written by a newer build — must fall back
    /// rather than throw, since a thrown config decode wipes the user's setup.
    func test_anUnknownStyleFallsBackToDiorama() throws {
        let json = Data(#"{"quietTheme":"bioluminescent"}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.quietTheme, .diorama)
    }

    func test_theDefaultConfigUsesDiorama() {
        XCTAssertEqual(PaperweightConfig().quietTheme, .diorama)
    }

    /// A wrong-typed value must fall back, not throw — a thrown config decode
    /// would take the user's registered unlock token down with it.
    func test_aWrongTypedStyleFallsBackToDiorama() throws {
        let json = Data(#"{"quietTheme":42}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.quietTheme, .diorama)
    }

    func test_anExplicitNullStyleFallsBackToDiorama() throws {
        let json = Data(#"{"quietTheme":null}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.quietTheme, .diorama)
    }
}
