import SwiftUI
import FamilyControls
import UIKit

struct HomeView: View {
    @StateObject private var vm = HomeViewModel(
        configStore: ConfigStore(),
        familyService: FamilyControlsService(),
        restrictionService: RestrictionService()
    )
    @ObservedObject private var shortcutManager = ShortcutManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPicker = false
    @State private var showingDisableSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if vm.config.isEnabled {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paperweight Active")
                                    .font(.body.bold())
                                Text("Tap to turn off (requires NFC token)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { showingDisableSheet = true }
                    } else {
                        Toggle("Paperweight Mode", isOn: Binding(
                            get: { false },
                            set: { newValue in
                                if newValue { Task { await enable() } }
                            }
                        ))
                        .tint(.orange)
                    }
                } footer: {
                    Text(vm.config.isEnabled
                         ? "Your selected apps are restricted."
                         : "Paperweight is off. All apps accessible.")
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Choose Apps & Categories", systemImage: "app.badge.checkmark")
                    }
                    let selectionSummary = vm.config.selection.summary
                    if selectionSummary.isEmpty {
                        Text("Nothing selected yet — tap above to choose")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        Text(selectionSummary)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                } header: {
                    Text("Restricted Apps")
                } footer: {
                    Text("The list may take a moment to populate on first open.")
                        .font(.footnote)
                }

                Section {
                    NavigationLink {
                        ScheduleView(vm: vm)
                    } label: {
                        HStack {
                            Text("Schedule")
                            Spacer()
                            scheduleStatus
                        }
                    }
                    NavigationLink("NFC Token & Recovery") {
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
            updateShortcutItems(isEnabled: isEnabled)
        }
        .onAppear { handlePendingShortcut() }
        .onChange(of: shortcutManager.pendingShortcutType) { _, _ in handlePendingShortcut() }
        .onChange(of: scenePhase) { _, phase in
            // Re-sync when returning to the app, in case the device was asleep
            // across a schedule boundary and the monitor didn't fire.
            if phase == .active {
                vm.syncRestrictions()
                if vm.config.isEnabled {
                    ScheduleService.shared.updateSchedule(vm.config.schedule)
                }
            }
        }
        .sheet(isPresented: $showingDisableSheet) {
            DisablePaperweightSheet(vm: vm)
        }
        .onAppear {
            updateShortcutItems(isEnabled: vm.config.isEnabled)
        }
    }

    @ViewBuilder
    private var scheduleStatus: some View {
        let schedule = vm.config.schedule
        if let schedule, !schedule.isEmpty {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if vm.config.isEnabled && !schedule.isFree(at: context.date) {
                    Label("Blocking", systemImage: "lock.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Set Up")
                .foregroundStyle(.secondary)
        }
    }

    private func enable() async {
        await vm.setEnabled(true)
        ScheduleService.shared.updateSchedule(vm.config.schedule)
    }

    private func handlePendingShortcut() {
        guard let type = shortcutManager.pendingShortcutType else { return }
        shortcutManager.pendingShortcutType = nil
        // Dispatch to the next run loop so the view is fully interactive
        // before attempting to enable or present a sheet.
        DispatchQueue.main.async {
            switch type {
            case "enable-paperweight":
                Task { await enable() }
            case "disable-paperweight":
                showingDisableSheet = true
            default:
                break
            }
        }
    }

    private func updateShortcutItems(isEnabled: Bool) {
        UIApplication.shared.shortcutItems = isEnabled
            ? [UIApplicationShortcutItem(
                type: "disable-paperweight",
                localizedTitle: "Turn Off Paperweight",
                localizedSubtitle: "Requires NFC token",
                icon: UIApplicationShortcutIcon(systemImageName: "lock.slash"),
                userInfo: nil)]
            : [UIApplicationShortcutItem(
                type: "enable-paperweight",
                localizedTitle: "Turn On Paperweight",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "lock.fill"),
                userInfo: nil)]
    }
}
