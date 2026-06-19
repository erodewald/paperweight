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
    /// Whether the full-screen Quiet orb is presented over the settings root.
    @State private var showQuiet = false
    @State private var footerLine = Phrases.homeFooter.randomElement() ?? ""
    /// Selection captured when the picker opens, to detect (and gate) removals.
    @State private var selectionSnapshot: FamilyActivitySelection?
    @State private var selectionRevertMessage: String?

    /// Quiet: armed and restricting right now (a scheduled blocked period, or
    /// always-blocked when no schedule is set).
    private var isQuiet: Bool {
        guard vm.config.isEnabled else { return false }
        if let s = vm.config.schedule, !s.isEmpty { return !s.isFree(at: Date()) }
        return true
    }

    var body: some View {
        ZStack {
            NavigationStack {
                settingsList
                    .navigationBarHidden(true)
            }
            .tint(PW.sage)

            // Quiet orb sits ABOVE a stable settings root as a plain overlay (not
            // a sheet/cover, which failed to present at cold launch). The root
            // never swaps, so pushing/popping the schedule stays clean.
            if showQuiet {
                QuietScreen(
                    vm: vm,
                    onUnlock: { showQuiet = false; showingDisableSheet = true },
                    onSettings: { showQuiet = false })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PW.black.ignoresSafeArea())
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showQuiet)
        .familyActivityPicker(
            headerText: "Choose apps and categories to restrict.",
            footerText: "Do not select Paperweight itself — blocking it could lock you out of these controls.",
            isPresented: $showingPicker,
            selection: $vm.config.selection)
        .onChange(of: showingPicker) { _, isPresented in
            if isPresented {
                selectionSnapshot = vm.config.selection
            } else {
                commitSelectionChange()
            }
        }
        .onChange(of: vm.config.isEnabled) { _, isEnabled in
            updateShortcutItems(isEnabled: isEnabled)
        }
        .onChange(of: isQuiet) { _, quiet in showQuiet = quiet }
        .onAppear {
            showQuiet = isQuiet
            handlePendingShortcut()
            updateShortcutItems(isEnabled: vm.config.isEnabled)
        }
        .onChange(of: shortcutManager.pendingShortcutType) { _, _ in handlePendingShortcut() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vm.syncRestrictions()
                ScheduleService.shared.updateSchedule(vm.config.schedule, enabled: vm.config.isEnabled)
                showQuiet = isQuiet
            }
        }
        .sheet(isPresented: $showingDisableSheet) {
            DisablePaperweightSheet(vm: vm)
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil }, set: { if !$0 { vm.error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(vm.error?.localizedDescription ?? "") }
        .alert("Change reverted", isPresented: Binding(
            get: { selectionRevertMessage != nil }, set: { if !$0 { selectionRevertMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(selectionRevertMessage ?? "") }
    }

    /// Applies a picker change. While Paperweight is active, *removing* any app
    /// or category requires an NFC token scan first (adding is always allowed);
    /// an unverified removal is reverted.
    private func commitSelectionChange() {
        let old = selectionSnapshot ?? FamilyActivitySelection()
        let new = vm.config.selection
        let removedSomething =
            !old.applicationTokens.isSubset(of: new.applicationTokens) ||
            !old.categoryTokens.isSubset(of: new.categoryTokens) ||
            !old.webDomainTokens.isSubset(of: new.webDomainTokens)

        guard vm.config.isEnabled, removedSomething else {
            vm.saveSelection()
            return
        }

        // Don't persist/apply the reduced set until the token is verified — the
        // old shield stays in force during the scan.
        Task { @MainActor in
            let unlock = UnlockService(nfcService: NFCService.shared)
            do {
                try await unlock.verifyTag()
                vm.saveSelection()   // verified — keep the change
            } catch is CancellationError {
                vm.config.selection = old
                vm.saveSelection()
            } catch {
                vm.config.selection = old
                vm.saveSelection()
                selectionRevertMessage = "Removing a blocked app needs your NFC token. Your list is unchanged."
            }
        }
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

                Text(footerLine)
                    .font(.spectral(14, italic: true))
                    .foregroundStyle(PW.textFaint)
                    .multilineTextAlignment(.center)
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
            case "disable-paperweight":
                // Drop the Quiet cover first so the sheet isn't hidden beneath it.
                showQuiet = false
                showingDisableSheet = true
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
    var onUnlock: () -> Void
    var onSettings: () -> Void

    @State private var line = Phrases.quiet.randomElement() ?? ""

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

                Text(line)
                    .font(.spectral(16, italic: true))
                    .foregroundStyle(PW.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 18)
                    .onAppear { line = Phrases.quiet.randomElement() ?? line }

                HoldToUnlockButton(onComplete: onUnlock)
                    .padding(.horizontal, 44)
                    .padding(.bottom, 18)

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
                .padding(.top, 14)
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

    private static func format(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Hold to unlock

/// A press-and-hold control: the fill accelerates (ease-in, slow → fast) as you
/// hold, with haptic pulses that quicken and intensify to match, then a success
/// thunk on completion (opens the NFC turn-off flow). Deliberate by design — a
/// moment of intention rather than a tap.
private struct HoldToUnlockButton: View {
    var onComplete: () -> Void

    private let duration: Double = 1.3
    private let easeExponent: Double = 2.2    // >1 = slow start, fast finish
    private let hapticStep: CGFloat = 0.06    // pulse every 6% of (eased) progress

    @State private var progress: CGFloat = 0
    @State private var holdStart: Date?
    @State private var lastHapticStep = 0
    @State private var timer: Timer?
    @State private var completed = false
    @State private var impact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Capsule().fill(PW.surface)
            GeometryReader { geo in
                Capsule()
                    .fill(PW.sage.opacity(0.28))
                    .frame(width: geo.size.width * progress)
            }
            .clipShape(Capsule())
            HStack(spacing: 8) {
                Image(systemName: "lock.open").font(.system(size: 14))
                Text("Hold to unlock").font(.grotesk(14, weight: .medium))
            }
            .foregroundStyle(PW.sage)
        }
        .frame(height: 50)
        .overlay(Capsule().stroke(PW.sage.opacity(0.4), lineWidth: 1))
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in start() }
                .onEnded { _ in cancel() }
        )
    }

    private func start() {
        guard timer == nil, !completed else { return }
        completed = false
        lastHapticStep = 0
        holdStart = Date()
        impact.prepare()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in tick() }
    }

    private func tick() {
        guard let holdStart else { return }
        let frac = min(Date().timeIntervalSince(holdStart) / duration, 1)
        let eased = CGFloat(pow(frac, easeExponent))
        progress = eased

        // Pulses are spaced evenly in eased progress; since progress
        // accelerates, the real-time gaps shrink — slow → fast.
        let step = Int(eased / hapticStep)
        if step > lastHapticStep {
            lastHapticStep = step
            impact.impactOccurred(intensity: 0.3 + 0.7 * eased)
            impact.prepare()
        }
        if frac >= 1 { complete() }
    }

    private func complete() {
        guard !completed else { return }
        completed = true
        invalidate()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete()
    }

    private func cancel() {
        guard !completed else { invalidate(); return }
        invalidate()
        withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
    }

    private func invalidate() {
        timer?.invalidate()
        timer = nil
        holdStart = nil
    }
}
