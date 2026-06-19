#if os(iOS)
import FamilyControls

protocol FamilyControlsServiceProtocol {
    var isAuthorized: Bool { get }
    func requestAuthorization() async throws
}
#endif
