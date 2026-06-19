#if os(iOS)
import Foundation

@MainActor
final class UnlockService: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var unlockExpiresAt: Date? = nil

    private let configStore: ConfigStore
    private let nfcService: NFCServiceProtocol
    private let restrictionService: RestrictionService
    private var relockTask: Task<Void, Never>?

    init(
        configStore: ConfigStore = ConfigStore(),
        nfcService: NFCServiceProtocol,
        restrictionService: RestrictionService = RestrictionService()
    ) {
        self.configStore = configStore
        self.nfcService = nfcService
        self.restrictionService = restrictionService
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
        let config = configStore.load()
        restrictionService.removeAll()
        isUnlocked = true
        unlockExpiresAt = Date().addingTimeInterval(duration)

        relockTask?.cancel()
        relockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self?.relock()
        }
        _ = config
    }

    func relock() {
        relockTask?.cancel()
        relockTask = nil
        isUnlocked = false
        unlockExpiresAt = nil
        syncRestrictions()
    }

    /// Re-applies the shield to match current state: lifted when Paperweight is
    /// off or inside a free window, restricted otherwise.
    private func syncRestrictions() {
        let config = configStore.load()
        guard config.isEnabled else {
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
