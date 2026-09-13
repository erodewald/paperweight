import XCTest

final class L10nTests: XCTestCase {
    override func setUp() { TestLocale.useTestBundle() }

    /// The shared catalog must compile into the test bundle, or every plural
    /// and every translated string silently falls back to its key.
    func test_testBundleCarriesTheCompiledCatalog() {
        let bundle = L10n.bundle
        let strings = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj")
        let loctable = bundle.url(forResource: "Localizable", withExtension: "loctable")
        XCTAssertTrue(strings != nil || loctable != nil, "no compiled Localizable table in \(bundle.bundlePath)")
    }
}
