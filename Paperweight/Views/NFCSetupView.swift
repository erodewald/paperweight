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

    var body: some View {
        Form {
            Section {
                if let uid = vm.config.registeredNFCTagUID {
                    LabeledContent("Registered Token", value: uid)
                    Button("Replace Token", role: .destructive) { scan() }
                } else {
                    Button("Register NFC Token") { scan() }
                }
            } header: {
                Text("Physical Token")
            } footer: {
                Text("Tap your NFC sticker to register it. Place the sticker on an object you won't carry everywhere.")
            }

            Section {
                Picker("Duration", selection: Binding(
                    get: { vm.config.unlockDuration },
                    set: { vm.config.unlockDuration = $0; vm.saveSelection() }
                )) {
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                    Text("30 min").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Unlock Duration")
            }

            Section {
                Toggle("Require Watch tap to unlock", isOn: Binding(
                    get: { vm.config.requireWatchConfirmation },
                    set: { vm.config.requireWatchConfirmation = $0; vm.saveSelection() }
                ))
            } header: {
                Text("Watch Confirmation")
            } footer: {
                Text("When on and a Watch is paired, the unlock button on your Watch must be tapped after NFC scan.")
            }

            Section {
                let unused = vm.config.recoveryCodes.filter { !$0.isUsed }.count
                if vm.config.recoveryCodes.isEmpty {
                    Button("Generate Recovery Codes") { generateCodes() }
                } else {
                    LabeledContent("Codes Remaining", value: "\(unused) of \(RecoveryCodeService.codeCount)")
                    Button("Regenerate All Codes", role: .destructive) { generateCodes() }
                }
            } header: {
                Text("Recovery Codes")
            } footer: {
                Text("Single-use backup codes to disable Paperweight if your NFC token is lost. Generated codes are shown once — save them somewhere safe.")
            }

            Section {
                Picker("Auto-unlock after", selection: Binding(
                    get: { vm.config.maxLockedDays ?? 0 },
                    set: { vm.config.maxLockedDays = $0 == 0 ? nil : $0; vm.saveSelection() }
                )) {
                    Text("Never (not recommended)").tag(0)
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
            } header: {
                Text("Auto-Unlock Failsafe")
            } footer: {
                Text("If Paperweight is still active this many days after being enabled, all restrictions lift automatically. Prevents permanent lockout.")
            }
        }
        .navigationTitle("NFC Token & Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isScanning {
                ProgressView("Scanning…")
                    .padding()
                    .background(.regularMaterial)
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
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
        .sheet(isPresented: $showingCodes) {
            RecoveryCodesView(codes: generatedCodes)
        }
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
            } catch {
                self.error = error
            }
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
