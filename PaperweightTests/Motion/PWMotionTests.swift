import XCTest

final class PWMotionTests: XCTestCase {

    // MARK: settle — weight lands: fast in, soft stop, never a bounce

    func test_settleSpansZeroToOne() {
        XCTAssertEqual(PWMotion.settle(0), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.settle(1), 1, accuracy: 0.0001)
    }

    func test_settleIsFastInSoftStop() {
        // 1 - (1-u)^3 at u = 0.5 is 0.875 — most of the distance is already covered.
        XCTAssertEqual(PWMotion.settle(0.5), 0.875, accuracy: 0.0001)
    }

    /// "Never a bounce" is the design's words — settle must never exceed 1.
    func test_settleNeverOvershoots() {
        for step in 0...100 {
            let value = PWMotion.settle(Double(step) / 100)
            XCTAssertLessThanOrEqual(value, 1.0)
            XCTAssertGreaterThanOrEqual(value, 0.0)
        }
    }

    func test_settleIsMonotonic() {
        var previous = -1.0
        for step in 0...100 {
            let value = PWMotion.settle(Double(step) / 100)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func test_settleClampsOutsideTheUnitRange() {
        XCTAssertEqual(PWMotion.settle(-5), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.settle(5), 1, accuracy: 0.0001)
    }

    // MARK: grow — sprout: overshoot, then rest

    func test_growSpansZeroToOne() {
        XCTAssertEqual(PWMotion.grow(0), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.grow(1), 1, accuracy: 0.0001)
    }

    /// The whole point of `grow` is that it passes 1 before settling back to it.
    func test_growActuallyOvershoots() {
        let peak = stride(from: 0.0, through: 1.0, by: 0.01)
            .map { PWMotion.grow($0) }
            .max() ?? 0
        XCTAssertGreaterThan(peak, 1.0)
    }

    func test_growClampsOutsideTheUnitRange() {
        XCTAssertEqual(PWMotion.grow(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.grow(2), 1, accuracy: 0.0001)
    }

    // MARK: sway — nothing is ever still

    func test_swayIsZeroAtTheStartOfItsPeriod() {
        XCTAssertEqual(PWMotion.sway(at: 0), 0, accuracy: 0.0001)
    }

    /// A quarter period in, the sway is at full amplitude.
    func test_swayReachesFullAmplitudeAtAQuarterPeriod() {
        XCTAssertEqual(PWMotion.sway(at: 3.5), 3.6, accuracy: 0.0001)
    }

    func test_swayReturnsToZeroAtHalfPeriod() {
        XCTAssertEqual(PWMotion.sway(at: 7), 0, accuracy: 0.0001)
    }

    func test_swayStaysWithinAmplitude() {
        for step in 0...280 {
            let value = PWMotion.sway(at: Double(step) / 10)
            XCTAssertLessThanOrEqual(abs(value), 3.6 + 0.0001)
        }
    }

    /// Phase is what keeps two trees from swaying in lockstep.
    func test_phaseShiftsTheSway() {
        XCTAssertNotEqual(PWMotion.sway(at: 1), PWMotion.sway(at: 1, phase: 2.1), accuracy: 0.0001)
    }

    // MARK: ramp

    func test_rampMapsAWindowToZeroOne() {
        XCTAssertEqual(PWMotion.ramp(0.25, 0.25, 0.75), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.50, 0.25, 0.75), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.75, 0.25, 0.75), 1, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.10, 0.25, 0.75), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.90, 0.25, 0.75), 1, accuracy: 0.0001)
    }

    // MARK: staggered growth — back to front

    func test_nothingHasGrownAtZeroLock() {
        for index in 0..<8 {
            XCTAssertEqual(PWMotion.growth(index: index, count: 8, lock: 0), 0, accuracy: 0.0001)
        }
    }

    /// Everything must be fully grown once the lock has landed, or elements
    /// would be stuck part-sprouted for the entire quiet window.
    func test_everythingIsGrownAtFullLock() {
        for index in 0..<8 {
            XCTAssertEqual(PWMotion.growth(index: index, count: 8, lock: 1), 1, accuracy: 0.0001)
        }
    }

    /// Earlier elements lead later ones — that is what "staggered, back to front" means.
    func test_earlierElementsLeadLaterOnes() {
        let first = PWMotion.growth(index: 0, count: 8, lock: 0.4)
        let last = PWMotion.growth(index: 7, count: 8, lock: 0.4)
        XCTAssertGreaterThan(first, last)
    }

    /// A single-element scene must not divide by zero.
    func test_singleElementIsSafe() {
        XCTAssertEqual(PWMotion.growth(index: 0, count: 1, lock: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.crawl(index: 0, count: 1, lock: 1), 1, accuracy: 0.0001)
    }

    // MARK: crawl — the Overgrown variant, wider and unaccelerated

    func test_crawlSpansZeroToOne() {
        XCTAssertEqual(PWMotion.crawl(index: 3, count: 11, lock: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.crawl(index: 3, count: 11, lock: 1), 1, accuracy: 0.0001)
    }

    func test_crawlEarlierElementsLeadLaterOnes() {
        let first = PWMotion.crawl(index: 0, count: 11, lock: 0.5)
        let last = PWMotion.crawl(index: 10, count: 11, lock: 0.5)
        XCTAssertGreaterThan(first, last)
    }

    /// Unlike `grow`, `crawl` is linear — a vine creeping, not a sprout popping.
    func test_crawlNeverOvershoots() {
        for step in 0...100 {
            let value = PWMotion.crawl(index: 0, count: 11, lock: Double(step) / 100)
            XCTAssertLessThanOrEqual(value, 1.0)
        }
    }
}
