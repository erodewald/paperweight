import SwiftUI

struct ConfirmUnlockView: View {
    @ObservedObject var session: WatchSessionService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Allow unlock?")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: session.denyUnlock) {
                    Image(systemName: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: session.confirmUnlock) {
                    Image(systemName: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
    }
}
