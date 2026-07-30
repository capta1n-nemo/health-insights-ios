import XCTest
@testable import InsightKit

private let contributorNow = Date(timeIntervalSince1970: 1_700_000_000)
private func contributorDay(_ i: Int) -> Date {
    contributorNow.addingTimeInterval(-Double(i) * 86_400)
}

/// The guarantees that stop the detail screen's chart drifting away from the
/// maths it claims to be showing.
///
/// The old screen charted one metric per insight from a hand-written switch in
/// the app target. Readiness weighted six signals and the switch named HRV, so
/// the screen quietly showed 40% of the story. These tests exist so the same
/// thing can't happen again silently.
final class ContributorsTests: XCTestCase {

    /// A sample set covering every metric any insight reads, dense enough for
    /// the baseline-dependent components to fire.
    private func fullCoverage(days: Int = 20) -> [HealthMetricSample] {
        let defaults: [MetricType: Double] = [
            .heartRate: 68, .restingHeartRate: 58, .walkingHeartRateAverage: 95,
            .heartRateVariabilitySDNN: 52, .heartRateVariabilityRMSSD: 48,
            .vo2Max: 46, .vascularAge: 34, .respiratoryRate: 14,
            .oxygenSaturation: 97, .dayStrain: 12,
            .bloodPressureSystolic: 118, .bloodPressureDiastolic: 76,
            .bodyMass: 78, .bodyFatPercentage: 18, .leanBodyMass: 62,
            .muscleMass: 58, .boneMass: 3.2, .bodyWaterPercentage: 58,
            .height: 1.83, .stepCount: 9000, .activeEnergyBurned: 520,
            .sleepDurationHours: 7.4, .bodyTemperature: 36.6,
            .skinTemperatureDeviation: 0.1
        ]
        var out: [HealthMetricSample] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            for (metric, base) in defaults {
                // A little movement so standard deviations aren't zero.
                let jitter = Double((i * 7) % 5) * 0.01 * base
                out.append(.init(type: metric, value: base + jitter,
                                 start: contributorDay(i), source: .oura))
            }
        }
        return out
    }

    private var profile: UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth, value: contributorNow.addingTimeInterval(-35 * 365.25 * 86_400).timeIntervalSince1970, recordedAt: contributorNow))
        p.set(.init(kind: .biologicalSex, value: 1, recordedAt: contributorNow))
        return p
    }

    /// Every insight must say what it reads. There is no default implementation
    /// of `candidateMetrics`, so this can only fail by someone declaring an
    /// empty list on purpose.
    func testEveryRegisteredInsightDeclaresItsInputs() {
        for model in InsightEngine().models {
            XCTAssertFalse(model.candidateMetrics.isEmpty,
                           "\(model.id) declares no candidate metrics")
        }
    }

    /// The anti-drift check: a component added to a score without being tagged
    /// with its metric, or tagged with a metric the insight never declared,
    /// fails here.
    func testReportedContributorsAreAlwaysDeclaredInputs() {
        let samples = fullCoverage()
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: contributorNow)
            let declared = Set(model.candidateMetrics)
            for contributor in result.contributors {
                XCTAssertTrue(declared.contains(contributor.metric),
                              "\(model.id) reported \(contributor.metric) but never declared it")
            }
        }
    }

    /// Readiness weights six signals; the chart must receive all six, not the
    /// one the old screen picked.
    func testReadinessReportsEveryComponentItWeighted() {
        let result = ReadinessInsight().evaluate(samples: fullCoverage(),
                                                 profile: profile, now: contributorNow)
        let charted = Set(result.contributors.map(\.metric))
        for expected: MetricType in [.heartRateVariabilityRMSSD, .restingHeartRate,
                                     .sleepDurationHours, .skinTemperatureDeviation,
                                     .respiratoryRate, .oxygenSaturation] {
            XCTAssertTrue(charted.contains(expected), "readiness dropped \(expected)")
        }
    }

    /// The weights shown in the legend are the ones the score actually applied,
    /// after renormalising over the components that had data.
    func testReadinessWeightsAreRenormalisedAndSumToOne() {
        let result = ReadinessInsight().evaluate(samples: fullCoverage(),
                                                 profile: profile, now: contributorNow)
        let total = result.contributors.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(total, 1, accuracy: 1e-9)
    }

    func testAPartialReadinessStillRenormalisesToOne() {
        // Sleep and HRV only — the other four components never fire.
        var samples: [HealthMetricSample] = []
        for i in stride(from: 9, through: 0, by: -1) {
            samples.append(.init(type: .heartRateVariabilityRMSSD, value: 45 + Double(i),
                                 start: contributorDay(i), source: .oura))
            samples.append(.init(type: .sleepDurationHours, value: 7.2,
                                 start: contributorDay(i), source: .oura))
        }
        let result = ReadinessInsight().evaluate(samples: samples, profile: profile,
                                                 now: contributorNow)
        XCTAssertEqual(result.contributors.count, 2)
        XCTAssertEqual(result.contributors.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
    }

    func testVitalsCheckChartsEveryVitalItScanned() {
        let result = VitalSignsInsight().evaluate(samples: fullCoverage(),
                                                  profile: profile, now: contributorNow)
        XCTAssertEqual(Set(result.contributors.map(\.metric)),
                       Set(VitalSignsCheck.specs.map(\.metric)))
    }

    /// Respiratory rate and body temperature are a concern in *both* directions,
    /// so neither end is "better" — saying otherwise in a legend would be wrong.
    func testTwoSidedVitalsHaveNoBetterDirection() {
        for spec in VitalSignsCheck.specs {
            if spec.concernWhenHigh && spec.concernWhenLow {
                XCTAssertNil(spec.higherIsBetter, "\(spec.metric) claims a better direction")
            }
        }
        let byMetric = Dictionary(uniqueKeysWithValues: VitalSignsCheck.specs.map { ($0.metric, $0) })
        XCTAssertEqual(byMetric[.oxygenSaturation]?.higherIsBetter, true)
        XCTAssertEqual(byMetric[.restingHeartRate]?.higherIsBetter, false)
    }

    func testInfluenceOrderingPutsTheHeaviestSignalFirst() {
        let contributions: [MetricContribution] = [
            .init(metric: .oxygenSaturation, higherIsBetter: true, weight: 0.05, detail: ""),
            .init(metric: .heartRateVariabilityRMSSD, higherIsBetter: true, weight: 0.40, detail: ""),
            .init(metric: .restingHeartRate, higherIsBetter: false, weight: 0.25, detail: "")
        ]
        XCTAssertEqual(contributions.byInfluence.metrics,
                       [.heartRateVariabilityRMSSD, .restingHeartRate, .oxygenSaturation])
    }
}

/// The overlay chart reuses eight hues across twenty-four metrics. That is only
/// safe while no two metrics sharing a hue can appear on the same chart, and
/// what appears together is decided by each insight's `candidateMetrics` — not
/// by the colour table. So adding a metric to an insight can break this test
/// from a file that never mentions colour. That is deliberate.
final class MetricColourSlotTests: XCTestCase {

    func testNoInsightPutsTwoMetricsOfTheSameHueOnOneChart() {
        for model in InsightEngine().models {
            var bySlot: [Int: MetricType] = [:]
            for metric in model.candidateMetrics {
                let slot = metric.colourSlot
                if let clash = bySlot[slot] {
                    XCTFail("\(model.id) charts \(metric) and \(clash) in the same hue (slot \(slot))")
                }
                bySlot[slot] = metric
            }
        }
    }

    /// Substance impact isn't an engine model but drives the same chart.
    func testSubstanceImpactMetricsAlsoAvoidACollision() {
        var bySlot: [Int: MetricType] = [:]
        for metric in SubstanceResponseAnalyzer.comparedMetrics {
            let slot = metric.colourSlot
            XCTAssertNil(bySlot[slot],
                         "\(metric) collides with \(String(describing: bySlot[slot])) in slot \(slot)")
            bySlot[slot] = metric
        }
    }

    func testEverySlotIsWithinThePalette() {
        for metric in MetricType.allCases {
            XCTAssertTrue((0..<8).contains(metric.colourSlot),
                          "\(metric) has slot \(metric.colourSlot), outside the eight-hue palette")
        }
    }
}
