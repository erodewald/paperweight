import Foundation
import Sentry

/// Opt-in crash reporting. Off until the user turns on Settings > Privacy >
/// "Share crash reports", and inert in any build without a DSN (a fresh clone,
/// CI, the Simulator unless you set one).
///
/// What it sends is deliberately thin: a stack trace and the app/OS version.
/// No user, no breadcrumbs, no screenshots, no view hierarchy, no performance
/// traces, no network capture. Nothing from the schedule, the chosen apps, the
/// NFC token or recovery codes is attached, and `scrub` removes anything the
/// SDK adds on its own.
enum CrashReporting {
    /// UserDefaults key behind the Settings switch (`@AppStorage`).
    static let optInKey = "paperweight.shareCrashReports"

    private static var dsn: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// Whether this build can report at all. Settings hides the switch when not.
    static var isAvailable: Bool { dsn != nil }

    /// Call once at launch.
    static func startIfOptedIn() {
        setEnabled(UserDefaults.standard.bool(forKey: optInKey))
    }

    /// Start or stop the SDK to match the user's choice, effective immediately.
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            guard let dsn, !SentrySDK.isEnabled else { return }
            SentrySDK.start { options in
                options.dsn = dsn
                options.sendDefaultPii = false
                options.attachScreenshot = false
                options.attachViewHierarchy = false
                options.enableAutoSessionTracking = false
                options.enableAutoBreadcrumbTracking = false
                options.enableNetworkBreadcrumbs = false
                options.enableCaptureFailedRequests = false
                options.enableAutoPerformanceTracing = false
                options.tracesSampleRate = 0
                options.beforeSend = { scrub($0) }
                #if DEBUG
                options.environment = "debug"
                #else
                options.environment = "production"
                #endif
            }
        } else if SentrySDK.isEnabled {
            SentrySDK.close()
        }
    }

    /// Last line of defence before an event leaves the device.
    private static func scrub(_ event: Event) -> Event {
        event.user = nil
        event.breadcrumbs = nil
        event.serverName = nil
        return event
    }
}
