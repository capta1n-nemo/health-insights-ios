import XCTest
@testable import InsightKit

/// The parametric body model: the shape, the morph between two scans, and the
/// forecast past the last one.
///
/// The reader named smooth movement between captures as the priority over the
/// scrubber itself, so `interpolate` is the load-bearing function here.
final class BodyModelParametersTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_785_000_000)

    private func measurements(waist: Double = 88, hip: Double = 100,
                              chest: Double = 104) -> BodyMeasurements {
        BodyMeasurements([
            .init(site: .waist, centimetres: waist),
            .init(site: .hip, centimetres: hip),
            .init(site: .chest, centimetres: chest)
        ])
    }

    private func model(waist: Double = 88, measured: Bool = true,
                       at when: Date? = nil) -> BodyModelParameters {
        BodyModelParameters.build(
            heightMetres: 1.80, weightKg: 82, bodyFatPercentage: 22, sex: .male,
            measurements: measured ? measurements(waist: waist) : nil,
            date: when ?? day)!
    }

    private func velocity(kgPerWeek: Double, weight: Double = 82,
                          residual: Double = 0.4) -> CompositionVelocity {
        CompositionVelocity(windowDays: 90, kilogramsPerWeek: kgPerWeek,
                            percentPerWeek: kgPerWeek / weight * 100,
                            leanKilogramsPerWeek: nil, leanShareOfChange: nil,
                            residualSD: residual, weighIns: 30, latestWeight: weight)
    }

    // MARK: - Building

    /// **Every model carries every station.** That is what makes a morph
    /// well-defined — two shapes with different station sets would need a
    /// correspondence nobody has.
    func testEveryModelCarriesEveryStation() {
        XCTAssertEqual(model().stations.map(\.station), BodyStation.allCases)
        XCTAssertEqual(model(measured: false).stations.map(\.station), BodyStation.allCases)
    }

    /// Stations come back in a fixed head-to-foot order whatever order they
    /// were supplied in, so the renderer never has to sort.
    func testStationOrderIsCanonical() {
        let shuffled = BodyModelParameters(
            heightMetres: 1.8,
            stations: [BodyStationValue(station: .calf, circumferenceCentimetres: 38,
                                        isMeasured: true),
                       BodyStationValue(station: .neck, circumferenceCentimetres: 39,
                                        isMeasured: true)],
            date: day)
        XCTAssertEqual(shuffled.stations.map(\.station), [.neck, .calf])
    }

    /// A measured site wins; the rest are filled so the shape is complete.
    func testMeasuredSitesWinAndTheRestAreFlaggedEstimated() throws {
        let built = model()
        XCTAssertEqual(built.girth(.waist), 88)
        XCTAssertTrue(try XCTUnwrap(built.stations.first { $0.station == .waist }).isMeasured)
        XCTAssertFalse(try XCTUnwrap(built.stations.first { $0.station == .calf }).isMeasured,
                       "nothing measured a calf")
    }

    /// **It renders before the first scan.** A body model that appears only
    /// after a scan cannot be the thing that persuades anyone to take one.
    func testItBuildsFromWeightAndFatAlone() {
        let estimated = model(measured: false)
        XCTAssertTrue(estimated.isWhollyEstimated)
        XCTAssertTrue(estimated.stations.allSatisfy { $0.circumferenceCentimetres > 0 })
    }

    /// A heavier body is drawn wider, and the trunk moves more than the calf —
    /// scaling everything by one number is what makes a projection look wrong.
    func testAHeavierBodyIsWiderAtTheTrunkFirst() throws {
        let light = BodyModelParameters.build(heightMetres: 1.80, weightKg: 70,
                                              bodyFatPercentage: 15, sex: .male,
                                              measurements: nil, date: day)!
        let heavy = BodyModelParameters.build(heightMetres: 1.80, weightKg: 110,
                                              bodyFatPercentage: 35, sex: .male,
                                              measurements: nil, date: day)!
        let waistGain = try XCTUnwrap(heavy.girth(.waist)) - (try XCTUnwrap(light.girth(.waist)))
        let calfGain = try XCTUnwrap(heavy.girth(.calf)) - (try XCTUnwrap(light.girth(.calf)))
        XCTAssertGreaterThan(waistGain, 0)
        XCTAssertGreaterThan(waistGain, calfGain)
    }

    func testNonsenseInputsBuildNothing() {
        XCTAssertNil(BodyModelParameters.build(heightMetres: 0, weightKg: 82,
                                               bodyFatPercentage: 20, sex: .male,
                                               measurements: nil, date: day))
        XCTAssertNil(BodyModelParameters.build(heightMetres: 1.8, weightKg: 0,
                                               bodyFatPercentage: 20, sex: .male,
                                               measurements: nil, date: day))
    }

    // MARK: - The morph

    func testInterpolationHitsBothEnds() throws {
        let a = model(waist: 88), b = model(waist: 80)
        XCTAssertEqual(try XCTUnwrap(BodyModelParameters.interpolate(from: a, to: b, t: 0)
            .girth(.waist)), 88, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(BodyModelParameters.interpolate(from: a, to: b, t: 1)
            .girth(.waist)), 80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(BodyModelParameters.interpolate(from: a, to: b, t: 0.5)
            .girth(.waist)), 84, accuracy: 1e-9)
    }

    /// Monotonic and continuous across the whole scrub — the property that makes
    /// the animation read as one body changing rather than as a slideshow.
    func testTheMorphIsMonotonicAcrossTheScrub() throws {
        let a = model(waist: 96), b = model(waist: 82)
        var previous = Double.infinity
        for step in 0...20 {
            let girth = try XCTUnwrap(BodyModelParameters.interpolate(
                from: a, to: b, t: Double(step) / 20).girth(.waist))
            XCTAssertLessThanOrEqual(girth, previous + 1e-9)
            previous = girth
        }
    }

    /// A scrubber cannot run off either end of its own track.
    func testTheScrubIsClamped() throws {
        let a = model(waist: 88), b = model(waist: 80)
        XCTAssertEqual(try XCTUnwrap(BodyModelParameters.interpolate(from: a, to: b, t: -3)
            .girth(.waist)), 88, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(BodyModelParameters.interpolate(from: a, to: b, t: 9)
            .girth(.waist)), 80, accuracy: 1e-9)
    }

    /// **A morph out of an estimate is still an estimate.** Inheriting the
    /// measured end would launder a guess into a fact halfway through the
    /// animation, and the renderer draws measured and estimated differently.
    func testAStationIsMeasuredOnlyWhenBothEndsWere() throws {
        let measured = model(waist: 88, measured: true)
        let guessed = model(waist: 88, measured: false)
        let mid = BodyModelParameters.interpolate(from: measured, to: guessed, t: 0.5)
        XCTAssertFalse(try XCTUnwrap(mid.stations.first { $0.station == .waist }).isMeasured)

        let both = BodyModelParameters.interpolate(from: measured, to: measured, t: 0.5)
        XCTAssertTrue(try XCTUnwrap(both.stations.first { $0.station == .waist }).isMeasured)
    }

    /// The interpolated date lands between the two, so a scrubber can label it.
    func testTheDateInterpolatesToo() {
        let a = model(at: day)
        let b = model(at: day.addingTimeInterval(100 * 24 * 3600))
        let mid = BodyModelParameters.interpolate(from: a, to: b, t: 0.5)
        XCTAssertEqual(mid.date.timeIntervalSince1970,
                       day.addingTimeInterval(50 * 24 * 3600).timeIntervalSince1970,
                       accuracy: 1)
    }

    // MARK: - The forecast

    /// Losing weight narrows the body, and the waist leads.
    func testLosingWeightNarrowsTheTrunkFastest() throws {
        let now = model()
        let future = try XCTUnwrap(BodyModelParameters.project(
            now, velocity: velocity(kgPerWeek: -0.5), weeks: 12))
        let waistDrop = try XCTUnwrap(now.girth(.waist)) - (try XCTUnwrap(future.girth(.waist)))
        let calfDrop = try XCTUnwrap(now.girth(.calf)) - (try XCTUnwrap(future.girth(.calf)))
        XCTAssertGreaterThan(waistDrop, 0)
        XCTAssertGreaterThan(waistDrop, calfDrop)
    }

    /// Gaining works in the other direction with the same machinery — a sign
    /// error here would show somebody shrinking as they bulk.
    func testGainingWidens() throws {
        let now = model()
        let future = try XCTUnwrap(BodyModelParameters.project(
            now, velocity: velocity(kgPerWeek: 0.4), weeks: 8))
        XCTAssertGreaterThan(try XCTUnwrap(future.girth(.waist)),
                             try XCTUnwrap(now.girth(.waist)))
    }

    /// **The calibration, pinned against the literature.**
    ///
    /// A girth is a length and mass scales with volume, so a relative mass
    /// change moves a circumference by roughly half as much — and the waist,
    /// carrying the top responsiveness, lands at about 0.7 of the mass change.
    /// A 10% weight loss should take 6–8% off the waist, which is the published
    /// range; the first version of this returned 11% because the weights were
    /// normalised to their own mean, and this test is what caught it.
    func testTheWaistTracksTheLiteratureBandForA10PercentLoss() throws {
        let now = model()
        let future = try XCTUnwrap(BodyModelParameters.project(
            now, velocity: velocity(kgPerWeek: -8.2), weeks: 1))   // −10% of 82 kg
        let drop = 1 - (try XCTUnwrap(future.girth(.waist)))
            / (try XCTUnwrap(now.girth(.waist)))
        XCTAssertGreaterThan(drop, 0.06)
        XCTAssertLessThan(drop, 0.08)
    }

    /// And no station may move *more* than the mass did — a circumference
    /// outrunning the weight change is the sign that a normalisation has crept
    /// back in.
    func testNoStationOutrunsTheMassChange() throws {
        let now = model()
        let future = try XCTUnwrap(BodyModelParameters.project(
            now, velocity: velocity(kgPerWeek: -8.2), weeks: 1))
        for station in BodyStation.allCases {
            let drop = 1 - (try XCTUnwrap(future.girth(station)))
                / (try XCTUnwrap(now.girth(station)))
            XCTAssertLessThan(drop, 0.10, "\(station) moved faster than the mass did")
        }
    }

    /// **Nothing in a forecast was measured.** No station may come back marked
    /// as though somebody had put a tape round it.
    func testAProjectionIsNeverMarkedMeasured() {
        let future = BodyModelParameters.project(model(), velocity: velocity(kgPerWeek: -0.5),
                                                 weeks: 6)
        XCTAssertEqual(future?.stations.filter(\.isMeasured).count, 0)
        XCTAssertTrue(future?.isWhollyEstimated ?? false)
    }

    /// A weight that is not meaningfully moving cannot be projected — drawing a
    /// change from a slope inside its own noise is the defect
    /// `CompositionVelocity.isMoving` exists to prevent.
    func testAStableWeightIsNotProjected() {
        XCTAssertNil(BodyModelParameters.project(model(), velocity: velocity(kgPerWeek: 0.01),
                                                 weeks: 12))
    }

    func testTheHorizonMustBePositive() {
        XCTAssertNil(BodyModelParameters.project(model(), velocity: velocity(kgPerWeek: -0.5),
                                                 weeks: 0))
    }

    /// The forecast's honest ± comes from the fit's own residual, exactly as
    /// the VO₂max trajectory already does.
    func testTheSpreadComesFromTheResidual() {
        XCTAssertEqual(BodyModelParameters.projectionSpreadKg(velocity(kgPerWeek: -0.5,
                                                                      residual: 0.7)),
                       0.7)
    }

    /// A projection far enough out must never invert a girth through zero.
    func testAnExtremeHorizonStaysPhysical() throws {
        let future = try XCTUnwrap(BodyModelParameters.project(
            model(), velocity: velocity(kgPerWeek: -1.5), weeks: 520))
        XCTAssertTrue(future.stations.allSatisfy { $0.circumferenceCentimetres > 0 })
    }
}
