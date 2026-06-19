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
        checkTimeBasedFailsafe()
    }

    func setEnabled(_ enabled: Bool) async {
        do {
            if enabled && !familyService.isAuthorized {
                try await familyService.requestAuthorization()
            }
            config.isEnabled = enabled
            config.lockedAt = enabled ? Date() : nil
            try configStore.save(config)
            syncRestrictions()
        } catch {
            self.error = error
        }
    }

    func disablePaperweight() async throws {
        config.isEnabled = false
        config.lockedAt = nil
        try configStore.save(config)
        restrictionService.removeAll()
    }

    func saveSelection() {
        try? configStore.save(config)
        syncRestrictions()
    }

    /// Brings the shield in line with the current config: lifted when disabled
    /// or inside a free window, applied otherwise. Safe to call any time.
    func syncRestrictions() {
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

    private func checkTimeBasedFailsafe() {
        guard config.isEnabled,
              let maxDays = config.maxLockedDays,
              let lockedAt = config.lockedAt else { return }
        if Date().timeIntervalSince(lockedAt) > Double(maxDays) * 86400 {
            config.isEnabled = false
            config.lockedAt = nil
            try? configStore.save(config)
            restrictionService.removeAll()
        }
    }
}
#endif
