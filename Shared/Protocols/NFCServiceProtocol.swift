#if os(iOS)
import Foundation

protocol NFCServiceProtocol {
    func readTagUID() async throws -> String
}
#endif
