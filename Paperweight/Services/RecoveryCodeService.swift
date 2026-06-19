import Foundation
import CryptoKit

enum RecoveryCodeService {
    static let codeCount = 5

    static func generateCodes() -> [(plain: String, model: RecoveryCode)] {
        (0..<codeCount).map { _ in
            let plain = makePlainCode()
            // Hash the normalized form so entry (which strips the dash) matches.
            return (plain, RecoveryCode(id: UUID(), codeHash: sha256(normalize(plain))))
        }
    }

    // Returns the ID of the matching unused code, or nil if invalid.
    static func verify(_ input: String, against codes: [RecoveryCode]) -> UUID? {
        let h = sha256(normalize(input))
        return codes.first { !$0.isUsed && $0.codeHash == h }?.id
    }

    /// Canonical form used for hashing on both generation and entry: uppercase,
    /// no whitespace, no separators.
    private static func normalize(_ s: String) -> String {
        s.uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "·", with: "")
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
