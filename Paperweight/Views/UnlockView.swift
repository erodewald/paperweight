import SwiftUI

struct UnlockView: View {
    @ObservedObject var vm: HomeViewModel
    @StateObject private var unlockService = UnlockService(
        nfcService: NFCService(),
        restrictionService: RestrictionService()
    )
    @State private var error: Error?
    @State private var showingRecoveryEntry = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                if !unlockService.isUnlocked {
                    NFCWaves(size: 150)
                }
                GlyphOrb(size: 116,
                         systemName: unlockService.isUnlocked ? "lock.open" : "lock",
                         tint: unlockService.isUnlocked ? PW.sage : PW.dawnGlow)
                    .animation(.spring(), value: unlockService.isUnlocked)
            }
            .padding(.bottom, 36)

            if unlockService.isUnlocked, let expires = unlockService.unlockExpiresAt {
                Text("Unlocked")
                    .font(.spectral(26)).foregroundStyle(PW.textPrimary)
                Text("Re-locks at \(expires.formatted(date: .omitted, time: .shortened))")
                    .font(.grotesk(14)).foregroundStyle(PW.textMuted)
                    .padding(.top, 12)
            } else {
                Text("Emergency unlock")
                    .font(.spectral(26)).foregroundStyle(PW.textPrimary)
                Text("Tap your NFC token to lift restrictions for \(unlockMinutes) minutes.")
                    .font(.grotesk(14)).foregroundStyle(PW.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .padding(.horizontal, 36)
            }

            Spacer()

            if unlockService.isUnlocked {
                GhostButton(title: "Re-lock now", tint: PW.clay,
                            borderColor: PW.clay.opacity(0.35)) { unlockService.relock() }
                    .padding(.horizontal, 30)
            } else {
                AccentButton(title: "Scan token", systemImage: "wave.3.right",
                             enabled: vm.config.registeredNFCTagUID != nil) {
                    scan()
                }
                .padding(.horizontal, 30)

                if !vm.config.recoveryCodes.filter({ !$0.isUsed }).isEmpty {
                    Button { showingRecoveryEntry = true } label: {
                        (Text("Lost your token? ").foregroundStyle(PW.textFaint)
                         + Text("Use a recovery code").foregroundStyle(PW.textMuted).underline())
                            .font(.grotesk(13))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
            }
        }
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pwScreen()
        .navigationTitle("Unlock")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error?.localizedDescription ?? "") }
        .sheet(isPresented: $showingRecoveryEntry) {
            RecoveryCodeEntryView(vm: vm, onSuccess: {})
        }
        .onChange(of: unlockService.isUnlocked) { _, isUnlocked in
            WatchConnectivityService.shared.sendStatusUpdate(
                isEnabled: vm.config.isEnabled,
                isUnlocked: isUnlocked,
                unlockExpires: unlockService.unlockExpiresAt)
        }
    }

    private var unlockMinutes: Int { Int(vm.config.unlockDuration / 60) }

    private func scan() {
        Task {
            do {
                try await unlockService.verifyTag()
                if vm.config.requireWatchConfirmation && WatchConnectivityService.shared.watchIsReachable {
                    let confirmed = await WatchConnectivityService.shared.requestWatchConfirmation()
                    guard confirmed else { return }
                }
                unlockService.grantUnlock(duration: vm.config.unlockDuration)
            } catch is CancellationError {
            } catch { self.error = error }
        }
    }
}
