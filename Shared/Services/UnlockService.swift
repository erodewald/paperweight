#if os(iOS)
import Foundation

@MainActor
final class UnlockService: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var unlockExpiresAt: Date? = nil

    private let configStore: ConfigStore
    private let nfcService: NFCServiceProtocol
    private let restrictionService: RestrictionService
    private let widgetStore: WidgetSnapshotStore
    private let scheduleService: ScheduleService
    private var relockTask: Task<Void, Never>?

    init(
        configStore: ConfigStore = ConfigStore(),
        nfcService: NFCServiceProtocol,
        restrictionService: RestrictionService = RestrictionService(),
        widgetStore: WidgetSnapshotStore = WidgetSnapshotStore(),
        scheduleService: ScheduleService = .shared
    ) {
        self.configStore = configStore
        self.nfcService = nfcService
        self.restrictionService = restrictionService
        self.widgetStore = widgetStore
        self.scheduleService = scheduleService
    }

    func registerTag() async throws {
        let uid = try await nfcService.readTagUID()
        var config = configStore.load()
        config.registeredNFCTagUID = uid
        try configStore.save(config)
    }

    func unlock() async throws {
        let config = configStore.load()
        guard let registeredUID = config.registeredNFCTagUID else {
            throw UnlockError.noTagRegistered
        }
        let scannedUID = try await nfcService.readTagUID()
        guard scannedUID == registeredUID else {
            throw UnlockError.tagMismatch
        }
        grantUnlock(duration: config.unlockDuration)
    }

    func verifyTag() async throws {
        let config = configStore.load()
        guard let registeredUID = config.registeredNFCTagUID else {
            throw UnlockError.noTagRegistered
        }
        let scannedUID = try await nfcService.readTagUID()
        guard scannedUID == registeredUID else {
            throw UnlockError.tagMismatch
        }
    }

    func grantUnlock(duration: TimeInterval) {
        let expiry = Date().addingTimeInterval(duration)
        restrictionService.removeAll()
        isUnlocked = true
        unlockExpiresAt = expiry

        // Persist the expiry, not just the in-memory countdown. Two reasons:
        // the widget can't see @Published state, and if the app is killed
        // mid-unlock the in-process timer dies with it — on next launch
        // `resumeIfUnlocked()` re-arms from this date instead of leaving the
        // shield lifted until the monitor's next boundary.
        var config = configStore.load()
        config.unlockExpiresAt = expiry
        try? configStore.save(config)
        widgetStore.write(config: config)

        // The in-process timer below only fires while the app is alive and in
        // the foreground — and the whole point of an unlock is to go use other
        // apps. The monitor extension re-shields at the expiry regardless.
        scheduleService.sync(config: config)
        scheduleRelock(after: duration)
    }

    func relock() {
        relockTask?.cancel()
        relockTask = nil
        isUnlocked = false
        unlockExpiresAt = nil

        var config = configStore.load()
        config.unlockExpiresAt = nil
        try? configStore.save(config)

        syncRestrictions()
        widgetStore.write(config: config)
        scheduleService.sync(config: config)
    }

    /// Re-establishes an unlock that outlived the process — call on launch and on
    /// foreground. Expired unlocks re-lock immediately; live ones get their timer
    /// back for whatever time is left.
    func resumeIfUnlocked() {
        let config = configStore.load()
        guard let expiry = config.unlockExpiresAt else { return }
        guard Date() < expiry else { relock(); return }

        isUnlocked = true
        unlockExpiresAt = expiry
        restrictionService.removeAll()
        scheduleRelock(after: expiry.timeIntervalSinceNow)
    }

    private func scheduleRelock(after delay: TimeInterval) {
        relockTask?.cancel()
        relockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled else { return }
            await self?.relock()
        }
    }

    /// Re-applies the shield to match current state: lifted when Paperweight is
    /// off, mid-unlock, or inside a free window; restricted otherwise.
    private func syncRestrictions() {
        let config = configStore.load()
        guard config.isEnabled, !config.isUnlocked() else {
            restrictionService.removeAll()
            return
        }
        if let schedule = config.schedule, !schedule.isEmpty, schedule.isFree(at: Date()) {
            restrictionService.removeAll()
        } else {
            restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
        }
    }
}
#endif
