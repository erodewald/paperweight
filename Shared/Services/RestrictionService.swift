#if os(iOS)
import ManagedSettings
import FamilyControls

extension ManagedSettingsStore: ManagedSettingsStoreProtocol {
    func setShield(applications: Set<ApplicationToken>?) {
        shield.applications = applications
    }
    func setShield(applicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>?) {
        shield.applicationCategories = applicationCategories
    }
    func setShield(webDomains: Set<WebDomainToken>?) {
        shield.webDomains = webDomains
    }
}

final class RestrictionService {
    private let store: ManagedSettingsStoreProtocol

    init(store: ManagedSettingsStoreProtocol = ManagedSettingsStore(named: .init(Paperweight.storeName))) {
        self.store = store
    }

    func apply(selection: FamilyActivitySelection, overrides: [AppScheduleOverride]) {
        var blocked = selection.applicationTokens
        let freeTokens = Set(overrides.filter { $0.mode == .alwaysFree }.map(\.token))
        blocked.subtract(freeTokens)
        let alwaysBlockedTokens = Set(overrides.filter { $0.mode == .alwaysBlocked }.map(\.token))
        blocked.formUnion(alwaysBlockedTokens)
        store.setShield(applications: blocked.isEmpty ? nil : blocked)

        let categories = selection.categoryTokens
        store.setShield(applicationCategories: categories.isEmpty ? nil : .specific(categories, except: []))

        let domains = selection.webDomainTokens
        store.setShield(webDomains: domains.isEmpty ? nil : domains)
    }

    func removeAll() {
        store.setShield(applications: nil)
        store.setShield(applicationCategories: nil)
        store.setShield(webDomains: nil)
    }
}
#endif
