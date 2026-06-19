import Foundation
import CryptoKit

enum RecoveryCodeService {
    static let codeCount = 5

    static func generateCodes() -> [(plain: String, model: RecoveryCode)] {
        (0..<codeCount).map { _ in
            let plain = makePlainCode()
            return (plain, RecoveryCode(id: UUID(), codeHash: sha256(plain)))
        }
    }

    // Returns the ID of the matching unused code, or nil if invalid.
    static func verify(_ input: String, against codes: [RecoveryCode]) -> UUID? {
        let normalized = input
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
        let h = sha256(normalized)
        return codes.first { !$0.isUsed && $0.codeHash == h }?.id
    }

    private static func makePlainCode() -> String {
        // No 0/O or 1/I/L to avoid visual ambiguity
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let half1 = (0..<5).map { _ in String(chars.randomElement()!) }.joined()
        let half2 = (0..<5).map { _ in String(chars.randomElement()!) }.joined()
        return "\(half1)-\(half2)"
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
