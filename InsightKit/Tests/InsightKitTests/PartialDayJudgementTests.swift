import XCTest
@testable import InsightKit

/// **The mid-day cumulative-metric rule, and the proof that moving it did not
/// change it.**
///
/// The rule: a cumulative metric read at 9 am is a fraction of a day being
/// judged against whole ones. The reader's own card export is the evidence —
/// "Steps: 224 · 1.5 SD below your normal", exported in the morning.
///
/// It used to be expressed by handing `VitalReader` a filtered copy of the
/// sample set, and that copy cost four fifths of the whole insight pass
/// (backlog `D57`): a new array is not the array the evaluation memo was opened
/// for, so every read behind it missed the memo and recomputed from scratch.
/// The rule now rides on `VitalReader.reading(excludingPartialDay:)`, which
/// drops the partial day from the *buckets* instead.
///
/// **These tests exist because that is an equivalence claim, and an equivalence
/// claim is worth exactly as much as its test.**
final class PartialDayJudgementTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let source = MetricSource(id: "test_watch", displayName: "Test Watch")

    /// A full day's worth of steps on each of `days` complete days, then a
    /// deliberately small partial total for today.
    private func stepHistory(days: Int, endingAt now: Date,
                             fullDay: Double, partialToday: Double) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let today = calendar.startOfDay(for: now)
        for back in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let at = day.addingTimeInterval(12 * 3600)
            // Deliberately not a flat line: a history with zero spread gives a
            // `nil` z-score, and an equivalence test whose interesting fields
            // are all `nil` on both sides proves nothing.
            let wobble = Double((back % 7) - 3) * 400
            out.append(HealthMetricSample(type: .stepCount, value: fullDay + wobble,
                                          start: at, end: at, source: source))
        }
        let thisMorning = today.addingTimeInterval(9 * 3600)
        out.append(HealthMetricSample(type: .stepCount, value: partialToday,
                                      start: thisMorning, end: thisMorning, source: source))
        return out
    }

    /// The rule itself: this morning's partial total is not what gets judged.
    func testAPartialDayIsNotTheDayThatGetsRead() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 9))!
        let samples = stepHistory(days: 30, endingAt: now, fullDay: 9_000, partialToday: 224)

        let unguarded = try XCTUnwrap(
            VitalReader.reading(.stepCount, from: samples, now: now, gap: .none, calendar: calendar))
        XCTAssertEqual(unguarded.value, 224, accuracy: 0.001,
                       "without the guard the morning's partial total is what is read — the defect")

        let guarded = try XCTUnwrap(
            VitalReader.reading(.stepCount, from: samples, now: now, gap: .none,
                                excludingPartialDay: true, calendar: calendar))
        // Yesterday's total, wobble included — see `stepHistory`.
        XCTAssertEqual(guarded.value, 8_200, accuracy: 0.001,
                       "the last complete day is what a cumulative metric is judged on")
        XCTAssertGreaterThan(guarded.value, 1_000,
                             "and it is a whole day's total, not a morning's")
    }

    /// The equivalence the optimisation rests on: dropping today's *samples*
    /// and dropping today's *bucket* must produce the same reading.
    func testTheFlagMatchesFilteringTheSamples() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 9))!
        let samples = stepHistory(days: 30, endingAt: now, fullDay: 9_000, partialToday: 224)
        let startOfToday = calendar.startOfDay(for: now)
        let filtered = samples.filter { $0.start < startOfToday }

        let byFilter = try XCTUnwrap(
            VitalReader.reading(.stepCount, from: filtered, now: now, gap: .none, calendar: calendar))
        let byFlag = try XCTUnwrap(
            VitalReader.reading(.stepCount, from: samples, now: now, gap: .none,
                                excludingPartialDay: true, calendar: calendar))

        XCTAssertEqual(byFlag.value, byFilter.value, accuracy: 0.001)
        XCTAssertEqual(byFlag.date, byFilter.date)
        // Optional equality rather than `?? .nan` — `nan != nan`, so the
        // sentinel version failed on the case where both sides agree there is
        // no answer, which is the one thing it could never be allowed to.
        XCTAssertEqual(byFlag.baseline, byFilter.baseline)
        XCTAssertEqual(byFlag.zScore, byFilter.zScore)
        XCTAssertNotNil(byFlag.zScore, "the fixture must produce a real z-score or this proves nothing")
        XCTAssertEqual(byFlag.history, byFilter.history)
        XCTAssertEqual(byFlag.sourceName, byFilter.sourceName)
        XCTAssertEqual(byFlag.isFresh, byFilter.isFresh)
    }

    /// The same equivalence **inside an evaluation memo**, which is the
    /// situation the optimisation is actually for — and the one where the two
    /// paths take genuinely different code: the flag hits the memo, the filtered
    /// array cannot.
    func testTheEquivalenceHoldsUnderTheEvaluationMemo() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 9))!
        let samples = stepHistory(days: 30, endingAt: now, fullDay: 9_000, partialToday: 224)
        let startOfToday = calendar.startOfDay(for: now)
        let filtered = samples.filter { $0.start < startOfToday }

        let byFilter = try XCTUnwrap(
            VitalReader.reading(.stepCount, from: filtered, now: now, gap: .none, calendar: calendar))
        let byFlag = try XCTUnwrap(MultiSource.withMemo(for: samples) {
            VitalReader.reading(.stepCount, from: samples, now: now, gap: .none,
                                excludingPartialDay: true, calendar: calendar)
        })
        XCTAssertEqual(byFlag.value, byFilter.value, accuracy: 0.001)
        XCTAssertEqual(byFlag.history, byFilter.history)
    }

    /// A point-in-time vital keeps today — a heart rate at 9 am is a whole
    /// measurement, not a fraction of one. The flag must be *off* for those, and
    /// `FitnessInsight` is what decides.
    func testOnlyCumulativeMetricsDropThePartialDay() {
        XCTAssertTrue(FitnessInsight.excludesPartialDay(.stepCount))
        XCTAssertTrue(FitnessInsight.excludesPartialDay(.activeEnergyBurned))
        XCTAssertFalse(FitnessInsight.excludesPartialDay(.restingHeartRate))
        XCTAssertFalse(FitnessInsight.excludesPartialDay(.heartRateRecovery))
    }

    /// A day with no complete history at all must still return nothing rather
    /// than inventing a reading out of the partial day it just dropped.
    func testTodayOnlyDataYieldsNoReadingRatherThanAPartialOne() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 9))!
        let thisMorning = calendar.startOfDay(for: now).addingTimeInterval(9 * 3600)
        let samples = [HealthMetricSample(type: .stepCount, value: 224,
                                          start: thisMorning, end: thisMorning, source: source)]
        XCTAssertNil(VitalReader.reading(.stepCount, from: samples, now: now, gap: .none,
                                         excludingPartialDay: true, calendar: calendar))
    }
}
