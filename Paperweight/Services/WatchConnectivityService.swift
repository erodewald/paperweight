import WatchConnectivity

final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()
    @Published var watchIsReachable: Bool = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendStatusUpdate(isEnabled: Bool, isUnlocked: Bool, unlockExpires: Date?) {
        let session = WCSession.default
        // Only send once the session is activated, paired, and reachable —
        // otherwise WatchConnectivity logs "WCSession has not been activated".
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled, session.isReachable else { return }
        let message: [String: Any] = [
            "isEnabled": isEnabled,
            "isUnlocked": isUnlocked,
            "unlockExpires": unlockExpires?.timeIntervalSince1970 ?? 0
        ]
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.watchIsReachable = state == .activated && session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.watchIsReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
