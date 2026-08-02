#if DEBUG
import SwiftUI

/// Development-only switches, persisted so they survive a relaunch.
///
/// This entire file is compiled out of Release builds. Paperweight's whole
/// premise is that the way out is a physical token; a bypass that shipped
/// would quietly undo that, so it must never exist outside a debug build.
final class DebugSettings: ObservableObject {
    static let shared = DebugSettings()

    private static let forceQuietKey = "debug.forceQuiet"
    private static let forceArmedKey = "debug.forceArmed"

    /// Renders the quiet screen regardless of schedule or armed state.
    /// Presentation only — nothing is actually restricted by this.
    @Published var forceQuiet: Bool {
        didSet { UserDefaults.standard.set(forceQuiet, forKey: Self.forceQuietKey) }
    }

    /// Makes the UI show the screens that only appear once Paperweight is armed.
    /// Presentation only — it never arms anything and never restricts an app.
    @Published var forceArmed: Bool {
        didSet { UserDefaults.standard.set(forceArmed, forKey: Self.forceArmedKey) }
    }

    private init() {
        forceQuiet = UserDefaults.standard.bool(forKey: Self.forceQuietKey)
        forceArmed = UserDefaults.standard.bool(forKey: Self.forceArmedKey)
    }
}
#endif
