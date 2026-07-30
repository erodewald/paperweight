import SwiftUI

extension WidgetState {
    /// Accent for the ring, glyph and headline.
    ///
    /// Sage is reserved for quiet — the state the product wants you in. A free
    /// window gets the dimmer moss on purpose: it's permitted, not celebrated.
    /// Clay marks every exit (timed unlock, cool-off), matching the app.
    var accent: Color {
        switch self {
        case .quietBounded, .quietOpen: return PW.sage
        case .freeWindow: return PW.moss
        case .timedUnlock, .coolOff: return PW.clay
        case .notAuthorized: return PW.warn
        case .off, .nothingChosen, .noWayBack, .unwritten: return PW.textFaint
        }
    }

    /// States that draw a dimmed orb and no live ring — nothing is running.
    var isDormant: Bool {
        switch self {
        case .off, .nothingChosen, .noWayBack, .notAuthorized, .unwritten: return true
        case .quietBounded, .quietOpen, .freeWindow, .timedUnlock, .coolOff: return false
        }
    }

    /// The headline colour: faint for dormant states so "Off" recedes rather
    /// than announcing itself.
    var headlineColor: Color {
        switch self {
        case .quietBounded, .quietOpen, .freeWindow: return PW.textPrimary
        case .timedUnlock, .coolOff: return PW.clay
        case .off, .nothingChosen, .noWayBack, .unwritten: return PW.textFaint
        case .notAuthorized: return PW.warn
        }
    }
}
