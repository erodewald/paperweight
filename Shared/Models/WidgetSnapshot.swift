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
}

extension WidgetState {
    func copy(at date: Date) -> WidgetCopy {
        switch self {
        case .quietBounded(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date))
            return WidgetCopy(eyebrow: "QUIET", value: .word(d),
                              caption: "of quiet left",
                              accessoryValue: d,
                              accessoryLine: "until \(WidgetState.dayClock(ends, from: date, abbreviated: true))",
                              boundaryLine: "Quiet until \(WidgetState.dayClock(ends, from: date))")

        case .quietOpen:
            return WidgetCopy(eyebrow: "QUIET", value: .word("Quiet"),
                              caption: "until you say otherwise",
                              accessoryValue: "Quiet",
                              accessoryLine: "no free windows set",
                              boundaryLine: "Quiet — no free windows set")

        case .freeWindow(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date))
            return WidgetCopy(eyebrow: "FREE WINDOW", value: .word(d),
                              caption: "before it goes quiet",
                              accessoryValue: d,
                              accessoryLine: "quiet at \(WidgetState.dayClock(ends, from: date, abbreviated: true))",
                              boundaryLine: "Free until \(WidgetState.dayClock(ends, from: date)), then quiet")

        case .timedUnlock(let ends, _):
            return WidgetCopy(eyebrow: "UNLOCKED", value: .countdown(to: ends),
                              caption: "then it closes on its own",
                              accessoryValue: WidgetState.compactDuration(ends.timeIntervalSince(date)),
                              accessoryLine: "re-locks \(WidgetState.dayClock(ends, from: date, abbreviated: true))",
                              boundaryLine: "Unlocked — re-locks at \(WidgetState.dayClock(ends, from: date))")

        case .coolOff(let ends, _):
            return WidgetCopy(eyebrow: "COOL-OFF",
                              value: .word(WidgetState.compactDuration(ends.timeIntervalSince(date))),
                              caption: "still quiet until then",
                              accessoryValue: WidgetState.compactDuration(ends.timeIntervalSince(date)),
                              accessoryLine: "unlocks \(WidgetState.relative(ends, from: date))",
                              boundaryLine: "Quiet until the cool-off lifts \(WidgetState.relative(ends, from: date))")

        case .off:
            return WidgetCopy(eyebrow: "PAPERWEIGHT", value: .word("Off"),
                              caption: "set it down when you're ready",
                              accessoryValue: "Off",
                              accessoryLine: "nothing is quiet",
                              boundaryLine: "Nothing is quiet right now")

        case .nothingChosen:
            return WidgetCopy(eyebrow: "PAPERWEIGHT", value: .word("Nothing"),
                              caption: "pick what to quiet",
                              accessoryValue: "Nothing chosen",
                              accessoryLine: "pick what to quiet",
                              boundaryLine: "Nothing chosen yet")

        case .noWayBack:
            return WidgetCopy(eyebrow: "PAPERWEIGHT", value: .word("Not yet"),
                              caption: "set up a way back first",
                              accessoryValue: "Not armed",
                              accessoryLine: "set up a way back",
                              boundaryLine: "Set up a way back first")

        case .notAuthorized:
            return WidgetCopy(eyebrow: "PAPERWEIGHT", value: .word("Waiting"),
                              caption: "Screen Time access is off",
                              accessoryValue: "Waiting",
                              accessoryLine: "Screen Time is off",
                              boundaryLine: "Screen Time access is off")

        case .unwritten:
            return WidgetCopy(eyebrow: "PAPERWEIGHT", value: .none,
                              caption: "open Paperweight to begin",
                              accessoryValue: "—",
                              accessoryLine: "open Paperweight",
                              boundaryLine: "Open Paperweight to begin")
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
    /// a different state, not a zero-length one.
    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = max(60, interval)
        // Past a day nobody thinks in hours. Nearest half day is enough — the
        // boundary line beside the value carries the exact time.
        if total >= 24 * 3600 {
            let halves = Int((total / (12 * 3600)).rounded())
            let whole = halves / 2
            let half = halves % 2 == 1
            let unit = (whole == 1 && !half) ? "day" : "days"
            return "\(whole)\(half ? "½" : "") \(unit)"
        }
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(max(1, minutes))m"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// `clock`, qualified by day whenever the boundary isn't today.
    ///
    /// A bare "02:00" is read as *tonight* — which is right most of the time and
    /// wrong in exactly the case that matters: a Friday evening looking down the
    /// barrel of a free window that runs until Sunday. "Free until 02:00" then
    /// promises quiet in three hours when it's really two and a half days out.
    ///
    /// The comparison is calendar days, not elapsed hours, so 23:50 → 00:10 is
    /// "tomorrow" (it is) while 09:00 → 22:00 stays bare (it's still today).
    /// `abbreviated` is for the Lock Screen rectangular line, which has room for
    /// about 24 characters and no more.
    static func dayClock(_ date: Date, from now: Date,
                         calendar: Calendar = .current,
                         abbreviated: Bool = false) -> String {
        let time = clock(date)
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1:
            return time
        case 1:
            return abbreviated ? "\(time) tmrw" : "\(time) tomorrow"
        default:
            // A weekly schedule never points more than 7 days out, so the
            // weekday alone is unambiguous.
            return "\(time) \(date.formatted(.dateTime.weekday(abbreviated ? .abbreviated : .wide)))"
        }
    }

    static func relative(_ date: Date, from now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
