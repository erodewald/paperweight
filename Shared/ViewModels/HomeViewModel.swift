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
    }

    func setEnabled(_ enabled: Bool) async {
        do {
            if enabled && !familyService.isAuthorized {
                try await familyService.requestAuthorization()
            }
            config.isEnabled = enabled
            try configStore.save(config)
            if enabled {
                restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
            } else {
                restrictionService.removeAll()
            }
        } catch {
            self.error = error
        }
    }

    func saveSelection() {
        try? configStore.save(config)
        if config.isEnabled {
            restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
        }
    }
}
#endif
