#if os(iOS)
import ManagedSettings
import FamilyControls

extension ManagedSettingsStore: ManagedSettingsStoreProtocol {
    func setShield(applications: Set<ApplicationToken>?) {
        shield.applications = applications
    }
}

final class RestrictionService {
    private let store: ManagedSettingsStoreProtocol

    init(store: ManagedSettingsStoreProtocol = ManagedSettingsStore(named: .init(Paperweight.storeName))) {
        self.store = store
    }

    func apply(selection: FamilyActivitySelection, overrides: [AppScheduleOverride]) {
        var blocked = selection.applicationTokens
        // Remove alwaysFree apps from the blocked set
        let freeTokens = Set(overrides.filter { $0.mode == .alwaysFree }.map(\.token))
        blocked.subtract(freeTokens)
        // Add alwaysBlocked apps regardless of schedule
        let alwaysBlockedTokens = Set(overrides.filter { $0.mode == .alwaysBlocked }.map(\.token))
        blocked.formUnion(alwaysBlockedTokens)

        store.setShield(applications: blocked.isEmpty ? nil : blocked)
    }

    func removeAll() {
        store.setShield(applications: nil)
    }
}
#endif
