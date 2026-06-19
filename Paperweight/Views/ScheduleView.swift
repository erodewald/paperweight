import SwiftUI

struct ScheduleView: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var freeSlots: Set<Int>
    @State private var dragPaintValue: Bool?
    @State private var lastPaintLocation: CGPoint?

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let hours = 24
    private let leftInset: CGFloat = 30
    private let colGap: CGFloat = 3
    private let rowGap: CGFloat = 3
    private let headerHeight: CGFloat = 18
    private let stackSpacing: CGFloat = 8

    init(vm: HomeViewModel) {
        self.vm = vm
        _freeSlots = State(initialValue: vm.config.schedule?.freeSlots ?? [])
    }

    private var blockedRightNow: Bool {
        !PaperweightSchedule(freeSlots: freeSlots).isFree(at: Date())
    }

    /// While Paperweight is active the schedule is read-only — otherwise you
    /// could repaint "now" as free and slip the lock without the token.
    private var locked: Bool { vm.config.isEnabled }

    private var now: (day: Int, hour: Int) {
        let c = Calendar.current.dateComponents([.weekday, .hour], from: Date())
        return ((c.weekday ?? 1) - 1, c.hour ?? 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            if locked {
                lockedBanner
            } else {
                VStack(spacing: 2) {
                    Text("Drag to paint when apps are free.")
                        .font(.grotesk(12)).foregroundStyle(PW.textMuted)
                    Text("Green = free · dark = quiet.")
                        .font(.grotesk(12)).foregroundStyle(PW.textFaint)
                }
                .padding(.top, 4).padding(.horizontal, 18)

                if blockedRightNow { lockWarning }
            }

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

            Text(String(format: "%g free hours / week",
                        PaperweightSchedule(freeSlots: freeSlots).freeHourCount))
                .font(.grotesk(12)).foregroundStyle(PW.textMuted)
                .padding(.top, 2)

            if locked {
                Text("Turn Paperweight off to change your schedule.")
                    .font(.grotesk(12)).foregroundStyle(PW.textFaint)
                    .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 8)
            } else {
                AccentButton(title: "Save schedule") { Task { await save() } }
                    .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 8)
            }
        }
        .padding(.vertical, 8)
        .pwScreen()
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !locked {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Free: Weekday Evenings") { freeSlots = PaperweightSchedule.weekdayEvenings().freeSlots }
                        Button("Free: All Week") { freeSlots = PaperweightSchedule.alwaysFree().freeSlots }
                        Button("Clear (block everything)", role: .destructive) { freeSlots = [] }
                    } label: {
                        Image(systemName: "wand.and.stars").foregroundStyle(PW.sage)
                    }
                }
            }
        }
    }

    private var lockedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
            Text("Locked while Paperweight is active. This is your schedule right now.")
        }
        .font(.grotesk(11))
        .foregroundStyle(PW.sage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PW.sage.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 18)
    }

    private var lockWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Now is a quiet period — saving locks restricted apps immediately.")
        }
        .font(.grotesk(11)).foregroundStyle(PW.clay)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PW.clay.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 18)
    }

    private func dayHeader(cellW: CGFloat) -> some View {
        HStack(spacing: colGap) {
            Color.clear.frame(width: leftInset, height: 1)
            ForEach(0..<7, id: \.self) { day in
                Text(dayLabels[day])
                    .font(.grotesk(11, weight: .semibold))
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

    private func cell(day: Int, hour: Int, w: CGFloat, h: CGFloat, isNow: Bool) -> some View {
        let free = isHourFree(day: day, hour: hour)
        return RoundedRectangle(cornerRadius: 4)
            .fill(free ? PW.moss : PW.deepForest)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isNow ? PW.dawnGlow
                                        : (free ? PW.mossLight.opacity(0.6) : Color.white.opacity(0.05)),
                                  lineWidth: isNow ? 2 : 1)
            )
            .shadow(color: isNow ? PW.sage.opacity(0.5) : .clear, radius: isNow ? 3 : 0)
            .frame(width: w, height: h)
    }

    // MARK: - Hour <-> slot helpers (model stays at 30-min; we paint whole hours)

    private func isHourFree(day: Int, hour: Int) -> Bool {
        freeSlots.contains(PaperweightSchedule.slot(day: day, halfHour: hour * 2))
    }

    private func setHour(day: Int, hour: Int, free: Bool) {
        for half in [hour * 2, hour * 2 + 1] {
            let s = PaperweightSchedule.slot(day: day, halfHour: half)
            if free { freeSlots.insert(s) } else { freeSlots.remove(s) }
        }
    }

    // MARK: - Painting

    private func paint(at location: CGPoint, cellW: CGFloat, cellH: CGFloat) {
        guard !locked, cellW > 0, cellH > 0 else { return }
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
        let schedule = freeSlots.isEmpty ? nil : PaperweightSchedule(freeSlots: freeSlots)
        vm.config.schedule = schedule
        await vm.setEnabled(true)
        ScheduleService.shared.updateSchedule(schedule, enabled: true)
        dismiss()
    }
}
