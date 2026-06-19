import SwiftUI

struct DisablePaperweightSheet: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var unlockService = UnlockService(
        nfcService: NFCService(),
        restrictionService: RestrictionService()
    )
    @State private var showingRecoveryEntry = false
    @State private var confirming = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "lock.slash")
                    .font(.system(size: 72))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text("Turn Off Paperweight")
                        .font(.title2.bold())
                    Text("Scan your NFC token to permanently remove all restrictions.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    Button {
                        Task { await scanAndConfirm() }
                    } label: {
                        Label("Scan NFC Token", systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(vm.config.registeredNFCTagUID == nil)

                    Button("Use Recovery Code Instead") {
                        showingRecoveryEntry = true
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Disable Paperweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Turn off Paperweight?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Turn Off", role: .destructive) {
                    Task {
                        try? await vm.disablePaperweight()
                        ScheduleService.shared.updateSchedule(nil)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all app restrictions. You can re-enable Paperweight anytime from the main screen.")
            }
            .sheet(isPresented: $showingRecoveryEntry) {
                RecoveryCodeEntryView(vm: vm, onSuccess: { dismiss() })
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error?.localizedDescription ?? "")
            }
        }
    }

    private func scanAndConfirm() async {
        do {
            try await unlockService.verifyTag()
            if vm.config.requireWatchConfirmation && WatchConnectivityService.shared.watchIsReachable {
                let confirmed = await WatchConnectivityService.shared.requestWatchConfirmation()
                guard confirmed else { return }
            }
            confirming = true
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}

struct RecoveryCodeEntryView: View {
    @ObservedObject var vm: HomeViewModel
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var showingInvalidAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text("Recovery Code")
                        .font(.title2.bold())
                    Text("Enter one of the single-use codes you saved when setting up your NFC token. This will permanently disable Paperweight.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                TextField("XXXXX-XXXXX", text: $codeInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .font(.system(.title3, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                Button("Verify & Disable Paperweight") {
                    verifyAndDisable()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Recovery Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Invalid Code", isPresented: $showingInvalidAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That code is incorrect or has already been used.")
            }
        }
    }

    private func verifyAndDisable() {
        guard let codeID = RecoveryCodeService.verify(codeInput, against: vm.config.recoveryCodes) else {
            showingInvalidAlert = true
            return
        }
        if let idx = vm.config.recoveryCodes.firstIndex(where: { $0.id == codeID }) {
            vm.config.recoveryCodes[idx].isUsed = true
        }
        Task {
            try? await vm.disablePaperweight()
            ScheduleService.shared.updateSchedule(nil)
            onSuccess()
        }
    }
}
