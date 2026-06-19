#if os(iOS)
import ManagedSettings
import FamilyControls

// SAFETY INVARIANT — do not break:
// We ONLY ever set `shield.applications`, `shield.applicationCategories`, and
// `shield.webDomains`. We must NEVER set `application.denyAppRemoval` (or any
// other ManagedSettings restriction). That guarantees the user can always
// delete Paperweight from the Home screen, which revokes our Family Controls
// authorization and makes iOS clear every shield we applied. Deleting the app
// is therefore an unconditional recovery path — the phone can't be bricked.

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
