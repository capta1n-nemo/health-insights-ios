import XCTest
@testable import InsightKit

private func day(_ i: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400) }

final class TemperatureReconstructorTests: XCTestCase {
    func testUsesDefaultBaselineWhenNoAbsolutes() {
        let devs = (0..<3).map { i in
            HealthMetricSample(type: .skinTemperatureDeviation, value: 0.2,
                               start: day(i), source: .oura)
        }
        let out = TemperatureReconstructor.reconstruct(from: devs)
        XCTAssertEqual(out.count, 3)
        // Skin, not core. Writing these as `.bodyTemperature` is what put a
        // 35.4 °C reconstruction under a 35.5 °C core floor.
        XCTAssertTrue(out.allSatisfy { $0.type == .skinTemperature })
        XCTAssertEqual(out.first!.value, TemperatureReconstructor.defaultBaselineCelsius + 0.2, accuracy: 1e-9)
    }

    func testLearnsBaselineFromAbsolutes() {
        var samples: [HealthMetricSample] = [
            HealthMetricSample(type: .skinTemperature, value: 33.8, start: day(0), source: .whoop),
            HealthMetricSample(type: .skinTemperature, value: 33.8, start: day(1), source: .whoop)
        ]
        samples.append(HealthMetricSample(type: .skinTemperatureDeviation, value: -0.3, start: day(2), source: .oura))
        let recon = TemperatureReconstructor.reconstruct(from: samples)
        XCTAssertEqual(recon.first!.value, 33.5, accuracy: 1e-9)   // 33.8 − 0.3
    }

    /// A thermometer reading says nothing about where this person's *skin* sits.
    /// Learning the skin baseline from core absolutes shifted every night of
    /// ring data about a degree and a half too warm.
    func testCoreReadingsDoNotSetTheSkinBaseline() {
        let samples: [HealthMetricSample] = [
            HealthMetricSample(type: .bodyTemperature, value: 36.6, start: day(0), source: .manual),
            HealthMetricSample(type: .skinTemperatureDeviation, value: -0.3, start: day(1), source: .oura)
        ]
        let recon = TemperatureReconstructor.reconstruct(from: samples)
        XCTAssertEqual(recon.first!.value,
                       TemperatureReconstructor.defaultBaselineCelsius - 0.3, accuracy: 1e-9)
    }
}

final class ReadinessTests: XCTestCase {
    private func hrvSamples(_ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { HealthMetricSample(type: .heartRateVariabilityRMSSD, value: $0.1, start: day($0.0), source: .oura) }
    }
    private func rhrSamples(_ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { HealthMetricSample(type: .restingHeartRate, value: $0.1, start: day($0.0), source: .oura) }
    }

    func testRecoveredDayScoresHigherThanStrainedDay() {
        // High HRV + low RHR + good sleep = recovered.
        var good = hrvSamples([55, 58, 54, 57, 56, 80])          // last well above baseline
        good += rhrSamples([56, 55, 57, 56, 55, 48])             // last below baseline
        good.append(HealthMetricSample(type: .sleepDurationHours, value: 8, start: day(5), source: .oura))
        // `now` is explicit because readiness only counts fresh readings now —
        // a fixture pinned to a 2023 epoch is otherwise entirely stale.
        let goodOut = ReadinessScore.evaluate(samples: good, now: day(5))!

        var bad = hrvSamples([55, 58, 54, 57, 56, 30])           // crashed HRV
        bad += rhrSamples([56, 55, 57, 56, 55, 74])              // spiked RHR
        bad.append(HealthMetricSample(type: .sleepDurationHours, value: 4.5, start: day(5), source: .oura))
        let badOut = ReadinessScore.evaluate(samples: bad, now: day(5))!

        XCTAssertGreaterThan(goodOut.score, badOut.score)
        XCTAssertGreaterThan(goodOut.score, 70)
        XCTAssertLessThan(badOut.score, 55)
    }

    func testReturnsNilWithoutData() {
        XCTAssertNil(ReadinessScore.evaluate(samples: []))
    }
}

final class SubstanceAnalyzerTests: XCTestCase {
    func testDetectsElevatedRestingHRAfterUse() {
        // 5 clean nights ~54 bpm, then 3 nights each ~11h after an alcohol event ~65 bpm.
        var samples: [HealthMetricSample] = []
        let clean = [54.0, 55, 56, 53, 55]
        for (i, v) in clean.enumerated() {
            samples.append(HealthMetricSample(type: .restingHeartRate, value: v,
                                              start: day(i).addingTimeInterval(7 * 3600), source: .oura))
        }
        var events: [SubstanceEvent] = []
        let affected = [64.0, 66, 65]
        for (j, v) in affected.enumerated() {
            let eveningBefore = day(10 + j).addingTimeInterval(20 * 3600)   // 8pm
            events.append(SubstanceEvent(substance: .alcohol, timestamp: eveningBefore))
            // sample next morning ~11h later
            samples.append(HealthMetricSample(type: .restingHeartRate, value: v,
                                              start: day(11 + j).addingTimeInterval(7 * 3600), source: .oura))
        }

        let analysis = SubstanceResponseAnalyzer.analyze(events: events, samples: samples)
        let rhr = analysis.effects.first { $0.metric == .restingHeartRate }
        XCTAssertNotNil(rhr)
        XCTAssertTrue(rhr!.isAdverse)
        XCTAssertEqual(rhr!.deltaAbsolute, 10, accuracy: 2.0)   // ~65 − ~55
        XCTAssertEqual(rhr!.affectedNights, 3)
    }

    func testEmptyEventsGivesLogPrompt() {
        let result = SubstanceResponseAnalyzer.insightResult(events: [], samples: [])
        XCTAssertEqual(result.id, .substanceImpact)
        XCTAssertNil(result.primaryValue)
        XCTAssertEqual(result.headline, "Log to see effects")
    }

    func testRecentLoadReflectsStimulantWeighting() {
        let now = day(30)
        let heavy = (0..<6).map { SubstanceEvent(substance: .stimulant, timestamp: now.addingTimeInterval(-Double($0) * 86_400)) }
        let light = (0..<6).map { SubstanceEvent(substance: .caffeine, timestamp: now.addingTimeInterval(-Double($0) * 86_400)) }
        let heavyLoad = SubstanceResponseAnalyzer.analyze(events: heavy, samples: [], now: now).recentLoad
        let lightLoad = SubstanceResponseAnalyzer.analyze(events: light, samples: [], now: now).recentLoad
        XCTAssertGreaterThan(heavyLoad, lightLoad)
    }
}

final class BloodPressureBivariateTests: XCTestCase {
    func testBivariateFitRecoversKnownPlane() {
        // x1 and x2 must be non-collinear or the normal equations are singular.
        let x1 = [50.0, 55, 60, 52, 58, 54]
        let x2 = [60.0, 58, 52, 55, 50, 57]
        let y = zip(x1, x2).map { 100 + 0.5 * $0 - 0.3 * $1 }
        let fit = BloodPressureEstimator.bivariateFit(x1: x1, x2: x2, y: y)!
        XCTAssertEqual(fit.b1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(fit.b2, -0.3, accuracy: 1e-6)
        XCTAssertEqual(fit.a, 100, accuracy: 1e-4)
        XCTAssertEqual(fit.residualSD, 0, accuracy: 1e-6)
    }

    func testEstimatorUsesHRVWhenAvailable() {
        // systolic = 90 + 0.6*hr − 0.2*hrv exactly, 6 points with HRV.
        let hrs = [52.0, 58, 61, 55, 60, 54]
        let hrvs = [70.0, 55, 48, 66, 52, 60]   // not a linear function of hrs
        let points = zip(hrs, hrvs).enumerated().map { idx, pair -> BloodPressureEstimator.CalibrationPoint in
            let (hr, hrv) = pair
            let sys = 90 + 0.6 * hr - 0.2 * hrv
            let dia = 60 + 0.3 * hr - 0.1 * hrv
            return .init(restingHR: hr, hrv: hrv, systolic: sys, diastolic: dia, date: day(idx))
        }
        let est = BloodPressureEstimator.estimate(currentRestingHR: 57, currentHRV: 58, calibration: points)!
        XCTAssertEqual(est.systolic, 90 + 0.6 * 57 - 0.2 * 58, accuracy: 0.5)
        XCTAssertLessThan(est.systolicUncertainty, 1.0)   // near-perfect fit
    }
}
