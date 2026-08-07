import XCTest
@testable import InsightKit

/// **The occasion, reported — and never scored.**
///
/// `SubstanceHonestyTests` holds the *pooled* card to the reader's ruling. This
/// holds the three sections that render an occasion at a time: the episode
/// explainer (backlog `S7`), the recovery timing and the per-substance
/// good-versus-bad split (backlog `P16`).
///
/// The ruling being enforced, verbatim and standing: **"Honest version,
/// always!"** — per-episode deltas, the named alternative explanation beside
/// each row, **no score**, and the sentence *"nothing has happened the same way
/// often enough to tell it from an ordinary run."*
final class SubstanceEpisodeReportTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func event(_ substance: SubstanceClass, daysAgo: Double) -> SubstanceEvent {
        SubstanceEvent(substance: substance,
                       timestamp: now.addingTimeInterval(-daysAgo * 86_400))
    }

    /// Daily readings across 60 days, raised by `bump` for the 18 hours after
    /// each of `after`. The jitter is deliberate: a flat baseline has no spread
    /// to divide a departure by, and `z` is correctly `nil` there.
    private func readings(_ metric: MetricType, base: Double, bump: Double,
                          after events: [SubstanceEvent],
                          perDay: Int = 4, days: Int = 60) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for day in stride(from: days, through: 0, by: -1) {
            for slot in 0..<perDay {
                let at = now.addingTimeInterval(-Double(day) * 86_400
                                                + Double(slot) * 5 * 3600)
                guard at <= now else { continue }
                let affected = events.contains {
                    let dt = at.timeIntervalSince($0.timestamp)
                    return dt >= 0 && dt <= SubstanceResponseAnalyzer.afterWindow
                }
                // ±1 sawtooth so the clean pool has a real standard deviation.
                let jitter = Double((day + slot) % 3) - 1
                out.append(HealthMetricSample(type: metric,
                                              value: base + jitter + (affected ? bump : 0),
                                              start: at, source: .appleHealth))
            }
        }
        return out
    }

    // MARK: - S7: what an occasion is, shown

    func testThreeDrinksInOneEveningAreOneOccasionWithItsOwnShape() {
        let evening = [event(.alcohol, daysAgo: 5.2), event(.alcohol, daysAgo: 5.15),
                       event(.alcohol, daysAgo: 5.1)]
        let report = SubstanceEpisodeReport.report(events: evening, samples: [],
                                                   now: now, calendar: utc)
        let alcohol = try? XCTUnwrap(report.substances.first)
        XCTAssertEqual(alcohol?.occasions, 1)
        XCTAssertEqual(alcohol?.episodes.first?.shape, .severalClose,
                       "an evening's several drinks must read as one occasion of several entries")
    }

    func testOneEntryIsTheSingleShape() {
        let report = SubstanceEpisodeReport.report(events: [event(.cannabis, daysAgo: 3)],
                                                   samples: [], now: now, calendar: utc)
        XCTAssertEqual(report.substances.first?.episodes.first?.shape, .single)
    }

    /// The evening that runs past midnight. It is two calendar days and one
    /// occasion, and a day-boundary test would have called it a stretch — the
    /// same day-boundary sensitivity that flipped this card's whole finding set
    /// across three time zones.
    func testAnEveningThatCrossesMidnightIsStillJustSeveralCloseTogether() {
        let lateNight = [event(.alcohol, daysAgo: 5.0), event(.alcohol, daysAgo: 4.95),
                         event(.alcohol, daysAgo: 4.9)]
        let report = SubstanceEpisodeReport.report(events: lateNight, samples: [],
                                                   now: now, calendar: utc)
        XCTAssertEqual(report.substances.first?.occasions, 1)
        XCTAssertEqual(report.substances.first?.episodes.first?.shape, .severalClose)
    }

    func testEntriesAcrossMoreThanADayAreTheExtendedShape() {
        // A weekend: Friday night, Saturday afternoon, Saturday night — 36 hours
        // end to end, each inside the 24-hour gap rule, so one occasion.
        let weekend = [event(.alcohol, daysAgo: 6.0), event(.alcohol, daysAgo: 5.2),
                       event(.alcohol, daysAgo: 4.5)]
        let report = SubstanceEpisodeReport.report(events: weekend, samples: [],
                                                   now: now, calendar: utc)
        XCTAssertEqual(report.substances.first?.occasions, 1)
        XCTAssertEqual(report.substances.first?.episodes.first?.shape, .extended,
                       "a two-night stretch is one occasion, and the copy must not imply the app knows how much")
    }

    func testEveryShapeSaysItIsCountingEntriesRatherThanAmount() {
        for shape in SubstanceEpisodeReport.Shape.allCases {
            XCTAssertTrue(shape.explanation.lowercased().contains("entr"),
                          "\(shape) must say it is counting entries — the app does not model dose")
        }
    }

    // MARK: - P16: no score, and the sentence

    func testUnderThreeOccasionsTheSubstanceIsNotAttributableAndSaysTheSentence() {
        let events = [event(.cannabis, daysAgo: 12)]
        let report = SubstanceEpisodeReport.report(
            events: events, samples: readings(.restingHeartRate, base: 55, bump: 8, after: events),
            now: now, calendar: utc)
        let cannabis = report.substances.first { $0.substance == .cannabis }
        XCTAssertEqual(cannabis?.occasions, 1)
        XCTAssertEqual(cannabis?.isAttributable, false,
                       "one occasion can never be attributable — this is the reader's real cannabis n")
        XCTAssertTrue(cannabis?.verdict.contains(SubstanceEpisodeReport.ordinaryRun) == true,
                      "the standing sentence must be the verdict below three occasions")
    }

    func testAtThreeOccasionsItDescribesAndStillRefusesToCallAnythingProven() {
        let events = [event(.stimulant, daysAgo: 20), event(.stimulant, daysAgo: 12),
                      event(.stimulant, daysAgo: 4)]
        let report = SubstanceEpisodeReport.report(
            events: events, samples: readings(.restingHeartRate, base: 55, bump: 8, after: events),
            now: now, calendar: utc)
        let stimulant = try? XCTUnwrap(report.substances.first)
        XCTAssertEqual(stimulant?.isAttributable, true)
        XCTAssertTrue(stimulant?.verdict.contains("not enough to call it proven") == true)
    }

    func testEveryReportedRowNamesAnAlternativeExplanationWhereOneIsKnown() {
        let events = [event(.stimulant, daysAgo: 20), event(.stimulant, daysAgo: 12),
                      event(.stimulant, daysAgo: 4)]
        let report = SubstanceEpisodeReport.report(
            events: events, samples: readings(.restingHeartRate, base: 55, bump: 8, after: events),
            now: now, calendar: utc)
        let deltas = report.substances.flatMap { $0.episodes.flatMap(\.deltas) }
        XCTAssertFalse(deltas.isEmpty, "the fixture must actually produce rows")
        for delta in deltas where SubstanceEpisodes.alternativeExplanation(for: delta.metric) != nil {
            XCTAssertNotNil(delta.alternative,
                            "\(delta.metric) has a known confounder and the row dropped it")
        }
    }

    /// The structural half of "no score": there is no number on any of these
    /// types for a dial to read, and `Report` is a description end to end.
    func testTheReportCarriesNoScoreOfAnyKind() {
        let events = [event(.stimulant, daysAgo: 20), event(.stimulant, daysAgo: 12),
                      event(.stimulant, daysAgo: 4)]
        let report = SubstanceEpisodeReport.report(
            events: events, samples: readings(.restingHeartRate, base: 55, bump: 8, after: events),
            now: now, calendar: utc)
        let mirror = Mirror(reflecting: report.substances.first as Any)
        for child in mirror.children {
            XCTAssertFalse((child.label ?? "").lowercased().contains("score"),
                           "a score reached the honest section — the ruling is 'no score'")
        }
    }

    // MARK: - P16: recovery time

    func testADepartureThatComesBackReportsHowLongItTook() {
        let events = [event(.stimulant, daysAgo: 20), event(.stimulant, daysAgo: 12),
                      event(.stimulant, daysAgo: 4)]
        let report = SubstanceEpisodeReport.report(
            events: events, samples: readings(.restingHeartRate, base: 55, bump: 12, after: events),
            now: now, calendar: utc)
        let recoveries = report.substances.flatMap { $0.episodes.flatMap(\.recoveries) }
        XCTAssertFalse(recoveries.isEmpty, "a 12 bpm bump on a ±1 baseline must depart")
        XCTAssertTrue(recoveries.contains { $0.hoursToBaseline != nil },
                      "readings return to the clean band the next day and nothing timed it")
    }

    func testASmallDifferenceIsNotTimedAtAll() {
        let events = [event(.alcohol, daysAgo: 20), event(.alcohol, daysAgo: 12),
                      event(.alcohol, daysAgo: 4)]
        // A quarter of a baseline SD: measured, shown, and far too small to
        // time a recovery from.
        let report = SubstanceEpisodeReport.report(
            events: events, samples: readings(.restingHeartRate, base: 55, bump: 0.2, after: events),
            now: now, calendar: utc)
        let episodes = report.substances.flatMap(\.episodes)
        XCTAssertFalse(episodes.flatMap(\.deltas).isEmpty, "the difference is still reported")
        XCTAssertTrue(episodes.allSatisfy { $0.recoveries.isEmpty },
                      "timing a return from a sub-SD wobble is timing noise")
    }

    // MARK: - P16: good versus bad, per substance

    func testAWelcomeMoveAndAnUnwelcomeMoveLandOnOppositeSides() {
        let events = [event(.stimulant, daysAgo: 20), event(.stimulant, daysAgo: 12),
                      event(.stimulant, daysAgo: 4)]
        let samples = readings(.restingHeartRate, base: 55, bump: 10, after: events)
            + readings(.sleepDurationHours, base: 7, bump: 1.5, after: events)
        let report = SubstanceEpisodeReport.report(events: events, samples: samples,
                                                   now: now, calendar: utc)
        let stimulant = report.substances.first { $0.substance == .stimulant }
        XCTAssertTrue(stimulant?.unwelcome.contains { $0.metric == .restingHeartRate } == true,
                      "resting heart rate going up is the unwelcome direction")
        XCTAssertTrue(stimulant?.welcome.contains { $0.metric == .sleepDurationHours } == true,
                      "more sleep is the welcome direction")
    }

    func testASignalWithNoBetterEndIsKeptRatherThanDropped() {
        let events = [event(.alcohol, daysAgo: 20), event(.alcohol, daysAgo: 12),
                      event(.alcohol, daysAgo: 4)]
        let samples = readings(.bodyTemperature, base: 36.6, bump: 0.5, after: events)
        let report = SubstanceEpisodeReport.report(events: events, samples: samples,
                                                   now: now, calendar: utc)
        let alcohol = report.substances.first { $0.substance == .alcohol }
        XCTAssertTrue(alcohol?.noBetterEnd.contains { $0.metric == .bodyTemperature } == true,
                      "a temperature has no better end and must not be claimed by either list")
        XCTAssertFalse(alcohol?.welcome.contains { $0.metric == .bodyTemperature } == true)
        XCTAssertFalse(alcohol?.unwelcome.contains { $0.metric == .bodyTemperature } == true)
    }

    // MARK: - Substances never merge

    func testAStimulantNightAndAnAlcoholNightNeverPoolIntoOneSubstance() {
        let events = [event(.stimulant, daysAgo: 10), event(.alcohol, daysAgo: 10.05)]
        let report = SubstanceEpisodeReport.report(events: events, samples: [],
                                                   now: now, calendar: utc)
        XCTAssertEqual(report.substances.count, 2)
        XCTAssertEqual(report.totalOccasions, 2)
    }

    /// A reading taken the night of a *different* substance is not a clean
    /// reading. Pooling it into the baseline would make the baseline the thing
    /// that moved.
    func testAnotherSubstancesNightIsNotPartOfTheCleanBaseline() {
        let stimulants = [event(.stimulant, daysAgo: 20), event(.stimulant, daysAgo: 12),
                          event(.stimulant, daysAgo: 4)]
        let alcohol = [event(.alcohol, daysAgo: 30)]
        let samples = readings(.restingHeartRate, base: 55, bump: 10,
                               after: stimulants + alcohol)
        let pooled = SubstanceEpisodeReport.report(events: stimulants + alcohol,
                                                   samples: samples, now: now, calendar: utc)
        let stimulantOnly = SubstanceEpisodeReport.report(events: stimulants, samples: samples,
                                                          now: now, calendar: utc)
        let a = pooled.substances.first { $0.substance == .stimulant }?
            .episodes.last?.deltas.first { $0.metric == .restingHeartRate }?.cleanMean
        let b = stimulantOnly.substances.first?
            .episodes.last?.deltas.first { $0.metric == .restingHeartRate }?.cleanMean
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertLessThan(try XCTUnwrap(a), try XCTUnwrap(b),
                          "the alcohol night stayed in the clean pool and raised the baseline")
    }
}
