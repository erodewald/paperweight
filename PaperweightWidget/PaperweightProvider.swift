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
    /// than that, to a 4-hour horizon. `maxEntries` leaves room for the extra
    /// just-past-boundary entries on top of the 49 stepped ones.
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

        // Entries run straight through every boundary inside the horizon — see
        // `WidgetSnapshot.timelineDates`. Each is computed for its own instant,
        // so the state on the far side is already right whenever the reload
        // WidgetKit owes us at the end turns out to be late.
        let dates = snapshot?.timelineDates(from: now, step: step, horizon: horizon, maxEntries: maxEntries)
            ?? [now]
        let entries = dates.map { entry(at: $0, from: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, from snapshot: WidgetSnapshot?) -> PaperweightEntry {
        PaperweightEntry(date: date,
                         state: snapshot?.state(at: date) ?? .unwritten,
                         schedule: snapshot?.schedule)
    }
}
