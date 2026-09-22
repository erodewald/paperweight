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

// MARK: - Deep link

extension DayException {
    /// Host of the `paperweight://` link that opens this day in the app. One
    /// host for all planned days; the id rides in the path.
    static let deepLinkHost = "planned-day"

    /// `paperweight://planned-day/<id>` — what a widget opens while this day is
    /// deciding the schedule, and what Home follows to land on the row itself.
    var deepLink: URL {
        URL(string: "paperweight://\(Self.deepLinkHost)/\(id.uuidString)")!
    }

    /// The id inside a `deepLink`, or nil for any other URL.
    static func plannedDayID(from url: URL) -> UUID? {
        guard url.scheme == "paperweight", url.host == deepLinkHost else { return nil }
        // pathComponents is ["/", "<id>"]; anything else isn't ours.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        return UUID(uuidString: parts[0])
    }
}
