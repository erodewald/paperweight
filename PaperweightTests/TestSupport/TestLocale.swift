import Foundation

/// The fixed frame every copy test uses, so nothing depends on the simulator's
/// language. The time zone stays the simulator's on purpose: `state(at:)` and
/// friends default to `Calendar.current`, and a test date built in another zone
/// would land on a different half-hour than the one the test names.
enum TestLocale {
    static let en = Locale(identifier: "en_US")

    static var calendar: Calendar {
        var c = Calendar.current
        c.locale = en
        c.firstWeekday = 1
        return c
    }

    /// Unit tests have no host app, so `Bundle.main` is the test runner. Point
    /// string lookups at the test bundle, which carries the compiled catalog.
    static func useTestBundle() {
        L10n.bundle = Bundle(for: BundleAnchor.self)
    }

    private final class BundleAnchor {}
}
