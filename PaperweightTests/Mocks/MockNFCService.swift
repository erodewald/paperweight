#if os(iOS)
import Foundation

final class MockNFCService: NFCServiceProtocol {
    var mockUID: String = "AABBCCDD"
    var shouldThrow: Bool = false
    var callCount: Int = 0

    func readTagUID() async throws -> String {
        callCount += 1
        if shouldThrow { throw NFCError.notSupported }
        return mockUID
    }
}
#endif
