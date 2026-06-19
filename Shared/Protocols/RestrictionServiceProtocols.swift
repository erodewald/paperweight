#if os(iOS)
import ManagedSettings
import FamilyControls

protocol ManagedSettingsStoreProtocol {
    func setShield(applications: Set<ApplicationToken>?)
    func setShield(applicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>?)
    func setShield(webDomains: Set<WebDomainToken>?)
}
#endif
