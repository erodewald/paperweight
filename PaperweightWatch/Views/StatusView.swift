import SwiftUI

struct StatusView: View {
    @StateObject private var session = WatchSessionService.shared

    var body: some View {
        ZStack {
            PW.black.ignoresSafeArea()
            mainStatus
        }
    }

    @ViewBuilder
    private var mainStatus: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(iconColor)

            Text(statusText)
                .font(.grotesk(16, weight: .semibold))
                .foregroundStyle(PW.textPrimary)
                .multilineTextAlignment(.center)

            if session.status.isUnlocked, let exp = session.status.unlockExpires {
                Text("Until \(exp.formatted(date: .omitted, time: .shortened))")
                    .font(.grotesk(12))
                    .foregroundStyle(PW.textMuted)
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
        if session.status.isUnlocked { return PW.dawnGlow }
        if session.status.isEnabled { return PW.sage }
        return PW.textFaint
    }

    private var statusText: String {
        if session.status.isUnlocked { return "Unlocked" }
        if session.status.isEnabled { return "Paperweight On" }
        return "Paperweight Off"
    }
}
