import Foundation

/// A calendar day, or an inclusive run of days, on which the weekly grid is
/// replaced by a whole-day treatment. Exceptions never overlap; the mutation
/// API on `PaperweightConfig` enforces that, so the resolver never ranks them.
struct DayException: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var firstDay: DayKey
    var lastDay: DayKey
    var treatment: Treatment
    /// Optional in the UI; "" when empty. At most 40 characters, trimmed.
    var note: String = ""
    var createdAt: Date = Date()

    enum Treatment: Codable, Equatable {
        case openAllDay
        case quietAllDay
        /// 0 = Sunday … 6 = Saturday, matching the grid's day index.
        case likeWeekday(Int)
    }

    init(id: UUID = UUID(), firstDay: DayKey, lastDay: DayKey, treatment: Treatment,
         note: String = "", createdAt: Date = Date()) {
        self.id = id; self.firstDay = firstDay; self.lastDay = lastDay
        self.treatment = treatment; self.note = note; self.createdAt = createdAt
    }

    func covers(_ day: DayKey) -> Bool { firstDay <= day && day <= lastDay }

    func overlaps(_ other: DayException) -> Bool {
        firstDay <= other.lastDay && other.firstDay <= lastDay
    }

    func dayCount(calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: firstDay.date(calendar: calendar),
                                 to: lastDay.date(calendar: calendar)).day ?? 0) + 1
    }
}
