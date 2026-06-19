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
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: unlockService.isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 80))
                .foregroundStyle(unlockService.isUnlocked ? .green : .orange)
                .animation(.spring(), value: unlockService.isUnlocked)

            if unlockService.isUnlocked, let expires = unlockService.unlockExpiresAt {
                VStack(spacing: 8) {
                    Text("Unlocked")
                        .font(.title2.bold())
                    Text("Re-locks at \(expires.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                    Button("Re-lock Now") { unlockService.relock() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Emergency Unlock")
                        .font(.title2.bold())
                    Text("Tap your NFC token to temporarily lift restrictions.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task {
                        do {
                            try await unlockService.verifyTag()
                            if vm.config.requireWatchConfirmation && WatchConnectivityService.shared.watchIsReachable {
                                let confirmed = await WatchConnectivityService.shared.requestWatchConfirmation()
                                guard confirmed else { return }
                            }
                            unlockService.grantUnlock(duration: vm.config.unlockDuration)
                        }
                        catch is CancellationError { }
                        catch { self.error = error }
                    }
                } label: {
                    Label("Scan Token", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.config.registeredNFCTagUID == nil)

                if !vm.config.recoveryCodes.filter({ !$0.isUsed }).isEmpty {
                    Button("Lost your token? Use a recovery code") {
                        showingRecoveryEntry = true
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Unlock")
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
        .sheet(isPresented: $showingRecoveryEntry) {
            RecoveryCodeEntryView(vm: vm, onSuccess: {})
        }
        .onChange(of: unlockService.isUnlocked) { _, isUnlocked in
            WatchConnectivityService.shared.sendStatusUpdate(
                isEnabled: vm.config.isEnabled,
                isUnlocked: isUnlocked,
                unlockExpires: unlockService.unlockExpiresAt
            )
        }
    }
}
