import Foundation

/// A calendar date with no time and no zone, so a planned day means the same
/// day across DST changes and travel. Encoded as "YYYY-MM-DD".
struct DayKey: Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1, month: c.month ?? 1, day: c.day ?? 1)
    }

    static func today(calendar: Calendar = .current) -> DayKey {
        DayKey(Date(), calendar: calendar)
    }

    /// The first instant of the day. A well-formed key always resolves; the
    /// `.distantFuture` fallback only matters for a malformed key, since
    /// `Calendar` normalises out-of-range components (month 13 → next January)
    /// rather than returning nil for them.
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantFuture
    }

    func advanced(by days: Int, calendar: Calendar = .current) -> DayKey {
        // Ask the calendar rather than adding 86 400 s, so a 23- or 25-hour
        // DST day is still one day.
        guard let d = calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) else { return self }
        return DayKey(d, calendar: calendar)
    }

    func next(calendar: Calendar = .current) -> DayKey { advanced(by: 1, calendar: calendar) }
    func previous(calendar: Calendar = .current) -> DayKey { advanced(by: -1, calendar: calendar) }

    /// 0 = Sunday … 6 = Saturday, matching `PaperweightSchedule`'s day index.
    func weekdayIndex(calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date(calendar: calendar)) - 1 + 7) % 7
    }

    /// Sunday through Saturday of the week containing `day`, in that order —
    /// the rows of the Home week strip.
    static func week(containing day: DayKey, calendar: Calendar = .current) -> [DayKey] {
        let sunday = day.advanced(by: -day.weekdayIndex(calendar: calendar), calendar: calendar)
        return (0..<7).map { sunday.advanced(by: $0, calendar: calendar) }
    }

    static func < (a: DayKey, b: DayKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: Codable — "YYYY-MM-DD"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "DayKey expects YYYY-MM-DD, got \(raw)"))
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }
}
