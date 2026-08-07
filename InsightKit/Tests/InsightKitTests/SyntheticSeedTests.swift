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

    // MARK: - Exhaustiveness

    /// **The rule the reader asked for, 2026-08-07.** *"each time we make a new
    /// feature, we should be updating the simulate data feature to support it…
    /// i see lots of data fields that have no data."*
    ///
    /// `MetricType.syntheticSeedPlan` makes that a compile error rather than a
    /// discovery — but only if `samples(days:)` actually honours it. This is the
    /// half a switch cannot hold: a plan that says `daily` must put readings on
    /// the chart.
    func testEveryMetricEitherHasSeededDataOrSaysWhyNot() {
        let samples = SyntheticSeed.samples(days: 120, endingOn: TestClock.now, calendar: cal)
        let present = Set(samples.map(\.type))
        for type in MetricType.allCases {
            switch type.syntheticSeedPlan {
            case .notSeeded(let reason):
                XCTAssertFalse(present.contains(type),
                               "\(type) is declared unseeded but the generator wrote it anyway")
                XCTAssertGreaterThan(reason.count, 30,
                                     "\(type) is unseeded with no usable reason — an empty chart with no explanation is the state this rule exists to stop")
            case .daily, .onWeekdays, .once:
                XCTAssertTrue(present.contains(type),
                              "\(type) has a seed plan but produced nothing — every value it generated was outside its own plausibleRange and got dropped")
            }
        }
    }

    /// A daily plan has to be *daily*, and a weekly one has to be sparse.
    /// Without this the difference between the two is a comment.
    func testTheCadenceOfAPlanIsWhatTheChartActuallyGets() {
        let days = 120
        let samples = SyntheticSeed.samples(days: days, endingOn: TestClock.now, calendar: cal)
        let byType = Dictionary(grouping: samples, by: \.type)
        for type in MetricType.allCases {
            let count = byType[type]?.count ?? 0
            switch type.syntheticSeedPlan {
            case .daily:
                XCTAssertEqual(count, days, "\(type) is declared daily")
            case .onWeekdays(let weekdays, _):
                let expected = Double(days) * Double(weekdays.count) / 7
                XCTAssertEqual(Double(count), expected, accuracy: 2,
                               "\(type) is declared on \(weekdays.count) weekday(s)")
            case .once:
                XCTAssertEqual(count, 1, "\(type) is a static attribute")
            case .notSeeded:
                XCTAssertEqual(count, 0)
            }
        }
    }

    /// **Adding a metric must not move any other series.** The generator used to
    /// draw every metric for a day from one stream in declaration order, so a new
    /// case shifted everything after it and quietly invalidated every screenshot
    /// taken before — which defeats the one property that makes this fixture
    /// worth having. Per-metric salts fix it; this holds them.
    func testEachMetricDrawsFromItsOwnStream() {
        let salts = MetricType.allCases.map(\.syntheticSeedSalt)
        XCTAssertEqual(Set(salts).count, MetricType.allCases.count,
                       "two metrics share a noise stream, so they will move together for no physiological reason")
        // Stable between processes, unlike `hashValue` — the property that makes
        // today's screenshot comparable with next week's.
        XCTAssertEqual(MetricType.bodyMass.syntheticSeedSalt,
                       MetricType.bodyMass.syntheticSeedSalt)
    }

    // MARK: - The seeded profile

    /// Several cards cannot produce a number from measurements alone, so a
    /// simulator with full vitals and an empty profile still shows them asking
    /// for details. `GroundingKind.syntheticSeedFact` is exhaustive; this checks
    /// what it produces is a profile the models can actually use.
    func testTheSeededProfileAnswersEveryGroundingKind() throws {
        let profile = SyntheticSeed.profile(asOf: TestClock.now)
        for kind in GroundingKind.allCases {
            switch kind.syntheticSeedFact(asOf: TestClock.now) {
            case .value:
                XCTAssertNotNil(profile.value(kind), "\(kind) is declared seeded but is not in the profile")
                XCTAssertTrue(try XCTUnwrap(profile.input(kind)).isFresh(asOf: TestClock.now),
                              "\(kind) is seeded stale, so the card will still prompt for it")
            case .notSeeded(let reason):
                XCTAssertNil(profile.value(kind))
                XCTAssertGreaterThan(reason.count, 30, "\(kind) is unseeded with no usable reason")
            }
        }
        let age = try XCTUnwrap(profile.age(asOf: TestClock.now))
        XCTAssertEqual(age, 41, accuracy: 0.1, "the risk models have age floors at 40")
        XCTAssertNotNil(profile.sex)
        XCTAssertNotNil(profile.weightGoal, "a weight rate has no meaning without a direction someone wanted")
    }

    /// **The card-level rule, asserted in both directions.**
    ///
    /// A card declared `scores` that stops scoring is a regression. A card
    /// declared `needsMore` that starts scoring is a *stale excuse* — and a stale
    /// excuse is worse than none, because it tells the next reader an empty card
    /// is expected when it no longer is.
    func testEveryCardEitherScoresOnASeededSimulatorOrSaysWhatItIsWaitingFor() throws {
        let samples = SyntheticSeed.samples(days: 120, endingOn: TestClock.now, calendar: cal)
        let profile = SyntheticSeed.profile(asOf: TestClock.now)
        let results = InsightEngine().models.map {
            $0.evaluate(samples: samples, profile: profile, now: TestClock.now)
        }
        for id in InsightID.allCases {
            let result = try XCTUnwrap(results.first { $0.id == id }, "\(id) is not registered")
            switch id.syntheticSeedExpectation {
            case .scores:
                XCTAssertNotNil(result.primaryValue,
                                "\(id) is declared to score on a seeded simulator and does not — \"\(result.headline)\". Either the seed is missing something it reads, or the card is broken, and an empty card on screen cannot tell those apart.")
            case .needsMore(let reason):
                XCTAssertNil(result.primaryValue,
                             "\(id) now scores on a seeded simulator, so its stated reason is stale: \(reason)")
                XCTAssertGreaterThan(reason.count, 40, "\(id) needs a usable reason")
            }
        }
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
