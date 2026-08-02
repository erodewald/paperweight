import SwiftUI
import FamilyControls

/// Everything Home used to be. v2 moves the list behind a gear so Home can be a
/// state, not a menu — and this is where the escape hatch lives, which is why
/// the locked Home still carries a route here.
struct SettingsView: View {
    @ObservedObject var vm: HomeViewModel
    @Binding var showingPicker: Bool
    var onTurnOff: () -> Void
    #if DEBUG
    @ObservedObject private var debug = DebugSettings.shared
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Restricted apps").pwScreenLabel()
                    .padding(.top, 6).padding(.bottom, 10)
                GroupedCard {
                    Button { showingPicker = true } label: {
                        NavRow(title: "Choose apps & categories",
                               systemImage: "app.badge.checkmark", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    if !vm.config.selection.isEmpty {
                        CardDivider()
                        RestrictedTokensList(selection: vm.config.selection)
                    }
                }

                Text("Configure").pwScreenLabel()
                    .padding(.top, 22).padding(.bottom, 10)
                GroupedCard {
                    NavigationLink { ScheduleView(vm: vm) } label: {
                        NavRow(title: "Schedule", value: scheduleStatusText)
                    }
                    CardDivider()
                    NavigationLink { NFCSetupView(vm: vm) } label: {
                        NavRow(title: "NFC Token & Recovery")
                    }
                    CardDivider()
                    NavigationLink { QuietThemePicker(vm: vm) } label: {
                        NavRow(title: "Theme", value: vm.config.quietTheme.title)
                    }
                    CardDivider()
                    NavigationLink { UnlockView(vm: vm) } label: {
                        NavRow(title: "Emergency unlock",
                               titleColor: vm.config.isEnabled ? PW.textPrimary : PW.textFaint,
                               value: vm.config.isEnabled ? nil : "Off",
                               valueColor: PW.textFaint,
                               showsChevron: vm.config.isEnabled)
                    }
                    .disabled(!vm.config.isEnabled)
                }

                if vm.config.isEnabled {
                    Text("Deviation").pwScreenLabel()
                        .padding(.top, 22).padding(.bottom, 10)
                    GroupedCard {
                        Button(action: onTurnOff) {
                            NavRow(title: "Turn off Paperweight",
                                   titleColor: PW.clay,
                                   value: vm.isCoolOffPending ? "Cool-off running" : nil,
                                   valueColor: PW.clay,
                                   showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                #if DEBUG
                Text("Developer").pwScreenLabel()
                    .padding(.top, 22).padding(.bottom, 10)
                GroupedCard {
                    Toggle(isOn: $debug.forceQuiet) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Force quiet screen")
                                .font(.grotesk(15))
                                .foregroundStyle(PW.textPrimary)
                            Text("Shows the quiet screen without arming anything. Nothing is actually blocked.")
                                .font(.grotesk(13))
                                .foregroundStyle(PW.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(PWToggleStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    CardDivider()

                    Button {
                        Task { try? await vm.disablePaperweight() }
                    } label: {
                        NavRow(title: "Turn off without a token",
                               titleColor: PW.clay,
                               showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }

                Text("Debug builds only — none of this exists in a release build.")
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scheduleStatusText: String {
        guard let s = vm.config.schedule, !s.isEmpty else { return "Set up" }
        if vm.config.isEnabled && !s.isFree(at: Date()) { return "Quiet now" }
        return "Ready"
    }
}
