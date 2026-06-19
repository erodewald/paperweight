import SwiftUI

struct ScheduleView: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var freeSlots: Set<Int>
    /// The value being painted for the current drag (true = mark free). Decided
    /// by the first cell touched so a single gesture toggles consistently.
    @State private var dragPaintValue: Bool?
    /// Last touch point in the current drag, used to fill cells between samples
    /// so fast swipes don't leave gaps.
    @State private var lastPaintLocation: CGPoint?

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let timeColumnWidth: CGFloat = 28
    private let rows = PaperweightSchedule.halfHoursPerDay  // 48

    init(vm: HomeViewModel) {
        self.vm = vm
        _freeSlots = State(initialValue: vm.config.schedule?.freeSlots ?? [])
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Drag to toggle when apps are free. Green = free, gray = blocked.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            dayHeader

            grid

            Text(String(format: "%g free hours/week", PaperweightSchedule(freeSlots: freeSlots).freeHourCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Free: Weekday Evenings") { freeSlots = PaperweightSchedule.weekdayEvenings().freeSlots }
                    Button("Free: All Week") { freeSlots = PaperweightSchedule.alwaysFree().freeSlots }
                    Button("Clear (block everything)", role: .destructive) { freeSlots = [] }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 1) {
            Color.clear.frame(width: timeColumnWidth, height: 1)
            ForEach(0..<7, id: \.self) { day in
                Text(dayLabels[day])
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 16)
        .padding(.horizontal, 8)
    }

    private var grid: some View {
        // One GeometryReader drives both the hour-label column and the cells so
        // their row heights stay identical and the whole grid fills the space
        // remaining between the header and footer.
        GeometryReader { geo in
            let labelSpacing: CGFloat = 1
            let gridWidth = geo.size.width - timeColumnWidth - labelSpacing
            let cellW = gridWidth / 7
            let cellH = geo.size.height / CGFloat(rows)

            HStack(spacing: labelSpacing) {
                // Hour labels — shown on the top-of-hour row only.
                VStack(spacing: 1) {
                    ForEach(0..<rows, id: \.self) { row in
                        Text(row % 2 == 0 ? PaperweightSchedule.hourLabel(row / 2) : "")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: timeColumnWidth, height: cellH, alignment: .topTrailing)
                    }
                }

                VStack(spacing: 1) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<7, id: \.self) { day in
                                Rectangle()
                                    .fill(freeSlots.contains(PaperweightSchedule.slot(day: day, halfHour: row))
                                          ? Color.green.opacity(0.75)
                                          : Color(.systemGray5))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: cellH)
                                    // Stronger line at the top of each hour.
                                    .overlay(alignment: .top) {
                                        if row % 2 == 0 {
                                            Rectangle().fill(Color(.systemGray3)).frame(height: 0.5)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        paint(at: value.location, cellW: cellW, cellH: cellH)
                    }
                    .onEnded { _ in
                        dragPaintValue = nil
                        lastPaintLocation = nil
                    }
            )
        }
        .padding(.horizontal, 8)
        .background(Color(.systemGray4))
    }

    private func paint(at location: CGPoint, cellW: CGFloat, cellH: CGFloat) {
        guard cellW > 0, cellH > 0 else { return }

        // First touch of the gesture decides direction: if that cell is currently
        // free we're erasing (paint blocked), otherwise we're adding free time.
        if dragPaintValue == nil, let slot = slot(at: location, cellW: cellW, cellH: cellH) {
            dragPaintValue = !freeSlots.contains(slot)
        }
        let value = dragPaintValue ?? true

        // Interpolate from the previous sample so fast swipes paint every cell on
        // the path rather than just the sampled endpoints.
        if let last = lastPaintLocation {
            let dx = location.x - last.x
            let dy = location.y - last.y
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

    /// Maps a touch point (in the grid's coordinate space, which includes the
    /// leading hour-label column) to a slot index, or nil if outside the cells.
    private func slot(at location: CGPoint, cellW: CGFloat, cellH: CGFloat) -> Int? {
        let xInCells = location.x - timeColumnWidth - 1
        guard xInCells >= 0 else { return nil }
        let day = min(max(Int(xInCells / cellW), 0), 6)
        let row = min(max(Int(location.y / cellH), 0), rows - 1)
        return PaperweightSchedule.slot(day: day, halfHour: row)
    }

    private func save() {
        let schedule = freeSlots.isEmpty ? nil : PaperweightSchedule(freeSlots: freeSlots)
        vm.config.schedule = schedule
        vm.saveSelection()
        ScheduleService.shared.updateSchedule(schedule)
        if vm.config.isEnabled { vm.syncRestrictions() }
        dismiss()
    }
}
