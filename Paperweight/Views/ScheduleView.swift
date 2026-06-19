import SwiftUI

struct ScheduleView: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var freeSlots: Set<Int>
    @State private var dragPaintValue: Bool?
    @State private var lastPaintLocation: CGPoint?

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let timeColumnWidth: CGFloat = 26
    private let rows = PaperweightSchedule.halfHoursPerDay  // 48

    init(vm: HomeViewModel) {
        self.vm = vm
        _freeSlots = State(initialValue: vm.config.schedule?.freeSlots ?? [])
    }

    private var blockedRightNow: Bool {
        !PaperweightSchedule(freeSlots: freeSlots).isFree(at: Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("Drag to paint when apps are free.")
                    .font(.grotesk(12)).foregroundStyle(PW.textMuted)
                Text("Green = free · dark = quiet.")
                    .font(.grotesk(12)).foregroundStyle(PW.textFaint)
            }
            .padding(.top, 4)
            .padding(.horizontal, 18)

            if blockedRightNow { lockWarning }

            dayHeader
            grid
            Text(String(format: "%g free hours / week",
                        PaperweightSchedule(freeSlots: freeSlots).freeHourCount))
                .font(.grotesk(12)).foregroundStyle(PW.textMuted)
                .padding(.top, 4)

            AccentButton(title: "Save schedule") { Task { await save() } }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .padding(.vertical, 8)
        .pwScreen()
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    private var lockWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Now is a quiet period — saving locks restricted apps immediately.")
        }
        .font(.grotesk(11))
        .foregroundStyle(PW.clay)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PW.clay.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 18)
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth, height: 1)
            ForEach(0..<7, id: \.self) { day in
                Text(dayLabels[day])
                    .font(.grotesk(11, weight: .semibold))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 16)
        .padding(.horizontal, 18)
    }

    private var grid: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width - timeColumnWidth) / 7
            let cellH = geo.size.height / CGFloat(rows)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        Text(row % 2 == 0 ? PaperweightSchedule.hourLabel(row / 2) : "")
                            .font(.system(size: 8.5))
                            .foregroundStyle(PW.textFaintest)
                            .frame(width: timeColumnWidth, height: cellH, alignment: .topTrailing)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { day in
                                cell(day: day, row: row, height: cellH)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { paint(at: $0.location, cellW: cellW, cellH: cellH) }
                    .onEnded { _ in dragPaintValue = nil; lastPaintLocation = nil }
            )
        }
        .padding(.horizontal, 18)
    }

    private func cell(day: Int, row: Int, height: CGFloat) -> some View {
        Rectangle()
            .fill(freeSlots.contains(PaperweightSchedule.slot(day: day, halfHour: row))
                  ? PW.moss : PW.deepForest)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(row % 2 == 0 ? 0.28 : 0.12))
                    .frame(height: 0.5)
            }
            .overlay(alignment: .leading) {
                if day > 0 { Rectangle().fill(Color.black.opacity(0.22)).frame(width: 0.5) }
            }
    }

    private func paint(at location: CGPoint, cellW: CGFloat, cellH: CGFloat) {
        guard cellW > 0, cellH > 0 else { return }
        if dragPaintValue == nil, let slot = slot(at: location, cellW: cellW, cellH: cellH) {
            dragPaintValue = !freeSlots.contains(slot)
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

    private func apply(_ free: Bool, at location: CGPoint, cellW: CGFloat, cellH: CGFloat) {
        guard let slot = slot(at: location, cellW: cellW, cellH: cellH) else { return }
        if free { freeSlots.insert(slot) } else { freeSlots.remove(slot) }
    }

    private func slot(at location: CGPoint, cellW: CGFloat, cellH: CGFloat) -> Int? {
        let xInCells = location.x - timeColumnWidth
        guard xInCells >= 0 else { return nil }
        let day = min(max(Int(xInCells / cellW), 0), 6)
        let row = min(max(Int(location.y / cellH), 0), rows - 1)
        return PaperweightSchedule.slot(day: day, halfHour: row)
    }

    private func save() async {
        let schedule = freeSlots.isEmpty ? nil : PaperweightSchedule(freeSlots: freeSlots)
        vm.config.schedule = schedule
        await vm.setEnabled(true)
        ScheduleService.shared.updateSchedule(schedule, enabled: true)
        dismiss()
    }
}
