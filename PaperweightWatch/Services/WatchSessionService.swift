import WatchConnectivity
import SwiftUI

struct WatchStatus {
    var isEnabled: Bool = false
    var isUnlocked: Bool = false
    var unlockExpires: Date? = nil
}

/// Status-only mirror: receives Paperweight's state from the iPhone and
/// publishes it for the wrist display. (App blocking is iOS-only; the watch
/// does not enforce restrictions.)
final class WatchSessionService: NSObject, ObservableObject {
    static let shared = WatchSessionService()
    @Published var status = WatchStatus()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension WatchSessionService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.status = WatchStatus(
                isEnabled: message["isEnabled"] as? Bool ?? false,
                isUnlocked: message["isUnlocked"] as? Bool ?? false,
                unlockExpires: {
                    let ts = message["unlockExpires"] as? TimeInterval ?? 0
                    return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
                }()
            )
            replyHandler([:])
        }
    }
}
