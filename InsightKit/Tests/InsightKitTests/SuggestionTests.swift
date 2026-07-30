import XCTest
@testable import InsightKit

private let sugNow = Date(timeIntervalSince1970: 1_700_000_000)
private let sugCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func sugDay(_ daysAgo: Int) -> Date {
    sugCalendar.startOfDay(for: sugNow.addingTimeInterval(-Double(daysAgo) * 86_400))
        .addingTimeInterval(12 * 3600)
}

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
            result(.heartAge, score: nil, unmet: [requirement(.cuffSystolic, mandatory: true)]),
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
