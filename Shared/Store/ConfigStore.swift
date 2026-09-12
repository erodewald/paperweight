import Foundation

final class ConfigStore {
    private let defaults: UserDefaults
    private let key = "paperweight.config"

    init(defaults: UserDefaults = UserDefaults(suiteName: Paperweight.appGroupID)!) {
        self.defaults = defaults
    }

    func save(_ config: PaperweightConfig) throws {
        let data = try JSONEncoder().encode(config)
        defaults.set(data, forKey: key)
    }

    func load() -> PaperweightConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(PaperweightConfig.self, from: data)
        else { return PaperweightConfig() }

        var promoted = config
        promoted.promotePendingScheduleIfDue()
        // Only a due promotion clears pendingSchedule here, so this also tells
        // us whether anything actually changed and needs persisting.
        var changed = config.pendingSchedule != nil && promoted.pendingSchedule == nil
        if promoted.pruneDayExceptions() { changed = true }
        if changed {
            // A failure to persist must not prevent returning the promoted,
            // pruned config — worst case it's recomputed on the next load.
            try? save(promoted)
        }
        return promoted
    }
}
