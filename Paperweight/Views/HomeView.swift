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
    @State private var showingSettings = false

    /// Quiet: armed and restricting right now (a scheduled blocked period, or
    /// always-blocked when no schedule is set).
    private var isQuiet: Bool {
        guard vm.config.isEnabled else { return false }
        if let s = vm.config.schedule, !s.isEmpty { return !s.isFree(at: Date()) }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PW.black.ignoresSafeArea()
                if isQuiet {
                    QuietScreen(vm: vm, onSettings: { showingSettings = true })
                } else {
                    settingsList
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showingSettings) {
                // Pushed from the Quiet screen — keep a bar so there's a back button.
                settingsList
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .tint(PW.sage)
        .familyActivityPicker(
            headerText: "Choose apps and categories to restrict.",
            footerText: "Do not select Paperweight itself — blocking it could lock you out of these controls.",
            isPresented: $showingPicker,
            selection: $vm.config.selection)
        .onChange(of: showingPicker) { _, isPresented in
            if !isPresented { vm.saveSelection() }
        }
        .onChange(of: vm.config.isEnabled) { _, isEnabled in
            WatchConnectivityService.shared.sendStatusUpdate(
                isEnabled: isEnabled, isUnlocked: false, unlockExpires: nil)
            updateShortcutItems(isEnabled: isEnabled)
        }
        .onAppear { handlePendingShortcut(); updateShortcutItems(isEnabled: vm.config.isEnabled) }
        .onChange(of: shortcutManager.pendingShortcutType) { _, _ in handlePendingShortcut() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vm.syncRestrictions()
                ScheduleService.shared.updateSchedule(vm.config.schedule, enabled: vm.config.isEnabled)
            }
        }
        .sheet(isPresented: $showingDisableSheet) {
            DisablePaperweightSheet(vm: vm)
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil }, set: { if !$0 { vm.error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(vm.error?.localizedDescription ?? "") }
    }

    // MARK: - Settings list

    private var settingsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Paperweight")
                    .font(.spectral(34))
                    .foregroundStyle(PW.textPrimary)
                    .padding(.top, 18)
                    .padding(.bottom, 18)

                statusCard
                    .padding(.bottom, 8)

                SectionHeader(text: "Restricted Apps").padding(.top, 16).padding(.bottom, 10)
                GroupedCard {
                    Button { showingPicker = true } label: {
                        NavRow(title: "Choose Apps & Categories",
                               systemImage: "app.badge.checkmark", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    if !vm.config.selection.isEmpty {
                        CardDivider()
                        RestrictedTokensList(selection: vm.config.selection)
                    }
                }

                SectionHeader(text: "Configure").padding(.top, 22).padding(.bottom, 10)
                GroupedCard {
                    NavigationLink { ScheduleView(vm: vm) } label: {
                        NavRow(title: "Schedule", value: scheduleStatusText)
                    }
                    CardDivider()
                    NavigationLink { NFCSetupView(vm: vm) } label: {
                        NavRow(title: "NFC Token & Recovery")
                    }
                    CardDivider()
                    NavigationLink { UnlockView(vm: vm) } label: {
                        NavRow(title: "Emergency Unlock",
                               titleColor: vm.config.isEnabled ? PW.textPrimary : PW.textFaint,
                               value: vm.config.isEnabled ? nil : "Off",
                               valueColor: PW.textFaint,
                               showsChevron: vm.config.isEnabled)
                    }
                    .disabled(!vm.config.isEnabled)
                }

                Text("Put it down. The world keeps turning.")
                    .font(.spectral(14, italic: true))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 18)
        }
        .scrollContentBackground(.hidden)
        .background(PW.black.ignoresSafeArea())
    }

    @ViewBuilder
    private var statusCard: some View {
        if vm.config.isEnabled {
            Button { showingDisableSheet = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: vm.isCoolOffPending ? "hourglass" : "lock.fill")
                        .foregroundStyle(vm.isCoolOffPending ? PW.clay : PW.sage)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Paperweight active").font(.grotesk(15, weight: .semibold))
                            .foregroundStyle(PW.textPrimary)
                        if vm.isCoolOffPending, let release = vm.config.coolOffReleaseDate {
                            Text("Timed unlock lifts \(release.formatted(.relative(presentation: .named)))")
                                .font(.grotesk(12.5)).foregroundStyle(PW.clay)
                        } else {
                            Text("Tap to turn off (requires NFC token)")
                                .font(.grotesk(12.5)).foregroundStyle(PW.textMuted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(PW.textFaint)
                }
                .padding(18)
                .background(PW.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PW.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("Paperweight is off").font(.grotesk(15, weight: .semibold))
                    .foregroundStyle(PW.textPrimary)
                Text("Set a schedule below to arm it. Restrictions then apply on their own — no switch to forget.")
                    .font(.grotesk(12.5)).foregroundStyle(PW.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(PW.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(PW.hairline, lineWidth: 1))
        }
    }

    private var scheduleStatusText: String {
        guard let s = vm.config.schedule, !s.isEmpty else { return "Set up" }
        if vm.config.isEnabled && !s.isFree(at: Date()) { return "Quiet now" }
        return "Ready"
    }

    // MARK: - Shortcuts (unchanged behavior)

    private func enable() async {
        await vm.setEnabled(true)
        ScheduleService.shared.updateSchedule(vm.config.schedule, enabled: true)
    }

    private func handlePendingShortcut() {
        guard let type = shortcutManager.pendingShortcutType else { return }
        shortcutManager.pendingShortcutType = nil
        DispatchQueue.main.async {
            switch type {
            case "enable-paperweight": Task { await enable() }
            case "disable-paperweight": showingDisableSheet = true
            default: break
            }
        }
    }

    private func updateShortcutItems(isEnabled: Bool) {
        UIApplication.shared.shortcutItems = isEnabled
            ? [UIApplicationShortcutItem(
                type: "disable-paperweight", localizedTitle: "Turn Off Paperweight",
                localizedSubtitle: "Requires NFC token",
                icon: UIApplicationShortcutIcon(systemImageName: "lock.slash"), userInfo: nil)]
            : [UIApplicationShortcutItem(
                type: "enable-paperweight", localizedTitle: "Turn On Paperweight",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "lock.fill"), userInfo: nil)]
    }
}

// MARK: - Restricted tokens list

/// Enumerates the actual restricted apps/categories using FamilyControls' own
/// `Label(token)` views (real names + icons). App names are privacy-gated and
/// can't be read as strings, so we render the system labels directly.
private struct RestrictedTokensList: View {
    let selection: FamilyActivitySelection
    private let limit = 6

    var body: some View {
        let apps = Array(selection.applicationTokens)
        let cats = Array(selection.categoryTokens)
        let webs = Array(selection.webDomainTokens)
        let total = apps.count + cats.count + webs.count

        return VStack(spacing: 0) {
            ForEach(apps.prefix(limit), id: \.self) { token in
                tokenRow { Label(token) }
            }
            ForEach(cats.prefix(max(0, limit - apps.count)), id: \.self) { token in
                tokenRow { Label(token) }
            }
            ForEach(webs.prefix(max(0, limit - apps.count - cats.count)), id: \.self) { token in
                tokenRow { Label(token) }
            }
            if total > limit {
                tokenRow {
                    Text("+\(total - limit) more")
                        .font(.grotesk(12.5)).foregroundStyle(PW.textMuted)
                }
            }
        }
    }

    private func tokenRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.grotesk(14))
            .foregroundStyle(PW.textPrimary)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .overlay(alignment: .top) { CardDivider() }
    }
}

// MARK: - Quiet screen

private struct QuietScreen: View {
    @ObservedObject var vm: HomeViewModel
    var onSettings: () -> Void

    private let encouragements = [
        "Nothing here needs you right now. That's the gift.",
        "The world is still turning without the scroll.",
        "Let it be heavy. Let it be quiet.",
        "You set this down on purpose. Well done."
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let quiet = vm.config.schedule?.quietStatus(at: context.date)
            VStack(spacing: 0) {
                Text("Brick Mode")
                    .font(.grotesk(11, weight: .medium))
                    .tracking(3.0)
                    .textCase(.uppercase)
                    .foregroundStyle(PW.textFaint)
                    .padding(.top, 22)

                Spacer()

                ZStack {
                    OrbGlow(size: 240)
                    ProgressRing(progress: quiet?.remainingFraction ?? 1, size: 180)
                    GlassOrb(size: 104)
                }

                if let quiet {
                    Text(Self.format(quiet.remaining))
                        .font(.grotesk(34, weight: .bold))
                        .foregroundStyle(PW.textPrimary)
                        .padding(.top, 30)
                    Text("of quiet remaining")
                        .font(.spectral(17, italic: true))
                        .foregroundStyle(PW.encourage)
                        .padding(.top, 4)
                } else {
                    Text("Quiet")
                        .font(.grotesk(28, weight: .bold))
                        .foregroundStyle(PW.textPrimary)
                        .padding(.top, 30)
                }

                Spacer()

                Text(encouragements[encouragementIndex])
                    .font(.spectral(16, italic: true))
                    .foregroundStyle(PW.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 22)

                Divider().overlay(PW.hairline)
                HStack {
                    Text(appsQuietLabel).font(.grotesk(13)).foregroundStyle(PW.textFaint)
                    Spacer()
                    Button(action: onSettings) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape").font(.system(size: 13))
                            Text("Settings").font(.grotesk(13))
                        }
                        .foregroundStyle(PW.moss)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
                .padding(.top, 16)
                .padding(.bottom, 22)
            }
        }
    }

    private var appsQuietLabel: String {
        let apps = vm.config.selection.applicationTokens.count
        let cats = vm.config.selection.categoryTokens.count
        if apps > 0 { return "\(apps) app\(apps == 1 ? "" : "s") quiet" }
        if cats > 0 { return "\(cats) categor\(cats == 1 ? "y" : "ies") quiet" }
        return "Apps quiet"
    }

    private var encouragementIndex: Int {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return day % encouragements.count
    }

    private static func format(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
