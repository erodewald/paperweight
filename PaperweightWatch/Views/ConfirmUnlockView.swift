import SwiftUI

struct ConfirmUnlockView: View {
    @ObservedObject var session: WatchSessionService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open")
                .font(.system(size: 32))
                .foregroundStyle(PW.dawnGlow)

            Text("Allow unlock?")
                .font(.grotesk(16, weight: .semibold))
                .foregroundStyle(PW.textPrimary)

            HStack(spacing: 12) {
                Button(action: session.denyUnlock) {
                    Image(systemName: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PW.clay)

                Button(action: session.confirmUnlock) {
                    Image(systemName: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PW.sage)
            }
        }
        .padding()
    }
}
