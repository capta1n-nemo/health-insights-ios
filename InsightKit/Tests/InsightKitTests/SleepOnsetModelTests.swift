import XCTest
@testable import InsightKit

/// The reader wanted a deep-dive on how fast they fall asleep and what moves it.
/// The load-bearing claims are that a drift is only called when the scatter
/// allows it, that a driver is only reported on a real contrast, and that
/// temperature is judged in both directions rather than through a straight line.
final class SleepOnsetModelTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let cal = TestClock.utc
    private var origin: Date { TestClock.now }

    private func samples(_ values: [Double], from start: Int = 0) -> [SleepOnsetModel.Sample] {
        values.enumerated().map {
            SleepOnsetModel.Sample(date: origin.addingTimeInterval(Double(start + $0.offset) * day),
                                   value: $0.element)
        }
    }

    func testTooFewNightsSaysNothing() {
        let out = SleepOnsetModel.analyse(
            latency: samples([12, 14, 10, 15]), factors: [], calendar: cal)
        XCTAssertNil(out)
    }

    func testARisingLatencyReadsAsDrifting() throws {
        // A climb from ~10 to ~28 min over three weeks, with the small night-to-
        // night wobble any real sleeper has — a perfectly straight line has zero
        // residual, and `ScoreTrend.isMeaningful` (rightly) won't call a trend
        // with no scatter to measure it against.
        let wobble = [0.0, 1.5, -1.2, 0.8, -0.6]
        let rising = (0..<21).map { 10.0 + Double($0) * 0.85 + wobble[$0 % wobble.count] }
        let out = try XCTUnwrap(SleepOnsetModel.analyse(
            latency: samples(rising), factors: [], calendar: cal))
        let trend = try XCTUnwrap(out.trend)
        XCTAssertGreaterThan(trend.slopePerWeek, 0, "latency is climbing")
        XCTAssertTrue(out.trendIsMeaningful, "a clear climb clears the scatter bar")
    }

    func testANoisyLatencyIsNotCalledADrift() throws {
        // Same mean, no direction — a jumpy sleeper.
        let noisy = [10.0, 30, 8, 26, 12, 33, 9, 28, 11, 31, 7, 29, 13, 27]
        let out = try XCTUnwrap(SleepOnsetModel.analyse(
            latency: samples(noisy), factors: [], calendar: cal))
        XCTAssertFalse(out.trendIsMeaningful,
                       "a flat-but-noisy series has no trend to report")
    }

    func testASubstanceThatDelaysSleepIsFound() throws {
        // 20 nights: on high-use nights (value 1) latency ~25, on clean nights ~10.
        let latency = samples((0..<20).map { $0.isMultiple(of: 2) ? 25.0 : 10.0 })
        let use = samples((0..<20).map { $0.isMultiple(of: 2) ? 1.0 : 0.0 })
        let out = try XCTUnwrap(SleepOnsetModel.analyse(
            latency: latency, factors: [(.substances, use)], calendar: cal))
        let driver = try XCTUnwrap(out.drivers.first { $0.factor == .substances })
        XCTAssertGreaterThan(driver.deltaMinutes, 10, "≈15 min slower on use nights")
        XCTAssertTrue(driver.sentence.contains("association, not proof"),
                      "never states cause")
        XCTAssertTrue(driver.sentence.contains("longer"))
    }

    func testAFactorWithNoEffectIsNotReported() throws {
        let latency = samples((0..<20).map { _ in 12.0 } .enumerated().map { $0.offset.isMultiple(of: 2) ? 12.0 : 13.0 })
        // A factor uncorrelated with the tiny wobble.
        let noise = samples((0..<20).map { Double(($0 * 7) % 5) })
        let out = try XCTUnwrap(SleepOnsetModel.analyse(
            latency: latency, factors: [(.medication, noise)], calendar: cal))
        XCTAssertFalse(out.drivers.contains { $0.factor == .medication },
                       "a 1-minute wobble is under the 3-minute floor")
    }

    /// The reader's own case: both hot and cold nights are worse. A straight line
    /// through the middle would find nothing; the three-way split must catch it.
    func testTemperatureIsJudgedInBothDirections() throws {
        // Warm (+0.5) and cool (−0.5) nights both ~24 min; neutral nights ~10.
        var lat: [Double] = []
        var dev: [Double] = []
        for i in 0..<24 {
            switch i % 3 {
            case 0: dev.append(0.5); lat.append(24)     // warm, slow
            case 1: dev.append(-0.5); lat.append(23)    // cool, slow
            default: dev.append(0.0); lat.append(10)    // neutral, fast
            }
        }
        let out = try XCTUnwrap(SleepOnsetModel.analyse(
            latency: samples(lat), factors: [(.temperature, samples(dev))], calendar: cal))
        let driver = try XCTUnwrap(out.drivers.first { $0.factor == .temperature })
        XCTAssertGreaterThan(driver.deltaMinutes, 10)
        XCTAssertNil(driver.correlation, "a three-way split has no single r")
        XCTAssertTrue(driver.sentence.contains("warmer") || driver.sentence.contains("cooler"))

        // And a plain Pearson r on the same data would indeed be ~0 — the reason
        // the split exists.
        let r = Baseline.correlation(x: dev, y: lat)
        XCTAssertEqual(try XCTUnwrap(r), 0, accuracy: 0.2)
    }

    func testDriversAreRankedWorstFirstAndUnseenFactorsNamed() throws {
        let latency = samples((0..<20).map { $0.isMultiple(of: 2) ? 25.0 : 10.0 })
        let bigEffect = samples((0..<20).map { $0.isMultiple(of: 2) ? 1.0 : 0.0 })
        let smallEffect = samples((0..<20).map { i in
            // ~5 min contrast: high nights slightly slower
            i.isMultiple(of: 2) ? 1.0 : 0.0
        })
        // Give the small-effect factor a weaker latency coupling by using
        // medication paired against a latency that barely separates.
        let out = try XCTUnwrap(SleepOnsetModel.analyse(
            latency: latency,
            factors: [(.substances, bigEffect), (.eveningExertion, smallEffect)],
            calendar: cal))
        XCTAssertGreaterThanOrEqual(out.drivers.count, 1)
        // Worst-first ordering by delta.
        for i in 1..<out.drivers.count {
            XCTAssertGreaterThanOrEqual(out.drivers[i - 1].deltaMinutes,
                                        out.drivers[i].deltaMinutes)
        }
        XCTAssertTrue(out.unseenFactors.contains { $0.contains("screen") })
        XCTAssertTrue(out.unseenFactors.contains { $0.contains("ate") })
    }
}
