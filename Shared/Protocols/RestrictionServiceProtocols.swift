#if os(iOS)
import ManagedSettings
import FamilyControls

protocol ManagedSettingsStoreProtocol {
    func setShield(applications: Set<ApplicationToken>?)
}
#endif
