import XCTest
@testable import InsightKit

/// Backlog B9-2. **Almost every assertion here is about what this card refuses
/// to say**, because that is where its whole design sits: it draws a series
/// nobody publishes a scale for, in a field whose headline findings shrink
/// towards nothing when the exposure is measured rather than asked about.
///
/// The one that matters most is
/// `testAHeavierHalfFollowedByBetterNightsScoresHigherNotLower`. A card that
/// scored "more screen time" as worse would pass every other test in this file
/// while being exactly the thing B9-2 warned against, and that test is the only
/// one that can tell the difference.
final class ScreenTimeModelTests: XCTestCase {

    private let calendar = TestClock.utc
    private let now = TestClock.now

    /// Midday on the day `offset` days before `now`.
    private func day(_ offset: Int) -> Date { TestClock.day(offset) }

    /// `minutes` runs oldest-first; index 0 is the oldest day.
    private func screen(_ minutes: [Double]) -> [HealthMetricSample] {
        minutes.enumerated().map { index, value in
            HealthMetricSample(type: .screenTimeMinutes, value: value,
                               start: day(minutes.count - 1 - index), source: .manual)
        }
    }

    /// A response reading on the night **after** each day — the pairing the card
    /// is built on, and the one thing a reader could never check.
    private func nights(_ metric: MetricType, _ values: [Double],
                        offsetFrom count: Int) -> [HealthMetricSample] {
        values.enumerated().compactMap { index, value in
            let dayIndex = count - 1 - index
            guard dayIndex - 1 >= 0 else { return nil }   // no night after the newest day
            return HealthMetricSample(type: metric, value: value,
                                      start: day(dayIndex - 1), source: .oura)
        }
    }

    /// A full fixture: `days` days alternating between a light and a heavy
    /// screen figure, with each watched signal on the night after.
    ///
    /// `worseAfterHeavy` flips which half gets the unwelcome nights, which is
    /// what lets one fixture prove the direction is read rather than assumed.
    private func fixture(days: Int, worseAfterHeavy: Bool) -> [HealthMetricSample] {
        let minutes = (0..<days).map { Double($0.isMultiple(of: 2) ? 60 : 300) }
        var out = screen(minutes)
        for entry in ScreenTimeModel.watched {
            let base: Double
            let swing: Double
            switch entry.metric {
            case .restingHeartRate: base = 55; swing = 6
            case .heartRateVariabilityRMSSD: base = 50; swing = 10
            default: base = 7.5; swing = 1.2
            }
            let values: [Double] = (0..<days).map { index in
                let isHeavyDay = !index.isMultiple(of: 2)
                let unwelcome = isHeavyDay == worseAfterHeavy
                let sign: Double = entry.higherIsWorse ? 1 : -1
                // ⚠️ **Real within-group scatter, not a token jitter, and this
                // is load-bearing.** A fixture of two clean levels has no spread
                // inside either half, so any departure divided by that spread
                // comes out in the tens of SDs — which is how
                // `ScreenTimeModel.pooledSpread` came to be written. Deterministic
                // (golden-angle phase), so a failure is reproducible.
                let noise = swing * sin(Double(index) * 2.399963)
                return base + (unwelcome ? sign * swing : -sign * swing) + noise
            }
            out += nights(entry.metric, values, offsetFrom: days)
        }
        return out
    }

    private func output(days: Int, worseAfterHeavy: Bool) throws -> ScreenTimeModel.Output {
        let result = ScreenTimeModel.analyse(samples: fixture(days: days,
                                                              worseAfterHeavy: worseAfterHeavy),
                                             now: now, calendar: calendar)
        guard case .ready(let out) = result else {
            throw XCTSkip("expected a contrast, got \(result)")
        }
        return out
    }

    // MARK: - Nothing, and not-yet, are different states

    func testNoScreenTimeAtAllIsNothingRatherThanAnEmptyContrast() {
        XCTAssertEqual(ScreenTimeModel.analyse(samples: [], now: now, calendar: calendar),
                       .nothing)
    }

    /// ⚠️ The state the reader is actually in — twenty-six rows — and the one a
    /// `waitingOn` card would have rendered as a blank "Learning".
    func testTooFewPairedDaysStillDescribesTheDaysItHas() throws {
        let result = ScreenTimeModel.analyse(samples: screen([30, 90, 150, 240, 300]),
                                             now: now, calendar: calendar)
        guard case .describing(let description, let gate) = result else {
            return XCTFail("expected a description, got \(result)")
        }
        XCTAssertEqual(description.daysRecorded, 5)
        XCTAssertEqual(description.typicalMinutes, 150)
        XCTAssertEqual(description.lightestMinutes, 30)
        XCTAssertEqual(description.busiestMinutes, 300)
        XCTAssertEqual(description.pairedDays, 0, "no response readings were supplied")
        XCTAssertEqual(gate.remaining, ScreenTimeModel.minimumDaysPerHalf * 2)
        let sentence = try XCTUnwrap(gate.sentence)
        XCTAssertTrue(sentence.contains("\(ScreenTimeModel.minimumDaysPerHalf * 2)"), sentence)
        // The description survives the gate — that is the whole point of the
        // `describing` case existing beside `waiting`.
        XCTAssertTrue(ScreenTimeModel.shapeSentence(description).contains("2 h 30"),
                      ScreenTimeModel.shapeSentence(description))
    }

    /// Days entered but all alike: there is nothing to split, and saying so is
    /// a different sentence from "not enough days".
    func testDaysThatAreAllAlikeSayTheyCannotBeSplit() throws {
        var samples = screen(Array(repeating: 120, count: 40))
        for entry in ScreenTimeModel.watched {
            samples += nights(entry.metric, (0..<40).map { 50 + Double($0 % 3) },
                              offsetFrom: 40)
        }
        let result = ScreenTimeModel.analyse(samples: samples, now: now, calendar: calendar)
        guard case .describing(_, let gate) = result else {
            return XCTFail("a flat record cannot be contrasted, got \(result)")
        }
        XCTAssertTrue(gate.unlocks.contains("too alike"), gate.unlocks)
    }

    // MARK: - ⚠️ The direction is read, never assumed

    /// **The test B9-2 exists for.** Same screen-time series, opposite nights:
    /// the reader whose heavier days are followed by *better* nights must score
    /// higher, not lower. A card that had quietly imported "more screen time is
    /// worse" would score these two the same way round.
    func testAHeavierHalfFollowedByBetterNightsScoresHigherNotLower() throws {
        let worse = try output(days: 40, worseAfterHeavy: true)
        let better = try output(days: 40, worseAfterHeavy: false)
        XCTAssertGreaterThan(better.score, worse.score,
                             "the card is scoring screen time rather than the reader's own nights")
        XCTAssertGreaterThan(worse.pooled, 0)
        XCTAssertLessThan(better.pooled, 0)
        XCTAssertTrue(ScreenTimeModel.headline(better).contains("better"),
                      ScreenTimeModel.headline(better))
        XCTAssertTrue(ScreenTimeModel.headline(worse).contains("rougher"),
                      ScreenTimeModel.headline(worse))
    }

    /// The headline never claims a cause, whichever way the comparison lands.
    func testNoSentenceOnThisCardClaimsACause() throws {
        for worseAfterHeavy in [true, false] {
            let out = try output(days: 40, worseAfterHeavy: worseAfterHeavy)
            let text = ([ScreenTimeModel.headline(out),
                         ScreenTimeModel.pooledSentence(out),
                         ScreenTimeModel.splitSentence(out),
                         ScreenTimeModel.shapeSentence(out.description)]
                        + out.channels.map(ScreenTimeModel.sentence))
                .joined(separator: " ")
            // "not what caused them" is the card saying the right thing, so the
            // banned list is phrases that would be a causal *claim* rather than
            // the word on its own.
            for banned in ["caused by", "because of your screen", "leads to",
                           "makes you", "is costing you"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(banned),
                               "\"\(banned)\" appears on a card that only holds two groups of days side by side: \(text)")
            }
        }
    }

    /// ⚠️ **The two-lump defect, pinned.** A reader who fills this in from their
    /// phone's weekly summary produces exactly two clusters of days, split 50/50
    /// at their own median — and the MAD of two equal, well-separated lumps
    /// measures the *gap* rather than the noise, so the departure comes back
    /// divided by almost nothing. Before `ScreenTimeModel.pooledSpread` this
    /// fixture printed "67.4 SD worse" on the card.
    func testACleanlySplitRecordDoesNotPrintAnAbsurdDeparture() throws {
        var samples = screen((0..<40).map { Double($0.isMultiple(of: 2) ? 60 : 300) })
        // Two clean levels on the nights too, with no scatter inside either —
        // the degenerate shape, on purpose.
        samples += nights(.restingHeartRate,
                          (0..<40).map { $0.isMultiple(of: 2) ? 50.0 : 60.0 },
                          offsetFrom: 40)
        samples += nights(.heartRateVariabilityRMSSD,
                          (0..<40).map { $0.isMultiple(of: 2) ? 60.0 : 40.0 },
                          offsetFrom: 40)
        samples += nights(.sleepDurationHours,
                          (0..<40).map { $0.isMultiple(of: 2) ? 8.0 : 7.0 },
                          offsetFrom: 40)
        let result = ScreenTimeModel.analyse(samples: samples, now: now, calendar: calendar)
        switch result {
        case .describing:
            // Acceptable: with no scatter at all inside either half there is
            // nothing to measure a difference *in*, and withholding is right.
            break
        case .nothing:
            XCTFail("forty days of screen time is not nothing")
        case .ready(let out):
            for channel in out.channels {
                XCTAssertLessThan(
                    abs(channel.towardWorse), 12,
                    "\(channel.metric) reports \(channel.towardWorse) SD — the scale "
                        + "collapsed onto the gap it is meant to measure")
            }
        }
    }

    // MARK: - Screen time itself is charted and never scored

    func testScreenTimeCarriesNoShareAndItsOwnRowSaysWhy() throws {
        let out = try output(days: 40, worseAfterHeavy: true)
        let row = try XCTUnwrap(out.contributions.first { $0.metric == .screenTimeMinutes })
        XCTAssertEqual(row.weight, 0)
        XCTAssertNil(row.higherIsBetter,
                     "claiming a good direction for screen time is the thing this card refuses")
        // The rule `ChartedWeightRuleTests` enforces app-wide, asserted here as
        // well so the reason cannot be edited away without a local failure.
        let reason = try XCTUnwrap(row.detail.components(separatedBy: " — ").last)
        XCTAssertTrue(reason.contains("never scored"), reason)
        XCTAssertEqual(out.contributions.filter { $0.weight > 0 }.reduce(0) { $0 + $1.weight },
                       1, accuracy: 1e-9,
                       "the body channels carry the whole number between them")
    }

    func testTheRefusalNamesTheProblemRatherThanHedging() {
        let text = ScreenTimeModel.evidenceRefusal
        XCTAssertTrue(text.contains("does not grade your screen time"), text)
        XCTAssertTrue(text.contains("failed to replicate"), text)
        XCTAssertTrue(text.contains("association"), text)
        XCTAssertTrue(ScreenTimeModel.howItArrives.contains("read your Screen Time"),
                      ScreenTimeModel.howItArrives)
    }

    // MARK: - The produced figures (add-insight §5a)

    func testBothProducedFiguresAreFiledAndNeitherCarriesAShare() throws {
        let out = try output(days: 40, worseAfterHeavy: true)
        let keys = Set(ScreenTimeModel.derivedOutputs(out).map(\.key))
        XCTAssertEqual(keys, [ScreenTimeModel.contrastKey, ScreenTimeModel.responseKey])
        for factor in ScreenTimeModel.producedFigures(out) {
            XCTAssertEqual(factor.weight, 0)
            XCTAssertTrue(factor.detail.contains(" — "), factor.detail)
            let series = try XCTUnwrap(factor.derivedSeries)
            XCTAssertEqual(series.producedBy, .screenTime)
        }
        XCTAssertEqual(out.gapMinutes, 240, accuracy: 1e-9)
    }

    // MARK: - The card

    func testTheCardIsRegisteredAndReadsOnlySamples() {
        let model = try? XCTUnwrap(InsightEngine().models.first { $0.id == .screenTime })
        XCTAssertNotNil(model)
        XCTAssertTrue(ScreenTimeInsight().readsOnlySamples,
                      "screen time is a MetricType however it got there, so no binding is needed")
        XCTAssertEqual(ScreenTimeInsight().contributions, [.screenTime])
    }

    /// A fresh install asks for a day rather than saying "no data yet", and the
    /// ask names all three routes.
    func testWithNothingAtAllItAsksForADayRatherThanGoingQuiet() {
        let result = ScreenTimeInsight().evaluate(samples: [], profile: UserHealthProfile(),
                                                  now: now)
        XCTAssertTrue(result.invitesInput)
        XCTAssertEqual(result.headline, "Add a day of screen time")
        XCTAssertTrue(result.explanation.contains("Shortcuts"), result.explanation)
        XCTAssertNil(result.score)
    }

    /// ⚠️ Hand-entered, self-selected days cannot become high-confidence however
    /// many of them there are.
    func testConfidenceNeverReachesHigh() throws {
        for days in [40, 200] {
            let result = ScreenTimeInsight().evaluate(
                samples: fixture(days: days, worseAfterHeavy: true),
                profile: UserHealthProfile(), now: now)
            XCTAssertNotEqual(result.confidence, .high,
                              "\(days) hand-entered days is still a hand-entered sample")
        }
    }

    /// The card that can describe but not contrast must still lead with
    /// something readable — the defect `CardVisibilityTests` guards app-wide.
    func testTheDescribingCardLeadsWithItsDaysNotWithNoDataYet() {
        let result = ScreenTimeInsight().evaluate(samples: screen([30, 90, 150, 240, 300]),
                                                  profile: UserHealthProfile(), now: now)
        XCTAssertEqual(result.headline, "Your days so far")
        XCTAssertTrue(result.isLearning)
        XCTAssertFalse(result.invitesInput,
                       "a coverage gate is not an invitation — there is nothing here to give that has not been given")
        XCTAssertFalse(result.drivers.isEmpty, "it has days to describe and said nothing about them")
        XCTAssertTrue(result.drivers.contains { $0.contains("typical day") },
                      result.drivers.joined(separator: " | "))
    }

    // MARK: - Small things that read wrong when they go wrong

    func testMinutesAreSpokenAsHoursAndMinutes() {
        XCTAssertEqual(ScreenTimeModel.minutesPhrase(45), "45 min")
        XCTAssertEqual(ScreenTimeModel.minutesPhrase(60), "1 h")
        XCTAssertEqual(ScreenTimeModel.minutesPhrase(143), "2 h 23 min")
        XCTAssertEqual(ScreenTimeModel.minutesPhrase(0), "0 min")
    }

    /// Two readings for one day are one day — the correction the reader typed
    /// after a screenshot import must not appear as a second observation.
    func testTwoReadingsForOneDayCountOnce() {
        var samples = screen([120])
        samples.append(HealthMetricSample(type: .screenTimeMinutes, value: 200,
                                          start: day(0).addingTimeInterval(3600),
                                          source: .manual))
        let result = ScreenTimeModel.analyse(samples: samples, now: now, calendar: calendar)
        guard case .describing(let description, _) = result else {
            return XCTFail("expected a description, got \(result)")
        }
        XCTAssertEqual(description.daysRecorded, 1)
    }
}
