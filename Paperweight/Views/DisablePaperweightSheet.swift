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
    @State private var requestingCoolOff = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                GlyphOrb(size: 76, systemName: "lock.slash", tint: PW.clay)
                    .padding(.bottom, 20)
                Text("Turn off Paperweight")
                    .font(.spectral(25)).foregroundStyle(PW.textPrimary)
                Text("Scan your NFC token to permanently remove all restrictions.")
                    .font(.grotesk(13.5)).foregroundStyle(PW.textMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10).padding(.horizontal, 20)

                Spacer(minLength: 24)

                AccentButton(title: "Scan NFC token", systemImage: "wave.3.right",
                             enabled: vm.config.registeredNFCTagUID != nil) {
                    Task { await scanAndConfirm() }
                }
                .padding(.bottom, 12)

                GhostButton(title: "Use a recovery code") { showingRecoveryEntry = true }

                Divider().overlay(PW.hairline).padding(.top, 22)

                coolOffSection.padding(.top, 18)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PW.surfaceRaised.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(PW.textMuted)
                }
            }
            .confirmationDialog("Turn off Paperweight?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Turn Off", role: .destructive) {
                    Task {
                        try? await vm.disablePaperweight()
                        ScheduleService.shared.updateSchedule(nil, enabled: false)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all app restrictions. You can re-arm Paperweight anytime by saving a schedule.")
            }
            .confirmationDialog("Start timed unlock?", isPresented: $requestingCoolOff, titleVisibility: .visible) {
                Button("Start \(vm.config.coolOffDays)-day Cool-off") { vm.requestCoolOffUnlock() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Paperweight stays on and keeps enforcing your schedule. After \(vm.config.coolOffDays) day\(vm.config.coolOffDays == 1 ? "" : "s") it lifts automatically. Use this only if your token is lost — scanning it or a recovery code unlocks immediately.")
            }
            .sheet(isPresented: $showingRecoveryEntry) {
                RecoveryCodeEntryView(vm: vm, onSuccess: { dismiss() })
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(error?.localizedDescription ?? "") }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var coolOffSection: some View {
        if vm.isCoolOffPending, let release = vm.config.coolOffReleaseDate {
            VStack(spacing: 8) {
                Label("Timed unlock in progress", systemImage: "hourglass")
                    .font(.grotesk(13.5, weight: .semibold)).foregroundStyle(PW.clay)
                Text("Lifts \(release.formatted(.relative(presentation: .named))) (\(release.formatted(date: .abbreviated, time: .shortened))).")
                    .font(.grotesk(11.5)).foregroundStyle(PW.textFaint)
                    .multilineTextAlignment(.center)
                Button("Cancel timed unlock") { vm.cancelCoolOffUnlock() }
                    .font(.grotesk(13)).foregroundStyle(PW.clay)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 4) {
                Button { requestingCoolOff = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 13))
                        Text("Lost your token? Start timed unlock").font(.grotesk(13.5))
                    }
                    .foregroundStyle(PW.clay)
                }
                .buttonStyle(.plain)
                Text("Releases on its own after a \(vm.config.coolOffDays)-day cool-off.")
                    .font(.grotesk(11.5)).foregroundStyle(PW.textFaint)
            }
            .frame(maxWidth: .infinity)
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
        } catch { self.error = error }
    }
}

struct RecoveryCodeEntryView: View {
    @ObservedObject var vm: HomeViewModel
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var showingInvalidAlert = false
    @State private var dissolving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                GlyphOrb(size: 72, systemName: "key.fill", tint: PW.dawnGlow)
                    .padding(.bottom, 20)
                Text(dissolving ? "Unlocked" : "Recovery code")
                    .font(.spectral(24)).foregroundStyle(PW.textPrimary)
                    .animation(.easeInOut, value: dissolving)
                Text(dissolving
                     ? "That code is spent. Paperweight is off."
                     : "Enter one of the single-use codes you saved. This will permanently disable Paperweight.")
                    .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10).padding(.horizontal, 20)

                if dissolving {
                    DissolveText(text: codeInput, dissolve: true)
                        .frame(height: 56)
                        .padding(.horizontal, 24).padding(.top, 28)
                } else {
                    TextField("", text: $codeInput, prompt: Text("XXXXX-XXXXX").foregroundColor(PW.textFaint))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .font(.grotesk(20, weight: .semibold))
                        .foregroundStyle(PW.textPrimary)
                        .tracking(0.14 * 20)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(PW.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(PW.hairline, lineWidth: 1))
                        .padding(.horizontal, 24).padding(.top, 28)

                    AccentButton(title: "Verify & disable Paperweight",
                                 enabled: !codeInput.trimmingCharacters(in: .whitespaces).isEmpty) {
                        verifyAndDisable()
                    }
                    .padding(.horizontal, 24).padding(.top, 18)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PW.surfaceRaised.ignoresSafeArea())
            .navigationTitle("Recovery Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !dissolving {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.foregroundStyle(PW.textMuted)
                    }
                }
            }
            .alert("Invalid Code", isPresented: $showingInvalidAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That code is incorrect or has already been used.")
            }
        }
        .interactiveDismissDisabled(dissolving)
    }

    private func verifyAndDisable() {
        guard let codeID = RecoveryCodeService.verify(codeInput, against: vm.config.recoveryCodes) else {
            showingInvalidAlert = true
            return
        }
        // Invalidate + disable immediately so the code is spent even if the app
        // is killed mid-animation, then play the dissolve and exit.
        vm.disableWithRecoveryCode(codeID)
        ScheduleService.shared.updateSchedule(nil, enabled: false)
        Task { @MainActor in
            withAnimation { dissolving = true }
            try? await Task.sleep(for: .seconds(1.3))
            dismiss()
            onSuccess()
        }
    }
}
