import Foundation

extension PaperweightSchedule {

    /// The schedule that takes effect immediately when `edit` is saved over this
    /// one: every tightening applies, every loosening is withheld.
    ///
    /// A slot is open only if it was open before *and* the edit leaves it open,
    /// which is what stops a deferred edit from being used to slip today's lock.
    func merging(tighteningFrom edit: PaperweightSchedule) -> PaperweightSchedule {
        PaperweightSchedule(freeSlots: freeSlots.intersection(edit.freeSlots))
    }
}

extension PaperweightConfig {

    /// Saves a schedule edit under the deferral rule: tightening now, loosening
    /// at the next calendar day boundary.
    mutating func applyScheduleEdit(_ edit: PaperweightSchedule,
                                    now: Date = Date(),
                                    calendar: Calendar = .current) {
        let active = schedule ?? PaperweightSchedule()
        let immediate = active.merging(tighteningFrom: edit)
        schedule = immediate

        if immediate == edit {
            // Pure tightening — nothing left to wait for.
            pendingSchedule = nil
            pendingScheduleEffectiveAt = nil
        } else {
            pendingSchedule = edit
            pendingScheduleEffectiveAt = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        }
    }

    /// Swaps in a pending schedule once its day boundary has passed.
    mutating func promotePendingScheduleIfDue(now: Date = Date(),
                                              calendar: Calendar = .current) {
        guard let pending = pendingSchedule,
              let effective = pendingScheduleEffectiveAt,
              now >= effective else { return }
        schedule = pending
        pendingSchedule = nil
        pendingScheduleEffectiveAt = nil
    }

    /// Slots that are quiet under the active schedule but open under the pending
    /// one — what the grid marks as "leaving".
    var pendingOpeningSlots: Set<Int> {
        guard let pending = pendingSchedule else { return [] }
        let active = schedule ?? PaperweightSchedule()
        return pending.freeSlots.subtracting(active.freeSlots)
    }
}
