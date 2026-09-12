#if os(iOS)
import Foundation
import FamilyControls

/// Projects a `PaperweightConfig` down to the token-free `WidgetSnapshot`.
///
/// Deliberately NOT compiled into the widget target — this is the one place the
/// two worlds meet, and it lives on the app/monitor side of the wall so the
/// widget never links FamilyControls.
extension WidgetSnapshot {
    init(config: PaperweightConfig, isScreenTimeAuthorized: Bool) {
        self.init()
        isArmed = config.isEnabled
        // Mirrors HomeViewModel.hasAppsSelected. Spelled out rather than using
        // the app target's `selection.isEmpty` helper, since the monitor
        // extension compiles this file too and doesn't have that extension.
        let selection = config.selection
        hasSelection = !(selection.applicationTokens.isEmpty
                         && selection.categoryTokens.isEmpty
                         && selection.webDomainTokens.isEmpty)
        hasNFCToken = config.registeredNFCTagUID != nil
        hasRecoveryCodes = config.recoveryCodes.contains { !$0.isUsed }
        self.isScreenTimeAuthorized = isScreenTimeAuthorized
        schedule = config.schedule
        coolOffReleaseDate = config.coolOffReleaseDate
        coolOffRequestedAt = config.unlockRequestedAt
        unlockExpiresAt = config.unlockExpiresAt
        unlockDuration = config.unlockDuration
        dayExceptions = config.dayExceptions
    }
}

extension WidgetSnapshotStore {
    /// Writes a snapshot for `config`.
    ///
    /// `isScreenTimeAuthorized` is optional because the monitor extension has no
    /// business asking `AuthorizationCenter` — it only ever runs when
    /// authorization exists. Passing nil keeps whatever the app last observed
    /// (defaulting to authorized, since a snapshot is only ever written after
    /// the config has been saved at least once).
    func write(config: PaperweightConfig, isScreenTimeAuthorized: Bool? = nil) {
        let authorized = isScreenTimeAuthorized ?? load()?.isScreenTimeAuthorized ?? true
        save(WidgetSnapshot(config: config, isScreenTimeAuthorized: authorized))
    }
}
#endif
