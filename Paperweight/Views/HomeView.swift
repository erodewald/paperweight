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
    #if DEBUG
    @ObservedObject private var debug = DebugSettings.shared
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPicker = false
    @State private var showingDisableSheet = false
    @State private var showNeedsUnlock = false
    @State private var showUnlockSetup = false
    @State private var showNeedsApps = false
    @State private var showingSchedule = false
    /// Selection captured when the picker opens, to detect (and gate) removals.
    @State private var selectionSnapshot: FamilyActivitySelection?
    @State private var selectionRevertMessage: String?
    /// Fixed origin for the scene clock, so sway and blink phases are stable
    /// across redraws rather than restarting whenever the body re-evaluates.
    @State private var sceneEpoch = Date()
    /// When the current quiet window began, or `.distantPast` when it was already
    /// underway as Home appeared — which is what keeps the sprout from replaying
    /// on every launch.
    @State private var quietSince: Date?

    /// Quiet: armed and restricting right now (a scheduled blocked period, or
    /// always-blocked when no schedule is set).
    private var isQuiet: Bool {
        #if DEBUG
        // Presentation only — this shows the quiet screen without restricting
        // anything, so the artwork can be looked at during development.
        if debug.forceQuiet { return true }
        #endif
        guard vm.config.isEnabled else { return false }
        if let s = vm.config.schedule, !s.isEmpty { return !s.isFree(at: Date()) }
        return true
    }

    var body: some View {
        NavigationStack {
            Group {
                // isQuiet is checked first so the #if DEBUG override inside it can
                // reach the locked screen. This is equivalent in Release: isQuiet
                // already guards on isEnabled, so not-armed still falls through to
                // setupState, armed-and-quiet still gives lockedState, and
                // armed-and-open still gives openState.
                if isQuiet {
                    lockedState
                } else if !vm.config.isEnabled {
                    setupState
                } else {
                    openState
                }
            }
            .pwScreen()
            .navigationTitle("")
            // The root never swaps, so pushing/popping the schedule stays clean —
            // keep this on the Group, not inside the branches, since setupState,
            // lockedState, and openState swap out from under it as config changes.
            .navigationDestination(isPresented: $showingSchedule) { ScheduleView(vm: vm) }
            .onAppear {
                // Already quiet at launch: start fully grown rather than replaying
                // the sprout, which would read as though the lock just happened.
                quietSince = isQuiet ? .distantPast : nil
            }
            .onChange(of: isQuiet) { _, quiet in
                quietSince = quiet ? Date() : nil
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView(vm: vm,
                                     showingPicker: $showingPicker,
                                     onTurnOff: { showingDisableSheet = true })
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17))
                            .foregroundStyle(PW.textMuted)
                    }
                }
            }
        }
        .tint(PW.sage)
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
        .onAppear {
            handlePendingShortcut()
            updateShortcutItems(isEnabled: vm.config.isEnabled)
        }
        .onChange(of: shortcutManager.pendingShortcutType) { _, _ in handlePendingShortcut() }
        .onOpenURL { url in handleWidgetLink(url) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vm.refresh()
                ScheduleService.shared.sync(config: vm.config)
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
        .alert("Choose apps to block first", isPresented: $showNeedsApps) {
            Button("Choose Apps") { showingPicker = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Paperweight has nothing to quiet yet. Pick the apps or categories to restrict first.")
        }
        .alert("Set up a way back first", isPresented: $showNeedsUnlock) {
            Button("Set It Up") { showUnlockSetup = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Before Paperweight can turn on, register an NFC token or generate recovery codes so you can always unlock.")
        }
        .sheet(isPresented: $showUnlockSetup) {
            NavigationStack { NFCSetupView(vm: vm) }
                .tint(PW.sage)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Locked (screen 01)

    private var lockedState: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = vm.config.schedule?.quietStatus(at: context.date)
            VStack(alignment: .leading, spacing: 0) {
                banner(
                    eyebrow: "● Locked",
                    eyebrowColor: PW.dawnGlow,
                    headline: status.map {
                        "Down until \(WidgetState.dayClock($0.ends, from: context.date))"
                    } ?? "Down until you say otherwise",
                    borderColor: PW.dawnGlow.opacity(0.4),
                    glow: true)

                if let status {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(HomeCopy.countdown(status.remaining))
                            .font(.grotesk(44, weight: .bold))
                            .foregroundStyle(PW.textPrimary)
                        Text("left")
                            .font(.grotesk(14, weight: .medium))
                            .foregroundStyle(PW.textMuted)
                    }
                    .padding(.top, 22)

                    progressBar(elapsed: 1 - status.remainingFraction)
                        .padding(.top, 10)

                    Text("Unlocks at \(WidgetState.dayClock(status.ends, from: context.date))")
                        .font(.grotesk(13))
                        .foregroundStyle(PW.textMuted)
                        .padding(.top, 6)
                }

                quietScene
                    .frame(maxHeight: .infinity)

                AccentButton(title: "View schedule") { showingSchedule = true }
                    .padding(.top, 8)

                Text("Emergency unlock lives in Settings — never here.")
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    /// How long the sprout takes once a quiet window begins.
    private static let sproutDuration: Double = 1.6

    /// Whether the chosen scene has anything that moves. Simple is static type,
    /// so it must not hold a 30fps clock open for no reason.
    private var sceneAnimates: Bool {
        vm.config.quietTheme != .simple && !reduceMotion
    }

    /// The chosen artwork, driven by one clock.
    ///
    /// `lock` is derived from the timeline's own date rather than an animated
    /// `@State`: a `Canvas` draw closure is not `Animatable`, so `withAnimation`
    /// on a stored `Double` would never interpolate it. Computing it per frame is
    /// what actually makes the scene grow in.
    ///
    /// Pausing rather than branching means a backgrounded app stops redrawing but
    /// keeps its last frame, so sway and blink don't snap when it returns.
    private var quietScene: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active || !sceneAnimates)) { context in
            let elapsed = quietSince.map { context.date.timeIntervalSince($0) } ?? 0
            scene(lock: PWMotion.settle(PWMotion.ramp(elapsed, 0, Self.sproutDuration)),
                  time: context.date.timeIntervalSince(sceneEpoch))
        }
    }

    @ViewBuilder
    private func scene(lock: Double, time: Double) -> some View {
        switch vm.config.quietTheme {
        case .simple:    SimpleScene(lock: lock)
        case .diorama:   DioramaScene(lock: lock, time: time)
        case .overgrown: OvergrownScene(lock: lock, time: time)
        }
    }

    // MARK: - Open (screen 02)

    private var openState: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = vm.config.schedule?.freeStatus(at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    banner(
                        eyebrow: "○ Open",
                        eyebrowColor: PW.textLabel,
                        headline: "In your hands.",
                        borderColor: PW.hairline,
                        glow: false,
                        detail: status.map {
                            "Locks at \(WidgetState.dayClock($0.ends, from: context.date)) · in \(WidgetState.compactDuration($0.remaining))"
                        })

                    if let schedule = vm.config.schedule, !schedule.isEmpty {
                        WeekStrip(schedule: schedule)
                            .padding(.top, 20)
                    }

                    GroupedCard {
                        Button { showingPicker = true } label: {
                            NavRow(title: "Restricted apps",
                                   systemImage: "lock",
                                   iconColor: PW.textMuted,
                                   value: restrictedCountText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 18)

                    AccentButton(title: "Edit schedule") { showingSchedule = true }
                        .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Not armed yet

    private var setupState: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner(eyebrow: "○ Off",
                   eyebrowColor: PW.textLabel,
                   headline: "Nothing is quiet yet.",
                   borderColor: PW.hairline,
                   glow: false,
                   detail: setupDetail)

            Spacer()

            if !vm.hasAppsSelected {
                AccentButton(title: "Choose apps") { showingPicker = true }
            } else if !vm.hasUnlockMethod {
                AccentButton(title: "Set up a way back") { showUnlockSetup = true }
            } else {
                AccentButton(title: "Set a schedule") { showingSchedule = true }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private var setupDetail: String {
        if !vm.hasAppsSelected {
            return "First, choose the apps and categories to quiet."
        }
        if !vm.hasUnlockMethod {
            return "Now set up a way back — an NFC token or recovery codes."
        }
        return "Paint a schedule and it arms itself. There is no switch to forget."
    }

    // MARK: - Shared pieces

    private func banner(eyebrow: String,
                        eyebrowColor: Color,
                        headline: String,
                        borderColor: Color,
                        glow: Bool,
                        detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.grotesk(13, weight: .bold))
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(eyebrowColor)
            Text(headline)
                .font(.spectral(26))
                .foregroundStyle(PW.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let detail {
                Text(detail)
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(PW.surfaceRaised)
                .overlay {
                    if glow {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(RadialGradient(
                                colors: [PW.dawnGlow.opacity(0.16), .clear],
                                center: .top, startRadius: 0, endRadius: 180))
                    }
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderColor, lineWidth: 1))
    }

    private func progressBar(elapsed: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [PW.moss, PW.dawnGlow],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * min(max(elapsed, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    private var restrictedCountText: String {
        let s = vm.config.selection
        let total = s.applicationTokens.count + s.categoryTokens.count + s.webDomainTokens.count
        return "\(total) app\(total == 1 ? "" : "s")"
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

    // MARK: - Shortcuts (unchanged behavior)

    private func enable() async {
        guard vm.hasAppsSelected else { showNeedsApps = true; return }
        guard vm.hasUnlockMethod else { showNeedsUnlock = true; return }
        await vm.setEnabled(true)
        ScheduleService.shared.sync(config: vm.config)
    }

    private func handlePendingShortcut() {
        guard let type = shortcutManager.pendingShortcutType else { return }
        shortcutManager.pendingShortcutType = nil
        DispatchQueue.main.async {
            switch type {
            case "enable-paperweight": Task { await enable() }
            case "disable-paperweight":
                showingDisableSheet = true
            default: break
            }
        }
    }

    /// Handles a `paperweight://` deep link from the widget. The widget is
    /// read-only, so every destination is somewhere the user still has to act —
    /// none of these change state on their own.
    private func handleWidgetLink(_ url: URL) {
        guard url.scheme == "paperweight" else { return }
        DispatchQueue.main.async {
            switch url.host {
            case "choose-apps":
                showingPicker = true
            case "unlock-setup":
                showUnlockSetup = true
            case "unlock":
                showingDisableSheet = true
            default:
                break   // "home" — the root is already what's on screen
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
struct RestrictedTokensList: View {
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
