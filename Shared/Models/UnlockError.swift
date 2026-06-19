#if os(iOS)
import Foundation

enum UnlockError: LocalizedError {
    case noTagRegistered
    case tagMismatch

    var errorDescription: String? {
        switch self {
        case .noTagRegistered: return "No NFC token registered. Set one up in settings."
        case .tagMismatch: return "That token wasn't recognized."
        }
    }
}
#endif
