import Foundation
#if os(iOS)
import FamilyControls
#endif

struct PaperweightConfig: Codable {
    var isEnabled: Bool = false
    var schedule: PaperweightSchedule? = nil
    var unlockDuration: TimeInterval = Paperweight.defaultUnlockDuration
    var registeredNFCTagUID: String? = nil
    var recoveryCodes: [RecoveryCode] = []
    // Cool-off unlock: if the token is lost, the user can request a timed unlock
    // that releases after this many days — a "sleep on it" delay that curbs
    // impulsive removal while guaranteeing they're never locked out for long.
    var coolOffDays: Int = 1
    // When non-nil, a tokenless unlock has been requested; Paperweight disables
    // itself once `coolOffDays` have elapsed from this moment.
    var unlockRequestedAt: Date? = nil
    // When non-nil, a timed NFC unlock is running and the shield stays lifted
    // until this moment. Persisted rather than held in memory so the widget and
    // the monitor extension can both see it, and so killing the app mid-unlock
    // can't strand the shield in a lifted state.
    var unlockExpiresAt: Date? = nil

    /// The moment a pending cool-off unlock will release, if one is requested.
    var coolOffReleaseDate: Date? {
        unlockRequestedAt.map { $0.addingTimeInterval(Double(coolOffDays) * 86400) }
    }

    /// True while a timed NFC unlock is still running.
    func isUnlocked(at date: Date = Date()) -> Bool {
        guard let expiry = unlockExpiresAt else { return false }
        return date < expiry
    }
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
        registeredNFCTagUID = try c.decodeIfPresent(String.self, forKey: .registeredNFCTagUID)
        recoveryCodes = try c.decodeIfPresent([RecoveryCode].self, forKey: .recoveryCodes) ?? []
        coolOffDays = try c.decodeIfPresent(Int.self, forKey: .coolOffDays) ?? 1
        unlockRequestedAt = try c.decodeIfPresent(Date.self, forKey: .unlockRequestedAt)
        unlockExpiresAt = try c.decodeIfPresent(Date.self, forKey: .unlockExpiresAt)
        #if os(iOS)
        selection = try c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection) ?? .init()
        appOverrides = try c.decodeIfPresent([AppScheduleOverride].self, forKey: .appOverrides) ?? []
        #endif
    }
}

