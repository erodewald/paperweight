import Foundation

/// The artwork shown while apps are quiet. Purely cosmetic — it never affects
/// what is restricted. The wording comes from the motion study, which names
/// each style by what it does rather than how it looks.
enum QuietTheme: String, Codable, CaseIterable, Identifiable {
    case simple
    case diorama
    case overgrown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return String(localized: "Simple", bundle: L10n.bundle, comment: "Quiet theme name")
        case .diorama: return String(localized: "Diorama", bundle: L10n.bundle, comment: "Quiet theme name")
        case .overgrown: return String(localized: "Overgrown", bundle: L10n.bundle, comment: "Quiet theme name")
        }
    }

    var blurb: String {
        switch self {
        case .simple: return String(localized: "The words carry the weight.", bundle: L10n.bundle, comment: "Quiet theme description")
        case .diorama: return String(localized: "A forest sprouts behind the words.", bundle: L10n.bundle, comment: "Quiet theme description")
        case .overgrown: return String(localized: "The screen is claimed at its corners.", bundle: L10n.bundle, comment: "Quiet theme description")
        }
    }

    /// Whether this theme draws anything. Simple is a line of type and nothing
    /// else, so the picker gives it a plain row rather than an empty preview.
    var hasArtwork: Bool { self != .simple }
}
