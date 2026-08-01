import WidgetKit
import Foundation

struct PaperweightEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
    /// Carried on the entry rather than re-read at render time, so the medium
    /// ribbon draws the same week the state was derived from.
    let schedule: PaperweightSchedule?

    var copy: WidgetCopy { state.copy(at: date) }

    /// The frame that sells the product. Used for the widget gallery and every
    /// placeholder — never an empty state, which would suggest the app does
    /// nothing until configured.
    static func preview(at date: Date = Date()) -> PaperweightEntry {
        PaperweightEntry(
            date: date,
            state: .quietBounded(ends: date.addingTimeInterval(2.5 * 3600), fraction: 0.72),
            schedule: .weekdayEvenings())
    }
}

/// Everything the widget shows is local schedule math over the App Group
/// snapshot — no network, no background refresh, no DeviceActivity dependency.
struct PaperweightProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    /// Entries every 5 minutes, so the "3h 20m" headline never drifts by more
    /// than that, capped at a 4-hour horizon.
    private let step: TimeInterval = 300
    private let horizon: TimeInterval = 4 * 3600
    private let maxEntries = 60

    func placeholder(in context: Context) -> PaperweightEntry { .preview() }

    func getSnapshot(in context: Context, completion: @escaping (PaperweightEntry) -> Void) {
        completion(context.isPreview ? .preview() : entry(at: Date(), from: store.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaperweightEntry>) -> Void) {
        let now = Date()
        let snapshot = store.load()
        let boundary = snapshot?.nextBoundary(at: now)

        var entries: [PaperweightEntry] = []
        let end = min(boundary ?? now.addingTimeInterval(horizon), now.addingTimeInterval(horizon))
        var cursor = now
        while cursor < end && entries.count < maxEntries - 1 {
            entries.append(entry(at: cursor, from: snapshot))
            cursor.addTimeInterval(step)
        }

        // One entry a second past the boundary, pre-rendering the state on the
        // far side. If the reload is late, the widget is already correct.
        if let boundary, boundary > now {
            entries.append(entry(at: boundary.addingTimeInterval(1), from: snapshot))
        }
        if entries.isEmpty {
            entries.append(entry(at: now, from: snapshot))
        }

        // Dormant states have no boundary of their own; check back hourly in case
        // the snapshot changed without a reload reaching us.
        let reload = boundary?.addingTimeInterval(1) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    private func entry(at date: Date, from snapshot: WidgetSnapshot?) -> PaperweightEntry {
        PaperweightEntry(date: date,
                         state: snapshot?.state(at: date) ?? .unwritten,
                         schedule: snapshot?.schedule)
    }
}
