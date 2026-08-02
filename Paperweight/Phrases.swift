import Foundation

/// Curated poetic lines for the italic (Spectral) text around the app. Calm,
/// warm, and nudging you outward — never nagging.
enum Phrases {

    /// Placement nudge on the token buying guide.
    static let placement: [String] = [
        "Put it somewhere a little inconvenient — another room, inside a book, under a shelf. The way out should take a moment of intention.",
        "Hide it where reaching it means standing up — across the house, in a drawer, behind a door. Friction is the feature.",
        "The harder it is to tap, the easier it is to stay present. Pick a spot that asks something of you."
    ]

    /// A stable-per-day pick (won't flicker within a session, varies over days).
    static func ofTheDay(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return lines[day % lines.count]
    }
}
