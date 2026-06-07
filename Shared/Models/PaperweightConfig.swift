import Foundation
#if os(iOS)
import FamilyControls
#endif

struct PaperweightConfig: Codable {
    var isEnabled: Bool = false
    var schedule: AllowSchedule? = nil
    var unlockDuration: TimeInterval = Paperweight.defaultUnlockDuration
    var requireWatchConfirmation: Bool = true
    var registeredNFCTagUID: String? = nil
    #if os(iOS)
    var selection: FamilyActivitySelection = .init()
    var appOverrides: [AppScheduleOverride] = []
    #endif
}

struct AllowSchedule: Codable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var weekdays: Set<Int>    // 1 = Sunday … 7 = Saturday (Calendar convention)

    var isValid: Bool {
        let startTotal = startHour * 60 + startMinute
        let endTotal = endHour * 60 + endMinute
        return endTotal > startTotal && !weekdays.isEmpty
    }

    func contains(hour: Int, minute: Int) -> Bool {
        guard isValid else { return false }
        let t = hour * 60 + minute
        let s = startHour * 60 + startMinute
        let e = endHour * 60 + endMinute
        return t >= s && t < e
    }
}
