import WidgetKit
import SwiftUI

struct PaperweightWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PaperweightEntry

    var body: some View {
        switch family {
        case .systemMedium:
            RibbonWidgetView(entry: entry)
                .containerBackground(PW.black, for: .widget)
                .widgetURL(entry.state.url)
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(entry.state.url)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(entry.state.url)
        default:
            PaperweightSmallView(entry: entry)
                .containerBackground(PW.black, for: .widget)
                .widgetURL(entry.state.url)
        }
    }
}

// MARK: - Headline

/// The one place a `WidgetValue` becomes text. Only the timed unlock gets a live
/// ticking timer; everything else is a static duration from the timeline entry.
struct WidgetHeadline: View {
    let value: WidgetValue
    let now: Date
    let font: Font
    let color: Color

    var body: some View {
        switch value {
        case .countdown(let ends) where ends > now:
            Text(timerInterval: now...ends,
                 countsDown: true,
                 showsHours: ends.timeIntervalSince(now) >= 3600)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
        case .countdown:
            Text(WidgetState.compactDuration(0))
                .font(font).monospacedDigit().foregroundStyle(color)
        case .word(let word):
            Text(word)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
        case .none:
            EmptyView()
        }
    }
}

/// Glass orb, glyph orb, or dimmed orb — whichever the state calls for.
struct StateOrb: View {
    let state: WidgetState
    let size: CGFloat

    var body: some View {
        if let glyph = state.glyph {
            GlyphOrb(size: size, systemName: glyph, tint: state.accent)
        } else {
            GlassOrb(size: size, dim: state.isDormant)
        }
    }
}

// MARK: - systemSmall — "The Paperweight"

struct PaperweightSmallView: View {
    let entry: PaperweightEntry

    private var copy: WidgetCopy { entry.copy }
    private var state: WidgetState { entry.state }

    var body: some View {
        VStack(spacing: 0) {
            Text(copy.eyebrow)
                .font(.grotesk(9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(PW.textFaint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The orb takes whatever the text rows leave, rather than claiming a
            // fixed 92pt. At a fixed size this stack came to 167pt inside a
            // 138pt widget; the host resolves that by clipping, which is what
            // shaved the eyebrow and pushed the caption off the bottom edge.
            // GeometryReader is greedy in a VStack, so it absorbs exactly the
            // remainder and the stack can no longer overflow at any widget size.
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height, 92)
                ZStack {
                    // pulse: false — the repeating animation never advances in a
                    // widget, so force the static branch rather than render the
                    // dimmer resting frame of an animation that will never run.
                    OrbGlow(size: d, pulse: false)
                    ProgressRing(progress: state.ringProgress ?? 0, size: d * 0.76, tint: state.accent)
                    StateOrb(state: state, size: d * 0.43)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            // A floor so the orb stays recognisable in the states whose caption
            // wraps to two lines. Worst case is the smallest widget with the
            // longest caption, which comes to 123pt of a 126pt box.
            .frame(minHeight: 44)
            .padding(.vertical, 6)

            WidgetHeadline(value: copy.value, now: entry.date,
                           font: .grotesk(22, weight: .bold), color: state.headlineColor)

            Text(copy.caption)
                .font(.spectral(11, italic: true))
                .foregroundStyle(PW.encourage)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
        }
    }
}

// MARK: - systemMedium — "The Ribbon"

struct RibbonWidgetView: View {
    let entry: PaperweightEntry

    private var copy: WidgetCopy { entry.copy }
    private var state: WidgetState { entry.state }

    /// Today's open half-hours, or nil when there is nothing to draw: dormant
    /// states, or no schedule and no exception covering today. Dormant states
    /// get a wide version of the small layout instead of a strip of empty cells.
    private var todaySlots: Set<Int>? {
        guard !state.isDormant, let resolver = entry.resolver else { return nil }
        let today = DayKey(entry.date)
        let hasWeekly = !(resolver.schedule?.isEmpty ?? true)
        guard hasWeekly || resolver.exception(on: today) != nil else { return nil }
        return resolver.openSlots(on: today)
    }

    var body: some View {
        if let todaySlots {
            ribbon(openSlots: todaySlots)
        } else {
            dormant
        }
    }

    private func ribbon(openSlots: Set<Int>) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.weekdayName(entry.date)).pwSectionLabel()
                Spacer()
                WidgetHeadline(value: copy.value, now: entry.date,
                               font: .grotesk(15, weight: .semibold), color: state.headlineColor)
            }

            Spacer(minLength: 10)

            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(PaperweightSchedule.hourLabel(hour))
                        .font(.grotesk(8))
                        .foregroundStyle(PW.textFaintest)
                    if hour != 24 { Spacer() }
                }
            }
            .padding(.bottom, 3)

            DayRibbon(openSlots: openSlots, date: entry.date)
                .frame(height: 14)

            Spacer(minLength: 10)

            Text(copy.boundaryLine)
                .font(.grotesk(11))
                .foregroundStyle(PW.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var dormant: some View {
        HStack(spacing: 16) {
            ZStack {
                OrbGlow(size: 78, pulse: false)
                ProgressRing(progress: state.ringProgress ?? 0, size: 60, tint: state.accent)
                StateOrb(state: state, size: 34)
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 3) {
                Text(copy.eyebrow)
                    .font(.grotesk(9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(PW.textFaint)
                WidgetHeadline(value: copy.value, now: entry.date,
                               font: .grotesk(24, weight: .bold), color: state.headlineColor)
                Text(copy.caption)
                    .font(.spectral(12, italic: true))
                    .foregroundStyle(PW.encourage)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private static func weekdayName(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide)).uppercased(with: .current)
    }
}

/// Today's 24 hours as 48 half-hour cells, with a marker at now. Free windows
/// are lit; cells already spent are dimmed, so the day visibly empties out.
struct DayRibbon: View {
    let openSlots: Set<Int>
    let date: Date

    private var nowFraction: Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        return minutes / (24 * 60)
    }

    private var currentHalfHour: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return PaperweightSchedule.halfHour(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 0.5) {
                    ForEach(0..<PaperweightSchedule.halfHoursPerDay, id: \.self) { half in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(openSlots.contains(half)
                                  ? PW.moss.opacity(0.55) : PW.deepForest)
                            .opacity(half < currentHalfHour ? 0.45 : 1)
                    }
                }

                Rectangle()
                    .fill(PW.dawnGlow)
                    .frame(width: 1.5, height: geo.size.height + 6)
                    .offset(x: min(max(0, geo.size.width * nowFraction - 0.75),
                                   geo.size.width - 1.5))
            }
        }
    }
}

// MARK: - accessoryCircular

struct CircularWidgetView: View {
    let entry: PaperweightEntry

    private var state: WidgetState { entry.state }

    /// Lock Screen accessories render in `vibrant` mode, where colour flattens to
    /// luminance — so glyph and arc geometry are what distinguish states here,
    /// never tint. Quiet-with-no-end gets the leaf; it's the only state whose
    /// identity is the absence of a number.
    private var glyph: String? {
        if let g = state.glyph { return g }
        if case .quietOpen = state { return "leaf" }
        return nil
    }

    /// "3h 20m" → "3h". A circular widget has room for one unit, not two.
    private var shortValue: String {
        entry.copy.accessoryValue.split(separator: " ").first.map(String.init) ?? ""
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: state.ringProgress ?? 0)
                .stroke(state.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
                .padding(2)

            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 13, weight: .regular))
            } else {
                Text(shortValue)
                    .font(.grotesk(14, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - accessoryRectangular

struct RectangularWidgetView: View {
    let entry: PaperweightEntry

    private var copy: WidgetCopy { entry.copy }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(copy.eyebrow)
                .font(.grotesk(9, weight: .semibold))
                .tracking(1.4)
                .widgetAccentable()

            switch copy.value {
            case .countdown(let ends) where ends > entry.date:
                Text(timerInterval: entry.date...ends,
                     countsDown: true,
                     showsHours: ends.timeIntervalSince(entry.date) >= 3600)
                    .font(.grotesk(15, weight: .semibold))
                    .monospacedDigit()
            default:
                Text(copy.accessoryValue)
                    .font(.grotesk(15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Text(copy.accessoryLine)
                .font(.grotesk(11))
                .opacity(0.75)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
