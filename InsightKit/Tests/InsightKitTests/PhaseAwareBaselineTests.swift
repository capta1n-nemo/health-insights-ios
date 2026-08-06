import XCTest
@testable import InsightKit

/// Per-phase baselines — backlog §B5 #31, and **a fix rather than a feature**.
///
/// The luteal phase raises resting heart rate and respiratory rate and lowers
/// HRV. That is the exact pattern `HealthWatchModel` reads as an immune
/// response, so a cycling reader gets a fortnight of "something is stirring"
/// every month. `testTheLutealPatternIsWhatTheRadarCallsIllness` pins the
/// defect; the rest pin the machinery that will eventually fix it.
final class PhaseAwareBaselineTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func day(_ offset: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(Double(offset) * 86_400))
    }

    private func log(starts: [Int], length: Int = 5) -> [CycleDay] {
        starts.flatMap { start in
            (0..<length).map { CycleDay(day: day(start + $0), flow: $0 < 2 ? .medium : .light) }
        }
    }

    /// Six 28-day cycles: five completed and one running, 20 days in. Enough
    /// for the phase model to speak (three) and for a shift to be measured from
    /// several luteal phases rather than one fortnight.
    private var sixCycles: CycleSummary {
        CycleModel.summarise(days: log(starts: [-160, -132, -104, -76, -48, -20]),
                             now: now, calendar: utc)
    }

    /// One sample a day, `value(offset)` deciding what it reads.
    ///
    /// A single source, because `VitalReader.dailySeries` never blends
    /// instruments and a fixture with two would be testing the tie-break rather
    /// than the phase split.
    private func daily(_ metric: MetricType, from firstOffset: Int, to lastOffset: Int,
                       value: (Int) -> Double) -> [HealthMetricSample] {
        (firstOffset...lastOffset).map { offset in
            HealthMetricSample(type: metric, value: value(offset),
                               start: day(offset).addingTimeInterval(12 * 3600),
                               source: .oura)
        }
    }

    /// The phase a day fell in, for building a fixture that depends on it.
    private func phase(_ offset: Int, _ summary: CycleSummary) -> CyclePhase? {
        CyclePhaseModel.phase(on: day(offset), summary: summary, now: now, calendar: utc)?.phase
    }

    // MARK: - The Oura temperature channel

    /// ⚠️ **The headline test.** `skinTemperatureDeviation` is the strongest
    /// phase marker the app receives: basal body temperature rises 0.3–0.5 °C
    /// after ovulation and stays up until the period — the classic *biphasic*
    /// shift — and Oura's nocturnal deviation channel reproduces it.
    ///
    /// The fixture is that curve and nothing else: flat at 0 °C before
    /// ovulation, +0.35 °C after it, with a small deterministic wobble so the
    /// medians are not recovering a constant. If the phase split is right, the
    /// luteal-minus-follicular shift comes back at 0.35 — and it must come back
    /// as **measured**, not as the 0.30 literature prior that happens to sit
    /// nearby.
    func testTheBiphasicTemperatureShiftIsRecoveredByThePhaseSplit() throws {
        let summary = sixCycles
        let samples = daily(.skinTemperatureDeviation, from: -160, to: 0) { offset in
            let wobble = Double((offset % 5) - 2) * 0.01     // ±0.02 °C, deterministic
            switch phase(offset, summary) {
            case .luteal: return 0.35 + wobble
            // Ovulation is the crossing itself; leaving it mid-way keeps the
            // fixture from putting a step change on a boundary the model is
            // simultaneously estimating.
            case .ovulatory: return 0.17 + wobble
            default: return 0.0 + wobble
            }
        }

        let profile = PhaseAwareBaseline.profile(metrics: [.skinTemperatureDeviation],
                                                 samples: samples, summary: summary,
                                                 now: now, calendar: utc)
        let shift = try XCTUnwrap(profile.expectedShift(metric: .skinTemperatureDeviation,
                                                        phase: .luteal))

        XCTAssertTrue(shift.isMeasured,
                      "a biphasic curve across six cycles must be measured, not priored")
        XCTAssertEqual(shift.delta, 0.35, accuracy: 0.03,
                       "the phase split did not recover the shift it was given")
        XCTAssertLessThan(shift.uncertainty, 0.05,
                          "a clean biphasic curve should produce a tight ±")

        // And the reference phase is the origin by construction.
        let follicular = try XCTUnwrap(profile.expectedShift(metric: .skinTemperatureDeviation,
                                                             phase: .follicular))
        XCTAssertEqual(follicular.delta, 0)
    }

    /// The same fixture read the other way: the per-phase baselines themselves
    /// must separate, or the shift above could be an artefact of the difference
    /// rather than of the split.
    func testThePerPhaseBaselinesSeparateOnTheBiphasicFixture() throws {
        let summary = sixCycles
        let samples = daily(.skinTemperatureDeviation, from: -160, to: 0) { offset in
            phase(offset, summary) == .luteal ? 0.35 : 0.0
        }
        let profile = PhaseAwareBaseline.profile(metrics: [.skinTemperatureDeviation],
                                                 samples: samples, summary: summary,
                                                 now: now, calendar: utc)

        let luteal = try XCTUnwrap(profile.baseline(metric: .skinTemperatureDeviation,
                                                    phase: .luteal))
        let follicular = try XCTUnwrap(profile.baseline(metric: .skinTemperatureDeviation,
                                                        phase: .follicular))
        XCTAssertEqual(luteal.median, 0.35, accuracy: 0.001)
        XCTAssertEqual(follicular.median, 0.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(luteal.cycleCount, 4,
                                    "the luteal days must come from several cycles, not one")
        XCTAssertGreaterThanOrEqual(luteal.dayCount, PhaseAwareBaseline.minimumDaysPerPhase)
    }

    // MARK: - Measured beats literature, and says which it is

    /// ⚠️ **The rule the whole file exists for.** With enough of the reader's own
    /// data the shift is theirs; the published figure is only ever a stand-in,
    /// and the two are never confusable — `isMeasured` separates them and the
    /// sentence says so out loud.
    func testTheReadersOwnShiftBeatsTheLiteraturePriorAndIsLabelledAsTheirs() throws {
        let summary = sixCycles
        // Deliberately unlike the +2.0 bpm prior, so a passing test cannot be a
        // coincidence: this reader's luteal rise is 5 bpm.
        let samples = daily(.restingHeartRate, from: -160, to: 0) { offset in
            let wobble = Double((offset % 4) - 1) * 0.3
            return (phase(offset, summary) == .luteal ? 60.0 : 55.0) + wobble
        }
        let profile = PhaseAwareBaseline.profile(metrics: [.restingHeartRate],
                                                 samples: samples, summary: summary,
                                                 now: now, calendar: utc)
        let shift = try XCTUnwrap(profile.expectedShift(metric: .restingHeartRate,
                                                        phase: .luteal))

        XCTAssertTrue(shift.isMeasured)
        XCTAssertEqual(shift.delta, 5.0, accuracy: 0.6,
                       "it reported the population figure instead of the reader's")
        XCTAssertTrue(shift.sentence.contains("your own days"), shift.sentence)
        XCTAssertFalse(shift.sentence.contains("Published"), shift.sentence)
    }

    /// And under that bar it falls back to the prior — **tagged**, and with a
    /// sentence that says whose number it is.
    func testTheLiteraturePriorIsUsedWhenThereIsNotEnoughDataAndIsNeverPassedOff() throws {
        // Three cycles is enough to place a phase but the samples below cover
        // only the last fortnight, so no phase clears `minimumDaysPerPhase`.
        let summary = CycleModel.summarise(days: log(starts: [-104, -76, -48, -20]),
                                           now: now, calendar: utc)
        let samples = daily(.restingHeartRate, from: -6, to: 0) { _ in 61 }
        let profile = PhaseAwareBaseline.profile(metrics: [.restingHeartRate],
                                                 samples: samples, summary: summary,
                                                 now: now, calendar: utc)
        let shift = try XCTUnwrap(profile.expectedShift(metric: .restingHeartRate,
                                                        phase: .luteal))

        XCTAssertFalse(shift.isMeasured)
        XCTAssertEqual(shift.basis, .literaturePrior)
        XCTAssertEqual(shift.delta, 2.0, accuracy: 0.001, "Goodale 2019 / Shilaih 2018")
        XCTAssertTrue(shift.sentence.contains("not yours"), shift.sentence)
        XCTAssertTrue(shift.sentence.contains("Published"), shift.sentence)
    }

    /// One cycle's luteal phase is one fortnight, and whatever else happened
    /// that fortnight is inside the estimate with no way to tell. Two cycles
    /// agreeing is the weakest evidence the pattern is the cycle.
    func testASingleCyclesWorthOfDaysIsNotAMeasuredShift() throws {
        // Three completed cycles so the model will speak, but samples covering
        // only the running cycle — one luteal phase.
        let summary = CycleModel.summarise(days: log(starts: [-104, -76, -48, -20]),
                                           now: now, calendar: utc)
        let samples = daily(.restingHeartRate, from: -20, to: 0) { offset in
            phase(offset, summary) == .luteal ? 60 : 55
        }
        let profile = PhaseAwareBaseline.profile(metrics: [.restingHeartRate],
                                                 samples: samples, summary: summary,
                                                 now: now, calendar: utc)
        let luteal = try XCTUnwrap(profile.baseline(metric: .restingHeartRate, phase: .luteal))
        XCTAssertEqual(luteal.cycleCount, 1)

        let shift = try XCTUnwrap(profile.expectedShift(metric: .restingHeartRate,
                                                        phase: .luteal))
        XCTAssertFalse(shift.isMeasured,
                       "one cycle's fortnight was reported as this reader's luteal phase")
    }

    /// A metric with no established luteal effect gets no prior invented for it.
    /// The gap in the table is a finding, not an oversight.
    func testAMetricWithNoEstablishedEffectGetsNoPrior() {
        let summary = sixCycles
        let profile = PhaseAwareBaseline.profile(metrics: [.oxygenSaturation],
                                                 samples: [], summary: summary,
                                                 now: now, calendar: utc)
        XCTAssertNil(profile.expectedShift(metric: .oxygenSaturation, phase: .luteal),
                     "a prior was invented for a metric the literature does not settle")
    }

    /// Every prior in the table points the way the physiology does. A sign error
    /// here would tell the radar that HRV *rises* in the luteal phase, which is
    /// the opposite correction to the one it needs.
    func testEveryLiteraturePriorPointsTheWayThePhysiologyDoes() {
        let priors = PhaseAwareBaseline.literaturePriors
        for metric in [MetricType.restingHeartRate, .respiratoryRate,
                       .skinTemperature, .skinTemperatureDeviation] {
            let entry = priors[metric]?[.luteal]
            XCTAssertNotNil(entry, "\(metric) has no luteal prior")
            XCTAssertGreaterThan(entry?.delta ?? 0, 0, "\(metric) should rise in the luteal phase")
        }
        for metric in [MetricType.heartRateVariabilityRMSSD, .heartRateVariabilitySDNN] {
            XCTAssertLessThan(priors[metric]?[.luteal]?.delta ?? 0, 0,
                              "\(metric) should fall in the luteal phase")
        }
        for (metric, byPhase) in priors {
            for (phase, entry) in byPhase {
                XCTAssertGreaterThan(entry.uncertainty, 0,
                                     "\(metric) in \(phase) has a population figure with no ±")
            }
        }
    }

    // MARK: - Why it is not wired in

    /// ⚠️ **The defect this machinery exists to fix, pinned as a test.**
    ///
    /// A synthetic reader with nothing wrong except a normal luteal phase —
    /// resting heart rate up 3, respiratory rate up 0.4, HRV down 7, skin
    /// temperature up 0.35 — is read by `HealthWatchModel` as several signals
    /// leaning together, which is its definition of an immune response.
    ///
    /// This test asserts the *current* behaviour on purpose. When the TODO in
    /// `PhaseAwareBaseline` is done and the radar reads phase-aware references,
    /// this test should fail and be rewritten to assert the opposite — that is
    /// the signal that the fix landed, and the reason it is written as a
    /// characterisation rather than deleted.
    func testTheLutealPatternIsWhatTheRadarCallsIllness() throws {
        let summary = sixCycles
        var samples: [HealthMetricSample] = []
        // The four channels that move together in the luteal phase, over a
        // window long enough for the radar's 21-day reference plus its gap.
        let shifts: [(MetricType, Double, Double)] = [
            (.restingHeartRate, 55, 3.0),
            (.respiratoryRate, 14.0, 0.4),
            (.heartRateVariabilityRMSSD, 60, -7.0),
            (.skinTemperatureDeviation, 0.0, 0.35)
        ]
        for (metric, base, luteal) in shifts {
            samples += daily(metric, from: -60, to: 0) { offset in
                base + (phase(offset, summary) == .luteal ? luteal : 0)
            }
        }

        // Today is day 21 of a 28-day cycle: mid-luteal, and nothing is wrong.
        XCTAssertEqual(phase(0, summary), .luteal)
        let output = try XCTUnwrap(HealthWatchModel.evaluate(samples: samples, now: now,
                                                             calendar: utc))
        XCTAssertFalse(output.leaning.isEmpty,
                       "the luteal false alarm has gone — rewrite this test, the fix has landed")
        XCTAssertLessThan(output.score, 100)

        // And the machinery that will fix it can see the same shift, from the
        // same samples, as the reader's own rather than as a population figure.
        let profile = PhaseAwareBaseline.profile(samples: samples, summary: summary,
                                                 now: now, calendar: utc)
        let rhr = try XCTUnwrap(profile.expectedShift(metric: .restingHeartRate, phase: .luteal))
        XCTAssertTrue(rhr.isMeasured)
        XCTAssertEqual(rhr.delta, 3.0, accuracy: 0.5)
    }

    /// The default metric list is the radar's own, derived and not re-typed —
    /// two lists that must agree are one list that will not.
    func testTheDefaultMetricsAreExactlyTheOnesTheRadarVotesOn() {
        XCTAssertEqual(PhaseAwareBaseline.defaultMetrics, HealthWatchModel.watchedMetrics)
    }

    /// A reader with no cycle log gets an empty profile rather than a profile of
    /// the whole record labelled "follicular".
    func testNoCycleLogProducesNoPhaseBaselinesRatherThanMislabelledOnes() {
        let empty = CycleModel.summarise(days: [], now: now, calendar: utc)
        let samples = daily(.restingHeartRate, from: -60, to: 0) { _ in 58 }
        let profile = PhaseAwareBaseline.profile(metrics: [.restingHeartRate],
                                                 samples: samples, summary: empty,
                                                 now: now, calendar: utc)
        XCTAssertTrue(profile.baselines.isEmpty)
        XCTAssertNil(profile.baseline(metric: .restingHeartRate, phase: .follicular))
    }
}
