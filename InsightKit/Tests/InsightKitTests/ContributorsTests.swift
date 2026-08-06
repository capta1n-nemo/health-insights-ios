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

    // **A season, not a fortnight.** "Full coverage" has to mean enough
        // *history* for every registered card, not just enough metrics: a card
        // whose whole point is a month against the months before it cannot
        // contribute to a 20-day fixture, and shortening its window to suit a
        // test would be the test dictating the model.
        private func fullCoverage(days: Int = 130) -> [HealthMetricSample] {
        ContributorsFixture.fullCoverage(days: days, now: contributorNow)
    }

    private var profile: UserHealthProfile { ContributorsFixture.profile(now: contributorNow) }

    /// Every insight must say what it reads. There is no default implementation
    /// of `candidateMetrics`, so this can only fail by someone declaring an
    /// empty list on purpose.
    func testEveryRegisteredInsightDeclaresItsInputs() {
        for model in InsightEngine().models {
            XCTAssertFalse(model.candidateMetrics.isEmpty,
                           "\(model.id) declares no candidate metrics")
        }
    }

    /// Which insights report what they weighed, and which one legitimately does
    /// not.
    ///
    /// This matters to the legend. `ChartedContributions.resolve` substitutes an
    /// insight's *declared* inputs when it reports nothing, and those stand-ins
    /// carry `weight: 0` and `higherIsBetter: nil` — values that are also real
    /// findings elsewhere (`dayStrain` is deliberately unscored; a temperature
    /// deviation deliberately has no good direction). Read as findings, a
    /// stand-in row announces itself as "tracked, not scored · neither direction
    /// is better", two claims no model made. `areReported` is what prevents
    /// that, and this is what stops a new insight silently joining the
    /// exception and losing its weights on the card.
    ///
    /// Nothing else in the suite pins it: every other check here quantifies over
    /// `result.contributors`, and an empty list satisfies all of them vacuously.
    func testOnlySubstanceImpactReportsNoContributorsUnderFullMetricCoverage() {
        let samples = fullCoverage()
        let silent = InsightEngine().models.filter {
            $0.evaluate(samples: samples, profile: profile, now: contributorNow)
                .contributors.isEmpty
        }.map(\.id)

        // Substance Impact reports one contributor per *measured effect of a
        // logged event*, and this fixture logs none — so it has genuinely
        // nothing to report rather than having forgotten to report it.
        // ⚠️ **Derived, and a SUBSET rather than an equality.** This was
        // `== [.substanceImpact]` and two new cards of exactly the same shape
        // broke it.
        //
        // The rule is one-directional and the earlier equality hid that: a card
        // reporting nothing under full coverage **must** be one whose input is
        // not in `samples` — but the converse is false. The symptom radar is
        // log-driven *and* reads vitals, so it reports plenty. Asserting
        // equality would demand that every log-driven card report nothing, which
        // is a different and untrue claim.
        let logDriven = Set(InsightEngine().models.filter { !$0.readsOnlySamples }.map(\.id))
        XCTAssertTrue(Set(silent).isSubset(of: logDriven),
                       "insights reporting no contributors: \(silent)")
    }

    // MARK: - The collapsed "How this is weighted" preview

    /// The preview line stands in for the bars while the section is closed, so
    /// for most readers it is the whole section. It claims a superlative, and a
    /// superlative can be false.
    func testThePreviewNeverClaimsALeaderThatIsTiedWithAnother() {
        let tied = [
            MetricContribution(metric: .restingHeartRate, higherIsBetter: false,
                               weight: 0.5, detail: ""),
            MetricContribution(metric: .sleepDurationHours, higherIsBetter: true,
                               weight: 0.5, detail: "")
        ]
        // `byInfluence` breaks ties by name, so the first here is not "the most".
        let preview = try? XCTUnwrap(tied.weightingPreview)
        XCTAssertEqual(preview?.contains("carries the most"), false, preview ?? "")
        XCTAssertEqual(preview?.contains("equally"), true, preview ?? "")

        let clear = [
            MetricContribution(metric: .restingHeartRate, higherIsBetter: false,
                               weight: 0.7, detail: ""),
            MetricContribution(metric: .sleepDurationHours, higherIsBetter: true,
                               weight: 0.3, detail: "")
        ]
        XCTAssertEqual(clear.weightingPreview,
                       "Resting Heart Rate carries the most, at 70% of 2 signals.")
    }

    /// Nothing weighted is not a 0% leader — the caller has a placeholder for
    /// that, and a cheerful sentence about a zero share is the failure worth
    /// designing out.
    func testThePreviewIsAbsentRatherThanZeroWhenNothingIsWeighted() {
        let unscored = [
            MetricContribution(metric: .dayStrain, higherIsBetter: nil,
                               weight: 0, detail: "14.2")
        ]
        XCTAssertNil(unscored.weightingPreview)
        XCTAssertTrue(unscored.weighted.isEmpty)
        XCTAssertNil([MetricContribution]().weightingPreview)
    }

    /// One weighted signal is the whole score, and saying "carries the most, of
    /// 1 signal" would be a comparison with nothing.
    func testASingleWeightedSignalIsDescribedAsTheWholeOfIt() {
        let only = [MetricContribution(metric: .vo2Max, higherIsBetter: true,
                                       weight: 1, detail: "")]
        XCTAssertEqual(only.weightingPreview,
                       "\(MetricType.vo2Max.displayName) is the whole of it, at 100%.")
        XCTAssertTrue(only.weightingPreview?.contains("100%") == true)
        XCTAssertFalse(only.weightingPreview?.contains("of 1 signals") == true)
    }

    /// Every card that *does* weight must produce a preview, or its section
    /// collapses to a blank line.
    func testEveryWeightedCardProducesAPreview() {
        let samples = fullCoverage()
        for model in InsightEngine().models {
            let contributors = model.evaluate(samples: samples, profile: profile,
                                              now: contributorNow).contributors
            if contributors.weighted.isEmpty {
                XCTAssertNil(contributors.weightingPreview, "\(model.id)")
            } else {
                XCTAssertNotNil(contributors.weightingPreview, "\(model.id)")
            }
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

    /// The converse of the check above, and the one that was missing.
    ///
    /// `testReportedContributorsAreAlwaysDeclaredInputs` catches a card charting
    /// something it never declared. Nothing caught the far commoner direction: a
    /// card **declaring** a metric and then never reporting it. The consequence
    /// is invisible rather than wrong — `resolvedContributions` substitutes the
    /// declared list only when a card reports *nothing*, so on a card that
    /// reports anything at all a declared-but-unreported input charts nowhere,
    /// links nowhere under "Full history", and appears in no legend.
    ///
    /// Four cards were doing it on 2026-08-01, all found by hand:
    /// the risk card drew VO₂max and vascular age in its own bespoke chart and
    /// declared neither; Heart Health's whole bespoke section is heart-rate
    /// recovery and it declared neither that nor reported it; Energy's drain
    /// half is driven by heart rate against resting, both declared and neither
    /// reported; Sleep declared two absolute temperatures and read neither.
    ///
    /// Scoped to metrics the fixture actually supplies, because "declared and
    /// not read" and "declared and not recorded" are different situations and
    /// only the first is a defect.
    func testEveryDeclaredInputWithDataIsActuallyRead() {
        let samples = fullCoverage()
        let recorded = Set(samples.map(\.type))
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: contributorNow)
            let reported = Set(result.contributors.map(\.metric))
            // A card reporting nothing falls back to its declared list, which is
            // the case this check has no opinion about.
            guard !reported.isEmpty else { continue }
            for declared in model.candidateMetrics where recorded.contains(declared) {
                XCTAssertTrue(
                    reported.contains(declared)
                        || !declared.interchangeable.isDisjoint(with: reported),
                    "\(model.id) declares \(declared), has data for it, and reports "
                        + "it nowhere — so it charts on no section of its own card")
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
