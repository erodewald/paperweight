import SwiftUI

struct NFCSetupView: View {
    @ObservedObject var vm: HomeViewModel
    @StateObject private var unlockService = UnlockService(
        nfcService: NFCService(),
        restrictionService: RestrictionService()
    )
    @State private var isScanning = false
    @State private var error: Error?
    @State private var didRegister = false
    @State private var generatedCodes: [String] = []
    @State private var showingCodes = false

    private let durations: [(value: TimeInterval, label: String)] =
        [(300, "5m"), (900, "15m"), (1800, "30m"), (3600, "1h")]
    private let coolOffs: [(value: Int, label: String)] = [(1, "1 day"), (2, "2 days"), (3, "3 days")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                SectionHeader(text: "Physical Token").padding(.bottom, 9)
                GroupedCard {
                    if let uid = vm.config.registeredNFCTagUID {
                        HStack(spacing: 12) {
                            Image(systemName: "wave.3.forward")
                                .font(.system(size: 16)).foregroundStyle(PW.sage).frame(width: 18)
                            Text("Registered Token").font(.grotesk(14.5)).foregroundStyle(PW.textPrimary)
                            Spacer()
                            Text(uid).font(.grotesk(12.5)).foregroundStyle(PW.textMuted).tracking(0.5)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        CardDivider()
                        Button { scan() } label: {
                            Text("Replace Token").font(.grotesk(14.5)).foregroundStyle(PW.clay)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    } else {
                        Button { scan() } label: {
                            Text("Register NFC Token").font(.grotesk(14.5)).foregroundStyle(PW.sage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Text("Tap your NFC sticker to register it. Place it on an object you won't carry everywhere.")
                    .font(.grotesk(11.5)).foregroundStyle(PW.textFaint)
                    .padding(.horizontal, 8).padding(.top, 8)

                SectionHeader(text: "Unlock Duration").padding(.top, 22).padding(.bottom, 9)
                PWSegmented(options: durations, selection: Binding(
                    get: { vm.config.unlockDuration },
                    set: { vm.config.unlockDuration = $0; vm.saveSelection() }))

                SectionHeader(text: "Watch Confirmation").padding(.top, 22).padding(.bottom, 9)
                GroupedCard {
                    Toggle(isOn: Binding(
                        get: { vm.config.requireWatchConfirmation },
                        set: { vm.config.requireWatchConfirmation = $0; vm.saveSelection() }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Require Watch tap").font(.grotesk(14.5)).foregroundStyle(PW.textPrimary)
                            Text("Confirm unlocks on your wrist").font(.grotesk(11.5)).foregroundStyle(PW.textFaint)
                        }
                    }
                    .toggleStyle(PWToggleStyle())
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }

                SectionHeader(text: "Recovery Codes").padding(.top, 22).padding(.bottom, 9)
                GroupedCard {
                    if vm.config.recoveryCodes.isEmpty {
                        Button { generateCodes() } label: {
                            Text("Generate Recovery Codes").font(.grotesk(14.5)).foregroundStyle(PW.sage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    } else {
                        let unused = vm.config.recoveryCodes.filter { !$0.isUsed }.count
                        HStack {
                            Text("Codes Remaining").font(.grotesk(14.5)).foregroundStyle(PW.textPrimary)
                            Spacer()
                            Text("\(unused) of \(RecoveryCodeService.codeCount)")
                                .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        CardDivider()
                        HStack {
                            Text("Cool-off if token lost").font(.grotesk(13.5)).foregroundStyle(PW.textFaint)
                            Spacer()
                            Menu {
                                ForEach(coolOffs, id: \.value) { o in
                                    Button(o.label) { vm.config.coolOffDays = o.value; vm.saveSelection() }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(coolOffLabel).font(.grotesk(13)).foregroundStyle(PW.textMuted)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10)).foregroundStyle(PW.textFaint)
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        CardDivider()
                        Button { generateCodes() } label: {
                            Text("Regenerate All Codes").font(.grotesk(14.5)).foregroundStyle(PW.clay)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Text("Single-use backup codes to disable Paperweight if your token is lost. Shown once — save them somewhere safe.")
                    .font(.grotesk(11.5)).foregroundStyle(PW.textFaint)
                    .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("NFC Token & Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isScanning {
                ProgressView("Scanning…")
                    .tint(PW.sage)
                    .padding().background(PW.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Token Registered", isPresented: $didRegister) {
            Button("Generate Recovery Codes Now") { generateCodes() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Your NFC token has been saved. Generate recovery codes now in case you ever lose it.")
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error?.localizedDescription ?? "") }
        .sheet(isPresented: $showingCodes) {
            RecoveryCodesView(codes: generatedCodes)
        }
    }

    private var coolOffLabel: String {
        "\(vm.config.coolOffDays) day\(vm.config.coolOffDays == 1 ? "" : "s")"
    }

    private func scan() {
        isScanning = true
        Task {
            do {
                try await unlockService.registerTag()
                vm.config.registeredNFCTagUID = ConfigStore().load().registeredNFCTagUID
                vm.saveSelection()
                didRegister = true
            } catch is CancellationError {
            } catch { self.error = error }
            isScanning = false
        }
    }

    private func generateCodes() {
        let pairs = RecoveryCodeService.generateCodes()
        vm.config.recoveryCodes = pairs.map(\.model)
        vm.saveSelection()
        generatedCodes = pairs.map(\.plain)
        showingCodes = true
    }
}
