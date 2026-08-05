import XCTest
@testable import InsightKit

/// The radar's report on itself — backlog #36.
///
/// The refusal was right that an honest **sensitivity** figure is years away at
/// one symptom tag, and these tests exist partly to keep it that way: the
/// counters here are all descriptive, and none of them can become an accuracy
/// claim without someone adding a symptom log this reader does not have.
final class SymptomRadarScorecardTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// A steady record: nothing should flag.
    private func steady(days: Int = 60) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let jitter: [Double] = [0, 0.01, -0.01, 0.02, -0.02, 0.005, -0.005, 0.015]
        for day in 0..<days {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            let n = jitter[day % jitter.count]
            func add(_ type: MetricType, _ value: Double) {
                out.append(HealthMetricSample(type: type, value: value,
                                              start: date, end: date, source: .appleHealth))
            }
            add(.restingHeartRate, 58 * (1 + n))
            add(.heartRateVariabilityRMSSD, 45 * (1 - n))
            add(.respiratoryRate, 14 * (1 + n))
            add(.skinTemperatureDeviation, n)
        }
        return out
    }

    /// ⚠️ **The three counters were computed and discarded on every evaluation.**
    /// `flags` counts episodes, which is why no flag *rate* was printable — and a
    /// reader asking "how often does this cry wolf" is asking about days.
    func testTheDayCountersAreReportedAtAll() {
        let counters = SymptomRadarModel.dayCounters(samples: steady(), now: now,
                                                     calendar: utc)
        XCTAssertGreaterThan(counters.gradedDays, 0)
        XCTAssertGreaterThan(counters.windowDays, 0)
        XCTAssertNotNil(counters.flagRate)
        XCTAssertNotNil(counters.coverage)
    }

    /// **"It never flagged" and "it never had anything to look at" are opposite
    /// statements**, and a 0% would say the first while meaning the second.
    func testAnUngradeableRecordReportsNoRateRatherThanZero() {
        let counters = SymptomRadarModel.dayCounters(samples: [], now: now, calendar: utc)
        XCTAssertEqual(counters.gradedDays, 0)
        XCTAssertNil(counters.flagRate,
                     "a zero flag rate over zero judged days is a false statement")
    }

    /// Coverage is the number that makes a quiet card readable: green over 30%
    /// of the window means something very different from green over 95%.
    func testCoverageIsAgainstTheWholeWindowAndNotTheGradedDays() {
        let counters = SymptomRadarModel.dayCounters(samples: steady(days: 20), now: now,
                                                     calendar: utc)
        XCTAssertEqual(counters.windowDays, SymptomRadarModel.ledgerDays,
                       "the denominator is the window, not what happened to be recorded")
        XCTAssertLessThan(try XCTUnwrap(counters.coverage), 1.0)
    }

    /// The counters do not read the symptom log or the medication schedule, and
    /// that is why they get their own entry point rather than a `ledger` call
    /// with two empty arguments.
    func testTheCountersAgreeWithTheFullLedgerOnTheDaysItAlsoCounts() {
        let samples = steady()
        let counters = SymptomRadarModel.dayCounters(samples: samples, now: now,
                                                     calendar: utc)
        let timeline = SymptomRadarModel.timeline(samples: samples,
                                                  days: SymptomRadarModel.ledgerDays,
                                                  endingAt: now, calendar: utc)
        let full = SymptomRadarModel.ledger(timeline: timeline, symptoms: [],
                                            medication: nil, now: now, calendar: utc)
        XCTAssertEqual(counters.gradedDays, full.gradedDays)
        XCTAssertEqual(counters.flaggedDays, full.flaggedDays)
        XCTAssertEqual(counters.windowDays, full.windowDays)
    }
}
