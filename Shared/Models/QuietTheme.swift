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
        case .simple: return "Simple"
        case .diorama: return "Diorama"
        case .overgrown: return "Overgrown"
        }
    }

    var blurb: String {
        switch self {
        case .simple: return "The words carry the weight."
        case .diorama: return "A forest sprouts behind the words."
        case .overgrown: return "The screen is claimed at its corners."
        }
    }

    /// Whether this theme draws anything. Simple is a line of type and nothing
    /// else, so the picker gives it a plain row rather than an empty preview.
    var hasArtwork: Bool { self != .simple }
}
