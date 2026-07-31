import XCTest
@testable import InsightKit

private let sugNow = TestClock.now
private let sugCalendar = TestClock.utc
private func sugDay(_ daysAgo: Int) -> Date { TestClock.day(daysAgo) }

/// The hard part of "Improve Your Health" is refusing to generate the wrong
/// suggestions. This app is not a medical device, so every line has to be one of
/// three factual things — an observation from the user's own history, a fact the
/// app is missing, or a signal that has moved — and never a prescription.
final class SuggestionTests: XCTestCase {

    private func result(_ id: InsightID, score: Double?,
                        unmet: [GroundingRequirement] = []) -> InsightResult {
        InsightResult(id: id, title: id.rawValue, primaryValue: score, headline: "",
                      score: score, confidence: .moderate, explanation: "",
                      drivers: [], unmetRequirements: unmet)
    }

    private func requirement(_ kind: GroundingKind, mandatory: Bool) -> GroundingRequirement {
        .init(kind: kind, isMandatory: mandatory, rationale: "")
    }

    private func suggestions(results: [InsightResult] = [],
                             samples: [HealthMetricSample] = [],
                             profile: UserHealthProfile = .init()) -> [Suggestion] {
        SuggestionEngine.suggestions(results: results, samples: samples, profile: profile,
                                     now: sugNow, calendar: sugCalendar)
    }

    // MARK: - Ordering

    /// The whole ranking argument in one test: an observation about *this person*
    /// outranks a gap in the app's inputs, which outranks a signal merely being
    /// off baseline.
    func testEvidenceStrengthDecidesTheOrder() {
        XCTAssertLessThan(Suggestion.Basis.yourOwnData, Suggestion.Basis.unlockAnInsight)
        XCTAssertLessThan(Suggestion.Basis.unlockAnInsight, Suggestion.Basis.signalOffBaseline)
    }

    func testNothingToSayMeansNothingIsSaid() {
        XCTAssertTrue(suggestions().isEmpty)
    }

    func testTheListIsCapped() {
        // Nine distinct grounding gaps across several cards.
        let kinds: [GroundingKind] = [.dateOfBirth, .biologicalSex, .totalCholesterol,
                                      .hdlCholesterol, .currentSmoker, .hasDiabetes,
                                      .onBPMedication, .cuffSystolic, .ascvdRaceGroup]
        let results = [result(.cardiovascularRisk, score: nil,
                              unmet: kinds.map { requirement($0, mandatory: true) })]
        XCTAssertEqual(suggestions(results: results).count, SuggestionEngine.defaultLimit)
    }

    // MARK: - Grounding gaps

    /// A grounding gap is a statement about the *software*, which is exactly why
    /// it can be phrased as something to do without becoming advice.
    func testAMissingFactBecomesAnUnlockSuggestion() throws {
        let results = [result(.cardiovascularRisk, score: nil,
                              unmet: [requirement(.cuffSystolic, mandatory: true)])]
        let suggestion = try XCTUnwrap(suggestions(results: results).first)
        XCTAssertEqual(suggestion.basis, .unlockAnInsight)
        XCTAssertTrue(suggestion.title.lowercased().contains("cuff"))
        XCTAssertTrue(suggestion.detail.contains("can't produce a score"))
    }

    /// One cuff reading feeds three cards; an ethnicity field refines one. The
    /// list should lead with the one that unblocks more.
    func testAFactBlockingMoreCardsRanksHigher() throws {
        let results = [
            result(.cardiovascularRisk, score: nil,
                   unmet: [requirement(.cuffSystolic, mandatory: true),
                           requirement(.ascvdRaceGroup, mandatory: false)]),
            result(.cardiovascularRisk, score: nil, unmet: [requirement(.cuffSystolic, mandatory: true)]),
            result(.bloodPressure, score: nil, unmet: [requirement(.cuffSystolic, mandatory: true)])
        ]
        let ranked = suggestions(results: results)
        XCTAssertEqual(ranked.first?.id, "grounding-cuffSystolic")
        let race = try XCTUnwrap(ranked.first { $0.id == "grounding-ascvdRaceGroup" })
        XCTAssertLessThan(race.strength, try XCTUnwrap(ranked.first?.strength))
    }

    /// A gap that only *refines* a card that already has a number reads
    /// differently from one that stops it producing anything.
    func testARefinementIsWordedAsARefinement() throws {
        let results = [result(.cardiovascularRisk, score: 72,
                              unmet: [requirement(.totalCholesterol, mandatory: false)])]
        let suggestion = try XCTUnwrap(suggestions(results: results).first)
        XCTAssertTrue(suggestion.detail.contains("more accurate"))
        XCTAssertFalse(suggestion.detail.contains("can't produce"))
    }

    // MARK: - Departures

    func testASignalWellOffBaselineIsReported() throws {
        // A fortnight of settled resting heart rate, then a clear departure.
        var samples: [HealthMetricSample] = []
        let history = (0..<15).map { 55 + Double($0 % 3) }
        for (index, value) in (history + [82]).enumerated() {
            samples.append(HealthMetricSample(
                type: .restingHeartRate, value: value,
                start: sugDay(history.count - index), source: .oura))
        }
        let found = suggestions(samples: samples)
        let departure = try XCTUnwrap(found.first { $0.basis == .signalOffBaseline })
        XCTAssertEqual(departure.metric, .restingHeartRate)
        XCTAssertTrue(departure.title.contains("above your usual range"), departure.title)
    }

    /// Reporting, not explaining. The moment a line says *why* a signal moved, or
    /// what to do about it, it has stopped being a description.
    func testADepartureIsNamedAndNotExplained() throws {
        var samples: [HealthMetricSample] = []
        let history = (0..<15).map { 55 + Double($0 % 3) }
        for (index, value) in (history + [82]).enumerated() {
            samples.append(HealthMetricSample(
                type: .restingHeartRate, value: value,
                start: sugDay(history.count - index), source: .oura))
        }
        let departure = try XCTUnwrap(
            suggestions(samples: samples).first { $0.basis == .signalOffBaseline })
        XCTAssertTrue(departure.detail.contains("not a diagnosis"))
        for banned in ["you should", "try to", "reduce your", "increase your", "we recommend"] {
            XCTAssertFalse(departure.detail.lowercased().contains(banned),
                           "a suggestion prescribed: \(departure.detail)")
        }
    }

    func testASettledSignalProducesNothing() {
        var samples: [HealthMetricSample] = []
        for index in 0..<16 {
            samples.append(HealthMetricSample(
                type: .restingHeartRate, value: 55 + Double(index % 3),
                start: sugDay(15 - index), source: .oura))
        }
        XCTAssertTrue(suggestions(samples: samples).filter { $0.basis == .signalOffBaseline }.isEmpty)
    }

    // MARK: - The guardrails, as an assertion

    /// No suggestion of any kind may read as an instruction. This sweeps every
    /// line the engine can currently produce.
    func testNoSuggestionEverPrescribes() throws {
        var samples: [HealthMetricSample] = []
        let history = (0..<15).map { 55 + Double($0 % 3) }
        for (index, value) in (history + [82]).enumerated() {
            samples.append(HealthMetricSample(
                type: .restingHeartRate, value: value,
                start: sugDay(history.count - index), source: .oura))
        }
        let results = [result(.cardiovascularRisk, score: nil,
                              unmet: [requirement(.cuffSystolic, mandatory: true)])]
        let banned = ["you should", "you must", "we recommend", "take ", "dose", "mg "]
        for suggestion in suggestions(results: results, samples: samples) {
            let text = (suggestion.title + " " + suggestion.detail).lowercased()
            for phrase in banned {
                XCTAssertFalse(text.contains(phrase),
                               "\(suggestion.id) prescribes: \(text)")
            }
        }
    }
}

/// The two cards `SuggestionEngine` predated. Health Watch's convergence is the
/// best-founded thing this app can say and was the one thing this list could not
/// say; Energy's morning charge is a contrast a sleep-duration series cannot
/// express, because charge is duration *and* overnight recovery together.
final class SuggestionsFromTheNewCardsTests: XCTestCase {

    /// A month of steady nights, then `leaningDays` in which the named metrics
    /// move by `shift` of their own spread.
    private func history(_ movers: [MetricType: Double], leaningDays: Int = 3,
                         steady: [MetricType: Double] = [:]) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for (metric, base) in movers.merging(steady, uniquingKeysWith: { a, _ in a }) {
            let shift = movers[metric]
            for day in 0..<35 {
                // A little noise so the spread is non-zero and the z-score is
                // finite — a flat reference period divides by zero and votes for
                // nothing.
                let wobble = Double(day % 3) * 0.01 * base
                let leaning = day < leaningDays && shift != nil
                out.append(HealthMetricSample(
                    type: metric,
                    value: base + wobble + (leaning ? 0.1 * base * (shift! > 0 ? 1 : -1) : 0),
                    start: sugDay(day), source: .oura))
            }
        }
        return out
    }

    private func suggestions(_ samples: [HealthMetricSample]) -> [Suggestion] {
        SuggestionEngine.suggestions(results: [], samples: samples,
                                     profile: .init(), now: sugNow, calendar: sugCalendar)
    }

    // MARK: - Health Watch

    func testConvergenceOutranksEverythingElse() {
        XCTAssertLessThan(Suggestion.Basis.convergingSignals, Suggestion.Basis.yourOwnData)
    }

    func testSeveralSignalsLeaningTogetherBecomeOneSuggestion() throws {
        let samples = history([.restingHeartRate: 1, .respiratoryRate: 1,
                               .skinTemperature: 1])
        let watch = try XCTUnwrap(HealthWatchModel.evaluate(samples: samples, now: sugNow,
                                                            calendar: sugCalendar))
        try XCTSkipUnless(watch.leaning.count >= 2, "fixture failed to produce a lean")

        let top = try XCTUnwrap(suggestions(samples).first)
        XCTAssertEqual(top.basis, .convergingSignals)
        XCTAssertEqual(top.insight, .readiness)
        // The count in the sentence is the model's, not a second opinion.
        XCTAssertTrue(top.title.hasPrefix("\(watch.leaning.count) signals"), top.title)
    }

    /// One signal moving is an ordinary Tuesday. Promoting it to the top of the
    /// list would destroy the distinction the card exists to draw — and
    /// `departures` already reports it, at the bottom where it belongs.
    func testOneSignalMovingIsNotAConvergence() {
        let samples = history([.restingHeartRate: 1],
                              steady: [.respiratoryRate: 15, .oxygenSaturation: 97])
        XCTAssertFalse(suggestions(samples).contains { $0.basis == .convergingSignals })
    }

    /// A signal named in the convergence row must not appear again three rows
    /// down as a lone departure — the same reading twice reads as two findings.
    func testASignalIsNeverBothConvergingAndALoneDeparture() throws {
        let samples = history([.restingHeartRate: 1, .respiratoryRate: 1,
                               .skinTemperature: 1])
        let all = suggestions(samples)
        try XCTSkipUnless(all.contains { $0.basis == .convergingSignals },
                          "fixture failed to produce a convergence")
        let watch = try XCTUnwrap(HealthWatchModel.evaluate(samples: samples, now: sugNow,
                                                            calendar: sugCalendar))
        let leaning = Set(watch.leaning.map(\.metric))
        for suggestion in all where suggestion.basis == .signalOffBaseline {
            XCTAssertFalse(leaning.contains(suggestion.metric!),
                           "\(suggestion.metric!) reported twice")
        }
    }

    // MARK: - Energy

    /// The series is the *charge*, not the sleep: two identical seven-hour
    /// nights start in different places when overnight recovery differs, and
    /// that difference is the whole reason this is Energy's suggestion.
    func testTheChargeSeriesSeparatesTwoIdenticalNights() throws {
        var samples: [HealthMetricSample] = []
        for day in 0..<40 {
            samples.append(HealthMetricSample(type: .sleepDurationHours, value: 7,
                                              start: sugDay(day), source: .oura))
            // HRV collapses over the most recent week.
            samples.append(HealthMetricSample(type: .heartRateVariabilityRMSSD,
                                              value: day < 7 ? 28 : 55,
                                              start: sugDay(day), source: .oura))
        }
        let series = EnergyModel.morningChargeSeries(samples: samples, days: 90,
                                                     now: sugNow, calendar: sugCalendar)
        XCTAssertGreaterThan(series.count, 30)
        let recent = try XCTUnwrap(series.last).value
        let earlier = try XCTUnwrap(series.first).value
        XCTAssertLessThan(recent, earlier - 5,
                          "identical sleep, worse recovery, and the charge did not move")
    }

    func testAWeekBelowYourOwnBestWeekIsReported() throws {
        var samples: [HealthMetricSample] = []
        for day in 0..<60 {
            samples.append(HealthMetricSample(type: .sleepDurationHours,
                                              value: day < 7 ? 5.2 : 8.1,
                                              start: sugDay(day), source: .oura))
        }
        let charge = try XCTUnwrap(suggestions(samples)
            .first { $0.id == "morning-charge" })
        XCTAssertEqual(charge.basis, .yourOwnData)
        XCTAssertEqual(charge.insight, .energy)
    }

    /// A good week must never be reported as falling short of itself.
    func testASteadyRunSaysNothing() {
        var samples: [HealthMetricSample] = []
        for day in 0..<60 {
            samples.append(HealthMetricSample(type: .sleepDurationHours, value: 7.8,
                                              start: sugDay(day), source: .oura))
        }
        XCTAssertFalse(suggestions(samples).contains { $0.id == "morning-charge" })
    }

    /// And the guardrail, swept over the lines only these two can produce.
    func testTheNewSuggestionsDoNotPrescribe() {
        var samples = history([.restingHeartRate: 1, .respiratoryRate: 1,
                               .skinTemperature: 1])
        for day in 0..<60 {
            samples.append(HealthMetricSample(type: .sleepDurationHours,
                                              value: day < 7 ? 5.2 : 8.1,
                                              start: sugDay(day), source: .oura))
        }
        let banned = ["you should", "you must", "we recommend", "take ", "dose", "mg ",
                      "try to", "need to", "make sure"]
        for suggestion in suggestions(samples) {
            let text = (suggestion.title + " " + suggestion.detail).lowercased()
            for phrase in banned {
                XCTAssertFalse(text.contains(phrase), "\(suggestion.id) prescribes: \(text)")
            }
        }
    }
}

/// The substance log was a data source for exactly one card and one chart
/// shading — a strange property for the only input the user enters by hand.
final class SubstanceSuggestionTests: XCTestCase {

    /// `clean` nights at `baseline` bpm, then `logged` nights that each follow a
    /// logged event and read `after` bpm.
    private func fixture(baseline: Double, after: Double,
                         clean: Int = 14, logged: Int = 6)
        -> (events: [SubstanceEvent], samples: [HealthMetricSample]) {
        var events: [SubstanceEvent] = []
        var samples: [HealthMetricSample] = []
        for day in 0..<(clean + logged) {
            let isLogged = day < logged
            // A little wobble so the clean nights have a spread to judge against.
            let wobble = Double(day % 3) * 0.4
            samples.append(HealthMetricSample(
                type: .restingHeartRate,
                value: (isLogged ? after : baseline) + wobble,
                start: sugDay(day), source: .oura))
            if isLogged {
                events.append(SubstanceEvent(substance: .alcohol,
                                             timestamp: sugDay(day).addingTimeInterval(-4 * 3600)))
            }
        }
        return (events, samples)
    }

    private func suggestions(_ f: (events: [SubstanceEvent], samples: [HealthMetricSample]))
        -> [Suggestion] {
        SuggestionEngine.suggestions(results: [], samples: f.samples, profile: .init(),
                                     substanceEvents: f.events, now: sugNow,
                                     calendar: sugCalendar)
    }

    func testAClearResponseBecomesASuggestion() throws {
        let all = suggestions(fixture(baseline: 55, after: 66))
        let row = try XCTUnwrap(all.first { $0.id.hasPrefix("substance-") })
        XCTAssertEqual(row.basis, .yourOwnData)
        XCTAssertEqual(row.insight, .substanceImpact)
        XCTAssertEqual(row.metric, .restingHeartRate)
        // Both sets of nights must be countable from the sentence, or it is an
        // assertion rather than a comparison.
        XCTAssertTrue(row.detail.contains("nights"), row.detail)
    }

    /// Two sets of nights that are the same distribution are not a finding.
    func testNoDifferenceSaysNothing() {
        XCTAssertFalse(suggestions(fixture(baseline: 55, after: 55.2))
            .contains { $0.id.hasPrefix("substance-") })
    }

    func testAnEmptyLogSaysNothing() {
        let f = fixture(baseline: 55, after: 66)
        XCTAssertFalse(SuggestionEngine
            .suggestions(results: [], samples: f.samples, profile: .init(),
                         substanceEvents: [], now: sugNow, calendar: sugCalendar)
            .contains { $0.id.hasPrefix("substance-") })
    }

    /// It reports two sets of the user's own nights and stops. Anything that
    /// reads as "so drink less" is the line this app does not cross — these
    /// features are harm-reduction and descriptive, never encouragement or
    /// discouragement.
    func testItDescribesRatherThanPrescribes() throws {
        let row = try XCTUnwrap(suggestions(fixture(baseline: 55, after: 66))
            .first { $0.id.hasPrefix("substance-") })
        let text = (row.title + " " + row.detail).lowercased()
        for phrase in ["you should", "cut down", "avoid", "reduce your", "stop ",
                       "we recommend", "try to"] {
            XCTAssertFalse(text.contains(phrase), "\(row.id) prescribes: \(text)")
        }
        XCTAssertTrue(text.contains("not a claim about cause"), text)
    }
}
