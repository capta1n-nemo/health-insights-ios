import XCTest
@testable import InsightKit

private let deepNow = Date(timeIntervalSince1970: 1_700_000_000)
private let deepCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Midday, `n` days before the reference.
private func deepDay(_ n: Int) -> Date {
    deepCalendar.startOfDay(for: deepNow.addingTimeInterval(-Double(n) * 86_400))
        .addingTimeInterval(12 * 3600)
}

final class LagFinderTests: XCTestCase {

    /// `values[0]` is the oldest day.
    private func series(_ metric: MetricType, _ values: [Double]) -> NormalizedSeries {
        let mean = Baseline.mean(values)!
        let sd = Baseline.standardDeviation(values)!
        let points = values.enumerated().map { index, value in
            NormalizedPoint(date: deepDay(values.count - 1 - index),
                            z: (value - mean) / sd, raw: value)
        }
        return NormalizedSeries(metric: metric, higherIsBetter: true,
                                points: points, baseline: mean)
    }

    /// The question the Today tab structurally cannot ask: does this signal come
    /// *first*? Built so the score on each day follows the metric from the day
    /// before — lag-1 correlates perfectly, same-day does not.
    func testASignalThatLeadsTheScoreIsFound() {
        let n = 30
        let values = (0..<n).map { Double(($0 * 7) % 11) }
        let scores = (1..<n).map { i in
            ScorePoint(date: deepDay(n - 1 - i), score: 40 + 3 * values[i - 1],
                       confidence: .high, contributorCount: 4)
        }
        let leads = LagFinder.relationships(between: [series(.sleepDurationHours, values)],
                                            and: scores, calendar: deepCalendar)
        XCTAssertEqual(leads.count, 1)
        XCTAssertEqual(leads.first?.metric, .sleepDurationHours)
        XCTAssertEqual(leads.first?.lag, 1)
        XCTAssertEqual(leads.first?.r ?? 0, 1, accuracy: 0.01)
    }

    /// A lag that merely echoes a same-day relationship is not a finding, so it
    /// must clear same-day by a real margin before it is reported.
    func testALagThatOnlyEchoesSameDayIsNotReported() {
        let n = 30
        let values = (0..<n).map { Double(($0 * 7) % 11) }
        // Score tracks the *same* day, so lag-1 can only be weaker.
        let scores = (0..<n).map { i in
            ScorePoint(date: deepDay(n - 1 - i), score: 40 + 3 * values[i],
                       confidence: .high, contributorCount: 4)
        }
        let leads = LagFinder.relationships(between: [series(.sleepDurationHours, values)],
                                            and: scores, calendar: deepCalendar)
        XCTAssertTrue(leads.isEmpty)
    }

    func testTooFewPairedDaysReportNothing() {
        let values = (0..<8).map { Double(($0 * 7) % 11) }
        let scores = (0..<8).map { i in
            ScorePoint(date: deepDay(7 - i), score: 40 + Double(i),
                       confidence: .high, contributorCount: 4)
        }
        XCTAssertTrue(LagFinder.relationships(between: [series(.sleepDurationHours, values)],
                                              and: scores, calendar: deepCalendar).isEmpty)
    }

    func testNoLagIsEverReportedBeyondTheTestedRange() {
        let n = 40
        let values = (0..<n).map { Double(($0 * 7) % 11) }
        let scores = (0..<n).map { i in
            ScorePoint(date: deepDay(n - 1 - i), score: 40 + values[i] * 2,
                       confidence: .high, contributorCount: 4)
        }
        let leads = LagFinder.relationships(between: [series(.sleepDurationHours, values)],
                                            and: scores, calendar: deepCalendar)
        XCTAssertTrue(leads.allSatisfy { $0.lag >= 1 && $0.lag <= LagFinder.maximumLag })
    }
}

final class PeriodContrastTests: XCTestCase {

    private func daily(_ metric: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: deepDay(values.count - 1 - index), source: .oura)
        }
    }

    private func contribution(_ metric: MetricType, higherIsBetter: Bool?) -> MetricContribution {
        .init(metric: metric, higherIsBetter: higherIsBetter, weight: 1, detail: "")
    }

    /// A z-score cannot see this: its baseline drifts along with the change, so
    /// each individual day looks unremarkable while the level has moved.
    func testAShiftBetweenPeriodsIsReported() throws {
        // 28 older days around 60, then 28 recent days around 54.
        let values = (0..<28).map { 60 + Double($0 % 3) - 1 }
            + (0..<28).map { 54 + Double($0 % 3) - 1 }
        let changes = PeriodContrast.changes(
            for: [contribution(.restingHeartRate, higherIsBetter: false)],
            samples: daily(.restingHeartRate, values),
            now: deepNow, calendar: deepCalendar)

        XCTAssertEqual(changes.count, 1)
        let change = try XCTUnwrap(changes.first)
        XCTAssertEqual(change.delta, -6, accuracy: 0.5)
        XCTAssertEqual(change.isImprovement, true, "resting heart rate falling is good news")
    }

    func testAChangeSmallerThanTheUsualWanderIsSuppressed() {
        // Noisy signal, tiny shift: not a change, just this fortnight.
        let values = (0..<28).map { 60 + Double(($0 * 7) % 11) - 5 }
            + (0..<28).map { 60.3 + Double(($0 * 7) % 11) - 5 }
        let changes = PeriodContrast.changes(
            for: [contribution(.restingHeartRate, higherIsBetter: false)],
            samples: daily(.restingHeartRate, values),
            now: deepNow, calendar: deepCalendar)
        XCTAssertTrue(changes.isEmpty)
    }

    func testTooLittleHistoryReportsNothing() {
        let changes = PeriodContrast.changes(
            for: [contribution(.restingHeartRate, higherIsBetter: false)],
            samples: daily(.restingHeartRate, [60, 61, 59, 55]),
            now: deepNow, calendar: deepCalendar)
        XCTAssertTrue(changes.isEmpty)
    }

    /// Where neither direction is better, no verdict is offered.
    func testANeutralMetricGetsNoImprovementVerdict() {
        let values = (0..<28).map { 0.0 + Double($0 % 3) * 0.05 }
            + (0..<28).map { 0.6 + Double($0 % 3) * 0.05 }
        let changes = PeriodContrast.changes(
            for: [contribution(.skinTemperatureDeviation, higherIsBetter: nil)],
            samples: daily(.skinTemperatureDeviation, values),
            now: deepNow, calendar: deepCalendar)
        XCTAssertEqual(changes.count, 1, "the shift itself must still be reported")
        XCTAssertNil(changes.first?.isImprovement)
    }
}

final class ScoreTrendTests: XCTestCase {

    func testRecoversAKnownSlopeAndItsScatter() throws {
        // Exactly +1 a day = +7 a week, with no scatter.
        let points = (0..<20).map { i in
            ScorePoint(date: deepDay(19 - i), score: 40 + Double(i),
                       confidence: .high, contributorCount: 4)
        }
        let trend = try XCTUnwrap(points.trend)
        XCTAssertEqual(trend.slopePerWeek, 7, accuracy: 1e-6)
        XCTAssertEqual(trend.residualSD, 0, accuracy: 1e-6)
        XCTAssertEqual(trend.value(at: deepDay(19)), 40, accuracy: 1e-6)
    }

    /// A slope small against the scatter is not a direction, and saying it is
    /// would be the same overclaim the bare trend number used to make.
    func testASlopeLostInTheScatterIsNotCalledMeaningful() throws {
        let noisy = (0..<20).map { i in
            ScorePoint(date: deepDay(19 - i),
                       score: 60 + Double((i * 7) % 13) - 6 + Double(i) * 0.02,
                       confidence: .high, contributorCount: 4)
        }
        let trend = try XCTUnwrap(noisy.trend)
        XCTAssertFalse(trend.isMeaningful)
    }

    func testTooFewPointsHaveNoTrend() {
        let few = (0..<5).map { i in
            ScorePoint(date: deepDay(4 - i), score: 50 + Double(i),
                       confidence: .high, contributorCount: 3)
        }
        XCTAssertNil(few.trend)
    }
}

final class TrendInsightContributorsTests: XCTestCase {

    private func profile() -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: deepNow.addingTimeInterval(-40 * 365.25 * 86_400).timeIntervalSince1970,
                    recordedAt: deepNow))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: deepNow))
        return p
    }

    private func samples() -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for i in 0..<20 {
            let date = deepDay(19 - i)
            out.append(.init(type: .vo2Max, value: 44 + Double(i % 3), start: date, source: .appleHealth))
            out.append(.init(type: .restingHeartRate, value: 55 + Double(i % 3), start: date, source: .appleHealth))
            out.append(.init(type: .heartRateVariabilitySDNN, value: 50 + Double(i % 3), start: date, source: .appleHealth))
            out.append(.init(type: .respiratoryRate, value: 14 + Double(i % 3) * 0.3, start: date, source: .appleHealth))
        }
        return out
    }

    /// Trend-tab models used to report no contributors at all, so their detail
    /// charts fell back to the declared candidate list — right lines, but no
    /// honest weights beside them.
    func testHeartHealthReportsTheComponentsItWeighted() {
        let result = HeartHealthInsight().evaluate(samples: samples(), profile: profile(), now: deepNow)
        let charted = Set(result.contributors.map(\.metric))
        XCTAssertTrue(charted.contains(.vo2Max))
        XCTAssertTrue(charted.contains(.restingHeartRate))
        XCTAssertEqual(result.contributors.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
    }

    /// It must chart the HRV flavour the score actually read, not a guess.
    func testHeartHealthChartsTheHRVFlavourItActuallyUsed() {
        let result = HeartHealthInsight().evaluate(samples: samples(), profile: profile(), now: deepNow)
        let hrv = result.contributors.map(\.metric).filter {
            $0 == .heartRateVariabilitySDNN || $0 == .heartRateVariabilityRMSSD
        }
        XCTAssertEqual(hrv, [.heartRateVariabilitySDNN],
                       "only SDNN was present, so SDNN is what should be charted")
    }

    func testCardioFitnessAndRestingHeartRateTrendBothReportTheirMetric() {
        XCTAssertEqual(CardioFitnessInsight()
            .evaluate(samples: samples(), profile: profile(), now: deepNow)
            .contributors.map(\.metric), [.vo2Max])
        XCTAssertEqual(RestingHeartRateTrendInsight()
            .evaluate(samples: samples(), profile: profile(), now: deepNow)
            .contributors.map(\.metric), [.restingHeartRate])
    }
}
