import XCTest
@testable import InsightKit

/// The Heart & Fitness Age card showed two numbers and a dial — where you are,
/// and nothing about which way it's going.
final class HeartAgeHistoryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func profile(age: Double) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-age * 365.25 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        return p
    }

    /// Replay is by truncation, not by passing a past `now` — `analyse` reads
    /// `latestValue`, so the only way to reconstruct a past day is to hand it
    /// only the samples that existed by then. If that contract broke, every
    /// point would carry today's VO₂max and the line would be flat.
    func testReplayReconstructsAFallingFitnessAge() throws {
        // A year of steadily improving VO₂max.
        let samples = (0..<52).map { week in
            HealthMetricSample(type: .vo2Max, value: 34 + Double(week) * 0.25,
                               start: now.addingTimeInterval(-Double(51 - week) * 7 * 86_400),
                               source: .appleHealth)
        }
        let points = HeartAgeHistory.replay(samples: samples, profile: profile(age: 50),
                                            days: 364, now: now)
        XCTAssertGreaterThan(points.count, 40)

        let first = try XCTUnwrap(points.first?.fitness)
        let last = try XCTUnwrap(points.last?.fitness)
        XCTAssertLessThan(last, first, "VO₂max rose all year, so fitness age must fall")
    }

    func testNoRelevantSamplesGivesNoHistory() {
        let samples = [HealthMetricSample(type: .stepCount, value: 8000,
                                          start: now, source: .appleHealth)]
        XCTAssertTrue(HeartAgeHistory.replay(samples: samples, profile: profile(age: 50),
                                             days: 364, now: now).isEmpty)
    }

    /// The pace is what the card reports, and it has to be measured against the
    /// one year per year everybody gets — a bare slope reads as good news at 0.9
    /// when it is merely not-quite-losing.
    func testPaceIsMeasuredInYearsPerYear() throws {
        let points = (0..<9).map { quarter -> AgePoint in
            let years = Double(quarter) * 0.25
            return AgePoint(date: now.addingTimeInterval((years - 2) * 365.25 * 86_400),
                            chronological: 48 + years,
                            heart: 50 + years * 2, fitness: nil)
        }
        let pace = try XCTUnwrap(points.yearsPerYear)
        XCTAssertEqual(pace, 2.0, accuracy: 0.02,
                       "two years of heart age per year of calendar")
    }

    func testTooFewPointsHaveNoPace() {
        let points = [AgePoint(date: now, chronological: 50, heart: 52, fitness: nil)]
        XCTAssertNil(points.yearsPerYear)
    }

    /// Falls back to fitness age where the risk equations can't run — without a
    /// blood pressure there is no heart age, and the card would otherwise report
    /// no pace at all for anyone who hasn't logged a cuff reading.
    func testPaceFallsBackToFitnessAge() throws {
        let points = (0..<9).map { quarter -> AgePoint in
            let years = Double(quarter) * 0.25
            return AgePoint(date: now.addingTimeInterval((years - 2) * 365.25 * 86_400),
                            chronological: 48 + years,
                            heart: nil, fitness: 46 + years * 0.5)
        }
        XCTAssertEqual(try XCTUnwrap(points.yearsPerYear), 0.5, accuracy: 0.02)
    }
}

/// **Backlog D22 — the chart and the comparison section disagreed about how many
/// ages exist.**
///
/// `AgePoint` held exactly two optional fields while the section beside it listed
/// four estimates. So the app's own biological age and the reader's ring's
/// vascular age could be *compared* today and never *drawn over time* — and for
/// the biological age that is the wrong half to lose, because
/// `BiologicalAgeModel`'s own documentation says the absolute number is soft to
/// about ±10 years and **the direction it moves is the part that survives**.
final class AgeHistorySeriesTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func profile(age: Double) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-age * 365.25 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        return p
    }

    /// The vendor's own number, replayed. It was already read by `analyse` — the
    /// analysis has carried `vascularAgeUsed` since it shipped — and thrown away
    /// one line later because there was no field to put it in.
    func testTheVendorsVascularAgeIsCarriedThroughTheReplay() throws {
        let samples = (0..<52).map { week in
            HealthMetricSample(type: .vascularAge, value: 44,
                               start: now.addingTimeInterval(-Double(51 - week) * 7 * 86_400),
                               source: .oura)
        }
        let points = HeartAgeHistory.replay(samples: samples, profile: profile(age: 50),
                                            days: 364, calendar: utc, now: now)
        XCTAssertGreaterThan(points.count, 40)
        XCTAssertTrue(points.allSatisfy { $0.vascular == 44 })
    }

    /// ⚠️ **The guard that would have kept the two new series empty.** The replay
    /// skipped any day without a heart *or* fitness age, so a reader whose only
    /// age estimate is their ring's — no cuff reading, no outdoor runs — would
    /// have got a chart with nothing on it, from a change made to give them one.
    func testADayWithOnlyAVendorAgeIsKeptRatherThanSkipped() {
        let samples = (0..<20).map { day in
            HealthMetricSample(type: .vascularAge, value: 44,
                               start: now.addingTimeInterval(-Double(day) * 86_400),
                               source: .oura)
        }
        let points = HeartAgeHistory.replay(samples: samples, profile: profile(age: 50),
                                            days: 60, calendar: utc, now: now)
        XCTAssertFalse(points.isEmpty)
        XCTAssertTrue(points.allSatisfy { $0.heart == nil && $0.fitness == nil })
    }

    /// This app's own composite, over time. The markers are pinned to the norm
    /// for a 45-year-old, so the answer is a stable ~45 and the assertion is
    /// about the series existing at all rather than about its level.
    ///
    /// **Monthly, not weekly** — see `biologicalStrideDays`. Thirteen points
    /// over a year is the resolution the model's own 90-to-365-day windows
    /// support; the other thirty-nine would be restatements.
    func testTheAppsOwnBiologicalAgeIsReplayedAsASeries() throws {
        var samples: [HealthMetricSample] = []
        for metric in [MetricType.vo2Max, .heartRateVariabilityRMSSD,
                       .bloodPressureSystolic, .bodyFatPercentage] {
            guard let value = BiologicalAgeModel.expected(metric, age: 45, sex: .male)
            else { continue }
            samples += (0..<400).map { day in
                let date = now.addingTimeInterval(-Double(day) * 86_400)
                return HealthMetricSample(type: metric, value: value, start: date,
                                          end: date, source: .appleHealth)
            }
        }
        let points = HeartAgeHistory.replay(samples: samples, profile: profile(age: 45),
                                            days: 364, calendar: utc, now: now)
        let drawn = points.compactMap(\.biological)
        XCTAssertGreaterThanOrEqual(drawn.count, 10,
                                    "the biological age had no history to draw")
        XCTAssertLessThan(drawn.count, points.count,
                          "a weekly replay of a model with 90-to-365-day windows")
        XCTAssertEqual(try XCTUnwrap(drawn.last), 45, accuracy: 6)
        // The newest point carries one, so the chart's last value and the card's
        // own number describe the same day.
        XCTAssertNotNil(points.last?.biological)
    }

    /// **Never an average.** Four optional fields is four relayed answers, not a
    /// blend — the same rule `AgeComparison` rests on, one level down.
    func testTheLeadingAgeIsPickedAndNeverAveraged() {
        let point = AgePoint(date: now, chronological: 40, heart: 50, fitness: 30,
                             vascular: 60, biological: 20)
        XCTAssertEqual(point.leadingAge, 50)
        XCTAssertEqual(point.excessYears, 10)
    }

    /// And each of the two new fields can lead on its own, which is what lets the
    /// Biological age card report a pace at all.
    func testTheNewSeriesCanLeadWhenTheyAreAllThereIs() throws {
        let points = (0..<9).map { quarter -> AgePoint in
            let years = Double(quarter) * 0.25
            return AgePoint(date: now.addingTimeInterval((years - 2) * 365.25 * 86_400),
                            chronological: 48 + years, heart: nil, fitness: nil,
                            vascular: nil, biological: 46 + years * 1.5)
        }
        XCTAssertEqual(try XCTUnwrap(points.yearsPerYear), 1.5, accuracy: 0.02)

        let vendorOnly = points.map {
            AgePoint(date: $0.date, chronological: $0.chronological, heart: nil,
                     fitness: nil, vascular: $0.biological, biological: nil)
        }
        XCTAssertEqual(try XCTUnwrap(vendorOnly.yearsPerYear), 1.5, accuracy: 0.02)
    }
}
