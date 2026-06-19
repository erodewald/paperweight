#if os(iOS)
import Foundation
import FamilyControls
import ManagedSettings

struct AppScheduleOverride: Codable, Identifiable {
    let id: UUID
    var token: ApplicationToken
    var mode: Mode

    enum Mode: String, Codable {
        case alwaysBlocked
        case alwaysFree
    }
}
#endif
