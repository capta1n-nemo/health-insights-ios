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

    /// The shape of this user's real history: fat and lean back to 2020, then
    /// muscle and bone from the day the Body Smart arrived. Each day gets the
    /// finest split its own readings support, so the lean band subdivides
    /// visibly rather than the old data being fabricated or the new flattened.
    func testTheSplitSubdividesOnTheDayTheScaleStartedReportingMore() throws {
        let series = BodyCompositionSplit.series(samples: [
            sample(.bodyMass, 120, daysAgo: 30), sample(.bodyFatPercentage, 35, daysAgo: 30),
            sample(.bodyMass, 115, daysAgo: 10), sample(.bodyFatPercentage, 33, daysAgo: 10),
            sample(.leanBodyMass, 77, daysAgo: 10), sample(.muscleMass, 73, daysAgo: 10),
            sample(.boneMass, 4, daysAgo: 10),
        ], calendar: TestClock.utc)
        XCTAssertEqual(series.points[0].split.parts.map(\.label), ["Fat", "Lean"])
        XCTAssertEqual(series.points[1].split.parts.map(\.label), ["Fat", "Muscle", "Bone"])
        XCTAssertEqual(series.finerSplitBegins, series.points[1].date)
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
