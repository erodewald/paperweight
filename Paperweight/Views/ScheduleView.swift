import SwiftUI
import FamilyControls

struct ScheduleView: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var freeSlots: Set<Int>
    @State private var dragPaintValue: Bool?
    @State private var lastPaintLocation: CGPoint?
    @State private var showNeedsUnlock = false
    @State private var showUnlockSetup = false
    @State private var showNeedsApps = false
    @State private var showingPicker = false

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let hours = 24
    private let leftInset: CGFloat = 30
    private let colGap: CGFloat = 3
    private let rowGap: CGFloat = 3
    private let headerHeight: CGFloat = 18
    private let stackSpacing: CGFloat = 8

    init(vm: HomeViewModel) {
        self.vm = vm
        // Seed from the pending edit when one exists, not the active schedule —
        // the active schedule doesn't yet include a loosening the user already
        // asked for, and painting on top of it would both misrepresent what was
        // last saved and discard that pending change on the next save.
        _freeSlots = State(initialValue: (vm.config.pendingSchedule ?? vm.config.schedule)?.freeSlots ?? [])
    }

    private var blockedRightNow: Bool {
        !PaperweightSchedule(freeSlots: freeSlots).isFree(at: Date())
    }

    /// The schedule actually in force right now, independent of what's being
    /// painted or what's still pending.
    private var activeSchedule: PaperweightSchedule { vm.config.schedule ?? PaperweightSchedule() }

    /// Slots that are quiet under the active schedule but open in the edit
    /// currently being painted — what will open once the loosening lands. This
    /// is deliberately computed from the live `freeSlots` being painted, not
    /// `config.pendingOpeningSlots`, which reflects the last *saved* pending
    /// change rather than what's on screen right now.
    private var openingSlots: Set<Int> {
        freeSlots.subtracting(activeSchedule.freeSlots)
    }

    private var hasPendingChange: Bool { !openingSlots.isEmpty }

    /// Copy shown under the quiet-hours total. Only relevant while armed, since
    /// there's no deferral rule to explain otherwise.
    private var pendingFooterText: String? {
        guard vm.config.isEnabled else { return nil }
        guard hasPendingChange else { return "Loosening takes effect tomorrow." }
        let hours = Double(openingSlots.count) / 2.0
        return String(format: "%g hours open up at midnight.", hours)
    }

    private var now: (day: Int, hour: Int) {
        let c = Calendar.current.dateComponents([.weekday, .hour], from: Date())
        return ((c.weekday ?? 1) - 1, c.hour ?? 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                Text("Paint your quiet hours.")
                    .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                HStack(spacing: 12) {
                    legend(color: PW.moss, label: "Locked — quiet")
                    legend(color: nil, label: "Open")
                    if hasPendingChange {
                        legend(color: PW.moss.opacity(0.35), label: "Opens tomorrow", dashed: true)
                    }
                }
            }
            .padding(.top, 4).padding(.horizontal, 18)

            // Always laid out, only sometimes visible: painting across "now"
            // used to insert this row mid-drag, which shoved the grid down
            // under the finger and painted cells the user never touched.
            lockWarning
                .opacity(blockedRightNow ? 1 : 0)
                .accessibilityHidden(!blockedRightNow)

            GeometryReader { geo in
                // Clamp to non-negative: during transient layout passes geo.size
                // can be ~0, which would make these negative and spam
                // "Invalid frame dimension".
                let cellW = max(0, (geo.size.width - leftInset - colGap * CGFloat(7)) / 7)
                let bodyH = geo.size.height - headerHeight - stackSpacing
                let cellH = max(0, (bodyH - rowGap * CGFloat(hours - 1)) / CGFloat(hours))

                VStack(spacing: stackSpacing) {
                    dayHeader(cellW: cellW)
                    gridBody(cellW: cellW, cellH: cellH)
                }
            }
            .padding(.horizontal, 18)

            Text(String(format: "%g quiet hours this week",
                        PaperweightSchedule(freeSlots: freeSlots).quietHourCount))
                .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                .padding(.top, 2)

            if let pendingFooterText {
                Text(pendingFooterText)
                    .font(.grotesk(13)).foregroundStyle(PW.textFaint)
                    .padding(.horizontal, 24).padding(.top, 2)
            }

            AccentButton(title: "Save schedule") { Task { await save() } }
                .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 8)
        }
        .padding(.vertical, 8)
        .pwScreen()
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Open: Weekday evenings") { freeSlots = PaperweightSchedule.weekdayEvenings().freeSlots }
                    Button("Open: All week") { freeSlots = PaperweightSchedule.alwaysFree().freeSlots }
                    Button("Quiet: The whole week", role: .destructive) { freeSlots = [] }
                } label: {
                    Image(systemName: "wand.and.stars").foregroundStyle(PW.sage)
                }
            }
        }
        .alert("Choose apps to block first", isPresented: $showNeedsApps) {
            Button("Choose Apps") { showingPicker = true }
            Button("Not now", role: .cancel) { dismiss() }
        } message: {
            Text("Paperweight has nothing to quiet yet. Pick the apps or categories to restrict, then save again to arm.")
        }
        .alert("Set up a way back first", isPresented: $showNeedsUnlock) {
            Button("Set It Up") { showUnlockSetup = true }
            Button("Not now", role: .cancel) { dismiss() }
        } message: {
            Text("Before Paperweight can turn on, register an NFC token or generate recovery codes so you can always unlock. Your schedule is saved — finish setup and save again to arm it.")
        }
        .sheet(isPresented: $showUnlockSetup) {
            NavigationStack { NFCSetupView(vm: vm) }
                .tint(PW.sage)
                .presentationDragIndicator(.visible)
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $vm.config.selection)
        .onChange(of: showingPicker) { _, presented in
            if !presented { vm.saveSelection() }
        }
    }

    private var lockWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Now is a quiet period — saving locks restricted apps immediately.")
        }
        .font(.grotesk(13)).foregroundStyle(PW.clay)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PW.clay.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 18)
    }

    /// Mirrors `WeekStrip`'s legend swatch styling so the two screens agree.
    /// `dashed` adds the outgoing-quiet border that marks the "opens tomorrow"
    /// swatch, matching state 2 in `cell(day:hour:w:h:isNow:)`.
    private func legend(color: Color?, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color ?? Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(dashed ? PW.moss : (color == nil ? Color.white.opacity(0.16) : .clear),
                                      style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 2] : []))
                )
                .frame(width: 10, height: 10)
            Text(label)
                .font(.grotesk(13))
                .foregroundStyle(PW.textMuted)
        }
    }

    private func dayHeader(cellW: CGFloat) -> some View {
        HStack(spacing: colGap) {
            Color.clear.frame(width: leftInset, height: 1)
            ForEach(0..<7, id: \.self) { day in
                Text(dayLabels[day])
                    .font(.grotesk(13, weight: .semibold))
                    .foregroundStyle(PW.textFaint)
                    .frame(width: cellW)
            }
        }
        .frame(height: headerHeight)
    }

    private func gridBody(cellW: CGFloat, cellH: CGFloat) -> some View {
        HStack(spacing: colGap) {
            VStack(spacing: rowGap) {
                ForEach(0..<hours, id: \.self) { hour in
                    Text(PaperweightSchedule.hourLabel(hour))
                        .font(.system(size: 9, weight: hour % 6 == 0 ? .semibold : .regular))
                        .foregroundStyle(hour % 6 == 0 ? PW.textFaint : PW.textFaintest)
                        .frame(width: leftInset, height: cellH, alignment: .trailing)
                }
            }
            VStack(spacing: rowGap) {
                let nowCell = now
                ForEach(0..<hours, id: \.self) { hour in
                    HStack(spacing: colGap) {
                        ForEach(0..<7, id: \.self) { day in
                            cell(day: day, hour: hour, w: cellW, h: cellH,
                                 isNow: day == nowCell.day && hour == nowCell.hour)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { paint(at: $0.location, cellW: cellW, cellH: cellH) }
                .onEnded { _ in dragPaintValue = nil; lastPaintLocation = nil }
        )
    }

    /// Three cell states, derived from two sources: `freeSlots` (the edit being
    /// painted) and `activeSchedule` (what's actually in force):
    ///   1. Quiet in the painted edit — solid `PW.moss`. This also covers a
    ///      brand-new tightening (open in `activeSchedule`, quiet in the edit):
    ///      tightening applies immediately on save, so it reads the same as an
    ///      already-quiet cell.
    ///   2. Open in the painted edit but still quiet in `activeSchedule` — the
    ///      loosening hasn't landed yet. Dashed `PW.moss` border over a faint
    ///      moss fill, so it reads as leaving rather than a third unrelated
    ///      category.
    ///   3. Open in both — the existing faint fill.
    private func cell(day: Int, hour: Int, w: CGFloat, h: CGFloat, isNow: Bool) -> some View {
        let paintedQuiet = !isHourFree(day: day, hour: hour, in: freeSlots)
        let openingSoon = !paintedQuiet && !isHourFree(day: day, hour: hour, in: activeSchedule.freeSlots)

        let fill: Color = paintedQuiet ? PW.moss : (openingSoon ? PW.moss.opacity(0.35) : Color.white.opacity(0.04))
        let borderColor: Color = isNow ? PW.dawnGlow
            : paintedQuiet ? PW.mossLight.opacity(0.6)
            : openingSoon ? PW.moss
            : Color.white.opacity(0.12)
        let dashed = openingSoon && !isNow

        return RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(borderColor, style: StrokeStyle(lineWidth: isNow ? 2 : 1, dash: dashed ? [2, 2] : []))
            )
            .shadow(color: isNow ? PW.sage.opacity(0.5) : .clear, radius: isNow ? 3 : 0)
            .frame(width: w, height: h)
    }

    // MARK: - Hour <-> slot helpers (model stays at 30-min; we paint whole hours)

    private func isHourFree(day: Int, hour: Int, in freeSlots: Set<Int>) -> Bool {
        freeSlots.contains(PaperweightSchedule.slot(day: day, halfHour: hour * 2))
    }

    private func isHourFree(day: Int, hour: Int) -> Bool {
        isHourFree(day: day, hour: hour, in: freeSlots)
    }

    private func setHour(day: Int, hour: Int, free: Bool) {
        for half in [hour * 2, hour * 2 + 1] {
            let s = PaperweightSchedule.slot(day: day, halfHour: half)
            if free { freeSlots.insert(s) } else { freeSlots.remove(s) }
        }
    }

    // MARK: - Painting

    private func paint(at location: CGPoint, cellW: CGFloat, cellH: CGFloat) {
        guard cellW > 0, cellH > 0 else { return }
        if dragPaintValue == nil, let c = cellAt(location, cellW: cellW, cellH: cellH) {
            dragPaintValue = !isHourFree(day: c.day, hour: c.hour)
        }
        let value = dragPaintValue ?? true

        if let last = lastPaintLocation {
            let dx = location.x - last.x, dy = location.y - last.y
            let stepSize = max(min(cellW, cellH) / 2, 1)
            let steps = max(Int(max(abs(dx), abs(dy)) / stepSize), 1)
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                apply(value, at: CGPoint(x: last.x + dx * t, y: last.y + dy * t), cellW: cellW, cellH: cellH)
            }
        } else {
            apply(value, at: location, cellW: cellW, cellH: cellH)
        }
        lastPaintLocation = location
    }

    private func apply(_ value: Bool, at location: CGPoint, cellW: CGFloat, cellH: CGFloat) {
        guard let c = cellAt(location, cellW: cellW, cellH: cellH) else { return }
        setHour(day: c.day, hour: c.hour, free: value)
    }

    private func cellAt(_ location: CGPoint, cellW: CGFloat, cellH: CGFloat) -> (day: Int, hour: Int)? {
        let xInCells = location.x - leftInset - colGap
        guard xInCells >= 0 else { return nil }
        let day = min(max(Int(xInCells / (cellW + colGap)), 0), 6)
        let hour = min(max(Int(location.y / (cellH + rowGap)), 0), hours - 1)
        return (day, hour)
    }

    private func save() async {
        let edit = freeSlots.isEmpty ? PaperweightSchedule() : PaperweightSchedule(freeSlots: freeSlots)

        // Already armed: saveScheduleEdit applies the asymmetric rule itself
        // (tighten now, loosen tomorrow) and persists. No arm-time guards apply —
        // it's already armed.
        guard !vm.config.isEnabled else {
            vm.saveScheduleEdit(edit)
            dismiss()
            return
        }

        // Not yet armed: persist the edit, but don't arm into a broken state —
        // require both something to block and a way back first.
        vm.saveScheduleEdit(edit)
        guard vm.hasAppsSelected else {
            vm.saveSelection()
            showNeedsApps = true
            return
        }
        guard vm.hasUnlockMethod else {
            vm.saveSelection()
            showNeedsUnlock = true
            return
        }
        await vm.setEnabled(true)
        ScheduleService.shared.sync(config: vm.config)
        dismiss()
    }
}
