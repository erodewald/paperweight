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
    ///
    /// Caller contract — this method does not enforce either of these, so getting
    /// them wrong compiles fine and just quietly breaks the safety property:
    /// - Call `promotePendingScheduleIfDue()` first, before calling this method.
    /// Applying an edit while a previous loosening is still pending recomputes
    /// the boundary from the current `now`, pushing that earlier promotion out
    /// by another day instead of letting it land.
    /// - Only call this on an already-armed config. It assumes `schedule` is the
    /// real, active schedule. Routing first-time setup through it will intersect
    /// the new schedule against an all-quiet default, locking the whole week and
    /// deferring the user's actual schedule to tomorrow.
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
            // Ask the calendar for "the next day" rather than adding a fixed
            // 86,400 seconds: on a fall-back DST day (25 real hours), a fixed
            // interval lands at 23:00 of the SAME day, promoting the loosening
            // an hour early. `date(byAdding:)` is essentially infallible for
            // `.day` on a well-formed calendar, but if it ever does fail, fall
            // back to `.distantFuture` rather than any same-day guess — the
            // safety property only breaks if the boundary comes too early, so
            // an unresolvable boundary must fail closed (later, never earlier).
            pendingScheduleEffectiveAt = calendar.date(byAdding: .day, value: 1,
                                                        to: calendar.startOfDay(for: now))
                ?? .distantFuture
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
