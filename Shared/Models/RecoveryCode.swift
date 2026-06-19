import Foundation

struct RecoveryCode: Codable, Identifiable {
    let id: UUID
    let codeHash: String
    var isUsed: Bool = false
}
