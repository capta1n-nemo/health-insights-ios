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
