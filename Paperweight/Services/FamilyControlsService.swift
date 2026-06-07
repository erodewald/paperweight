import FamilyControls

final class FamilyControlsService: FamilyControlsServiceProtocol {
    private let center = AuthorizationCenter.shared

    var isAuthorized: Bool {
        center.authorizationStatus == .approved
    }

    func requestAuthorization() async throws {
        try await center.requestAuthorization(for: .individual)
    }
}
