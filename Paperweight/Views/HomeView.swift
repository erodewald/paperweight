import SwiftUI
import FamilyControls

struct HomeView: View {
    @StateObject private var vm = HomeViewModel(
        configStore: ConfigStore(),
        familyService: FamilyControlsService(),
        restrictionService: RestrictionService()
    )
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Paperweight Mode", isOn: Binding(
                        get: { vm.config.isEnabled },
                        set: { newValue in Task { await vm.setEnabled(newValue) } }
                    ))
                    .tint(.orange)
                } footer: {
                    Text(vm.config.isEnabled
                         ? "Your selected apps are restricted."
                         : "Paperweight is off. All apps accessible.")
                }

                Section("Restricted Apps") {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Choose Apps to Restrict", systemImage: "app.badge.checkmark")
                    }
                    let count = vm.config.selection.applicationTokens.count
                    if count > 0 {
                        Text("\(count) app\(count == 1 ? "" : "s") selected")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink("Schedule") {
                        ScheduleView(vm: vm)
                    }
                    NavigationLink("NFC Unlock Token") {
                        NFCSetupView(vm: vm)
                    }
                    NavigationLink("Emergency Unlock") {
                        UnlockView(vm: vm)
                    }
                }
            }
            .navigationTitle("Paperweight")
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil },
                set: { if !$0 { vm.error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.error?.localizedDescription ?? "")
            }
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $vm.config.selection)
        .onChange(of: showingPicker) { _, isPresented in
            if !isPresented { vm.saveSelection() }
        }
        .onChange(of: vm.config.isEnabled) { _, isEnabled in
            WatchConnectivityService.shared.sendStatusUpdate(
                isEnabled: isEnabled,
                isUnlocked: false,
                unlockExpires: nil
            )
        }
    }
}
