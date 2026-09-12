import Foundation

extension PaperweightSchedule {

    /// One contiguous run within a single day, as a share of that day.
    ///
    /// `isLocked` is the v2 reading of the grid: painted means *quiet*. The
    /// stored truth is still `freeSlots`, so this is a presentation flip only.
    struct DaySegment: Equatable {
        let isLocked: Bool
        let fraction: Double
    }

    /// The day's runs in clock order from midnight. Always at least one segment,
    /// and the fractions always sum to 1.
    func daySegments(day: Int) -> [DaySegment] {
        Self.segments(openSlots: Set((0..<Self.halfHoursPerDay).filter { isFreeSlot(day: day, halfHour: $0) }))
    }

    /// `daySegments(day:)` for an arbitrary day expressed as its open half-hours
    /// (0…47) — how the resolver draws an exception day.
    static func segments(openSlots: Set<Int>) -> [DaySegment] {
        var segments: [DaySegment] = []
        var half = 0
        while half < halfHoursPerDay {
            let locked = !openSlots.contains(half)
            var end = half
            while end < halfHoursPerDay, (!openSlots.contains(end)) == locked { end += 1 }
            segments.append(DaySegment(isLocked: locked, fraction: Double(end - half) / Double(halfHoursPerDay)))
            half = end
        }
        return segments
    }

    /// True when no part of the day is quiet — screen 02's "OPEN ALL DAY" row.
    func isOpenAllDay(day: Int) -> Bool {
        (0..<Self.halfHoursPerDay).allSatisfy { isFreeSlot(day: day, halfHour: $0) }
    }

    /// Hours the week is quiet — the number screen 03 reports.
    var quietHourCount: Double {
        Double(Self.slotCount - freeSlots.count) / 2.0
    }
}
