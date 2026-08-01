import Foundation

/// The Paperweight motion grammar: four verbs, and every easing in the design is
/// one of them.
///
/// - `settle` — the state lands like a weight: fast in, soft stop, never a bounce.
/// - `grow` — life fills in: a slight overshoot, then rest.
/// - `sway` — nothing is ever still.
/// - Release is not a function: it is the same curves run backwards, which the
///   caller gets for free by driving `lock` back toward zero.
///
/// Pure math, no SwiftUI, so it can be tested directly. The constants are fixed
/// by the design and are not tuning knobs.
enum PWMotion {

    /// Back-out overshoot amount. From the motion study's locked tweak defaults.
    static let overshoot: Double = 0.16
    /// Sway amplitude in degrees.
    static let swayDegrees: Double = 3.6
    /// Seconds for one full sway cycle.
    static let swayPeriod: Double = 14

    /// Maps `value` within `[from, to]` onto `0…1`, clamped at both ends.
    static func ramp(_ value: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        return min(max((value - from) / (to - from), 0), 1)
    }

    /// Weight lands: fast in, soft stop, no bounce. `1 - (1-u)³`.
    static func settle(_ u: Double) -> Double {
        let t = min(max(u, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// Sprout: overshoots past 1, then rests on it.
    static func grow(_ u: Double) -> Double {
        let t = min(max(u, 0), 1)
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let c1 = overshoot * 7
        let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }

    /// Perpetual sway, in degrees, for an element at the given phase offset.
    static func sway(at time: Double, phase: Double = 0) -> Double {
        swayDegrees * sin(2 * .pi * time / swayPeriod + phase)
    }

    /// How far element `index` of `count` has sprouted at the given lock amount.
    ///
    /// Elements start in order and each takes `window` of the lock to complete,
    /// so the scene fills in back to front and is fully grown by `lock == 1`.
    static func growth(index: Int, count: Int, lock: Double, window: Double = 0.4) -> Double {
        grow(stagger(index: index, count: count, lock: lock, window: window))
    }

    /// The Overgrown variant: a wider window and no overshoot — creeping, not popping.
    static func crawl(index: Int, count: Int, lock: Double, window: Double = 0.6) -> Double {
        stagger(index: index, count: count, lock: lock, window: window)
    }

    private static func stagger(index: Int, count: Int, lock: Double, window: Double) -> Double {
        let slots = max(count - 1, 1)
        let start = (Double(index) / Double(slots)) * (1 - window)
        return ramp(lock, start, start + window)
    }
}
