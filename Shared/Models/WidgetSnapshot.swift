import Foundation

/// A token-free projection of `PaperweightConfig` for the widget extension.
///
/// The widget deliberately never sees `FamilyActivitySelection` or
/// `AppScheduleOverride`: those carry Family Controls tokens, which would drag
/// the `com.apple.developer.family-controls` entitlement onto the widget target
/// for data it could only count anyway. Everything here is plain `Codable`
/// values, so the widget target compiles without FamilyControls at all.
///
/// Written to the App Group on every config save, on foreground, and from the
/// monitor extension at each schedule boundary. See `WidgetSnapshotStore`.
struct WidgetSnapshot: Codable, Equatable {
    var isArmed: Bool = false
    var hasSelection: Bool = false
    var hasNFCToken: Bool = false
    var hasRecoveryCodes: Bool = false
    var isScreenTimeAuthorized: Bool = false
    var schedule: PaperweightSchedule? = nil
    var coolOffReleaseDate: Date? = nil
    /// When the cool-off was requested. Needed only so its ring can deplete —
    /// the release date alone gives an end but no span.
    var coolOffRequestedAt: Date? = nil
    var unlockExpiresAt: Date? = nil
    var unlockDuration: TimeInterval = Paperweight.defaultUnlockDuration
    var dayExceptions: [DayException] = []
    var updatedAt: Date = .distantPast

    var hasUnlockMethod: Bool { hasNFCToken || hasRecoveryCodes }

    // Forward/backward compatible like PaperweightConfig: a snapshot written by
    // an older or newer build still decodes, with missing keys taking defaults.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isArmed = try c.decodeIfPresent(Bool.self, forKey: .isArmed) ?? false
        hasSelection = try c.decodeIfPresent(Bool.self, forKey: .hasSelection) ?? false
        hasNFCToken = try c.decodeIfPresent(Bool.self, forKey: .hasNFCToken) ?? false
        hasRecoveryCodes = try c.decodeIfPresent(Bool.self, forKey: .hasRecoveryCodes) ?? false
        isScreenTimeAuthorized = try c.decodeIfPresent(Bool.self, forKey: .isScreenTimeAuthorized) ?? false
        schedule = (try? c.decodeIfPresent(PaperweightSchedule.self, forKey: .schedule)) ?? nil
        coolOffReleaseDate = try c.decodeIfPresent(Date.self, forKey: .coolOffReleaseDate)
        coolOffRequestedAt = try c.decodeIfPresent(Date.self, forKey: .coolOffRequestedAt)
        unlockExpiresAt = try c.decodeIfPresent(Date.self, forKey: .unlockExpiresAt)
        unlockDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .unlockDuration)
            ?? Paperweight.defaultUnlockDuration
        dayExceptions = (try? c.decodeIfPresent([DayException].self, forKey: .dayExceptions)) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

// MARK: - State

/// What the widget is showing. Derived, never stored.
///
/// The `fraction` on each case is the `ProgressRing` progress value directly:
/// quiet and unlock rings *deplete* (fraction = time remaining), the free-window
/// ring *fills* (fraction = time spent), so the sage ring always drains toward
/// the boundary the user is waiting for.
enum WidgetState: Equatable {
    case unwritten
    case notAuthorized
    case nothingChosen
    case noWayBack
    case off
    case timedUnlock(ends: Date, fraction: Double)
    case coolOff(ends: Date, fraction: Double)
    case quietBounded(ends: Date, fraction: Double)
    case quietOpen
    case freeWindow(ends: Date, fraction: Double)
}

extension WidgetSnapshot {
    func resolver(calendar: Calendar = .current) -> ScheduleResolver {
        ScheduleResolver(schedule: schedule, exceptions: dayExceptions, calendar: calendar)
    }

    /// Resolves the state at a given instant. Precedence is deliberate and
    /// top-down: setup problems outrank running state (there's no point showing
    /// a countdown to someone who hasn't chosen any apps), and a live timed
    /// unlock outranks a pending cool-off because it resolves far sooner.
    func state(at date: Date, calendar: Calendar = .current) -> WidgetState {
        if !isScreenTimeAuthorized { return .notAuthorized }
        if !hasSelection { return .nothingChosen }
        if !hasUnlockMethod { return .noWayBack }
        if !isArmed { return .off }

        if let expiry = unlockExpiresAt, date < expiry {
            let remaining = expiry.timeIntervalSince(date)
            let fraction = unlockDuration > 0 ? remaining / unlockDuration : 0
            return .timedUnlock(ends: expiry, fraction: max(0, min(1, fraction)))
        }

        if let release = coolOffReleaseDate, date < release {
            let total = coolOffRequestedAt.map { release.timeIntervalSince($0) } ?? 0
            let remaining = release.timeIntervalSince(date)
            let fraction = total > 0 ? remaining / total : 0
            return .coolOff(ends: release, fraction: max(0, min(1, fraction)))
        }

        let resolver = resolver(calendar: calendar)
        if let free = resolver.freeStatus(at: date) {
            return .freeWindow(ends: free.ends, fraction: free.elapsedFraction)
        }
        if resolver.isFree(at: date) {
            // Open with no boundary ahead (always open).
            return .off
        }
        if let quiet = resolver.quietStatus(at: date) {
            return .quietBounded(ends: quiet.ends, fraction: quiet.remainingFraction)
        }
        return .quietOpen
    }

    /// The next moment the state could change on its own — the widget's timeline
    /// pivot. Nil when nothing is scheduled to happen.
    func nextBoundary(at date: Date, calendar: Calendar = .current) -> Date? {
        var candidates: [Date] = []
        if let expiry = unlockExpiresAt, date < expiry { candidates.append(expiry) }
        if let release = coolOffReleaseDate, date < release { candidates.append(release) }
        let resolver = resolver(calendar: calendar)
        if let quiet = resolver.quietStatus(at: date) { candidates.append(quiet.ends) }
        if let free = resolver.freeStatus(at: date) { candidates.append(free.ends) }
        return candidates.min()
    }
}

// MARK: - Timeline

extension WidgetSnapshot {
    /// The instants the widget should render, from `now` to `now + horizon`:
    /// one every `step`, plus one a second past each boundary in between so the
    /// state flips sharply rather than up to a step late.
    ///
    /// Entries deliberately continue on the far side of every boundary. Each
    /// one is computed by `state(at:)` for its own instant, so this is pure
    /// schedule math that stays correct until the snapshot itself changes —
    /// and a snapshot change triggers its own reload. A timeline that stopped
    /// at the boundary relied on WidgetKit honouring the reload policy
    /// promptly, which it does on its own budget; the last entry's "3h 20m"
    /// then sat frozen on screen for as long as that took.
    func timelineDates(from now: Date, step: TimeInterval, horizon: TimeInterval,
                       maxEntries: Int, calendar: Calendar = .current) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates = Set<Date>()

        var cursor = now
        while cursor <= end {
            dates.insert(cursor)
            cursor.addTimeInterval(step)
        }

        var probe = now
        while let boundary = nextBoundary(at: probe, calendar: calendar), boundary < end {
            let justPast = boundary.addingTimeInterval(1)
            dates.insert(justPast)
            probe = justPast
        }

        return Array(dates.sorted().prefix(max(1, maxEntries)))
    }
}

// MARK: - Value

/// How the widget's headline reads. Only the timed unlock ticks live: at 15
/// minutes, seconds genuinely matter. Every other state renders a static
/// compact duration refreshed by the timeline, because a seconds counter
/// running down a three-hour quiet window is exactly the restless energy
/// Paperweight exists to remove.
enum WidgetValue: Equatable {
    case countdown(to: Date)
    case word(String)
    case none
}

// MARK: - Copy

/// Every string the widget renders, in the app's voice.
///
/// House rules, for whoever edits these next: the word is **quiet**, never
/// *blocked* or *restricted* — those belong to Screen Time's vocabulary, not
/// Paperweight's. No exclamation marks. No streaks, no praise, and no shame for
/// unlocking: the escape hatch is a feature, and clay already carries that
/// meaning without a word of judgment.
struct WidgetCopy: Equatable {
    var eyebrow: String
    var value: WidgetValue
    /// Spectral italic line under the headline (small widget).
    var caption: String
    /// Second line of the Lock Screen rectangular widget — a bare word or
    /// duration, ≤ 24 characters at 13pt.
    var accessoryValue: String
    /// Third line of the rectangular widget: the boundary, in plain words.
    var accessoryLine: String
    /// Footer of the medium day-ribbon — a whole sentence, since there's room.
    var boundaryLine: String

    /// The widget gallery's name and one-line description. Kept here, in a file
    /// the app compiles, so the app target's build extracts them; the widget
    /// target never extracts.
    static var displayName: String {
        String(localized: "Paperweight", bundle: L10n.bundle, comment: "Widget gallery name; the app name, never translated")
    }
    static var widgetDescription: String {
        String(localized: "How long the quiet lasts.", bundle: L10n.bundle, comment: "Widget gallery description")
    }
}

extension WidgetState {
    func copy(at date: Date, calendar: Calendar = .current, locale: Locale = .current) -> WidgetCopy {
        let b = L10n.bundle
        switch self {
        case .quietBounded(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale)
            let short = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale, abbreviated: true)
            let long = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "QUIET", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .word(d),
                caption: String(localized: "of quiet left", bundle: b, locale: locale, comment: "Follows a duration: '3h 20m of quiet left'"),
                accessoryValue: d,
                accessoryLine: String(localized: "until \(short)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Quiet until \(long)", bundle: b, locale: locale))

        case .quietOpen:
            return WidgetCopy(
                eyebrow: String(localized: "QUIET", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .word(String(localized: "Quiet", bundle: b, locale: locale)),
                caption: String(localized: "until you say otherwise", bundle: b, locale: locale),
                accessoryValue: String(localized: "Quiet", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "no open hours set", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Quiet — no open hours set", bundle: b, locale: locale))

        case .freeWindow(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale)
            let short = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale, abbreviated: true)
            let long = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "OPEN", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .word(d),
                caption: String(localized: "before it goes quiet", bundle: b, locale: locale),
                accessoryValue: d,
                accessoryLine: String(localized: "quiet at \(short)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Open until \(long), then quiet", bundle: b, locale: locale))

        case .timedUnlock(let ends, _):
            let short = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale, abbreviated: true)
            let long = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "UNLOCKED", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .countdown(to: ends),
                caption: String(localized: "then it closes on its own", bundle: b, locale: locale),
                accessoryValue: WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale),
                accessoryLine: String(localized: "re-locks \(short)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Unlocked — re-locks at \(long)", bundle: b, locale: locale))

        case .coolOff(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale)
            let rel = WidgetState.relative(ends, from: date, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "COOL-OFF", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form; the multi-day tokenless unlock"),
                value: .word(d),
                caption: String(localized: "still quiet until then", bundle: b, locale: locale),
                accessoryValue: d,
                accessoryLine: String(localized: "unlocks \(rel)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters; a relative time follows ('in 2 days')"),
                boundaryLine: String(localized: "Quiet until the cool-off lifts \(rel)", bundle: b, locale: locale))

        case .off:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Off", bundle: b, locale: locale)),
                caption: String(localized: "set it down when you're ready", bundle: b, locale: locale),
                accessoryValue: String(localized: "Off", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "nothing is quiet", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Nothing is quiet right now", bundle: b, locale: locale))

        case .nothingChosen:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Nothing", bundle: b, locale: locale, comment: "Widget headline: no apps chosen yet")),
                caption: String(localized: "pick what to quiet", bundle: b, locale: locale),
                accessoryValue: String(localized: "Nothing chosen", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "pick what to quiet", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Nothing chosen yet", bundle: b, locale: locale))

        case .noWayBack:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Not yet", bundle: b, locale: locale, comment: "Widget headline: cannot arm until an unlock method exists")),
                caption: String(localized: "set up a way back first", bundle: b, locale: locale),
                accessoryValue: String(localized: "Not armed", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "set up a way back", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Set up a way back first", bundle: b, locale: locale))

        case .notAuthorized:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Waiting", bundle: b, locale: locale, comment: "Widget headline: Screen Time permission missing")),
                caption: String(localized: "Screen Time access is off", bundle: b, locale: locale),
                accessoryValue: String(localized: "Waiting", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "Screen Time is off", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Screen Time access is off", bundle: b, locale: locale))

        case .unwritten:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .none,
                caption: String(localized: "open Paperweight to begin", bundle: b, locale: locale),
                accessoryValue: "—",
                accessoryLine: String(localized: "open Paperweight", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Open Paperweight to begin", bundle: b, locale: locale))
        }
    }

    /// The ring's progress value, or nil for states that draw an empty track.
    var ringProgress: Double? {
        switch self {
        case .quietBounded(_, let f), .freeWindow(_, let f),
             .timedUnlock(_, let f), .coolOff(_, let f): return f
        case .quietOpen: return 1
        case .off, .nothingChosen, .noWayBack, .notAuthorized, .unwritten: return nil
        }
    }

    /// SF Symbol shown in place of the leaf, when the state calls for one.
    /// Lock Screen accessories render in `vibrant` mode where colour flattens to
    /// luminance, so glyph and arc geometry — never tint — are what tell states
    /// apart there. The running states keep the leaf and are distinguished by
    /// their arc; every other state gets a glyph of its own.
    var glyph: String? {
        switch self {
        case .timedUnlock: return "lock.open"
        case .coolOff: return "hourglass"
        case .off: return "lock.slash"
        case .nothingChosen: return "app.badge.checkmark"
        case .noWayBack: return "key"
        case .notAuthorized: return "exclamationmark.triangle"
        case .unwritten, .quietBounded, .quietOpen, .freeWindow: return nil
        }
    }

    /// Deep link opened on tap. One target per widget — no sub-regions.
    var url: URL? {
        switch self {
        case .timedUnlock: return URL(string: "paperweight://unlock")
        case .nothingChosen: return URL(string: "paperweight://choose-apps")
        case .noWayBack: return URL(string: "paperweight://unlock-setup")
        default: return URL(string: "paperweight://home")
        }
    }

    // MARK: Formatting

    /// "3h 20m", "3h", "42m" — never zero, since a boundary that has arrived is
    /// a different state, not a zero-length one. Under a day the units come
    /// from Foundation in the locale's own words; past a day it is the app's
    /// day-speak, rounded to the nearest half day, with the plural rule in the
    /// catalog.
    static func compactDuration(_ interval: TimeInterval, locale: Locale = .current) -> String {
        let total = max(60, interval)
        if total >= 24 * 3600 {
            let halves = Int((total / (12 * 3600)).rounded())
            let whole = halves / 2
            if halves % 2 == 1 {
                return String(localized: "\(whole)½ days", bundle: L10n.bundle, locale: locale,
                              comment: "Duration rounded to a half day; ½ is part of the value")
            }
            return String(localized: "\(whole) days", bundle: L10n.bundle, locale: locale,
                          comment: "Duration in whole days; has a plural rule")
        }
        let hours = Int(total) / 3600
        let minutes = max(hours > 0 ? 0 : 1, (Int(total) % 3600) / 60)
        return Duration.seconds(hours * 3600 + minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
    }

    static func clock(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    }

    /// `clock`, qualified by day whenever the boundary isn't today.
    ///
    /// A bare "02:00" is read as *tonight* — which is right most of the time and
    /// wrong in exactly the case that matters: a Friday evening looking down the
    /// barrel of a free window that runs until Sunday. "Open until 02:00" then
    /// promises quiet in three hours when it's really two and a half days out.
    ///
    /// The comparison is calendar days, not elapsed hours, so 23:50 → 00:10 is
    /// "tomorrow" (it is) while 09:00 → 22:00 stays bare (it's still today).
    /// `abbreviated` is for the Lock Screen rectangular line, which has room for
    /// about 24 characters and no more.
    static func dayClock(_ date: Date, from now: Date,
                         calendar: Calendar = .current,
                         locale: Locale = .current,
                         abbreviated: Bool = false) -> String {
        let time = clock(date, calendar: calendar, locale: locale)
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1:
            return time
        case 1:
            return abbreviated
                ? String(localized: "\(time) tmrw", bundle: L10n.bundle, locale: locale,
                         comment: "Lock Screen; a time then 'tomorrow' shortened; keep under 24 characters")
                : String(localized: "\(time) tomorrow", bundle: L10n.bundle, locale: locale,
                         comment: "A time, then the word tomorrow")
        default:
            // A weekly schedule never points more than 7 days out, so the
            // weekday alone is unambiguous.
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(abbreviated ? .abbreviated : .wide)
            let weekday = date.formatted(style)
            return String(localized: "\(time) \(weekday)", bundle: L10n.bundle, locale: locale,
                          comment: "A time and a weekday name; reorder freely")
        }
    }

    static func relative(_ date: Date, from now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
