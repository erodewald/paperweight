#if os(iOS)
import Foundation

enum NFCError: LocalizedError {
    case notSupported
    case sessionFailed(Error)
    case noTagFound
    case readFailed
    case busy

    var errorDescription: String? {
        switch self {
        case .notSupported: return "NFC is not supported on this device."
        case .sessionFailed(let e): return "NFC session failed: \(e.localizedDescription)"
        case .noTagFound: return "No NFC tag found."
        case .readFailed: return "Could not read the NFC tag."
        case .busy: return "A scan is already in progress. Try again in a moment."
        }
    }
}
#endif
