import XCTest
@testable import InsightKit

/// The mental health card.
///
/// **Most of these pin honesty rather than arithmetic**, because the objection
/// that kept this card unbuilt for months was never about the maths. It was
/// *"'you seem fine' arriving by arithmetic to someone having a bad month is the
/// worst available failure"* — which is true, is a design constraint rather than
/// a reason to refuse, and is only a constraint if something enforces it.
final class MentalHealthTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// A season of steady behaviour, with the last `shiftedDays` moved by the
    /// given fractions. Negative shifts mean less of the thing.
    private func record(shiftedDays: Int = 0, steps: Double = 0, exercise: Double = 0,
                        bedtime: Double = 0, hrv: Double = 0) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let jitter: [Double] = [0, 0.03, -0.02, 0.04, -0.03, 0.01, -0.04, 0.02, -0.01, 0.03]
        for day in 0..<200 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            let shifted = day < shiftedDays
            let n = jitter[day % jitter.count]
            func add(_ type: MetricType, _ value: Double) {
                out.append(HealthMetricSample(type: type, value: value,
                                              start: date, end: date, source: .appleHealth))
            }
            add(.stepCount, 9000 * (1 + n) + (shifted ? steps : 0))
            add(.exerciseMinutes, 30 * (1 + n) + (shifted ? exercise : 0))
            // Hours from local midnight, negative before it — so a *larger*
            // value is a later bedtime.
            add(.sleepOnset, -1.5 + n + (shifted ? bedtime : 0))
            add(.heartRateVariabilityRMSSD, 45 * (1 + n) + (shifted ? hrv : 0))
        }
        return out
    }

    // MARK: - The honesty rules

    /// ⚠️ **The rule the whole card exists under.** With nothing moved, the copy
    /// must be about the measurements and must say, in words, that the reader
    /// outranks it. A card that says "you're doing well" here is the failure the
    /// refusal named.
    func testWithNothingMovedItTalksAboutTheMeasurementsAndNotAboutThePerson() throws {
        let result = MentalHealthInsight().evaluate(
            samples: record(), profile: UserHealthProfile(), now: now)
        let lead = try XCTUnwrap(result.drivers.first).lowercased()

        XCTAssertTrue(lead.contains("step count") || lead.contains("statement about"),
                      "the empty case must name what it actually looked at: \(lead)")
        XCTAssertTrue(lead.contains("not about how you"),
                      "it must disclaim the thing it cannot see: \(lead)")
        for banned in ["you are fine", "you're fine", "you seem fine", "doing well",
                       "you are well", "no concerns", "nothing to worry"] {
            XCTAssertFalse(result.drivers.joined(separator: " ").lowercased().contains(banned),
                           "this card reassured, which is the one thing it may never do: \(banned)")
        }
    }

    /// It makes no diagnostic claim anywhere — not in a headline, not in a
    /// band, not in an explanation.
    ///
    /// ⚠️ **Checked per sentence, not per card**, and the first version of this
    /// test got that wrong: it banned the substring "diagnos" outright and
    /// failed on *the card's own disclaimer* — "it does not diagnose anything
    /// and it cannot". Forbidding a word forbids denying it too, which would
    /// have forced the card to be less clear about its limits in order to pass
    /// the test that exists to keep it honest. The rule is that a diagnostic
    /// word may appear only in a sentence that negates it.
    func testItNeverMakesADiagnosticClaim() {
        let cases = [record(), record(shiftedDays: 14, steps: -5000, exercise: -25,
                                      bedtime: 2.0, hrv: -18)]
        for samples in cases {
            let result = MentalHealthInsight().evaluate(
                samples: samples, profile: UserHealthProfile(), now: now)
            let sentences = ([result.headline, result.explanation] + result.drivers)
                .joined(separator: " ")
                .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            for sentence in sentences {
                let lower = sentence.lowercased()
                for banned in ["depress", "anxiet", "anxious", "disorder", "diagnos",
                               "symptom of", "mental illness", "screen for"] {
                    guard lower.contains(banned) else { continue }
                    XCTAssertTrue(lower.contains("not") || lower.contains("cannot")
                                    || lower.contains("never"),
                                  "\"\(banned)\" is used as a claim rather than denied: \(sentence)")
                }
            }
        }
    }

    /// **The dial cannot certify a good fortnight.** Its top is well below 100,
    /// because "none of these four moved" is a much smaller claim than "you are
    /// well" and the number has to reflect the smaller one.
    func testTheDialCannotCertifyAGoodFortnight() {
        let best = MentalHealthModel.score(pooled: -3)
        XCTAssertLessThan(best, 85,
                          "a dial at or near 100 on this card is a clean bill of mental health, which nothing here can issue")
        XCTAssertGreaterThan(best, MentalHealthModel.score(pooled: 2),
                             "and it must still be directional")
    }

    /// Every channel carries the ordinary explanation that has nothing to do
    /// with mood. Without it the card invites a conclusion its data cannot
    /// support.
    func testEveryChannelNamesItsAlternativeExplanation() {
        for channel in MentalHealthModel.channels {
            XCTAssertFalse(channel.alternative.isEmpty,
                           "\(channel.metric) is reported with no innocent explanation beside it")
        }
    }

    /// ⚠️ **The copy never names a behaviour it did not read.**
    ///
    /// Found on a screenshot: the card said "None of the four has moved" while
    /// running on three channels, and its empty-state line named all four
    /// behaviours by hand — including the one it had no data for. The repo's own
    /// ledger has "a hard-coded count going stale" at four-plus sessions; this
    /// is that fault inside a sentence rather than inside a document, and it is
    /// worse there, because the sentence is a claim about what was looked at.
    func testTheCopyNeverNamesABehaviourItDidNotRead() {
        let samples = record().filter {
            $0.type != .exerciseMinutes && $0.type != .heartRateVariabilityRMSSD
        }
        let result = MentalHealthInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: now)
        let lead = result.drivers.first ?? ""

        XCTAssertFalse(lead.contains("four"),
                       "a count was written out rather than derived: \(lead)")
        XCTAssertFalse(lead.lowercased().contains("deliberate exercise"),
                       "the lead sentence named a behaviour with no data behind it: \(lead)")
        XCTAssertTrue(lead.lowercased().contains("moving around"),
                      "and it must name the ones it did read: \(lead)")
    }

    // MARK: - The arithmetic

    /// Four unrelated behaviours moving the same way is the only thing this card
    /// claims to notice, and it has to actually notice it.
    func testAFortnightOfWithdrawalMovesTheNumber() throws {
        let steady = MentalHealthModel.evaluate(samples: record(), now: now, calendar: utc)
        let withdrawn = try XCTUnwrap(MentalHealthModel.evaluate(
            samples: record(shiftedDays: 14, steps: -4500, exercise: -20,
                            bedtime: 1.5, hrv: -14),
            now: now, calendar: utc))
        XCTAssertGreaterThan(withdrawn.pooled, 1.0)
        XCTAssertLessThan(withdrawn.score, try XCTUnwrap(steady).score - 15)
        XCTAssertGreaterThanOrEqual(withdrawn.moved.count, 3)
    }

    /// Moving the other way is reported as such and is not scored as trouble.
    func testMovingAwayFromThePatternIsNotReportedAsTrouble() throws {
        let out = try XCTUnwrap(MentalHealthModel.evaluate(
            samples: record(shiftedDays: 14, steps: 4000, exercise: 25,
                            bedtime: -1.2, hrv: 12),
            now: now, calendar: utc))
        XCTAssertLessThan(out.pooled, 0)
        XCTAssertGreaterThan(out.score, 78)
    }

    /// ⚠️ **One channel is a fact about a step count, not a pattern.** The claim
    /// this card is allowed to make needs several signals, so it declines below
    /// two — the same argument as biological age's three-marker floor.
    func testItDeclinesToSpeakOnASingleChannel() {
        var samples: [HealthMetricSample] = []
        for day in 0..<200 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            samples.append(HealthMetricSample(type: .stepCount, value: 9000,
                                              start: date, end: date, source: .appleHealth))
        }
        XCTAssertNil(MentalHealthModel.evaluate(samples: samples, now: now, calendar: utc))
    }

    /// A channel with no data is named at weight 0 rather than dropped, so the
    /// card cannot claim to read something it did not.
    func testAChannelWithNoDataIsNamedRatherThanOmitted() {
        let samples = record().filter { $0.type != .exerciseMinutes }
        let result = MentalHealthInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: now)
        XCTAssertTrue(result.contributors.contains { $0.metric == .exerciseMinutes && $0.weight == 0 },
                      "a declared channel with nothing behind it must still say so")
        XCTAssertTrue(result.drivers.joined(separator: " ").contains("Deliberate exercise"))
    }

    /// The dial must not lurch as the pooled statistic crosses zero.
    func testTheScoreCurveHasNoCliff() {
        var previous = MentalHealthModel.score(pooled: -3)
        for step in stride(from: -3.0, through: 3.0, by: 0.01) {
            let here = MentalHealthModel.score(pooled: step)
            XCTAssertLessThan(abs(here - previous), 1, "the score jumps at \(step)")
            previous = here
        }
    }
}
