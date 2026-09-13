import Foundation

enum Paperweight {
    static let appGroupID = "group.media.baltar.paperweight"
    static let activityName = "dailySchedule"
    static let storeName = "paperweight"
    static let defaultUnlockDuration: TimeInterval = 15 * 60

    /// Where translation feedback goes; the app never talks to it, it opens URLs.
    static let repositoryURL = URL(string: "https://github.com/erodewald/paperweight")!
}
