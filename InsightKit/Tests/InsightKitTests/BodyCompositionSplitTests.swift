import XCTest
@testable import InsightKit

/// The composition split behind Body Composition's bespoke section (Phase 2).
///
/// The fixtures are the user's own latest readings from the 2026-08-01 export,
/// because the arithmetic's failure mode is a bar that doesn't add up and only
/// real, mutually-inconsistent scale readings show whether it does.
final class BodyCompositionSplitTests: XCTestCase {

    private func sample(_ type: MetricType, _ value: Double,
                        daysAgo: Double = 0) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value,
                           start: TestClock.now.addingTimeInterval(-daysAgo * 86_400),
                           source: .withings)
    }

    /// Weight 110.73 kg, fat 30.61%, lean 77.0, muscle 73.19, bone 3.81 —
    /// Withings' own figures, which happen to be self-consistent: muscle plus
    /// bone is exactly the lean mass, and fat plus lean is the weight.
    private var actual: [HealthMetricSample] {
        [sample(.bodyMass, 110.73), sample(.bodyFatPercentage, 30.61),
         sample(.leanBodyMass, 77.0), sample(.muscleMass, 73.19),
         sample(.boneMass, 3.81), sample(.bodyWaterPercentage, 52.20)]
    }

    func testTheSplitAddsUpToBodyMass() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: actual))
        let summed = split.parts.reduce(0) { $0 + $1.kilograms }
        XCTAssertEqual(summed, split.total, accuracy: 0.5)
        XCTAssertFalse(split.isPartial)
        XCTAssertEqual(split.parts.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.01)
    }

    func testFatMassIsDerivedFromThePercentageOfWeight() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: actual))
        let fat = try XCTUnwrap(split.parts.first { $0.label == "Fat" })
        // 110.73 × 30.61% — and `withings.measure.8` in the export reads 33.98.
        XCTAssertEqual(fat.kilograms, 33.90, accuracy: 0.1)
    }

    func testMuscleAndBoneDivideTheLeanMassRatherThanAddingToIt() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: actual))
        XCTAssertEqual(split.parts.map(\.label), ["Fat", "Muscle", "Bone"],
                       "muscle + bone exactly fills lean, so there is no remainder block")
    }

    /// Water is a percentage of tissue already counted as muscle. Adding it to
    /// the bar would count the same kilograms twice.
    func testWaterIsCarriedButIsNotAPartOfTheBar() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: actual))
        XCTAssertEqual(split.waterPercentage, 52.20)
        XCTAssertFalse(split.parts.contains { $0.label.contains("ater") })
    }

    // MARK: - Water drawn inside its host

    /// 110.73 kg × 52.20% = 57.8 kg of water, inside 73.19 kg of muscle — 79% of
    /// the muscle block. Roughly what physiology predicts (muscle is ~75% water,
    /// and blood and organs carry the rest), which is the sanity check on the
    /// whole idea of drawing it as an inset.
    func testWaterSitsInsideTheMuscleBlock() throws {
        let inset = try XCTUnwrap(try XCTUnwrap(BodyCompositionSplit.from(samples: actual)).water)
        XCTAssertEqual(inset.host, .muscleMass)
        XCTAssertEqual(inset.kilograms, 57.80, accuracy: 0.05)
        XCTAssertEqual(inset.fractionOfHost, 0.79, accuracy: 0.01)
        XCTAssertFalse(inset.exceedsHost)
    }

    /// Without a muscle reading the lean block hosts it. Never fat — the point
    /// of the inset is that water is held in lean tissue.
    func testWaterFallsBackToTheLeanBlock() throws {
        let inset = try XCTUnwrap(try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.bodyFatPercentage, 30),
            sample(.bodyWaterPercentage, 50),
        ])).water)
        XCTAssertEqual(inset.host, .leanBodyMass)
        XCTAssertEqual(inset.kilograms, 50, accuracy: 0.001)
        XCTAssertEqual(inset.fractionOfHost, 50.0 / 70.0, accuracy: 0.001)
    }

    /// Total body water can genuinely exceed muscle mass. Clamp and flag rather
    /// than drawing an inset that overflows the block it is inside.
    func testWaterExceedingItsHostIsClampedAndFlagged() throws {
        let inset = try XCTUnwrap(try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.leanBodyMass, 60),
            sample(.muscleMass, 40), sample(.boneMass, 3),
            sample(.bodyWaterPercentage, 55),   // 55 kg of water in a 40 kg block
        ])).water)
        XCTAssertEqual(inset.host, .muscleMass)
        XCTAssertTrue(inset.exceedsHost)
        XCTAssertEqual(inset.fractionOfHost, 1, "clamped, not overflowing")
    }

    func testNoWaterReadingMeansNoInset() throws {
        XCTAssertNil(try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.bodyFatPercentage, 25),
        ])).water)
    }

    // MARK: - Where the water film goes

    /// Water is not a band and adds no mass. It is a rectangle painted over the
    /// band that hosts it, so what matters is that its span sits *inside* that
    /// band — carving it out instead is what made three attempts read as a third
    /// substance whatever colour they were given.
    func testTheWaterSpanSitsInsideItsHostBand() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: actual))
        let span = try XCTUnwrap(split.waterSpan)
        // Fat is 33.9 kg, so the muscle band runs from there to 33.9 + 73.19.
        let fat = try XCTUnwrap(split.parts.first { $0.label == "Fat" }).kilograms
        let muscle = try XCTUnwrap(split.parts.first { $0.label == "Muscle" }).kilograms
        XCTAssertEqual(span.from, fat, accuracy: 0.01, "starts at the top of fat")
        XCTAssertEqual(span.to, fat + 57.80, accuracy: 0.05)
        XCTAssertLessThanOrEqual(span.to, fat + muscle + 0.001, "never escapes the band")
    }

    /// The bands are the whole partition again — water is drawn over them, not
    /// among them, so it must not appear as a band and must not change the sum.
    func testWaterIsNotABandAndDoesNotChangeTheTotal() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: actual))
        XCTAssertEqual(split.bands.map(\.kind), [.fat, .muscle, .bone])
        XCTAssertEqual(split.bands.reduce(0) { $0 + $1.kilograms },
                       split.total, accuracy: 0.5)
    }

    /// Water above its host is clamped, so the film cannot spill out of the band
    /// it is painted on.
    func testTheWaterSpanIsClampedToItsHost() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.leanBodyMass, 60),
            sample(.muscleMass, 40), sample(.boneMass, 3),
            sample(.bodyWaterPercentage, 55),
        ]))
        let span = try XCTUnwrap(split.waterSpan)
        let fat = try XCTUnwrap(split.parts.first { $0.label == "Fat" }).kilograms
        XCTAssertEqual(span.to - span.from, 40, accuracy: 0.01, "capped at the muscle")
        XCTAssertEqual(span.from, fat, accuracy: 0.01)
    }

    func testNoWaterMeansNoSpan() throws {
        XCTAssertNil(try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.bodyFatPercentage, 25),
        ])).waterSpan)
    }

    // MARK: - The series

    private func dayOffset(_ n: Int) -> Double { Double(n) }

    /// One point per weigh-in, and none invented in between. A carry-forward
    /// build would draw a body changing on days nothing was measured.
    func testOnePointPerMeasuredDay() {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 100, daysAgo: 10), sample(.bodyFatPercentage, 30, daysAgo: 10),
            sample(.bodyMass, 99, daysAgo: 5), sample(.bodyFatPercentage, 29, daysAgo: 5),
        ], calendar: TestClock.utc)
        XCTAssertEqual(series.points.count, 2)
        XCTAssertLessThan(series.points[0].date, series.points[1].date, "oldest first")
    }

    /// A weigh-in with no composition reading yields no point rather than a
    /// point with a guessed composition.
    func testAWeightWithNoCompositionIsSkipped() {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 100, daysAgo: 10),
            sample(.bodyMass, 99, daysAgo: 5), sample(.bodyFatPercentage, 29, daysAgo: 5),
        ], calendar: TestClock.utc)
        XCTAssertEqual(series.points.count, 1)
    }

    /// The defect behind "missing data breaks the graph". The scale logs a
    /// weight far more often than a full composition, so band membership used to
    /// change from point to point — and a stacked area whose series vanishes at
    /// one x collapses that band to zero and back, drawing a row of notches.
    ///
    /// Every point now carries the same bands. The day that measured only fat
    /// and lean borrows the muscle/bone ratio from the day that measured one,
    /// and says so.
    func testADayWithoutTheDivisionBorrowsItRatherThanDroppingBands() throws {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 120, daysAgo: 30), sample(.bodyFatPercentage, 35, daysAgo: 30),
            sample(.bodyMass, 115, daysAgo: 10), sample(.bodyFatPercentage, 33, daysAgo: 10),
            sample(.leanBodyMass, 77, daysAgo: 10), sample(.muscleMass, 73, daysAgo: 10),
            sample(.boneMass, 4, daysAgo: 10),
        ], calendar: TestClock.utc)
        XCTAssertEqual(series.points.map { $0.split.parts.map(\.label) },
                       [["Fat", "Muscle", "Bone"], ["Fat", "Muscle", "Bone"]],
                       "both points must carry the same bands, in the same order")
        XCTAssertTrue(series.points[0].isEstimated, "the borrowed day is flagged")
        XCTAssertFalse(series.points[1].isEstimated, "the measured day is not")
        XCTAssertEqual(series.finerSplitBegins, series.points[1].date)
    }

    /// Only the *ratio* is borrowed. Total, fat and lean are measured on the
    /// estimated day and must survive untouched — the bar is real, only its
    /// internal division is inferred.
    func testOnlyTheRatioIsBorrowedNotTheQuantities() throws {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 100, daysAgo: 30), sample(.bodyFatPercentage, 30, daysAgo: 30),
            sample(.bodyMass, 115, daysAgo: 10), sample(.bodyFatPercentage, 33, daysAgo: 10),
            sample(.leanBodyMass, 80, daysAgo: 10), sample(.muscleMass, 76, daysAgo: 10),
            sample(.boneMass, 4, daysAgo: 10),
        ], calendar: TestClock.utc)
        let estimated = series.points[0]
        XCTAssertEqual(estimated.split.total, 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(estimated.split.parts.first).kilograms, 30, accuracy: 0.001,
                       "measured fat is untouched")
        // Lean is 70 kg, divided 76:4 like the donor → 66.5 muscle, 3.5 bone.
        XCTAssertEqual(estimated.split.parts.reduce(0) { $0 + $1.kilograms },
                       100, accuracy: 0.01, "and the bands still sum to the weight")
        XCTAssertEqual(try XCTUnwrap(estimated.split.parts.first { $0.label == "Muscle" }).kilograms,
                       66.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(estimated.split.parts.first { $0.label == "Bone" }).kilograms,
                       3.5, accuracy: 0.01)
    }

    /// With nothing in the whole history dividing lean, there is no ratio to
    /// borrow — so nothing is estimated and nothing is invented.
    func testNoDonorMeansNothingIsEstimated() {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 120, daysAgo: 30), sample(.bodyFatPercentage, 35, daysAgo: 30),
            sample(.bodyMass, 115, daysAgo: 10), sample(.bodyFatPercentage, 33, daysAgo: 10),
        ], calendar: TestClock.utc)
        XCTAssertFalse(series.points.contains { $0.isEstimated })
        XCTAssertEqual(series.points[0].split.parts.map(\.label), ["Fat", "Lean"])
        XCTAssertNil(series.finerSplitBegins)
    }

    /// The water inset has to follow the lean block when it subdivides,
    /// otherwise it would point at a block that no longer exists and vanish.
    func testWaterFollowsTheLeanBlockWhenItIsSubdivided() throws {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 100, daysAgo: 30), sample(.bodyFatPercentage, 30, daysAgo: 30),
            sample(.bodyWaterPercentage, 50, daysAgo: 30),
            sample(.bodyMass, 100, daysAgo: 10), sample(.bodyFatPercentage, 30, daysAgo: 10),
            sample(.leanBodyMass, 70, daysAgo: 10), sample(.muscleMass, 66, daysAgo: 10),
            sample(.boneMass, 4, daysAgo: 10),
        ], calendar: TestClock.utc)
        let water = try XCTUnwrap(series.points[0].split.water)
        XCTAssertEqual(water.host, .muscleMass)
        XCTAssertEqual(water.kilograms, 50, accuracy: 0.001)
    }

    /// A window that is entirely fine-grained has no transition to explain, and
    /// a caption about one would point at nothing.
    func testNoTransitionIsReportedWhenTheWholeWindowIsTheSameResolution() {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 115, daysAgo: 10), sample(.bodyFatPercentage, 33, daysAgo: 10),
            sample(.leanBodyMass, 77, daysAgo: 10), sample(.muscleMass, 73, daysAgo: 10),
            sample(.boneMass, 4, daysAgo: 10),
        ], calendar: TestClock.utc)
        XCTAssertNil(series.finerSplitBegins)
    }

    // MARK: - What changed

    /// The question a composition history is opened for, which the chart could
    /// not answer: not what the body *is* but what it has *done*.
    func testTheChangeIsReportedWholeAndByBand() throws {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 120, daysAgo: 60), sample(.bodyFatPercentage, 40, daysAgo: 60),
            sample(.leanBodyMass, 72, daysAgo: 60), sample(.muscleMass, 68, daysAgo: 60),
            sample(.boneMass, 4, daysAgo: 60),
            sample(.bodyMass, 110, daysAgo: 1), sample(.bodyFatPercentage, 30, daysAgo: 1),
            sample(.leanBodyMass, 77, daysAgo: 1), sample(.muscleMass, 73, daysAgo: 1),
            sample(.boneMass, 4, daysAgo: 1),
        ], calendar: TestClock.utc)
        let change = try XCTUnwrap(BodyCompositionSplit.change(over: series.points))
        XCTAssertEqual(change.totalDelta, -10, accuracy: 0.001)
        // 48 kg of fat down to 33 — the loss came off fat while muscle rose.
        XCTAssertEqual(try XCTUnwrap(change.bands.first { $0.kind == .fat }).delta,
                       -15, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(change.bands.first { $0.kind == .muscle }).delta,
                       5, accuracy: 0.01)
    }

    /// The reason a total on its own is not enough: the same 10 kg off reads
    /// completely differently depending on which band it came out of.
    func testTheSameTotalLossIsADifferentEventDependingOnItsBand() throws {
        func lastFat(_ fatPercent: Double, lean: Double, muscle: Double) throws -> Double {
            let series = BodyCompositionSplit.series(samples: [
                sample(.bodyMass, 120, daysAgo: 60), sample(.bodyFatPercentage, 40, daysAgo: 60),
                sample(.leanBodyMass, 72, daysAgo: 60), sample(.muscleMass, 68, daysAgo: 60),
                sample(.boneMass, 4, daysAgo: 60),
                sample(.bodyMass, 110, daysAgo: 1), sample(.bodyFatPercentage, fatPercent, daysAgo: 1),
                sample(.leanBodyMass, lean, daysAgo: 1), sample(.muscleMass, muscle, daysAgo: 1),
                sample(.boneMass, 4, daysAgo: 1),
            ], calendar: TestClock.utc)
            let change = try XCTUnwrap(BodyCompositionSplit.change(over: series.points))
            return try XCTUnwrap(change.bands.first { $0.kind == .muscle }).delta
        }
        // Losing it off fat leaves muscle up; losing it off muscle does not.
        XCTAssertGreaterThan(try lastFat(30, lean: 77, muscle: 73), 0)
        XCTAssertLessThan(try lastFat(43.6, lean: 62, muscle: 58), 0)
    }

    /// Direction-of-good is per band and is not a judgement about weight: fat
    /// down is welcome, muscle down is not, and water is neither.
    func testDirectionOfGoodIsPerBand() {
        let kinds = BodyCompositionSplit.Band.Kind.self
        func better(_ k: BodyCompositionSplit.Band.Kind) -> Bool? {
            BodyCompositionSplit.BandChange(kind: k, label: "", delta: 0).higherIsBetter
        }
        XCTAssertEqual(better(kinds.fat), false)
        XCTAssertEqual(better(kinds.muscle), true)
        XCTAssertEqual(better(kinds.bone), true)
        XCTAssertNil(better(kinds.muscleWater), "hydration is not an achievement")
        XCTAssertNil(better(kinds.otherLean))
    }

    /// One weigh-in is a reading, not a change.
    func testASinglePointHasNoChange() {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 110, daysAgo: 1), sample(.bodyFatPercentage, 30, daysAgo: 1),
        ], calendar: TestClock.utc)
        XCTAssertNil(BodyCompositionSplit.change(over: series.points))
    }

    /// A band at one end and not the other is skipped rather than counted as
    /// having appeared out of nothing.
    func testABandMissingAtOneEndIsSkipped() throws {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 120, daysAgo: 60), sample(.bodyFatPercentage, 40, daysAgo: 60),
            sample(.bodyMass, 110, daysAgo: 1), sample(.bodyFatPercentage, 30, daysAgo: 1),
        ], calendar: TestClock.utc)
        let change = try XCTUnwrap(BodyCompositionSplit.change(over: series.points))
        XCTAssertEqual(change.bands.map(\.kind), [.fat, .lean])
        XCTAssertEqual(change.totalDelta, -10, accuracy: 0.001)
    }

    func testAnEmptyHistoryProducesNoPoints() {
        XCTAssertTrue(BodyCompositionSplit.series(samples: [],
                                                  calendar: TestClock.utc).points.isEmpty)
    }

    // MARK: - Partial and inconsistent input

    /// Fat and lean partition body mass, so either one implies the other.
    func testLeanAloneIsEnough() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.leanBodyMass, 70),
        ]))
        XCTAssertEqual(try XCTUnwrap(split.parts.first { $0.label == "Fat" }).kilograms,
                       30, accuracy: 0.001)
    }

    func testBodyFatAloneIsEnough() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.bodyFatPercentage, 25),
        ]))
        XCTAssertEqual(split.parts.map(\.label), ["Fat", "Lean"])
        XCTAssertEqual(try XCTUnwrap(split.parts.last).kilograms, 75, accuracy: 0.001)
    }

    /// A weight on its own divides into nothing. One block labelled "you" is not
    /// a composition split.
    func testWeightAloneProducesNoSplit() {
        XCTAssertNil(BodyCompositionSplit.from(samples: [sample(.bodyMass, 100)]))
    }

    func testNoWeightProducesNoSplit() {
        XCTAssertNil(BodyCompositionSplit.from(samples: [sample(.bodyFatPercentage, 25)]))
    }

    /// The failure that would draw a bar summing past the person's weight. A
    /// scale disagreeing with itself gets one undivided lean block.
    func testMuscleAndBoneExceedingLeanFallsBackToOneLeanBlock() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.leanBodyMass, 70),
            sample(.muscleMass, 68), sample(.boneMass, 5),   // 73 > 70
        ]))
        XCTAssertEqual(split.parts.map(\.label), ["Fat", "Lean"])
        XCTAssertEqual(split.parts.reduce(0) { $0 + $1.kilograms }, 100, accuracy: 0.001)
    }

    /// Lean tissue the scale didn't attribute is shown rather than hidden — but
    /// only when it is real, not when it is rounding.
    func testUnattributedLeanMassBecomesItsOwnBlock() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.leanBodyMass, 70),
            sample(.muscleMass, 60), sample(.boneMass, 4),
        ]))
        XCTAssertEqual(split.parts.map(\.label), ["Fat", "Muscle", "Bone", "Other lean"])
        XCTAssertEqual(try XCTUnwrap(split.parts.last).kilograms, 6, accuracy: 0.001)
    }

    func testARoundingSizedRemainderIsNotDrawn() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 100), sample(.leanBodyMass, 70),
            sample(.muscleMass, 66), sample(.boneMass, 3.95),
        ]))
        XCTAssertEqual(split.parts.map(\.label), ["Fat", "Muscle", "Bone"])
    }

    /// The latest reading wins — a scale reports every morning and the card is
    /// about today.
    func testTheLatestReadingIsTheOneUsed() throws {
        let split = try XCTUnwrap(BodyCompositionSplit.from(samples: [
            sample(.bodyMass, 120, daysAgo: 30), sample(.bodyMass, 100, daysAgo: 0),
            sample(.bodyFatPercentage, 25, daysAgo: 0),
        ]))
        XCTAssertEqual(split.total, 100, accuracy: 0.001)
    }
}
