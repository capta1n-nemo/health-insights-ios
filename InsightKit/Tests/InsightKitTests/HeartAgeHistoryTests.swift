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
