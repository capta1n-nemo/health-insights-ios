import XCTest
@testable import InsightKit

/// The reader's instruction, 2026-08-06: every derived insight becomes a data
/// source — trendable, and usable as an input elsewhere.
///
/// These pin the substrate. The rules that keep it *safe* to feed a score with
/// one of these — the dependency graph, the lag on a back edge, the loop gain —
/// are a separate suite, because nothing yet reads a derived series as an input
/// and a test asserting otherwise would be describing an intention.
final class DerivedSeriesTests: XCTestCase {

    private let now = TestClock.day(0)
    private let calendar = TestClock.utc

    // MARK: - Identity

    func testAnIDIsNamespacedByTheCardThatProducedIt() {
        let id = DerivedSeriesID(.fitness, "fitnessAge")
        XCTAssertEqual(id.rawValue, "fitness.fitnessAge")
        XCTAssertEqual(id.producedBy, .fitness,
                       "a reader has to be able to see which card owns a figure")
    }

    func testTwoCardsDerivingTheSameNameDoNotCollide() {
        XCTAssertNotEqual(DerivedSeriesID(.fitness, "age"),
                          DerivedSeriesID(.biologicalAge, "age"))
    }

    func testAnUnrecognisedIDReportsNoProducerRatherThanCrashing() {
        // A stored id from an older build, or a card that has since been
        // renamed. Returning nil is the honest handling.
        XCTAssertNil(DerivedSeriesID(rawValue: "somethingElse.age").producedBy)
    }

    // MARK: - The harvest, which is what makes the component tier free

    private func result(contributors: [MetricContribution],
                        outputs: [DerivedOutput] = []) -> InsightResult {
        InsightResult(id: .fitness, title: "Fitness", primaryValue: 40,
                      headline: "Fair", score: 60, confidence: .high,
                      explanation: "", drivers: [], unmetRequirements: [],
                      contributors: contributors, derivedOutputs: outputs)
    }

    func testEveryComponentSubScoreBecomesASeriesWithNoModelWork() {
        // The whole reason "do the sub-scores too" is affordable: these have
        // been on MetricContribution since the score decomposition, and this
        // simply stops throwing them away.
        let harvested = DerivedHarvest.series(from: result(contributors: [
            .init(metric: .vo2Max, higherIsBetter: true, weight: 0.6,
                  detail: "40", componentScore: 55, value: 40, baseline: 42, z: -0.4),
            .init(metric: .stepCount, higherIsBetter: true, weight: 0.4,
                  detail: "9000", componentScore: 70, value: 9000, baseline: 8000, z: 1.2)
        ]))
        let ids = Set(harvested.map { $0.0.id })
        XCTAssertTrue(ids.contains(DerivedHarvest.componentScoreID(.fitness, .vo2Max)))
        XCTAssertTrue(ids.contains(DerivedHarvest.componentDepartureID(.fitness, .vo2Max)))
        XCTAssertTrue(ids.contains(DerivedHarvest.componentScoreID(.fitness, .stepCount)))
        XCTAssertEqual(harvested.count, 4)
    }

    func testAContributorWithNoSubScoreYieldsNoScoreSeries() {
        // `nil` means "this model has not been taught to say", which is a
        // different and more honest statement than a zero — so it must not
        // become a series of zeroes.
        let harvested = DerivedHarvest.series(from: result(contributors: [
            .init(metric: .vo2Max, higherIsBetter: true, weight: 1, detail: "40")
        ]))
        XCTAssertTrue(harvested.isEmpty)
    }

    func testAnUnscoredContributorStillYieldsItsSeries() {
        // Weight 0 means charted and narrated but not averaged in. Its
        // sub-score is still a real statement about the reader, and dropping it
        // would make the Data tab disagree with the card above it.
        let harvested = DerivedHarvest.series(from: result(contributors: [
            .init(metric: .dayStrain, higherIsBetter: nil, weight: 0,
                  detail: "12", componentScore: 44, value: 12, baseline: 11, z: 0.3)
        ]))
        XCTAssertEqual(harvested.count, 2)
    }

    func testAComponentScoreIsOrientedAndADepartureIsNot() throws {
        let harvested = DerivedHarvest.series(from: result(contributors: [
            .init(metric: .restingHeartRate, higherIsBetter: false, weight: 1,
                  detail: "58", componentScore: 80, value: 58, baseline: 60, z: -0.5)
        ]))
        let score = try XCTUnwrap(harvested.first { $0.0.kind == .componentScore })
        let departure = try XCTUnwrap(harvested.first { $0.0.kind == .componentDeparture })
        XCTAssertEqual(score.0.higherIsBetter, true,
                       "100 is good whatever the underlying metric does")
        XCTAssertNil(departure.0.higherIsBetter,
                     "a departure is signed as the metric is measured, not as good or bad — resting heart rate falling is a negative z and a welcome one")
    }

    func testAModelOutputCarriesItsOwnNameAndUnit() throws {
        let harvested = DerivedHarvest.series(from: result(
            contributors: [],
            outputs: [.init(key: "fitnessAge", displayName: "Fitness age",
                            unit: "years", value: 67, higherIsBetter: false,
                            precision: 0)]))
        let (spec, value) = try XCTUnwrap(harvested.first)
        XCTAssertEqual(spec.id.rawValue, "fitness.fitnessAge")
        XCTAssertEqual(spec.kind, .modelOutput)
        XCTAssertEqual(value, 67)
        XCTAssertEqual(spec.string(67), "67 years")
    }

    // MARK: - The store

    func testRecordingTheSameDayTwiceIsIdempotent() {
        // A replay runs on every launch. If a second run doubled the series,
        // every figure would drift a little further from the truth each time
        // the app opened — the worst kind of bug, because nothing looks wrong.
        var store = DerivedSeriesStore()
        let evaluated = result(contributors: [], outputs: [
            .init(key: "fitnessAge", displayName: "Fitness age", unit: "years",
                  value: 67, precision: 0)])
        store.record(evaluated, on: now, calendar: calendar)
        store.record(evaluated, on: now, calendar: calendar)
        XCTAssertEqual(store.pointCount, 1)
    }

    func testALaterRunForTheSameDayWins() {
        var store = DerivedSeriesStore()
        for value in [67.0, 66.0] {
            store.record(result(contributors: [], outputs: [
                .init(key: "fitnessAge", displayName: "Fitness age", unit: "years",
                      value: value, precision: 0)]), on: now, calendar: calendar)
        }
        XCTAssertEqual(store.latest(DerivedSeriesID(.fitness, "fitnessAge"))?.value, 66)
    }

    func testASeriesReadsOldestFirst() {
        var store = DerivedSeriesStore()
        for day in [3, 1, 2] {
            store.record(result(contributors: [], outputs: [
                .init(key: "fitnessAge", displayName: "Fitness age", unit: "years",
                      value: Double(70 - day), precision: 0)]),
                         on: TestClock.day(day), calendar: calendar)
        }
        let series = store.series(DerivedSeriesID(.fitness, "fitnessAge"))
        XCTAssertEqual(series.map(\.day), series.map(\.day).sorted())
        XCTAssertEqual(series.count, 3)
    }

    func testANonFiniteValueIsRefusedRatherThanStored() {
        // A ratio with a zero denominator reaches here as `inf`, and one `inf`
        // in a series makes every chart of it unreadable and every mean of it
        // meaningless.
        var store = DerivedSeriesStore()
        store.record(result(contributors: [], outputs: [
            .init(key: "ratio", displayName: "Ratio", value: .infinity)]),
                     on: now, calendar: calendar)
        store.record(result(contributors: [], outputs: [
            .init(key: "nan", displayName: "NaN", value: .nan)]),
                     on: now, calendar: calendar)
        XCTAssertEqual(store.pointCount, 0)
    }

    /// ⚠️ **The read a score input must use.** Reaching for `latest` would let
    /// a figure from last week silently stand in for the day being scored.
    func testAValueIsReadableForASpecificDayAndAbsentForOthers() {
        var store = DerivedSeriesStore()
        store.record(result(contributors: [], outputs: [
            .init(key: "fitnessAge", displayName: "Fitness age", unit: "years",
                  value: 67, precision: 0)]), on: TestClock.day(3), calendar: calendar)
        let id = DerivedSeriesID(.fitness, "fitnessAge")
        XCTAssertEqual(store.value(id, on: TestClock.day(3), calendar: calendar), 67)
        XCTAssertNil(store.value(id, on: TestClock.day(2), calendar: calendar),
                     "a day the app computed nothing has no value, and must not borrow one")
    }

    func testANeverProducedSeriesIsAbsentRatherThanEmpty() {
        let store = DerivedSeriesStore()
        XCTAssertNil(store.spec(DerivedSeriesID(.fitness, "fitnessAge")),
                     "'never computed' and 'computed and got nothing' are different claims")
    }

    // MARK: - The backfill

    private func profile(age: Double = 40) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-age * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        return p
    }

    func testTheBackfillProducesHistoryRatherThanASinglePoint() throws {
        // The reader chose backfill over collect-from-today precisely so a
        // derived series is trendable on day one instead of in three months.
        let samples = ContributorsFixture.fullCoverage(days: 40, now: now)
        let store = DerivedBackfill.fill(
            models: [FitnessInsight()], samples: samples,
            profile: ContributorsFixture.profile(now: now),
            days: 30, calendar: calendar, now: now)
        let age = store.series(DerivedSeriesID(.fitness, "fitnessAge"))
        XCTAssertGreaterThan(age.count, 20,
                             "thirty replayed days on a fully covered fixture should yield a real series")
        XCTAssertTrue(age.allSatisfy { $0.value > 0 })
    }

    func testTheBackfillIsIdempotent() {
        let samples = ContributorsFixture.fullCoverage(days: 40, now: now)
        let once = DerivedBackfill.fill(models: [FitnessInsight()], samples: samples,
                                        profile: ContributorsFixture.profile(now: now),
                                        days: 30, calendar: calendar, now: now)
        var twice = once
        twice.merge(DerivedBackfill.fill(models: [FitnessInsight()], samples: samples,
                                         profile: ContributorsFixture.profile(now: now),
                                         days: 30, calendar: calendar, now: now))
        XCTAssertEqual(once.pointCount, twice.pointCount)
    }

    func testTheBackfillHarvestsComponentSeriesTooAndTheyAreDated() throws {
        let samples = ContributorsFixture.fullCoverage(days: 40, now: now)
        let store = DerivedBackfill.fill(models: [FitnessInsight()], samples: samples,
                                         profile: ContributorsFixture.profile(now: now),
                                         days: 30, calendar: calendar, now: now)
        let components = store.series(ofKind: .componentScore)
        XCTAssertFalse(components.isEmpty,
                       "the component tier is the reader's 'do the sub-scores too' and it comes free from MetricContribution")
        let first = try XCTUnwrap(components.first)
        XCTAssertGreaterThan(store.series(first.id).count, 1)
    }

    /// The observer must see every evaluated day, not only the ones whose score
    /// survived `ScoreHistory`'s own filters — a fitness age is a real figure on
    /// a day the score was suppressed for resting on one signal.
    func testTheReplayObserverSeesDaysTheScoreChartDrops() {
        let samples = ContributorsFixture.fullCoverage(days: 40, now: now)
        var observed = 0
        let points = ScoreHistory.replay(
            model: FitnessInsight(), samples: samples,
            profile: ContributorsFixture.profile(now: now),
            days: 30, calendar: calendar, now: now,
            observing: { _, _ in observed += 1 })
        XCTAssertGreaterThanOrEqual(observed, points.count)
    }

    // MARK: - Fitness, the first producer

    func testFitnessNamesTheFiguresItUsedToThrowAway() throws {
        let samples = ContributorsFixture.fullCoverage(days: 130, now: now)
        let result = FitnessInsight().evaluate(
            samples: samples, profile: ContributorsFixture.profile(now: now), now: now)
        let keys = Set(result.derivedOutputs.map(\.key))
        XCTAssertTrue(keys.contains("fitnessAge"),
                      "recomputed every launch and remembered nowhere until today")
        XCTAssertTrue(keys.contains("moderateEquivalentMinutes"))
    }

    func testAppendingDriverLinesKeepsTheDerivedOutputs() {
        // `ReadinessInsight.evaluate` dropped `invitesInput` through exactly
        // this shape on 2026-08-05, and this copy was dropping `subheadline`.
        let base = InsightResult(
            id: .fitness, title: "Fitness", primaryValue: 40, headline: "Fair",
            subheadline: "second figure", score: 60, confidence: .high,
            explanation: "", drivers: [], unmetRequirements: [],
            derivedOutputs: [.init(key: "fitnessAge", displayName: "Fitness age",
                                   unit: "years", value: 67, precision: 0)])
        let appended = base.appending(driverLines: [InsightDriver(text: "extra")])
        XCTAssertEqual(appended.derivedOutputs.count, 1)
        XCTAssertEqual(appended.subheadline, "second figure")
    }
}
