import Foundation

/// Prefilled GitHub issue-form links for translation feedback. Pure: the app
/// hands the URL to the system and nothing else happens.
enum TranslationFeedback {
    struct Context: Equatable {
        var appLanguage: String
        var deviceLanguages: [String]
        var appVersion: String
        var build: String

        static func current(bundle: Bundle = .main) -> Context {
            let info = bundle.infoDictionary
            return Context(
                appLanguage: bundle.preferredLocalizations.first ?? "en",
                deviceLanguages: Locale.preferredLanguages,
                appVersion: info?["CFBundleShortVersionString"] as? String ?? "—",
                build: info?["CFBundleVersion"] as? String ?? "—")
        }

        var versionLine: String { "\(appVersion) (\(build))" }
        var deviceLanguageList: String { deviceLanguages.joined(separator: ", ") }
    }

    static func reportURL(_ c: Context) -> URL {
        issueURL(template: "translation-fix.yml", title: "Wrong translation (\(c.appLanguage))", fields: [
            ("language", c.appLanguage),
            ("device-languages", c.deviceLanguageList),
            ("app-version", c.versionLine),
        ])
    }

    static func requestURL(_ c: Context) -> URL {
        issueURL(template: "translation-request.yml", title: "Language request", fields: [
            ("device-languages", c.deviceLanguageList),
        ])
    }

    /// The language's own name for itself when the locale is that language,
    /// otherwise its name in the current locale ("Korean").
    static func languageName(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: code) ?? code
    }

    private static func issueURL(template: String, title: String, fields: [(String, String)]) -> URL {
        var components = URLComponents(url: Paperweight.repositoryURL.appendingPathComponent("issues/new"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "template", value: template),
                                 URLQueryItem(name: "title", value: title)]
            + fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}
