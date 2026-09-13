#if os(iOS)
import Foundation

enum UnlockError: LocalizedError {
    case noTagRegistered
    case tagMismatch

    var errorDescription: String? {
        switch self {
        case .noTagRegistered: return String(localized: "No NFC token registered. Set one up in settings.", bundle: L10n.bundle)
        case .tagMismatch: return String(localized: "That token wasn't recognized.", bundle: L10n.bundle)
        }
    }
}
#endif
