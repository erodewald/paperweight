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
        return config
    }
}
