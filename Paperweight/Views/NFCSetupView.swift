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

            Section("Unlock Duration") {
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
        }
        .navigationTitle("NFC Token Setup")
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
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your NFC token has been saved. Keep it somewhere inconvenient.")
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

    private func scan() {
        isScanning = true
        Task {
            do {
                try await unlockService.registerTag()
                vm.config.registeredNFCTagUID = ConfigStore().load().registeredNFCTagUID
                vm.saveSelection()
                didRegister = true
            } catch is CancellationError {
                // user cancelled — silent
            } catch {
                self.error = error
            }
            isScanning = false
        }
    }
}
