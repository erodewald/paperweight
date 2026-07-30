import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Reads and writes the widget's token-free view of the world in the App Group.
///
/// Separate from `ConfigStore` on purpose: the widget target compiles this file
/// and `WidgetSnapshot`, but never `PaperweightConfig`, so no Family Controls
/// type — and no entitlement — is needed to render the widget.
final class WidgetSnapshotStore {
    private let defaults: UserDefaults
    private let key = "paperweight.widget.snapshot"

    init(defaults: UserDefaults = UserDefaults(suiteName: Paperweight.appGroupID)!) {
        self.defaults = defaults
    }

    /// Nil when nothing has been written yet — the widget renders `.unwritten`
    /// rather than pretending Paperweight is off.
    func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Persists the snapshot and asks WidgetKit to redraw — but only when
    /// something the widget can see actually changed. Reload budget is finite,
    /// and `syncRestrictions()` runs on every foreground, so writing
    /// unconditionally would spend the day's refreshes on identical frames.
    func save(_ snapshot: WidgetSnapshot) {
        var incoming = snapshot
        incoming.updatedAt = load()?.updatedAt ?? .distantPast
        guard incoming != load() else { return }

        var stamped = snapshot
        stamped.updatedAt = Date()
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        defaults.set(data, forKey: key)
        reloadWidgets()
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
