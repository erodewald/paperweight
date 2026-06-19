import Foundation
#if os(iOS)
import FamilyControls
#endif

struct PaperweightConfig: Codable {
    var isEnabled: Bool = false
    var schedule: PaperweightSchedule? = nil
    var unlockDuration: TimeInterval = Paperweight.defaultUnlockDuration
    var requireWatchConfirmation: Bool = true
    var registeredNFCTagUID: String? = nil
    var recoveryCodes: [RecoveryCode] = []
    var maxLockedDays: Int? = nil
    var lockedAt: Date? = nil
    #if os(iOS)
    var selection: FamilyActivitySelection = .init()
    var appOverrides: [AppScheduleOverride] = []
    #endif

    // Custom decoder for forward/backward compatibility: new keys fall back to defaults
    // so existing saved configs don't get wiped when we add fields.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        // Tolerant of the legacy single-window schedule shape: a failed decode
        // (old format) simply resets the schedule rather than throwing.
        schedule = (try? c.decodeIfPresent(PaperweightSchedule.self, forKey: .schedule)) ?? nil
        unlockDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .unlockDuration) ?? Paperweight.defaultUnlockDuration
        requireWatchConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requireWatchConfirmation) ?? true
        registeredNFCTagUID = try c.decodeIfPresent(String.self, forKey: .registeredNFCTagUID)
        recoveryCodes = try c.decodeIfPresent([RecoveryCode].self, forKey: .recoveryCodes) ?? []
        maxLockedDays = try c.decodeIfPresent(Int.self, forKey: .maxLockedDays)
        lockedAt = try c.decodeIfPresent(Date.self, forKey: .lockedAt)
        #if os(iOS)
        selection = try c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection) ?? .init()
        appOverrides = try c.decodeIfPresent([AppScheduleOverride].self, forKey: .appOverrides) ?? []
        #endif
    }
}

