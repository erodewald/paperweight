#if os(iOS)
import Foundation

enum UnlockError: LocalizedError {
    case noTagRegistered
    case tagMismatch
    case watchConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .noTagRegistered: return "No NFC token registered. Set one up in settings."
        case .tagMismatch: return "That token wasn't recognized."
        case .watchConfirmationRequired: return "Waiting for Watch confirmation."
        }
    }
}
#endif
