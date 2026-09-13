import XCTest

final class TranslationFeedbackTests: XCTestCase {
    private let context = TranslationFeedback.Context(appLanguage: "ko", deviceLanguages: ["ko-KR", "en-US"],
                                                      appVersion: "1.3.0", build: "1010")

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func test_reportURL_targets_the_fix_form_with_prefilled_fields() {
        let url = TranslationFeedback.reportURL(context)
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/erodewald/paperweight/issues/new")
        let q = query(url)
        XCTAssertEqual(q["template"], "translation-fix.yml")
        XCTAssertEqual(q["language"], "ko")
        XCTAssertEqual(q["device-languages"], "ko-KR, en-US")
        XCTAssertEqual(q["app-version"], "1.3.0 (1010)")
        XCTAssertEqual(q["title"], "Wrong translation (ko)")
    }

    func test_requestURL_targets_the_request_form() {
        let q = query(TranslationFeedback.requestURL(context))
        XCTAssertEqual(q["template"], "translation-request.yml")
        XCTAssertEqual(q["device-languages"], "ko-KR, en-US")
        XCTAssertEqual(q["title"], "Language request")
        XCTAssertNil(q["language"])
    }

    func test_values_are_percent_escaped() {
        let odd = TranslationFeedback.Context(appLanguage: "pt-BR", deviceLanguages: ["pt-BR"], appVersion: "1.0 β", build: "1")
        let url = TranslationFeedback.reportURL(odd)
        XCTAssertFalse(url.absoluteString.contains(" "))
        XCTAssertEqual(query(url)["app-version"], "1.0 β (1)")
    }

    func test_languageName_is_localized() {
        XCTAssertEqual(TranslationFeedback.languageName("ko", locale: TestLocale.en), "Korean")
        XCTAssertEqual(TranslationFeedback.languageName("nl", locale: Locale(identifier: "nl_NL")), "Nederlands")
    }

    func test_current_context_reads_the_bundle_and_locale() {
        let c = TranslationFeedback.Context.current(bundle: Bundle(for: Self.self), locale: TestLocale.en)
        XCTAssertFalse(c.appLanguage.isEmpty)
        XCTAssertFalse(c.deviceLanguages.isEmpty)
    }
}
