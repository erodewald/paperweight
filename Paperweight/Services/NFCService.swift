import CoreNFC

final class NFCService: NSObject, NFCServiceProtocol {
    private var continuation: CheckedContinuation<String, Error>?
    private var session: NFCTagReaderSession?

    func readTagUID() async throws -> String {
        guard NFCTagReaderSession.readingAvailable else { throw NFCError.notSupported }
        // Never start a second session on top of an in-flight one — doing so
        // would overwrite (and leak) the pending continuation.
        guard continuation == nil else { throw NFCError.busy }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
            self.session = session
            session?.alertMessage = "Hold your Paperweight token near the top of your iPhone."
            session?.begin()
        }
    }

    /// Resumes the pending continuation exactly once and clears session state.
    /// Safe to call from any delegate path; later calls are no-ops.
    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.session = nil
        switch result {
        case .success(let uid): continuation.resume(returning: uid)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

extension NFCService: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        if nfcError?.code == .readerSessionInvalidationErrorUserCanceled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(NFCError.sessionFailed(error)))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No token found.")
            finish(.failure(NFCError.noTagFound))
            return
        }
        session.connect(to: tag) { [weak self] error in
            if let error {
                session.invalidate(errorMessage: "Couldn't read the token.")
                self?.finish(.failure(NFCError.sessionFailed(error)))
                return
            }
            let uid: String
            switch tag {
            case .iso7816(let t):   uid = t.identifier.hexString
            case .miFare(let t):    uid = t.identifier.hexString
            case .iso15693(let t):  uid = t.identifier.hexString
            case .feliCa(let t):    uid = t.currentIDm.hexString
            @unknown default:
                session.invalidate(errorMessage: "Unsupported token.")
                self?.finish(.failure(NFCError.readFailed))
                return
            }
            session.alertMessage = "Token recognized."
            session.invalidate()
            self?.finish(.success(uid))
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
