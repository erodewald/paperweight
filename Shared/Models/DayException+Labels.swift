import Foundation

extension DayException.Treatment {
    /// The pill text. Sentence case; the word is "quiet", never "blocked".
    func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch self {
        case .openAllDay:
            return String(localized: "Open all day", bundle: L10n.bundle, locale: locale,
                          comment: "Day treatment: apps open the whole day")
        case .quietAllDay:
            return String(localized: "Quiet all day", bundle: L10n.bundle, locale: locale,
                          comment: "Day treatment: apps quiet the whole day")
        case .likeWeekday(let w):
            let name = DayException.weekdayName(w, calendar: calendar, locale: locale)
            return String(localized: "Like \(name)", bundle: L10n.bundle, locale: locale,
                          comment: "Day treatment: use another weekday's schedule; a weekday name follows")
        }
    }
}

extension DayException {
    /// Full weekday name for the app's Sunday-based index, in the locale's own
    /// words, for any integer (negative or over 6 wraps).
    static func weekdayName(_ index: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var c = calendar
        c.locale = locale
        return c.weekdaySymbols[((index % 7) + 7) % 7]
    }

    /// "Fri, Sep 18" or "Mon, Sep 21 – Fri, Sep 25".
    func dateLabel(calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).month(.abbreviated).day()
        let first = firstDay.date(calendar: calendar).formatted(style)
        guard firstDay != lastDay else { return first }
        let last = lastDay.date(calendar: calendar).formatted(style)
        return String(localized: "\(first) – \(last)", bundle: L10n.bundle, locale: locale,
                      comment: "A date range: first day, en dash, last day")
    }

    /// Compact form for the Home row value: a bare weekday when the day is
    /// within the next six days ("Fri"), otherwise "Sep 18"; ranges as
    /// "Sep 21–25" or "Sep 28 – Oct 2".
    func shortDateLabel(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let monthDay = base.month(.abbreviated).day()
        let firstDate = firstDay.date(calendar: calendar)
        if firstDay == lastDay {
            let today = DayKey(now, calendar: calendar)
            let days = calendar.dateComponents([.day], from: today.date(calendar: calendar), to: firstDate).day ?? 7
            if (0...6).contains(days) {
                return firstDate.formatted(base.weekday(.abbreviated))
            }
            return firstDate.formatted(monthDay)
        }
        let lastDate = lastDay.date(calendar: calendar)
        if firstDay.month == lastDay.month && firstDay.year == lastDay.year {
            let first = firstDate.formatted(monthDay)
            return String(localized: "\(first)–\(lastDay.day)", bundle: L10n.bundle, locale: locale,
                          comment: "A range inside one month: 'Sep 21' then the last day's number")
        }
        let first = firstDate.formatted(monthDay)
        let last = lastDate.formatted(monthDay)
        return String(localized: "\(first) – \(last)", bundle: L10n.bundle, locale: locale,
                      comment: "A date range across months")
    }
}

extension PaperweightConfig {
    /// The Home row's trailing value: the next planned day and how many are
    /// upcoming, or nil when there are none.
    func dayExceptionsRowValue(now: Date = Date(), calendar: Calendar = .current,
                               locale: Locale = .current) -> String? {
        let upcoming = upcomingDayExceptions(now: now, calendar: calendar)
        guard let next = upcoming.first else { return nil }
        let day = next.shortDateLabel(now: now, calendar: calendar, locale: locale)
        let count = String(localized: "\(upcoming.count) upcoming", bundle: L10n.bundle, locale: locale,
                           comment: "How many planned days are ahead; has a plural rule")
        return String(localized: "\(day) · \(count)", bundle: L10n.bundle, locale: locale,
                      comment: "Two short phrases joined by a middle dot")
    }
}
