import XCTest
@testable import InsightKit

/// The seed exists so a Mac session can look at a chart. It is only worth having
/// if what it produces could have arrived through the real ingest path and is
/// the same every time — otherwise a screenshot proves nothing and cannot be
/// compared against the next one.
final class SyntheticSeedTests: XCTestCase {

    private let cal = TestClock.utc

    func testItGeneratesSomethingForEveryDayAsked() {
        let samples = SyntheticSeed.samples(days: 30, endingOn: TestClock.now, calendar: cal)
        let days = Set(samples.map { cal.startOfDay(for: $0.start) })
        XCTAssertEqual(days.count, 30, "a day with no samples is a gap in every chart")
    }

    func testZeroDaysIsEmptyRatherThanACrash() {
        XCTAssertTrue(SyntheticSeed.samples(days: 0, endingOn: TestClock.now, calendar: cal).isEmpty)
        XCTAssertTrue(SyntheticSeed.samples(days: -5, endingOn: TestClock.now, calendar: cal).isEmpty)
    }

    /// **The property that makes a screenshot comparable.** A fixture that
    /// changes between runs turns every visual diff into noise.
    func testItIsDeterministic() {
        let a = SyntheticSeed.samples(days: 20, endingOn: TestClock.now, calendar: cal)
        let b = SyntheticSeed.samples(days: 20, endingOn: TestClock.now, calendar: cal)
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.type, y.type)
            XCTAssertEqual(x.value, y.value, accuracy: 1e-9)
            XCTAssertEqual(x.start, y.start)
        }
    }

    /// **Everything it emits must be something the app would have accepted.**
    ///
    /// `ShortcutIngest` drops a value outside the metric's `plausibleRange`, so
    /// a generator that ignored those bounds would quietly produce a series the
    /// real ingest path would have refused — a fixture proving something about
    /// a route nobody uses. Same trap as a test suite that only passes in UTC.
    func testEveryValueIsInsideTheMetricsOwnPlausibleRange() {
        for sample in SyntheticSeed.samples(days: 120, endingOn: TestClock.now, calendar: cal) {
            if let range = sample.type.plausibleRange {
                XCTAssertTrue(range.contains(sample.value),
                              "\(sample.type) generated \(sample.value), outside its own plausible range — the real ingest would drop it")
            }
            if sample.type.requiresPositiveValue {
                XCTAssertGreaterThan(sample.value, 0, "\(sample.type) must be positive")
            }
        }
    }

    /// The shapes the charts exist to show. A flat series would satisfy every
    /// test above and still make every chart a straight line.
    func testTheSeriesActuallyMove() throws {
        let samples = SyntheticSeed.samples(days: 90, endingOn: TestClock.now, calendar: cal)

        let weights = samples.filter { $0.type == .bodyMass }.sorted { $0.start < $1.start }
        let firstWeight = try XCTUnwrap(weights.first?.value)
        let lastWeight = try XCTUnwrap(weights.last?.value)
        XCTAssertLessThan(lastWeight, firstWeight, "weight should trend down over the window")

        let steps = samples.filter { $0.type == .stepCount }.map(\.value)
        XCTAssertGreaterThan(try XCTUnwrap(steps.max()) - (try XCTUnwrap(steps.min())), 2000,
                             "steps need a real spread or the activity charts draw a flat line")
    }

    /// A cuff reading is an event the reader performs. Daily blood pressure
    /// would misrepresent how that data arrives and would defeat the "0 of 5
    /// readings in the last 30 days" gate the Blood Pressure card shows.
    func testBloodPressureIsOccasionalRatherThanDaily() {
        let samples = SyntheticSeed.samples(days: 70, endingOn: TestClock.now, calendar: cal)
        let bpDays = Set(samples.filter { $0.type == .bloodPressureSystolic }
            .map { cal.startOfDay(for: $0.start) }).count
        XCTAssertGreaterThan(bpDays, 10, "too few to ground an estimate")
        XCTAssertLessThan(bpDays, 35, "a cuff reading every day is not what this data looks like")
    }

    // MARK: - The cycle log

    /// The seeded log must survive `CycleModel`'s own arithmetic: the right
    /// number of cycles, every length inside the conventional normal range, and
    /// **a real spread** — a metronome fixture would leave the phase model's
    /// half-the-spread ± resting entirely on its floor.
    func testTheSeededCycleLogIsPlausibleUnderTheAppsOwnRules() throws {
        let start = cal.startOfDay(for: TestClock.now.addingTimeInterval(-8 * 86_400))
        let days = SyntheticSeed.cycleDays(cycles: 4, mostRecentPeriodStart: start, calendar: cal)
        let summary = CycleModel.summarise(days: days, now: TestClock.now, calendar: cal)

        XCTAssertEqual(summary.cycles.count, 4)
        XCTAssertEqual(summary.lengths.count, 3, "the running cycle has no length")
        for length in summary.lengths {
            XCTAssertTrue(SyntheticSeed.plausibleCycleLengths.contains(length),
                          "\(length)-day cycle is outside the range the generator promises")
        }
        for length in summary.periodLengths {
            XCTAssertTrue(SyntheticSeed.plausiblePeriodLengths.contains(length), "\(length)")
        }
        XCTAssertGreaterThan(try XCTUnwrap(summary.spread), 0,
                             "a metronome fixture exercises none of the ± arithmetic")
        XCTAssertEqual(summary.currentDay, 9)
    }

    /// Four cycles clears the three the phase model needs, so a seeded simulator
    /// shows the tab's *populated* state rather than its refusal — which is the
    /// entire reason this generator exists.
    func testFourSeededCyclesAreEnoughForTheModelToSpeak() throws {
        let start = cal.startOfDay(for: TestClock.now.addingTimeInterval(-8 * 86_400))
        let days = SyntheticSeed.cycleDays(cycles: 4, mostRecentPeriodStart: start, calendar: cal)
        let summary = CycleModel.summarise(days: days, now: TestClock.now, calendar: cal)

        let prediction = try XCTUnwrap(
            CyclePhaseModel.forecast(summary, now: TestClock.now, calendar: cal).prediction)
        XCTAssertEqual(prediction.basedOnCycles, 3)
        XCTAssertNotNil(CyclePhaseModel.phase(on: TestClock.now, summary: summary,
                                              now: TestClock.now, calendar: cal))
        XCTAssertNotNil(summary.lengthRange, "the range sentence needs three lengths")
    }

    /// And the vitals go biphasic when a log is supplied — so the phase-aware
    /// shifts card has something measured to show on a simulator, and shows a
    /// figure that is **not** the literature prior.
    func testTheVitalsAreBiphasicOnlyWhenACycleLogIsSeededAlongsideThem() throws {
        let start = cal.startOfDay(for: TestClock.now.addingTimeInterval(-8 * 86_400))
        let log = SyntheticSeed.cycleDays(cycles: 6, mostRecentPeriodStart: start, calendar: cal)
        let summary = CycleModel.summarise(days: log, now: TestClock.now, calendar: cal)

        let flat = SyntheticSeed.samples(days: 180, endingOn: TestClock.now, calendar: cal)
        let biphasic = SyntheticSeed.samples(days: 180, endingOn: TestClock.now,
                                             cycleDays: log, calendar: cal)

        let withoutLog = PhaseAwareBaseline.profile(metrics: [.skinTemperatureDeviation],
                                                    samples: flat, summary: summary,
                                                    now: TestClock.now, calendar: cal)
        let withLog = PhaseAwareBaseline.profile(metrics: [.skinTemperatureDeviation,
                                                          .restingHeartRate],
                                                 samples: biphasic, summary: summary,
                                                 now: TestClock.now, calendar: cal)

        let flatShift = try XCTUnwrap(withoutLog.expectedShift(metric: .skinTemperatureDeviation,
                                                               phase: .luteal))
        XCTAssertEqual(flatShift.delta, 0, accuracy: 0.1,
                       "the plain seed must stay cycle-agnostic for every other caller")

        let shift = try XCTUnwrap(withLog.expectedShift(metric: .skinTemperatureDeviation,
                                                        phase: .luteal))
        XCTAssertTrue(shift.isMeasured)
        XCTAssertEqual(shift.delta, 0.35, accuracy: 0.08)

        // Distinguishable from the textbook figure, or a screenshot cannot tell
        // a measured card from a priored one.
        let prior = try XCTUnwrap(PhaseAwareBaseline.literaturePriors[.restingHeartRate]?[.luteal])
        let rhr = try XCTUnwrap(withLog.expectedShift(metric: .restingHeartRate, phase: .luteal))
        XCTAssertNotEqual(rhr.delta, prior.delta, accuracy: 0.3)
    }

    /// Determinism, for the cycle log too — the same reason as the vitals.
    func testTheSeededCycleLogIsDeterministic() {
        let start = cal.startOfDay(for: TestClock.now)
        let a = SyntheticSeed.cycleDays(cycles: 5, mostRecentPeriodStart: start, calendar: cal)
        let b = SyntheticSeed.cycleDays(cycles: 5, mostRecentPeriodStart: start, calendar: cal)
        XCTAssertEqual(a, b)
        XCTAssertTrue(SyntheticSeed.cycleDays(cycles: 0, mostRecentPeriodStart: start,
                                              calendar: cal).isEmpty)
    }
}
