import XCTest
@testable import InsightKit

/// Backlog P32 / Q6 — the event confirmation feed, its detector, and the place
/// model the reader attached conditions to.
///
/// The privacy assertions here are not decoration. `PlaceContext` promises three
/// things — coarse on the way in, forgotten on review, capped anchors — and a
/// promise nothing tests is a comment.
final class EventConfirmationFeedTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Fixtures

    /// A month of ordinary heart rate: a daypart-shaped baseline with a little
    /// noise, sampled every ten minutes so a ten-minute window is reachable.
    private func ordinaryHeartRate(days: Int, endingOn end: Date) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for day in 0..<days {
            guard let midnight = calendar.date(byAdding: .day, value: -day,
                                               to: calendar.startOfDay(for: end))
            else { continue }
            for slot in 0..<(24 * 6) {
                let stamp = midnight.addingTimeInterval(Double(slot) * 600)
                let hour = calendar.component(.hour, from: stamp)
                let base: Double = hour < 6 ? 55 : (hour < 18 ? 70 : 65)
                // Deterministic wobble, so the MAD is non-zero and the fixture
                // does not depend on a random generator.
                let wobble = Double((slot &* 7 &+ day &* 13) % 7) - 3
                out.append(HealthMetricSample(type: .heartRate, value: base + wobble,
                                              start: stamp, end: stamp.addingTimeInterval(60),
                                              source: .appleHealth))
            }
        }
        return out
    }

    private func spike(at start: Date, minutes: Int, value: Double) -> [HealthMetricSample] {
        stride(from: 0, to: minutes * 60, by: 300).map { offset in
            let stamp = start.addingTimeInterval(Double(offset))
            return HealthMetricSample(type: .heartRate, value: value, start: stamp,
                                      end: stamp.addingTimeInterval(60),
                                      source: .appleHealth)
        }
    }

    private func evening(daysAgo: Int, from now: Date) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo,
                                to: calendar.startOfDay(for: now)) ?? now
        return day.addingTimeInterval(20 * 3600)
    }

    private var now: Date {
        // A fixed instant so nothing here depends on when the suite runs.
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 23))!
    }

    // MARK: - The detector

    func testAnUnexplainedEveningElevationIsFlagged() {
        let start = evening(daysAgo: 1, from: now)
        let samples = ordinaryHeartRate(days: 28, endingOn: now)
            + spike(at: start, minutes: 30, value: 105)

        let events = FlaggedEventDetector.detect(samples: samples, now: now, calendar: calendar)
        XCTAssertEqual(events.count, 1, "one unexplained stretch should flag exactly one event")
        let event = try! XCTUnwrap(events.first)
        XCTAssertGreaterThanOrEqual(event.minutes, 20)
        XCTAssertEqual(event.trigger, .restingHeartRateElevation)
        XCTAssertGreaterThan(event.evidence.departures,
                             FlaggedEventDetector.departureThreshold)
    }

    /// The cost the detector accepts on purpose — see its type comment. A feed
    /// that asked about every walk would be answered once and never opened.
    func testAnElevationWithMovementIsNotFlagged() {
        let start = evening(daysAgo: 1, from: now)
        let steps = HealthMetricSample(type: .stepCount, value: 900,
                                       start: start, end: start.addingTimeInterval(1800),
                                       source: .appleHealth)
        let samples = ordinaryHeartRate(days: 28, endingOn: now)
            + spike(at: start, minutes: 30, value: 105) + [steps]

        XCTAssertTrue(FlaggedEventDetector.detect(samples: samples, now: now,
                                                  calendar: calendar).isEmpty)
    }

    func testAShortExcursionIsNotFlagged() {
        let start = evening(daysAgo: 1, from: now)
        let samples = ordinaryHeartRate(days: 28, endingOn: now)
            + spike(at: start, minutes: 6, value: 105)
        XCTAssertTrue(FlaggedEventDetector.detect(samples: samples, now: now,
                                                  calendar: calendar).isEmpty)
    }

    /// The gate rule: nothing is flagged against a reference that is not one.
    func testThinHistoryFlagsNothingAndSaysWhatItNeeds() {
        let start = evening(daysAgo: 1, from: now)
        let samples = ordinaryHeartRate(days: 5, endingOn: now)
            + spike(at: start, minutes: 30, value: 105)

        XCTAssertTrue(FlaggedEventDetector.detect(samples: samples, now: now,
                                                  calendar: calendar).isEmpty)
        let gate = try! XCTUnwrap(FlaggedEventDetector.referenceGate(samples: samples,
                                                                    now: now,
                                                                    calendar: calendar))
        XCTAssertFalse(gate.isMet)
        let sentence = try! XCTUnwrap(gate.sentence)
        XCTAssertTrue(sentence.contains("14"), "the gate has to name the number it needs")
        // ⚠️ `CoverageGate` pluralises by appending an "s", so the unit must be
        // a bare noun. This shipped as "day of heart-rate history" and rendered
        // *"14 day of heart-rate historys"* on the simulator — a phrase unit
        // cannot be pluralised by a suffix.
        XCTAssertFalse(sentence.contains("historys"))
        XCTAssertTrue(sentence.contains("14 days"))
    }

    /// Every gate this feature produces has to survive the same suffix.
    func testEveryGateUnitPluralisesByAddingAnS() {
        let gates: [CoverageGate?] = [
            FlaggedEventDetector.referenceGate(samples: [], now: now, calendar: calendar),
            FlaggedEventAccuracy.measure([]).gate,
            PlaceAnchorSet().gate]
        for gate in gates {
            let unit = try! XCTUnwrap(gate).unit
            XCTAssertFalse(unit.contains(" of "),
                           "\"\(unit)\" is a phrase; the pluraliser will put the s on the wrong word")
            // A consonant before a final "y" takes -ies ("history" → "histories"),
            // which a suffix cannot produce. A vowel before it is fine — "day"
            // → "days" — so the check is the consonant, not the "y".
            let tail = unit.suffix(2)
            let takesIES = tail.count == 2 && tail.hasSuffix("y")
                && !"aeiou".contains(tail.first!)
            XCTAssertFalse(takesIES,
                           "\"\(unit)\" pluralises to \"\(unit)s\", which is not a word")
        }
    }

    func testAMetGateSaysNothing() {
        let samples = ordinaryHeartRate(days: 28, endingOn: now)
        XCTAssertNil(FlaggedEventDetector.referenceGate(samples: samples, now: now,
                                                        calendar: calendar))
    }

    /// A stable id is what keeps a reader's answer attached across re-detection.
    func testTheSameStretchKeepsItsIdentifierAcrossRuns() {
        let start = evening(daysAgo: 1, from: now)
        let samples = ordinaryHeartRate(days: 28, endingOn: now)
            + spike(at: start, minutes: 30, value: 105)
        let first = FlaggedEventDetector.detect(samples: samples, now: now, calendar: calendar)
        let second = FlaggedEventDetector.detect(samples: samples, now: now, calendar: calendar)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    /// The reference is per daypart, so an evening level that would be unusual
    /// at 3am is not flagged at 8pm.
    func testTheReferenceIsPerDaypart() {
        let samples = ordinaryHeartRate(days: 28, endingOn: now)
        let refs = FlaggedEventDetector.daypartReferences(samples, calendar: calendar)
        let night = try! XCTUnwrap(refs[.night])
        let afternoon = try! XCTUnwrap(refs[.afternoon])
        XCTAssertLessThan(night.typical, afternoon.typical)
    }

    /// A stuck sensor reporting one value all night must not make every later
    /// reading infinitely unusual.
    func testAZeroSpreadDaypartIsDroppedRatherThanDividedBy() {
        let midnight = calendar.startOfDay(for: now)
        let flat = (0..<60).map { slot -> HealthMetricSample in
            let stamp = midnight.addingTimeInterval(Double(slot) * 60)
            return HealthMetricSample(type: .heartRate, value: 60, start: stamp,
                                      source: .appleHealth)
        }
        let refs = FlaggedEventDetector.daypartReferences(flat, calendar: calendar)
        XCTAssertNil(refs[.night])
    }

    /// **The scoping the main thread depends on, pinned behaviourally.**
    ///
    /// `detect` filters the whole history to the reference window *before*
    /// calling `samples(of:)`, because that call sorts everything it selects —
    /// 3.0 s on the reader's three-year export, once per `recompute()` call
    /// site, of which there are thirty-three. It SIGKILLed the app target's
    /// tests, and on a phone it would have been the freeze reported on
    /// 2026-08-06.
    ///
    /// Asserted as an **equivalence rather than a duration**: a wall-clock
    /// assertion would flake on a loaded machine, and what actually has to hold
    /// is that discarding everything older than the window changes no answer.
    /// If somebody widens the reference window without widening the filter, or
    /// narrows the filter below the window, this fails.
    func testHistoryOlderThanTheReferenceWindowChangesNothing() {
        let start = evening(daysAgo: 1, from: now)
        let recent = ordinaryHeartRate(days: FlaggedEventDetector.referenceWindowDays,
                                       endingOn: now)
            + spike(at: start, minutes: 30, value: 105)
        // Two more years underneath it, at a different level, so anything
        // leaking into the reference would move the answer visibly.
        let older = ordinaryHeartRate(days: 60,
                                      endingOn: calendar.date(byAdding: .day,
                                                              value: -60, to: now)!)
            .map { HealthMetricSample(type: $0.type, value: $0.value + 25,
                                      start: $0.start, end: $0.end, source: $0.source) }

        let scoped = FlaggedEventDetector.detect(samples: recent, now: now, calendar: calendar)
        let whole = FlaggedEventDetector.detect(samples: recent + older, now: now,
                                                calendar: calendar)
        XCTAssertFalse(scoped.isEmpty, "the fixture must actually flag something")
        XCTAssertEqual(scoped.map(\.id), whole.map(\.id))
        XCTAssertEqual(scoped.first?.evidence, whole.first?.evidence,
                       "old history reached the reference — the filter and the window disagree")
    }

    // MARK: - Candidates

    func testALoggedSubstanceOutranksATimeOfDayGuess() {
        let start = evening(daysAgo: 1, from: now)
        let logged = SubstanceEvent(substance: .stimulant,
                                    timestamp: start.addingTimeInterval(-1800))
        let candidates = FlaggedEventDetector.candidates(
            for: start, end: start.addingTimeInterval(1800),
            substanceEvents: [logged], calendar: calendar)

        let top = try! XCTUnwrap(candidates.first)
        XCTAssertEqual(top.cause, .otherSubstance)
        XCTAssertEqual(top.basis, .loggedByYou)
        XCTAssertTrue(top.basis.isEvidenceBacked)
        XCTAssertNotNil(top.why)

        // And every time-of-day guess sits strictly below it, which is the only
        // ordering guarantee the function makes.
        for candidate in candidates where candidate.basis == .timeOfDay {
            XCTAssertLessThan(candidate.weight, top.weight)
        }
    }

    func testTheAnswerListIsNeverAForcedChoice() {
        let start = evening(daysAgo: 1, from: now)
        let causes = FlaggedEventDetector.candidates(for: start,
                                                     end: start.addingTimeInterval(1800),
                                                     substanceEvents: [],
                                                     calendar: calendar).map(\.cause)
        XCTAssertTrue(causes.contains(.somethingElse))
        XCTAssertTrue(causes.contains(.nothingNotable))
    }

    /// A guess resting on the time of day must say so — that sentence is the
    /// only thing standing between a coin flip and a finding.
    func testATimeOfDayGuessDeclaresItself() {
        let start = evening(daysAgo: 1, from: now)
        let candidates = FlaggedEventDetector.candidates(for: start,
                                                         end: start.addingTimeInterval(1800),
                                                         substanceEvents: [],
                                                         calendar: calendar)
        let top = try! XCTUnwrap(candidates.first)
        XCTAssertEqual(top.basis, .timeOfDay)
        XCTAssertFalse(top.basis.isEvidenceBacked)
        XCTAssertTrue(top.basis.sentence.lowercased().contains("nothing measured"))
    }

    /// The overnight prior deliberately omits intimacy — see
    /// `timeOfDayPriors`. An early fever is the pattern that shape actually
    /// makes, and the app must not lead with the more sensitive option on its
    /// weakest evidence.
    func testTheOvernightPriorDoesNotLeadWithTheSensitiveOption() {
        let threeAM = calendar.startOfDay(for: now).addingTimeInterval(3 * 3600)
        let priors = FlaggedEventDetector.timeOfDayPriors(at: threeAM, calendar: calendar)
        XCTAssertFalse(priors.contains(.intimacy))
    }

    /// P32's own example, and the shape of the question the app asks.
    func testTheQuestionIsAQuestion() {
        let start = evening(daysAgo: 1, from: now)
        let samples = ordinaryHeartRate(days: 28, endingOn: now)
            + spike(at: start, minutes: 30, value: 105)
        let event = try! XCTUnwrap(FlaggedEventDetector.detect(samples: samples, now: now,
                                                               calendar: calendar).first)
        XCTAssertTrue(event.question.hasSuffix("?"))
        XCTAssertTrue(event.headline.contains("weren't moving"))
        XCTAssertTrue(event.evidence.sentence.contains("your usual"))
        XCTAssertTrue(event.evidence.sentence.contains("last 28 days"),
                      "a departure has to travel with the depth of its reference")
    }

    // MARK: - The judgement: guess and answer kept apart

    private func judgement(guess: EventCause) -> FlaggedEventJudgement {
        FlaggedEventJudgement(eventID: "e1", guess: guess)
    }

    func testACorrectionNeverOverwritesTheGuess() {
        let judged = judgement(guess: .intimacy)
            .reviewed(correction: .stress, confirmed: false, at: now)
        XCTAssertEqual(judged.guess, .intimacy)
        XCTAssertEqual(judged.correction, .stress)
        XCTAssertEqual(judged.effective, .stress)
        XCTAssertTrue(judged.wasCorrected)
    }

    /// Tapping the option the app already offered is agreement, not a miss.
    func testACorrectionMatchingTheGuessIsNotADisagreement() {
        let judged = judgement(guess: .stress)
            .reviewed(correction: .stress, confirmed: false, at: now)
        XCTAssertFalse(judged.wasCorrected)
    }

    /// "Confirmed correct" is a label; "not looked at" is not.
    func testAnUnreviewedJudgementIsNotAnAgreement() {
        let pending = judgement(guess: .stress)
        XCTAssertFalse(pending.isReviewed)
        XCTAssertEqual(FlaggedEventAccuracy.measure([pending]).scored, 0)
    }

    func testRedetectionMovesTheGuessAndLeavesTheAnswerAlone() {
        let start = evening(daysAgo: 1, from: now)
        let evidence = FlagEvidence(peak: 105, typical: 65, spread: 5,
                                    referenceDays: 28, stepsInWindow: 0, sampleCount: 6)
        let event = FlaggedEvent(id: "e1", start: start,
                                 end: start.addingTimeInterval(1800),
                                 trigger: .restingHeartRateElevation,
                                 evidence: evidence,
                                 candidates: [CauseCandidate(cause: .caffeine, weight: 0.7,
                                                             basis: .loggedByYou)])
        let judged = judgement(guess: .intimacy)
            .reviewed(correction: .stress, confirmed: false, at: now)
            .redetected(as: event)
        XCTAssertEqual(judged.guess, .caffeine, "the guess follows the detector")
        XCTAssertEqual(judged.correction, .stress, "the reader's answer does not")
    }

    /// The drift rule, copied from `CalendarEventJudgement`: surfaced, never
    /// resolved by the thing that refreshes the snapshot.
    func testAnAnswerAboutAWindowThatHasMovedIsSurfaced() {
        let start = evening(daysAgo: 1, from: now)
        let evidence = FlagEvidence(peak: 105, typical: 65, spread: 5,
                                    referenceDays: 28, stepsInWindow: 0, sampleCount: 6)
        let original = FlaggedEvent(id: "e1", start: start,
                                    end: start.addingTimeInterval(1200),
                                    trigger: .restingHeartRateElevation, evidence: evidence)
        let grown = FlaggedEvent(id: "e1", start: start,
                                 end: start.addingTimeInterval(3000),
                                 trigger: .restingHeartRateElevation, evidence: evidence)

        let answered = FlaggedEventJudgement(pending: original)
            .reviewed(correction: .stress, confirmed: false, at: now)
        XCTAssertTrue(answered.artifact!.differs(from: grown))

        let feed = EventConfirmationFeed.assemble(events: [grown], judgements: [answered],
                                                  historyGate: nil, now: now)
        XCTAssertEqual(feed.needingRereview.count, 1)
        XCTAssertTrue(feed.answered.isEmpty)
        // And the flag survives the re-detection that refreshed the snapshot,
        // which is the whole reason it is stored rather than derived.
        XCTAssertTrue(feed.needingRereview[0].judgement.needsRereview)
    }

    // MARK: - Accuracy

    private func answered(_ index: Int, guess: EventCause,
                          correction: EventCause?) -> FlaggedEventJudgement {
        FlaggedEventJudgement(eventID: "e\(index)", guess: guess)
            .reviewed(correction: correction, confirmed: correction == nil, at: now)
    }

    func testAccuracyRefusesAFigureBelowTenReviews() {
        let judgements = (0..<9).map { answered($0, guess: .stress, correction: nil) }
        let accuracy = FlaggedEventAccuracy.measure(judgements)
        XCTAssertEqual(accuracy.scored, 9)
        XCTAssertNil(accuracy.rate, "nine reviews is not an accuracy figure")
        let gate = try! XCTUnwrap(accuracy.gate)
        XCTAssertEqual(gate.remaining, 1)
        XCTAssertTrue(accuracy.sentence.contains("1 more"))
    }

    func testAccuracyOffersAFigureAtTenAndCarriesItsDenominator() {
        var judgements = (0..<7).map { answered($0, guess: .stress, correction: nil) }
        judgements += (7..<10).map { answered($0, guess: .stress, correction: .intimacy) }
        let accuracy = FlaggedEventAccuracy.measure(judgements)
        XCTAssertEqual(accuracy.rate, 0.7)
        XCTAssertNil(accuracy.gate)
        XCTAssertTrue(accuracy.sentence.contains("70%"))
        XCTAssertTrue(accuracy.sentence.contains("10 answered"),
                      "a rate without its denominator is not a rate")
    }

    /// An answer the app had no guess for is neither a hit nor a miss.
    func testAnAnswerWithNoGuessIsReportedSeparately() {
        var judgements = (0..<3).map { answered($0, guess: .stress, correction: nil) }
        judgements.append(FlaggedEventJudgement(eventID: "x", guess: nil)
            .reviewed(correction: .travel, confirmed: false, at: now))
        let accuracy = FlaggedEventAccuracy.measure(judgements)
        XCTAssertEqual(accuracy.scored, 3)
        XCTAssertEqual(accuracy.answeredWithoutAGuess, 1)
    }

    /// An answered event whose window stops detecting still counts — otherwise
    /// every threshold change quietly shrinks the denominator.
    func testAnAnsweredEventWithNoLiveWindowStillCounts() {
        let judgements = (0..<10).map { answered($0, guess: .stress, correction: nil) }
        let feed = EventConfirmationFeed.assemble(events: [], judgements: judgements,
                                                  historyGate: nil, now: now)
        XCTAssertEqual(feed.accuracy.scored, 10)
        XCTAssertNotNil(feed.accuracy.rate)
    }

    // MARK: - The feed

    func testPendingAndAnsweredAreSeparated() {
        let evidence = FlagEvidence(peak: 105, typical: 65, spread: 5,
                                    referenceDays: 28, stepsInWindow: 0, sampleCount: 6)
        let events = (0..<3).map { index in
            FlaggedEvent(id: "e\(index)",
                         start: evening(daysAgo: index + 1, from: now),
                         end: evening(daysAgo: index + 1, from: now).addingTimeInterval(1800),
                         trigger: .restingHeartRateElevation, evidence: evidence)
        }
        let answeredOne = FlaggedEventJudgement(pending: events[1])
            .reviewed(correction: .stress, confirmed: false, at: now)

        let feed = EventConfirmationFeed.assemble(events: events, judgements: [answeredOne],
                                                  historyGate: nil, now: now)
        XCTAssertEqual(feed.pending.map(\.id), ["e0", "e2"])
        XCTAssertEqual(feed.answered.map(\.id), ["e1"])
    }

    /// Rule 7: an empty surface says what it is waiting for.
    func testAnEmptyFeedSaysWhatItIsWaitingFor() {
        let gate = CoverageGate(need: 14, have: 3, unit: "day of heart-rate history",
                                unlocks: "the app can tell an unusual half-hour from an ordinary one")
        let waiting = EventConfirmationFeed(pending: [], answered: [], needingRereview: [],
                                            accuracy: .measure([]), gate: gate)
        XCTAssertTrue(waiting.emptyMessage(access: .always).contains("11 more"))

        let ready = EventConfirmationFeed(pending: [], answered: [], needingRereview: [],
                                          accuracy: .measure([]), gate: nil)
        let message = ready.emptyMessage(access: .notAsked)
        XCTAssertTrue(message.contains("watching"))
        XCTAssertTrue(message.contains("Location is off"),
                      "an absent permission is part of what the empty state has to say")
    }

    // MARK: - Place: the reader's conditions

    func testACoordinateIsRoundedOnTheWayIn() {
        let precise = CoarseCoordinate(rounding: -33.865143, longitude: 151.209900)
        XCTAssertNotEqual(precise.latitude, -33.865143)
        XCTAssertEqual(precise.precisionMetres, CoarseCoordinate.defaultPrecisionMetres)
        // Whatever it snapped to, it must be inside the cell it claims.
        let exact = CoarseCoordinate(alreadyRoundedLatitude: -33.865143,
                                     longitude: 151.209900,
                                     precisionMetres: 0)
        XCTAssertLessThanOrEqual(precise.metres(to: exact), precise.precisionMetres)
    }

    /// The rounding has to be square on the ground, or `precisionMetres` is a
    /// claim the data does not support — this app's standing rule about stated
    /// uncertainty.
    func testTheCellIsSquareOnTheGroundAtHighLatitude() {
        // At 60° N a degree of longitude is half a degree of latitude on the
        // ground. Walk east until the rounding lands on the next cell, and check
        // that step is 250 m rather than the ~125 m a fixed decimal step would
        // give — which is the discrepancy that would make `precisionMetres` a
        // claim the data does not support.
        let origin = CoarseCoordinate(rounding: 60, longitude: 0, toMetres: 250)
        var eastward = origin
        var degrees = 0.0
        while eastward.longitude == origin.longitude, degrees < 1 {
            degrees += 0.0001
            eastward = CoarseCoordinate(rounding: 60, longitude: degrees, toMetres: 250)
        }
        XCTAssertNotEqual(eastward.longitude, origin.longitude, "never crossed a cell edge")
        XCTAssertEqual(origin.metres(to: eastward), 250, accuracy: 30)

        // And the same walk northward gives the same ground distance, which is
        // what "square on the ground" means.
        var northward = origin
        degrees = 60
        while northward.latitude == origin.latitude, degrees < 61 {
            degrees += 0.0001
            northward = CoarseCoordinate(rounding: degrees, longitude: 0, toMetres: 250)
        }
        XCTAssertEqual(origin.metres(to: northward), 250, accuracy: 30)
    }

    func testAnsweringForgetsThePosition() {
        let place = PlaceContext(familiarity: .usual,
                                 coordinate: CoarseCoordinate(rounding: -33.86, longitude: 151.2),
                                 capture: .visit, capturedAt: now)
        XCTAssertTrue(place.canDrawMap)
        let forgotten = place.forgettingCoordinate()
        XCTAssertNil(forgotten.coordinate)
        XCTAssertNil(forgotten.capturedAt, "the time of a fix locates too, once it is all that is left")
        XCTAssertEqual(forgotten.familiarity, .usual, "the comparison survives; the position does not")
    }

    func testRetentionDropsPositionsOnAnsweredAndOnExpiredEvents() {
        let evidence = FlagEvidence(peak: 105, typical: 65, spread: 5,
                                    referenceDays: 28, stepsInWindow: 0, sampleCount: 6)
        func event(_ id: String, daysAgo: Int) -> FlaggedEvent {
            let start = evening(daysAgo: daysAgo, from: now)
            return FlaggedEvent(id: id, start: start, end: start.addingTimeInterval(1800),
                                trigger: .restingHeartRateElevation, evidence: evidence,
                                place: PlaceContext(familiarity: .usual,
                                                    coordinate: CoarseCoordinate(rounding: -33.86,
                                                                                 longitude: 151.2),
                                                    capture: .visit, capturedAt: start))
        }
        let swept = FlaggedEventRetention.sweep(
            events: [event("fresh", daysAgo: 1),
                     event("answered", daysAgo: 1),
                     event("stale", daysAgo: 30),
                     event("ancient", daysAgo: 90)],
            answeredIDs: ["answered"], now: now, calendar: calendar)

        let byID = Dictionary(uniqueKeysWithValues: swept.map { ($0.id, $0) })
        XCTAssertNotNil(byID["fresh"]?.place.coordinate, "an unanswered question keeps its map")
        XCTAssertNil(byID["answered"]?.place.coordinate)
        XCTAssertNil(byID["stale"]?.place.coordinate)
        XCTAssertNil(byID["ancient"], "past the question lifetime it is dropped entirely")
        XCTAssertEqual(byID["answered"]?.place.familiarity, .usual)
    }

    // MARK: - Anchors

    private func anchorSet(places: Int, visitsEach: Int) -> PlaceAnchorSet {
        var set = PlaceAnchorSet()
        for place in 0..<places {
            let cell = CoarseCoordinate(rounding: -33.86 + Double(place) * 0.05,
                                        longitude: 151.2)
            for _ in 0..<visitsEach { set = set.noting(cell, on: now, calendar: calendar) }
        }
        return set
    }

    func testFamiliarityRefusesToJudgeOnTooFewAnchors() {
        let set = anchorSet(places: 2, visitsEach: 20)
        let elsewhere = CoarseCoordinate(rounding: -34.5, longitude: 150.0)
        XCTAssertEqual(set.familiarity(of: elsewhere), .unknown,
                       "two anchors make 'unusual' true of the whole planet")
    }

    func testFamiliaritySeparatesUsualFromOccasionalFromUnfamiliar() {
        var set = anchorSet(places: 4, visitsEach: 1)
        let home = CoarseCoordinate(rounding: -33.86, longitude: 151.2)
        for _ in 0..<PlaceAnchorSet.usualVisitFloor {
            set = set.noting(home, on: now, calendar: calendar)
        }
        XCTAssertEqual(set.familiarity(of: home), .usual)
        // The second anchor `anchorSet` laid down — visited once, so known but
        // not a habit. (It steps *up* in latitude; querying -33.91 tested a cell
        // that was never an anchor and passed nothing but the fixture's own
        // arithmetic.)
        XCTAssertEqual(set.familiarity(of: CoarseCoordinate(rounding: -33.81, longitude: 151.2)),
                       .occasional)
        XCTAssertEqual(set.familiarity(of: CoarseCoordinate(rounding: -34.9, longitude: 150.0)),
                       .unfamiliar)
    }

    /// The cap is the privacy control: an uncapped set of visited cells is a
    /// location history with the times filed off.
    func testTheAnchorSetIsCappedAndForgetsTheLeastVisited() {
        var set = PlaceAnchorSet()
        for place in 0..<(PlaceAnchorSet.maximumAnchors + 5) {
            let cell = CoarseCoordinate(rounding: -33.0 + Double(place) * 0.05, longitude: 151.2)
            // The first place is visited often; the rest once each.
            for _ in 0..<(place == 0 ? 20 : 1) {
                set = set.noting(cell, on: now, calendar: calendar)
            }
        }
        XCTAssertEqual(set.anchors.count, PlaceAnchorSet.maximumAnchors)
        let frequent = CoarseCoordinate(rounding: -33.0, longitude: 151.2)
        XCTAssertEqual(set.familiarity(of: frequent), .usual,
                       "the habit survives the cap; the one-offs are what get forgotten")
    }

    func testNearbyFixesFoldIntoOneAnchorRatherThanBreeding() {
        var set = PlaceAnchorSet()
        let home = CoarseCoordinate(rounding: -33.860, longitude: 151.200)
        // A few metres away — the same kitchen, a different cell.
        let alsoHome = CoarseCoordinate(rounding: -33.8615, longitude: 151.2005)
        set = set.noting(home, on: now, calendar: calendar)
        set = set.noting(alsoHome, on: now, calendar: calendar)
        XCTAssertEqual(set.anchors.count, 1)
        XCTAssertEqual(set.anchors[0].visits, 2)
    }

    func testAnchorsCarryOnlyADayResolutionTimestamp() {
        let set = PlaceAnchorSet().noting(CoarseCoordinate(rounding: -33.86, longitude: 151.2),
                                          on: now, calendar: calendar)
        XCTAssertEqual(set.anchors[0].lastSeenDay, calendar.startOfDay(for: now),
                       "a precise time beside a coarse cell re-introduces what the rounding removed")
    }

    // MARK: - Permission, and the suggestion the reader made a condition

    func testTheLocationRowAppearsOnlyWhileAskingCouldChangeSomething() {
        XCTAssertEqual(SuggestionEngine.locationPermission(access: .notAsked).count, 1)
        XCTAssertTrue(SuggestionEngine.locationPermission(access: .denied).isEmpty,
                      "iOS will not re-prompt, so this would be a nag")
        XCTAssertTrue(SuggestionEngine.locationPermission(access: .whileUsing).isEmpty)
        XCTAssertTrue(SuggestionEngine.locationPermission(access: .always).isEmpty)
        XCTAssertTrue(SuggestionEngine.locationPermission(access: .unavailable).isEmpty)
    }

    /// The row must not claim the feature needs the permission. It does not.
    func testTheLocationRowSaysTheFeatureWorksWithoutIt() {
        let row = try! XCTUnwrap(SuggestionEngine.locationPermission(access: .notAsked).first)
        XCTAssertTrue(row.detail.contains("Everything works without it"))
        XCTAssertTrue(row.detail.lowercased().contains("never builds a location history"))
        // Weakest thing in the list: a permission ask must never outrank a
        // finding about the reader's own data.
        XCTAssertLessThan(row.strength, 0.15)
    }

    func testTheWaitingQueueRaisesOneRowCarryingACount() {
        XCTAssertTrue(SuggestionEngine.eventsAwaitingReview(count: 0).isEmpty)
        let rows = SuggestionEngine.eventsAwaitingReview(count: 4)
        XCTAssertEqual(rows.count, 1, "one row for the queue, not one per event")
        XCTAssertTrue(rows[0].title.contains("4 flagged moments"))
        // Stable across counts, so a dismissal is not undone by a fifth event.
        XCTAssertEqual(rows[0].id, SuggestionEngine.eventsAwaitingReview(count: 9)[0].id)
        XCTAssertGreaterThan(rows[0].strength,
                             SuggestionEngine.locationPermission(access: .notAsked)[0].strength)
    }

    // MARK: - Export

    func testTheExportCarriesTheGuessAndTheAnswerButNoPlaceOrNote() throws {
        let start = evening(daysAgo: 1, from: now)
        let artifact = FlaggedEventArtifact(
            start: start, end: start.addingTimeInterval(1800),
            trigger: .restingHeartRateElevation,
            evidence: FlagEvidence(peak: 105, typical: 65, spread: 5,
                                   referenceDays: 28, stepsInWindow: 0, sampleCount: 6),
            placeFamiliarity: .usual, candidates: [],
            modelVersion: FlaggedEventDetector.modelVersion)
        let judged = FlaggedEventJudgement(eventID: "e1", guess: .intimacy,
                                           correction: .stress,
                                           note: "argument with the landlord",
                                           artifact: artifact,
                                           isConfirmed: false, reviewedAt: now)
        let row = try XCTUnwrap(HealthDataExport.FlaggedEventExport(judged, calendar: calendar))
        XCTAssertEqual(row.guess, "intimacy")
        XCTAssertEqual(row.answer, "stress")
        XCTAssertEqual(row.placeFamiliarity, "usual")
        XCTAssertEqual(row.day, calendar.startOfDay(for: start))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(row), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("landlord"), "the reader's own words stay on the phone")
        XCTAssertFalse(json.lowercased().contains("latitude"))
        XCTAssertFalse(json.lowercased().contains("coordinate"))
        // Every key present, including the nullable ones — the file must be able
        // to say "no answer yet" rather than omitting the key.
        for key in ["day", "minutes", "trigger", "departures", "referenceDays",
                    "stepsInWindow", "placeFamiliarity", "guess", "answer",
                    "confirmed", "modelVersion"] {
            XCTAssertTrue(json.contains("\"\(key)\""), "missing \(key)")
        }
    }

    func testAJudgementWithNoSnapshotDoesNotInventOne() {
        let judged = FlaggedEventJudgement(eventID: "e1", guess: .stress)
        XCTAssertNil(HealthDataExport.FlaggedEventExport(judged, calendar: calendar))
    }

    func testTheDomainNamesItsExportKey() {
        XCTAssertEqual(HealthDataExport.exportKey(for: .flaggedEvents), "flaggedEvents")
    }
}
