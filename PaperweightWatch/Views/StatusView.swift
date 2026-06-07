import SwiftUI

struct StatusView: View {
    @StateObject private var session = WatchSessionService.shared

    var body: some View {
        ZStack {
            if session.unlockConfirmationPending {
                ConfirmUnlockView(session: session)
            } else {
                mainStatus
            }
        }
        .animation(.easeInOut, value: session.unlockConfirmationPending)
    }

    @ViewBuilder
    private var mainStatus: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(iconColor)

            Text(statusText)
                .font(.headline)
                .multilineTextAlignment(.center)

            if session.status.isUnlocked, let exp = session.status.unlockExpires {
                Text("Until \(exp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var iconName: String {
        if session.status.isUnlocked { return "lock.open.fill" }
        if session.status.isEnabled { return "lock.fill" }
        return "lock.slash"
    }

    private var iconColor: Color {
        if session.status.isUnlocked { return .green }
        if session.status.isEnabled { return .orange }
        return .gray
    }

    private var statusText: String {
        if session.status.isUnlocked { return "Unlocked" }
        if session.status.isEnabled { return "Paperweight On" }
        return "Paperweight Off"
    }
}
