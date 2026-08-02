import XCTest
@testable import InsightKit

/// The helper that turns a band table into a curve, and the shipped ladders
/// built on it.
final class ScoreCurveTests: XCTestCase {

    private let anchors: [(input: Double, score: Double)] = [(0, 20), (10, 60), (20, 100)]

    func testItHitsEveryAnchorExactly() {
        for anchor in anchors {
            XCTAssertEqual(ScoreCurve.through(anchors, at: anchor.input), anchor.score,
                           accuracy: 1e-9, "anchor at \(anchor.input)")
        }
    }

    func testItInterpolatesLinearlyBetweenAnchors() {
        XCTAssertEqual(ScoreCurve.through(anchors, at: 5), 40, accuracy: 1e-9)
        XCTAssertEqual(ScoreCurve.through(anchors, at: 15), 80, accuracy: 1e-9)
        XCTAssertEqual(ScoreCurve.through(anchors, at: 2.5), 30, accuracy: 1e-9)
    }

    /// Flat outside, never extrapolated — extrapolating a clinical band table
    /// past its own evidence is how a score reaches −40.
    func testItIsFlatBeyondTheEnds() {
        XCTAssertEqual(ScoreCurve.through(anchors, at: -1000), 20)
        XCTAssertEqual(ScoreCurve.through(anchors, at: 1000), 100)
    }

    func testAnEmptyCurveIsZeroRatherThanACrash() {
        XCTAssertEqual(ScoreCurve.through([], at: 5), 0)
    }

    /// A single anchor is a constant, not a division by zero.
    func testASingleAnchorIsAConstant() {
        XCTAssertEqual(ScoreCurve.through([(5, 70)], at: -3), 70)
        XCTAssertEqual(ScoreCurve.through([(5, 70)], at: 5), 70)
        XCTAssertEqual(ScoreCurve.through([(5, 70)], at: 99), 70)
    }

    /// **Every shipped ladder must be sorted by input.** `through` walks the
    /// pairs in order and an unsorted table silently returns the wrong arm — a
    /// failure with no symptom at the call site, so it is checked here rather
    /// than guarded at runtime on every score.
    func testEveryShippedLadderIsSorted() {
        let ladders: [(String, [(input: Double, score: Double)])] = [
            ("BloodPressureEstimator.systolicLadder", BloodPressureEstimator.systolicLadder),
            ("BloodPressureEstimator.diastolicLadder", BloodPressureEstimator.diastolicLadder)
        ]
        for (name, ladder) in ladders {
            XCTAssertEqual(ladder.map(\.input), ladder.map(\.input).sorted(),
                           "\(name) is not sorted by input")
            XCTAssertGreaterThan(ladder.count, 1, "\(name) is not a curve")
        }
    }

    /// The blood-pressure ladders must **fall** — a higher pressure can never
    /// score better than a lower one, which is the one thing a mis-typed anchor
    /// would break without any test noticing.
    func testTheBloodPressureLaddersOnlyEverFall() {
        for (name, ladder) in [("systolic", BloodPressureEstimator.systolicLadder),
                               ("diastolic", BloodPressureEstimator.diastolicLadder)] {
            for (low, high) in zip(ladder, ladder.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    low.score, high.score,
                    "\(name) ladder rises from \(low.input) to \(high.input)")
            }
        }
    }

    /// The published boundaries still read as the published boundaries — the
    /// curve replaced the cliff, not the guidance.
    func testTheBandBoundariesKeepTheirScores() {
        // Systolic 130 and diastolic 80 are both the entry to stage 1, and must
        // agree: neither axis is harsher than the other about the same band.
        XCTAssertEqual(BloodPressureEstimator.score(systolic: 130, diastolic: 60), 65,
                       accuracy: 1e-9)
        XCTAssertEqual(BloodPressureEstimator.score(systolic: 90, diastolic: 80), 65,
                       accuracy: 1e-9)
        // Stage 2, likewise.
        XCTAssertEqual(BloodPressureEstimator.score(systolic: 140, diastolic: 60), 40,
                       accuracy: 1e-9)
        XCTAssertEqual(BloodPressureEstimator.score(systolic: 90, diastolic: 90), 40,
                       accuracy: 1e-9)
    }

    /// **The regression.** A tenth of a mmHg of diastolic used to cost forty
    /// points, because the band was chosen by both numbers and the position
    /// inside it was graded by systolic alone.
    func testATenthOfAMillimetreNoLongerCostsFortyPoints() {
        let below = BloodPressureEstimator.score(systolic: 90, diastolic: 79.9)
        let above = BloodPressureEstimator.score(systolic: 90, diastolic: 80.0)
        XCTAssertLessThan(abs(below - above), 1,
                          "90/79.9 scored \(below) and 90/80.0 scored \(above)")
    }

    /// And a healthy reading still reads as healthy — the fix must not have
    /// bought continuity by marking everybody down.
    func testAHealthyReadingStillScoresWell() {
        XCTAssertGreaterThan(BloodPressureEstimator.score(systolic: 118, diastolic: 76), 80)
        XCTAssertGreaterThan(BloodPressureEstimator.score(systolic: 110, diastolic: 70), 85)
        XCTAssertLessThan(BloodPressureEstimator.score(systolic: 185, diastolic: 125), 20)
    }
}
