import Foundation

/// Per-language review state, written by Scripts/translate.py into
/// Shared/Resources/TranslationStatus.json and read once at launch. A language
/// with unreviewed machine translations gets an honest notice in Settings.
struct TranslationStatus: Decodable, Equatable {
    struct Language: Decodable, Equatable {
        var keys: Int
        var needsReview: Int
    }

    var languages: [String: Language]

    static func load(from bundle: Bundle = L10n.bundle) -> TranslationStatus? {
        guard let url = bundle.url(forResource: "TranslationStatus", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TranslationStatus.self, from: data)
    }

    /// True only for a language that ships machine translations nobody has
    /// reviewed yet. The source language and unknown languages are never flagged.
    func needsReview(_ code: String) -> Bool {
        (languages[code]?.needsReview ?? 0) > 0
    }
}
