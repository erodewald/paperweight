#if os(iOS)
import SwiftUI
import FamilyControls

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var config: PaperweightConfig
    @Published var error: Error?

    private let configStore: ConfigStore
    private let familyService: FamilyControlsServiceProtocol
    private let restrictionService: RestrictionService

    init(
        configStore: ConfigStore = ConfigStore(),
        familyService: FamilyControlsServiceProtocol,
        restrictionService: RestrictionService = RestrictionService()
    ) {
        self.configStore = configStore
        self.familyService = familyService
        self.restrictionService = restrictionService
        self.config = configStore.load()
        enforceCoolOffExpiry()
    }

    func setEnabled(_ enabled: Bool) async {
        do {
            if enabled && !familyService.isAuthorized {
                try await familyService.requestAuthorization()
            }
            config.isEnabled = enabled
            // A fresh activation clears any pending tokenless-unlock request.
            if enabled { config.unlockRequestedAt = nil }
            try configStore.save(config)
            syncRestrictions()
        } catch {
            self.error = error
        }
    }

    func disablePaperweight() async throws {
        config.isEnabled = false
        config.unlockRequestedAt = nil
        try configStore.save(config)
        restrictionService.removeAll()
    }

    func saveSelection() {
        try? configStore.save(config)
        syncRestrictions()
    }

    // MARK: Cool-off unlock (tokenless)

    /// Whether a tokenless unlock is currently counting down.
    var isCoolOffPending: Bool { config.unlockRequestedAt != nil }

    /// Starts the cool-off countdown; Paperweight keeps enforcing until it
    /// elapses, then disables automatically.
    func requestCoolOffUnlock() {
        guard config.unlockRequestedAt == nil else { return }
        config.unlockRequestedAt = Date()
        try? configStore.save(config)
    }

    /// Cancels a pending cool-off unlock (e.g. the token turned up).
    func cancelCoolOffUnlock() {
        config.unlockRequestedAt = nil
        try? configStore.save(config)
    }

    /// Brings the shield in line with the current config: lifted when disabled
    /// or inside a free window, applied otherwise. Safe to call any time.
    func syncRestrictions() {
        enforceCoolOffExpiry()
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

    /// If a requested cool-off unlock has elapsed, disable Paperweight.
    private func enforceCoolOffExpiry() {
        guard config.isEnabled, let release = config.coolOffReleaseDate else { return }
        if Date() >= release {
            config.isEnabled = false
            config.unlockRequestedAt = nil
            try? configStore.save(config)
            restrictionService.removeAll()
        }
    }
}
#endif
