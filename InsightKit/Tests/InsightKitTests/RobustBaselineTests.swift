import XCTest
@testable import InsightKit

/// **A standard deviation has a breakdown point of zero, and the symptom radar
/// divides by one.**
///
/// The reader, 2026-08-05: *"Today my heart rate is still elevated, my HRV is
/// still down, and yesterday it flagged I had symptoms which was absolutely
/// correct. Why am I now back at 99% just 1 day later?"*
///
/// Part of the answer is in the denominator. `HealthWatchModel` scores today
/// against the mean and SD of a trailing 21-day reference window. When the
/// reader was genuinely unwell, those nights aged into that window and — on
/// their own export — the reference spread for resting heart rate swung **2.7×**
/// (0.59 → 1.57 in units of its own median). Every z-score divides by it, so a
/// still-elevated reading scored as normal. The bar moved.
///
/// Measured the same way with median/MAD, the same window moved 1.00 → 1.26.
final class RobustBaselineTests: XCTestCase {

    /// Twenty ordinary days and one bad one. The mean-and-SD estimator is
    /// visibly moved by the single outlier; the robust pair is not.
    func testOneExcursionMovesTheSDAndNotTheMAD() throws {
        let ordinary = [50.0, 51, 49, 50, 52, 48, 51, 50, 49, 51,
                        50, 52, 49, 50, 51, 48, 50, 51, 49, 50]
        let withExcursion = ordinary + [75.0]

        let sdBefore = try XCTUnwrap(Baseline.standardDeviation(ordinary))
        let sdAfter = try XCTUnwrap(Baseline.standardDeviation(withExcursion))
        let robustBefore = try XCTUnwrap(Baseline.robustScale(ordinary))
        let robustAfter = try XCTUnwrap(Baseline.robustScale(withExcursion))

        XCTAssertGreaterThan(sdAfter / sdBefore, 2.5,
                             "one bad day should visibly inflate the SD — if it does not, this fixture is too tame to prove anything")
        XCTAssertLessThan(robustAfter / robustBefore, 1.3,
                          "the robust scale moved nearly as much as the SD, so it is not buying the property it exists for")
    }

    /// **The non-circularity property, asserted directly.** A 50% breakdown
    /// point is what lets the radar avoid marking days as perturbed — a rule
    /// that would need the very flag those days feed. Up to half the window can
    /// be excursion and the estimate still describes the ordinary half.
    func testUpToHalfTheWindowCanBeExcursionWithoutMovingTheEstimate() throws {
        let ordinary = Array(repeating: 50.0, count: 11)
        let excursions = Array(repeating: 90.0, count: 10)
        let contaminated = ordinary + excursions

        XCTAssertEqual(try XCTUnwrap(Baseline.median(contaminated)), 50, accuracy: 0.001,
                       "ten excursion days in twenty-one moved the median, so the breakdown point is not 50%")
        // The mean, for contrast, is dragged most of the way to the excursions.
        XCTAssertGreaterThan(try XCTUnwrap(Baseline.mean(contaminated)), 65)
    }

    /// The consistency constant means a robust scale and an SD agree when
    /// nothing is wrong — which is what makes this a drop-in for a divisor
    /// rather than a change of units.
    func testRobustScaleAgreesWithSDOnCleanData() throws {
        // A symmetric, evenly-spread sample: the two estimators should land
        // within a modest factor of each other.
        let clean = stride(from: 40.0, through: 60.0, by: 1.0).map { $0 }
        let sd = try XCTUnwrap(Baseline.standardDeviation(clean))
        let robust = try XCTUnwrap(Baseline.robustScale(clean))
        XCTAssertEqual(robust / sd, 1.0, accuracy: 0.25,
                       "the 1.4826 consistency constant is not doing its job — these are not the same scale")
    }

    /// **MAD is exactly zero whenever more than half the values are identical**,
    /// which a rounded daily metric reaches easily — and a z-score dividing by
    /// it is infinite. The floor is the guard, and it is why `floor` exists.
    func testAFlatWindowWouldDivideByZeroWithoutTheFloor() throws {
        let flat = Array(repeating: 50.0, count: 21)
        XCTAssertEqual(try XCTUnwrap(Baseline.medianAbsoluteDeviation(flat)), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Baseline.robustScale(flat)), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Baseline.robustScale(flat, floor: 2.5)), 2.5, accuracy: 1e-12,
                       "the floor is the only thing standing between a rounded metric and an infinite z-score")
    }

    /// A majority-identical window is the realistic version of the case above:
    /// eleven of twenty-one readings equal, and MAD is still zero.
    func testAMajorityIdenticalWindowAlsoHasZeroMAD() throws {
        let majority = Array(repeating: 50.0, count: 11) + [48.0, 49, 51, 52, 47, 53, 46, 54, 45, 55]
        XCTAssertEqual(try XCTUnwrap(Baseline.medianAbsoluteDeviation(majority)), 0, accuracy: 1e-12)
        XCTAssertGreaterThan(try XCTUnwrap(Baseline.standardDeviation(majority)), 0)
    }

    // MARK: - The ordinary properties

    func testMedianIsTheMiddleValue() throws {
        XCTAssertEqual(try XCTUnwrap(Baseline.median([3, 1, 2])), 2, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Baseline.median([4, 1, 3, 2])), 2.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Baseline.median([7])), 7, accuracy: 1e-12)
    }

    func testEmptyInputIsNilRatherThanZero() {
        XCTAssertNil(Baseline.median([]))
        XCTAssertNil(Baseline.medianAbsoluteDeviation([]))
        XCTAssertNil(Baseline.robustScale([]))
        XCTAssertNil(Baseline.robustScale([], floor: 5),
                     "a floor must not manufacture a scale for a window with no readings in it")
    }
}
