import SwiftUI

/// Screen 02's "The week ahead": one row per day from today, each a
/// proportional bar of quiet (moss) and open (faint) runs, drawn for the real
/// dates so a planned day shows as it will really be. Each row carries its
/// date so the strip reads as an outlook, not as the weekly pattern — that
/// lives on the Schedule screen. A day with nothing quiet reads as a
/// dashed outline rather than an empty bar, so "no lock at all" can't be
/// mistaken for a rendering failure. A planned day gets a sage dot after its
/// name — the bar already says *what*, the dot says *why*.
struct WeekStrip: View {
    let resolver: ScheduleResolver
    /// Today and the six days after; see `DayKey.weekAhead(from:)`.
    let week: [DayKey]

    private static let dayNames = Calendar.current.shortWeekdaySymbols
    private static let barHeight: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The week ahead").pwScreenLabel()

            VStack(spacing: 6) {
                ForEach(week, id: \.self) { day in
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            let name = Self.dayNames[day.weekdayIndex()]
                            Text("\(name) \(day.day)", comment: "Short weekday name then day of month: 'Mon 14'; reorder freely")
                                .font(.grotesk(13, weight: .semibold))
                                .foregroundStyle(PW.textMuted)
                            if resolver.exception(on: day) != nil {
                                Circle().fill(PW.sage).frame(width: 6, height: 6)
                            }
                        }
                        .frame(width: 64, alignment: .leading)
                        row(day: day)
                    }
                }
            }

            HStack(spacing: 12) {
                legend(color: PW.moss, label: String(localized: "Locked — quiet", bundle: L10n.bundle, comment: "Legend swatch"))
                legend(color: nil, label: String(localized: "Open", bundle: L10n.bundle, comment: "Legend swatch"))
                HStack(spacing: 6) {
                    Circle().fill(PW.sage).frame(width: 6, height: 6)
                    Text("Planned", comment: "Legend: a day with a planned exception").font(.grotesk(13)).foregroundStyle(PW.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private func row(day: DayKey) -> some View {
        if resolver.isOpenAllDay(on: day) {
            Text("OPEN ALL DAY")
                .font(.grotesk(13, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(PW.textLabel)
                .frame(maxWidth: .infinity)
                .frame(height: Self.barHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.18),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                )
        } else {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(resolver.daySegments(on: day).enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(segment.isLocked ? PW.moss : Color.white.opacity(0.04))
                            .frame(width: max(0, geo.size.width * segment.fraction))
                    }
                }
            }
            .frame(height: Self.barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func legend(color: Color?, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color ?? Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color == nil ? Color.white.opacity(0.16) : .clear, lineWidth: 1)
                )
                .frame(width: 10, height: 10)
            Text(label)
                .font(.grotesk(13))
                .foregroundStyle(PW.textMuted)
        }
    }
}
