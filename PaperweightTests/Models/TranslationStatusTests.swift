import XCTest

final class TranslationStatusTests: XCTestCase {
    private let fixture = """
    {"languages": {"ko": {"keys": 248, "needsReview": 248}, "nl": {"keys": 248, "needsReview": 0}}}
    """

    func test_decodes_and_reports_review_state() throws {
        let status = try JSONDecoder().decode(TranslationStatus.self, from: Data(fixture.utf8))
        XCTAssertTrue(status.needsReview("ko"))
        XCTAssertFalse(status.needsReview("nl"), "a fully reviewed language shows no notice")
        XCTAssertFalse(status.needsReview("en"), "the source language is never machine-translated")
        XCTAssertFalse(status.needsReview("fr"), "a language absent from the file shows no notice")
    }

    func test_loads_from_the_bundle() {
        TestLocale.useTestBundle()
        XCTAssertNotNil(TranslationStatus.load(), "TranslationStatus.json must ship in the bundle")
    }
}
