#if os(iOS)
import Foundation
import ManagedSettings
import FamilyControls

// Protocol lives in Shared/Protocols/RestrictionServiceProtocols.swift
final class MockManagedSettingsStore: ManagedSettingsStoreProtocol {
    var shieldApplicationsWasSet = false
    var shieldWasCleared = false
    var applyCallCount = 0
    var lastCategories: ShieldSettings.ActivityCategoryPolicy<Application>?
    var lastWebDomains: Set<WebDomainToken>?

    func setShield(applications: Set<ApplicationToken>?) {
        applyCallCount += 1
        if applications == nil {
            shieldWasCleared = true
        } else {
            shieldApplicationsWasSet = true
        }
    }

    func setShield(applicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>?) {
        lastCategories = applicationCategories
    }

    func setShield(webDomains: Set<WebDomainToken>?) {
        lastWebDomains = webDomains
    }
}
#endif
