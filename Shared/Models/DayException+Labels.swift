import Foundation

extension DayException.Treatment {
    /// The pill text. Sentence case; the word is "quiet", never "blocked".
    var title: String {
        switch self {
        case .openAllDay: return "Open all day"
        case .quietAllDay: return "Quiet all day"
        case .likeWeekday(let w):
            return "Like \(DayException.weekdayNames[((w % 7) + 7) % 7])"
        }
    }
}

extension DayException {
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "Fri, Sep 18" or "Mon, Sep 21 – Fri, Sep 25".
    func dateLabel(calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated).month(.abbreviated).day()
        let first = firstDay.date(calendar: calendar).formatted(style)
        guard firstDay != lastDay else { return first }
        return "\(first) – \(lastDay.date(calendar: calendar).formatted(style))"
    }

    /// Compact form for the Home row value: a bare weekday when the day is
    /// within the next six days ("Fri"), otherwise "Sep 18"; ranges as
    /// "Sep 21–25" or "Sep 28 – Oct 2".
    func shortDateLabel(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let monthDay = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
        let firstDate = firstDay.date(calendar: calendar)
        if firstDay == lastDay {
            let today = DayKey(now, calendar: calendar)
            let days = calendar.dateComponents([.day], from: today.date(calendar: calendar), to: firstDate).day ?? 7
            if (0...6).contains(days) {
                return firstDate.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated))
            }
            return firstDate.formatted(monthDay)
        }
        let lastDate = lastDay.date(calendar: calendar)
        if firstDay.month == lastDay.month && firstDay.year == lastDay.year {
            return "\(firstDate.formatted(monthDay))–\(lastDay.day)"
        }
        return "\(firstDate.formatted(monthDay)) – \(lastDate.formatted(monthDay))"
    }
}

extension PaperweightConfig {
    /// The Home row's trailing value: the next planned day and how many are
    /// upcoming, or nil when there are none.
    func dayExceptionsRowValue(now: Date = Date(), calendar: Calendar = .current,
                               locale: Locale = .current) -> String? {
        let upcoming = upcomingDayExceptions(now: now, calendar: calendar)
        guard let next = upcoming.first else { return nil }
        return "\(next.shortDateLabel(now: now, calendar: calendar, locale: locale)) · \(upcoming.count) upcoming"
    }
}
