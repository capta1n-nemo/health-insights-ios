import XCTest
@testable import InsightKit

/// Binds the centile *words* to the centile *bands*.
///
/// `Standing.phrase` used to hold the edges 90 / 75 / 60 / 40 / 25 inline. The
/// Heart Health strip draws those bands, so the shading and the sentence beside
/// it are now two readings of one threshold table — exactly the situation
/// `PressureBandTests` exists for on the blood-pressure side, where `Category.of`
/// classifies and `systolicRange` shades. Two copies of a threshold drift; a test
/// that sweeps the domain is what stops them.
final class PeerStandingBandTests: XCTestCase {

    private typealias Band = PeerStandingModel.Band

    /// No gaps, no overlaps, and the whole 0–100 axis covered. A gap would be a
    /// centile the strip can draw but cannot name; an overlap would be a centile
    /// with two names.
    func testBandsTileTheWholeAxisExactlyOnce() {
        let ordered = Band.allCases.sorted { $0.bounds.lowerBound < $1.bounds.lowerBound }
        XCTAssertEqual(ordered.first?.bounds.lowerBound, 0)
        XCTAssertEqual(ordered.last?.bounds.upperBound, 100)
        for (lower, upper) in zip(ordered, ordered.dropFirst()) {
            XCTAssertEqual(lower.bounds.upperBound, upper.bounds.lowerBound,
                           "\(lower) and \(upper) do not meet")
        }
    }

    /// The band `of(_:)` picks always contains the value it was picked for.
    /// This is the one that would fail if someone edited `bounds` and left
    /// `of(_:)` reading the old numbers, or vice versa.
    func testEveryCentileFallsInsideTheBandChosenForIt() {
        for tenth in 0...999 {
            let percentile = Double(tenth) / 10
            let band = Band.of(percentile)
            XCTAssertTrue(band.bounds.contains(percentile),
                          "\(percentile) was called \(band) but that band is \(band.bounds)")
        }
    }

    /// Six bands, six different words. A duplicate phrase would make two
    /// visually distinct positions read identically.
    func testEveryBandHasItsOwnWords() {
        XCTAssertEqual(Set(Band.allCases.map(\.phrase)).count, Band.allCases.count)
    }

    /// Exactly one band is marked typical — the strip shades one stretch, and
    /// "ordinary" cannot be two places at once.
    func testExactlyOneBandIsTheTypicalOne() {
        XCTAssertEqual(Band.allCases.filter(\.isTypical).count, 1)
        XCTAssertEqual(Band.aroundAverage.bounds, 40..<60)
    }

    /// `Standing` must keep delegating rather than growing its own copy of the
    /// switch back — which is the state this extraction was undoing.
    func testStandingPhraseIsTheBandsPhrase() {
        for whole in 0...100 {
            let standing = PeerStandingModel.Standing(
                metric: .restingHeartRate, value: 60, percentile: Double(whole))
            XCTAssertEqual(standing.phrase, Band.of(Double(whole)).phrase)
            XCTAssertEqual(standing.band, Band.of(Double(whole)))
        }
    }

    /// The domain the strip actually has to draw. `percentile(_:norm:)` clamps,
    /// so an axis of 0–100 never has to render a point at either extreme — and
    /// a band table that only tiles [0, 100) is therefore complete.
    func testPercentilesAreClampedInsideTheAxis() {
        let norm = PeerStandingModel.Norm(mean: 60, sd: 10, higherIsBetter: false)
        for value in stride(from: -200.0, through: 400.0, by: 5) {
            let p = PeerStandingModel.percentile(value, norm: norm)
            XCTAssertGreaterThanOrEqual(p, 1)
            XCTAssertLessThanOrEqual(p, 99)
        }
    }

    /// The orientation the whole type rests on: a *low* resting heart rate is a
    /// *high* centile. Re-asserted here because the strip draws position, and a
    /// flipped axis would be invisible in prose but obvious as a picture.
    func testLowerIsBetterMetricsAreDrawnHigherUpTheAxis() {
        let norm = PeerStandingModel.Norm(mean: 68, sd: 10, higherIsBetter: false)
        let athlete = PeerStandingModel.percentile(48, norm: norm)
        let typical = PeerStandingModel.percentile(68, norm: norm)
        XCTAssertGreaterThan(athlete, typical)
        XCTAssertEqual(Band.of(typical), .aroundAverage)
    }
}
