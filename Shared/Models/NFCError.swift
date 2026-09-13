#if os(iOS)
import Foundation

enum NFCError: LocalizedError {
    case notSupported
    case sessionFailed(Error)
    case noTagFound
    case readFailed
    case busy

    var errorDescription: String? {
        let b = L10n.bundle
        switch self {
        case .notSupported: return String(localized: "NFC is not supported on this device.", bundle: b)
        case .sessionFailed(let e): return String(localized: "NFC session failed: \(e.localizedDescription)", bundle: b, comment: "A system error message follows")
        case .noTagFound: return String(localized: "No NFC tag found.", bundle: b)
        case .readFailed: return String(localized: "Could not read the NFC tag.", bundle: b)
        case .busy: return String(localized: "A scan is already in progress. Try again in a moment.", bundle: b)
        }
    }
}
#endif
