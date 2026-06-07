import XCTest

#if os(iOS)
final class MockFamilyControlsService: FamilyControlsServiceProtocol {
    var isAuthorized: Bool = false
    var shouldThrow: Bool = false
    var authorizationCallCount: Int = 0

    func requestAuthorization() async throws {
        authorizationCallCount += 1
        if shouldThrow { throw URLError(.cancelled) }
        isAuthorized = true
    }
}
#endif
