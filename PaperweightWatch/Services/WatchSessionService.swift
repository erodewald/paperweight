import WatchConnectivity
import SwiftUI

struct WatchStatus {
    var isEnabled: Bool = false
    var isUnlocked: Bool = false
    var unlockExpires: Date? = nil
}

final class WatchSessionService: NSObject, ObservableObject {
    static let shared = WatchSessionService()
    @Published var status = WatchStatus()
    @Published var unlockConfirmationPending = false

    private var confirmationReply: (([String: Any]) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func confirmUnlock() {
        confirmationReply?(["confirmed": true])
        confirmationReply = nil
        unlockConfirmationPending = false
    }

    func denyUnlock() {
        confirmationReply?(["confirmed": false])
        confirmationReply = nil
        unlockConfirmationPending = false
    }
}

extension WatchSessionService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            if let action = message["action"] as? String, action == "confirmUnlock" {
                self.confirmationReply = replyHandler
                self.unlockConfirmationPending = true
            } else {
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
}
