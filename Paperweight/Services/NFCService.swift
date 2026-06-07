import CoreNFC

final class NFCService: NSObject, NFCServiceProtocol {
    private var continuation: CheckedContinuation<String, Error>?
    private var session: NFCTagReaderSession?

    func readTagUID() async throws -> String {
        guard NFCTagReaderSession.readingAvailable else { throw NFCError.notSupported }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
            session?.alertMessage = "Hold your Paperweight token near the top of your iPhone."
            session?.begin()
        }
    }
}

extension NFCService: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
            continuation?.resume(throwing: NFCError.sessionFailed(error))
        } else {
            continuation?.resume(throwing: CancellationError())
        }
        continuation = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            continuation?.resume(throwing: NFCError.noTagFound)
            session.invalidate()
            return
        }
        session.connect(to: tag) { [weak self] error in
            if let error {
                self?.continuation?.resume(throwing: NFCError.sessionFailed(error))
                session.invalidate()
                return
            }
            let uid: String
            switch tag {
            case .iso7816(let t):   uid = t.identifier.hexString
            case .miFare(let t):    uid = t.identifier.hexString
            case .iso15693(let t):  uid = t.identifier.hexString
            case .feliCa(let t):    uid = t.currentIDm.hexString
            @unknown default:
                self?.continuation?.resume(throwing: NFCError.readFailed)
                session.invalidate()
                return
            }
            session.alertMessage = "Token recognized."
            session.invalidate()
            self?.continuation?.resume(returning: uid)
            self?.continuation = nil
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
