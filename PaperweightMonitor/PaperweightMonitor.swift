import Foundation
import DeviceActivity
import ManagedSettings

@objc(PaperweightMonitor)
class PaperweightMonitor: DeviceActivityMonitor {
    private let managedStore = ManagedSettingsStore(named: .init(Paperweight.storeName))
    private let configStore = ConfigStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Free window started — lift restrictions
        let service = RestrictionService(store: managedStore)
        service.removeAll()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Free window ended — apply restrictions
        let config = configStore.load()
        guard config.isEnabled else { return }
        let service = RestrictionService(store: managedStore)
        #if os(iOS)
        service.apply(selection: config.selection, overrides: config.appOverrides)
        #endif
    }
}
