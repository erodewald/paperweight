import Foundation
import DeviceActivity
import ManagedSettings

@objc(PaperweightMonitor)
class PaperweightMonitor: DeviceActivityMonitor {
    private let managedStore = ManagedSettingsStore(named: .init(Paperweight.storeName))
    private let configStore = ConfigStore()
    private let widgetStore = WidgetSnapshotStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        syncShield()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        syncShield()
    }

    /// Sets the shield to match the current moment: free if we're inside a free
    /// window for today's weekday, restricted otherwise. Because every free
    /// window registers a daily-repeating schedule, this runs at each boundary;
    /// the weekday check inside `isFree(at:)` makes days with no free window a
    /// no-op (shield stays applied).
    private func syncShield() {
        var config = configStore.load()
        let service = RestrictionService(store: managedStore)
        defer { widgetStore.write(config: config) }

        // Cool-off unlock: if a tokenless unlock was requested and its delay has
        // elapsed, disable everything. This runs in the extension — which is
        // never shielded — so it releases even if the app itself was blocked.
        // The daily heartbeat guarantees it runs.
        if config.isEnabled, let release = config.coolOffReleaseDate, Date() >= release {
            config.isEnabled = false
            config.unlockRequestedAt = nil
            config.unlockExpiresAt = nil
            try? configStore.save(config)
            service.removeAll()
            return
        }

        // A timed NFC unlock that outlived the app: clear it once it has closed,
        // so the boundary we're handling re-applies the shield instead of the
        // stale expiry keeping it lifted.
        if let expiry = config.unlockExpiresAt, Date() >= expiry {
            config.unlockExpiresAt = nil
            try? configStore.save(config)
        }

        guard config.isEnabled, !config.isUnlocked() else {
            service.removeAll()
            return
        }

        if let schedule = config.schedule, !schedule.isEmpty, schedule.isFree(at: Date()) {
            service.removeAll()
        } else {
            #if os(iOS)
            service.apply(selection: config.selection, overrides: config.appOverrides)
            #endif
        }
    }
}
