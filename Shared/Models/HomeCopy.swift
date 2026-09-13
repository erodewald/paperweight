import Foundation

/// Copy helpers for the v2 Home screen. Deliberately separate from `WidgetCopy`:
/// the widget's "2h 14m" reads well in a small tile, while Home wants the bare
/// numeral "2:14" carrying its unit in a separate label.
enum HomeCopy {

    /// A remaining interval as `h:mm`, or `Nm` under an hour.
    static func countdown(_ remaining: TimeInterval, locale: Locale = .current) -> String {
        // Past a day the widget's day-speak applies here too: "51:30" is not a
        // countdown anyone reads.
        if remaining >= 24 * 3600 { return WidgetState.compactDuration(remaining, locale: locale) }
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        guard hours > 0 else {
            return String(localized: "\(minutes)m", bundle: L10n.bundle, locale: locale,
                          comment: "Big countdown under an hour: a number and a one-letter minutes unit")
        }
        return String(format: "%d:%02d", hours, minutes)
    }
}
