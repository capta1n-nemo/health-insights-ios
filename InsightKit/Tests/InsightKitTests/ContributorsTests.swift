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
            .skinTemperature: 33.8, .skinTemperatureDeviation: 0.1,
            // The vitals promoted out of the raw layer. Present here so
            // "full coverage" stays literally true — without them Vitals Check
            // correctly charts only what it measured, and the equality below
            // would be asserting something the fixture never supplied.
            .bloodGlucose: 5.2, .peripheralPerfusionIndex: 2.0,
            .atrialFibrillationBurden: 0.5, .heartRateRecovery: 25,
            .walkingSteadiness: 85, .walkingAsymmetry: 2
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
        let result = ReadinessInsight().evaluate(samples: fullCoverage(),
                                                  profile: profile, now: contributorNow)
        // Every spec except the ones deliberately standing down. The fixture
        // supplies data for all of them, so a spec that is scanned must chart.
        let expected = VitalSignsCheck.specs.filter { $0.supersededBy == nil }.map(\.metric)
        // A superset now: Readiness charts its own scored components as well as
        // every vital the scan covered. The rule the merge had to preserve is
        // that nothing scanned goes unplotted.
        XCTAssertTrue(Set(result.contributors.map(\.metric)).isSuperset(of: Set(expected)),
                      "a scanned vital stopped being charted")
    }

    /// The other half of the rule above: a derived metric standing down is not
    /// the same as the app forgetting to chart it. Absolute skin temperature is
    /// an affine shift of the deviation it was reconstructed from, so charting
    /// both would draw one signal as two lines and score it twice.
    func testADerivedVitalStandsDownWhenItsSourceSignalSpoke() {
        let result = ReadinessInsight().evaluate(samples: fullCoverage(),
                                                  profile: profile, now: contributorNow)
        let charted = Set(result.contributors.map(\.metric))
        XCTAssertTrue(charted.contains(.skinTemperatureDeviation))
        XCTAssertFalse(charted.contains(.skinTemperature))
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

    /// The drivers card leads with departures on **every** card, not just the
    /// one that prompted the change. An insight that leaves its lines
    /// unclassified renders as a flat wall again, which is the regression this
    /// catches.
    func testEveryInsightClassifiesItsDriverLines() {
        let samples = fullCoverage()
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: contributorNow)
            guard !result.driverLines.isEmpty else { continue }
            XCTAssertTrue(result.driverLines.allSatisfy { $0.isNotable != nil },
                          "\(model.id) still reports unclassified driver lines")
        }
    }

    /// Substance Impact isn't an engine model but feeds the same card.
    func testSubstanceImpactClassifiesItsDriverLines() {
        let events = (0..<6).map {
            SubstanceEvent(substance: .alcohol,
                           timestamp: contributorDay($0 * 2).addingTimeInterval(-3600),
                           units: 2, note: nil)
        }
        let result = SubstanceResponseAnalyzer.insightResult(
            events: events, samples: fullCoverage(), now: contributorNow)
        XCTAssertFalse(result.driverLines.isEmpty)
        XCTAssertTrue(result.driverLines.allSatisfy { $0.isNotable != nil })
    }

    /// Every insight should also chart what it read, not fall back to the
    /// declared candidate list.
    func testEveryInsightWithDataReportsItsContributors() {
        let samples = fullCoverage()
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: contributorNow)
            guard result.primaryValue != nil else { continue }
            XCTAssertFalse(result.contributors.isEmpty,
                           "\(model.id) reports no contributors, so its chart guesses")
        }
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

/// Identity on a chart is hue alone now. Dash used to carry the overflow, which
/// was measurably safe and practically wrong — a dashed line reads as an
/// estimate or a gap, not as a different signal.
///
/// So the safety property moved: instead of "every metric is globally unique",
/// it is "every chart resolves its own hues, and no chart shows more series than
/// hue can carry". These tests pin both halves.
final class MetricColourSlotTests: XCTestCase {

    func testStyleIndicesAreContiguousFromZero() {
        // Contiguity is what makes the first eight metrics claim eight distinct
        // hues before any preference has to be overridden.
        let indices = MetricType.allCases.map(\.chartStyleIndex).sorted()
        XCTAssertEqual(indices, Array(0..<MetricType.allCases.count))
    }

    func testEverySlotIsWithinThePalette() {
        for metric in MetricType.allCases {
            XCTAssertTrue((0..<MetricPalette.hueCount).contains(metric.colourSlot),
                          "\(metric) has slot \(metric.colourSlot), outside the palette")
        }
    }

    /// The property the chart depends on: any set up to the palette size comes
    /// back with every member on its own hue. This is what replaces the old
    /// global-uniqueness guarantee, and it holds for *any* combination rather
    /// than only the ones an insight happens to declare today.
    func testAnySetUpToThePaletteSizeGetsDistinctHues() {
        let all = MetricType.allCases
        // Every contiguous window, plus a stride that mixes distant metrics —
        // the shapes a real contributor list takes.
        for size in 1...MetricPalette.hueCount {
            for start in 0..<(all.count - size) {
                let set = Array(all[start..<(start + size)])
                let slots = MetricPalette.slots(for: set)
                XCTAssertEqual(Set(slots.values).count, size,
                               "\(set.map(\.rawValue)) collided")
            }
            let spread = Array(stride(from: 0, to: all.count, by: 3).prefix(size).map { all[$0] })
            XCTAssertEqual(Set(MetricPalette.slots(for: spread).values).count, spread.count)
        }
    }

    /// A metric keeps its own hue wherever that hue is free, so the same signal
    /// usually looks the same from one card to the next.
    func testAMetricKeepsItsPreferredHueWhenNothingContendsForIt() {
        let slots = MetricPalette.slots(for: [.heartRate, .oxygenSaturation])
        XCTAssertEqual(slots[.heartRate], MetricType.heartRate.colourSlot)
        XCTAssertEqual(slots[.oxygenSaturation], MetricType.oxygenSaturation.colourSlot)
    }

    /// Two metrics preferring the same hue is the case global assignment could
    /// not solve once dash was gone. The later one must move rather than clash.
    func testAContendedHueIsResolvedRatherThanShared() {
        let contending = MetricType.allCases.filter { $0.chartStyleIndex % MetricPalette.hueCount == 0 }
        XCTAssertGreaterThan(contending.count, 1, "fixture assumes a genuine contention exists")
        let pair = Array(contending.prefix(2))
        let slots = MetricPalette.slots(for: pair)
        XCTAssertEqual(Set(slots.values).count, 2)
        XCTAssertEqual(slots[pair[0]], pair[0].colourSlot, "the first claimant keeps its own")
    }

    /// Vitals Check scans far more signals than hue can separate. That is
    /// exactly why the chart draws only the ones away from baseline by default —
    /// but the hues it does hand out must still all differ.
    func testACrowdedChartStillSpendsEveryHueBeforeRepeating() {
        let metrics = ReadinessInsight().candidateMetrics
        XCTAssertGreaterThan(metrics.count, MetricPalette.hueCount)
        let slots = MetricPalette.slots(for: metrics)
        XCTAssertEqual(Set(slots.values).count, MetricPalette.hueCount)
    }

    /// Past the palette the function must still answer for every metric handed
    /// to it rather than dropping one on the floor.
    func testEveryMetricGetsAnAnswerEvenPastThePalette() {
        let slots = MetricPalette.slots(for: MetricType.allCases)
        XCTAssertEqual(slots.count, MetricType.allCases.count)
    }
}

final class VitalEventTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func rawEvent(_ identifier: String, value: Double, hoursAgo: Double) -> RawMetricSample {
        RawMetricSample(identifier: identifier, displayName: identifier,
                        value: value, unit: "",
                        start: Date(timeIntervalSince1970: 1_700_000_000 - hoursAgo * 3600),
                        source: .appleHealthDevice("Apple Watch"))
    }

    /// A category sample whose value is `notApplicable` (0) and which has a
    /// duration is stored by the importer as **minutes**, not the enum. So a
    /// zero is not "no event" and a positive number is not necessarily a
    /// category value — the sample's existence is the signal.
    func testAnEventIsReadFromItsExistenceNotItsValue() {
        let raw = [rawEvent("HKCategoryTypeIdentifierIrregularHeartRhythmEvent", value: 0, hoursAgo: 3),
                   rawEvent("HKCategoryTypeIdentifierHighHeartRateEvent", value: 17, hoursAgo: 5)]
        let events = VitalEventReader.events(from: raw)
        XCTAssertEqual(events.map(\.kind), [.irregularRhythm, .highHeartRate])
    }

    func testUnrelatedRawSamplesAreIgnored() {
        let raw = [rawEvent("HKQuantityTypeIdentifierDietaryCaffeine", value: 95, hoursAgo: 1),
                   rawEvent("HKCategoryTypeIdentifierToothbrushingEvent", value: 2, hoursAgo: 1)]
        XCTAssertTrue(VitalEventReader.events(from: raw).isEmpty)
    }

    func testOnlyRecentEventsDescribeToday() {
        let events = [VitalEvent(kind: .irregularRhythm, date: now.addingTimeInterval(-3 * 3600),
                                 sourceName: "Apple Watch"),
                      VitalEvent(kind: .highHeartRate, date: now.addingTimeInterval(-20 * 86_400),
                                 sourceName: "Apple Watch")]
        XCTAssertEqual(events.recent(within: VitalSignsCheck.eventWindow, of: now).map(\.kind),
                       [.irregularRhythm])
    }

    /// The whole reason events exist as their own input: Apple has already made
    /// the judgement, so it flags with no baseline and no z-score.
    func testAnIrregularRhythmFlagsOnItsOwn() {
        let event = VitalEvent(kind: .irregularRhythm, date: now.addingTimeInterval(-3600),
                               sourceName: "Apple Watch")
        let result = ReadinessInsight().evaluate(samples: [], events: [event],
                                                  profile: UserHealthProfile(), now: now)
        XCTAssertEqual(result.headline, "Irregular rhythm")
        XCTAssertLessThan(result.score ?? 100, 50)
        XCTAssertTrue(result.explanation.contains("irregular rhythm"))
    }

    /// A watch notification must outrank a day of ordinary numbers.
    func testAnEventDominatesAnOtherwiseNormalDay() {
        let samples = (0..<14).map { i in
            HealthMetricSample(type: .restingHeartRate, value: 55 + Double(i % 3) - 1,
                               start: now.addingTimeInterval(-Double(13 - i) * 86_400),
                               source: .appleHealth)
        }
        let clean = ReadinessInsight().evaluate(samples: samples, events: [],
                                                 profile: UserHealthProfile(), now: now)
        let flagged = ReadinessInsight().evaluate(
            samples: samples,
            events: [VitalEvent(kind: .irregularRhythm, date: now.addingTimeInterval(-3600),
                                sourceName: "Apple Watch")],
            profile: UserHealthProfile(), now: now)
        XCTAssertGreaterThan(clean.score ?? 0, flagged.score ?? 100)
    }

    /// Three notifications of the same thing is one finding.
    func testRepeatedEventsOfOneKindAreCountedOnce() {
        let dates = [1.0, 4, 9].map { now.addingTimeInterval(-$0 * 3600) }
        let many = dates.map { VitalEvent(kind: .irregularRhythm, date: $0, sourceName: "Apple Watch") }
        let one = [VitalEvent(kind: .irregularRhythm, date: dates[0], sourceName: "Apple Watch")]
        XCTAssertEqual(VitalSignsCheck.score(readings: [], events: many, coverage: 1),
                       VitalSignsCheck.score(readings: [], events: one, coverage: 1))
    }

    /// Models that don't read events must be untouched by their presence.
    func testInsightsThatIgnoreEventsAreUnaffected() {
        let samples = (0..<14).map { i in
            HealthMetricSample(type: .restingHeartRate, value: 55 + Double(i % 3) - 1,
                               start: now.addingTimeInterval(-Double(13 - i) * 86_400),
                               source: .oura)
        }
        let event = VitalEvent(kind: .irregularRhythm, date: now, sourceName: "Apple Watch")
        let without = HeartHealthInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: now)
        let with = HeartHealthInsight().evaluate(
            samples: samples, events: [event], profile: UserHealthProfile(), now: now)
        XCTAssertEqual(without.headline, with.headline)
        XCTAssertEqual(without.explanation, with.explanation)
    }
}
