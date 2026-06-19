import Foundation

/// Curated poetic lines for the italic (Spectral) text around the app. Calm,
/// warm, and nudging you outward — never nagging.
enum Phrases {

    /// Brick-mode encouragement, shown under the orb while quiet.
    static let quiet: [String] = [
        "Nothing here needs you right now. That's the gift.",
        "The world is still turning without the scroll.",
        "Let it be heavy. Let it be quiet.",
        "You set this down on purpose. Well done.",
        "Go find some sky.",
        "The grass is real. Go touch it.",
        "Somewhere outside, the light is good.",
        "Look up — the world is wider than this screen.",
        "Be where your feet are.",
        "Boredom is where the good ideas hide.",
        "Let your eyes rest on something far away.",
        "Call someone. Walk somewhere. Breathe.",
        "You won't remember the scroll. You'll remember the walk.",
        "Go make something a screen never could.",
        "The best feed is the one out your window."
    ]

    /// Closing line at the bottom of the Home settings screen.
    static let homeFooter: [String] = [
        "Put it down. The world keeps turning.",
        "Less screen. More of everything else.",
        "The quiet is yours whenever you want it.",
        "Go be somewhere real.",
        "Set it down. Pick your life back up.",
        "Touch grass. It's still out there.",
        "Your attention is worth more than this."
    ]

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
