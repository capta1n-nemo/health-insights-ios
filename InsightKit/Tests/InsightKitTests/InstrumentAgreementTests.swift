import XCTest
@testable import InsightKit

/// Backlog `B3-23` / `S8` — *"where Watch, ring and scale disagree, show both,
/// say which the app used and why."*
///
/// The section this covers makes two claims the reader cannot check: **which
/// instrument the app used**, and **why**. Both are cheap to get subtly wrong
/// and expensive to have wrong, because a confident false sentence about
/// provenance is worse than no section at all. So:
///
/// - the *reading* winner is never re-derived, it is read off
///   `VitalReader.reading`, and one test pins that wiring;
/// - the *chart* winner has to be re-derived (`dailySeries` throws the name
///   away), and `testTheNamedChartInstrumentIsTheOneDailySeriesActuallyReturns`
///   is the drift guard that makes the duplication safe;
/// - the sentences quote the margin that **actually decided it**. An early
///   draft quoted total days reported, which decides nothing —
///   `reading()` ranks fresh sources by the size of the 28-day baseline window
///   behind them. `testTheReadingSentenceQuotesTheMarginThatDecidedIt` is what
///   caught that class.
final class InstrumentAgreementTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// Readings from one source on the given days-ago, one per day at midday.
    private func days(_ source: MetricSource, _ metric: MetricType,
                      _ range: some Sequence<Int>,
                      value: Double) -> [HealthMetricSample] {
        range.map { day in
            HealthMetricSample(type: metric, value: value,
                               start: TestClock.day(day), source: source)
        }
    }

    private func panel(_ samples: [HealthMetricSample],
                       _ metrics: [MetricType] = [.restingHeartRate],
                       windowDays: Int = 90) -> InstrumentAgreementPanel {
        InstrumentAgreementPanel.forCard(metrics: metrics, samples: samples,
                                         now: now, windowDays: windowDays,
                                         calendar: utc)
    }

    // MARK: - Both are shown, and one is named

    /// The whole ask in one assertion: the instrument the app discarded is on
    /// screen with its own number.
    func testTheDiscardedInstrumentIsStillListedWithItsOwnReading() throws {
        var samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<40, value: 66)

        let row = try XCTUnwrap(panel(samples).rows.first)
        XCTAssertEqual(row.instruments.count, 2)
        XCTAssertEqual(Set(row.instruments.compactMap(\.latest)), [52, 66])
        // Exactly one is used for the judged reading, and the other is not
        // dropped for losing.
        XCTAssertEqual(row.instruments.filter(\.feedsReading).count, 1)
        XCTAssertTrue(row.instruments.contains { $0.isUnused == false })
        XCTAssertEqual(try XCTUnwrap(row.spread), 14, accuracy: 0.001)
    }

    /// The reading winner is the app's own answer, not this file's opinion of it.
    func testTheNamedReadingInstrumentIsTheOneVitalReaderActuallyUsed() throws {
        var samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<12, value: 66)

        let row = try XCTUnwrap(panel(samples).rows.first)
        let truth = try XCTUnwrap(VitalReader.reading(.restingHeartRate, from: samples,
                                                      now: now,
                                                      gap: VitalReader.judgementGap,
                                                      calendar: utc))
        XCTAssertEqual(row.readingSource, truth.sourceName)
    }

    /// **The drift guard.** `dailySeries` returns values with the source name
    /// discarded, so the panel re-derives the ranking — and this is what stops
    /// that copy quietly diverging into a confident false sentence. If this
    /// fails, the section is naming the wrong instrument.
    func testTheNamedChartInstrumentIsTheOneDailySeriesActuallyReturns() throws {
        // Ring: every other day for 90 days. Watch: every day for the last 28.
        var samples = days(.oura, .restingHeartRate, stride(from: 0, to: 90, by: 2),
                           value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<28, value: 66)

        let row = try XCTUnwrap(panel(samples, windowDays: 90).rows.first)
        let named = try XCTUnwrap(row.chartSource)

        let drawn = VitalReader.dailySeries(.restingHeartRate, from: samples,
                                            days: 90, now: now, calendar: utc)
        let expected = try XCTUnwrap(row.instruments.first { $0.name == named })
        XCTAssertFalse(drawn.isEmpty)
        // Every point of the drawn series carries the named instrument's value.
        // Two constant fixtures make this an exact identification.
        for point in drawn {
            XCTAssertEqual(point.value, try XCTUnwrap(expected.latest), accuracy: 0.001,
                           "the chart is drawn from an instrument the section is not naming")
        }
        XCTAssertEqual(drawn.count, expected.daysInWindow)
    }

    // MARK: - The two rules can name different instruments

    /// The finding that makes this section worth building rather than a
    /// footnote: `reading()` and `dailySeries()` are different rules with
    /// different jobs, and on real fixtures they choose differently.
    ///
    /// Watch has the last 28 days solid, so its baseline is the better
    /// established and it wins the *reading*. Ring covers 45 of the 90 days on
    /// screen, so it wins the *chart*. Neither is blended.
    func testTheTwoRulesChooseDifferentInstrumentsAndBothAreNamed() throws {
        var samples = days(.oura, .restingHeartRate, stride(from: 0, to: 90, by: 2),
                           value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<28, value: 66)

        let row = try XCTUnwrap(panel(samples, windowDays: 90).rows.first)
        XCTAssertTrue(row.rulesDisagree,
                      "reading=\(row.readingSource ?? "-") chart=\(row.chartSource ?? "-")")
        XCTAssertNotNil(row.chartReason, "a disagreement between the rules must be said out loud")
        XCTAssertEqual(panel(samples, windowDays: 90).conflicted.count, 1)
    }

    /// And when they agree, the second sentence is absent rather than repeated —
    /// two sentences would imply two decisions where there was one.
    func testTheChartSentenceIsSilentWhenBothRulesPickTheSameInstrument() throws {
        var samples = days(.oura, .restingHeartRate, 0..<60, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<6, value: 66)

        let row = try XCTUnwrap(panel(samples).rows.first)
        XCTAssertEqual(row.readingSource, row.chartSource)
        XCTAssertFalse(row.rulesDisagree)
        XCTAssertNil(row.chartReason)
    }

    // MARK: - The words

    /// The sentence must quote the margin the rule decided on — the days behind
    /// each baseline — and not the length of the record, which decides nothing.
    ///
    /// ⚠️ An early draft quoted total days reported. On this fixture that reads
    /// "60 days against 28" while the rule compared 27 against 27 and broke the
    /// tie on recency: a true-sounding sentence about a comparison that never
    /// happened.
    func testTheReadingSentenceQuotesTheMarginThatDecidedIt() throws {
        var samples = days(.oura, .restingHeartRate, 0..<60, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<6, value: 66)

        let row = try XCTUnwrap(panel(samples).rows.first)
        let winner = try XCTUnwrap(row.instruments.first(where: \.feedsReading))
        let loser = try XCTUnwrap(row.instruments.first(where: { !$0.feedsReading }))
        XCTAssertGreaterThan(winner.baselineDays, loser.baselineDays)
        XCTAssertTrue(row.readingReason.contains("\(winner.baselineDays) days against \(loser.baselineDays)"),
                      row.readingReason)
        XCTAssertTrue(row.readingReason.contains(winner.name), row.readingReason)
        XCTAssertTrue(row.readingReason.contains(loser.name), row.readingReason)
        // And it never claims the losing reading was folded in.
        XCTAssertTrue(row.readingReason.contains("never a blend"), row.readingReason)
    }

    /// A quiet instrument is named as quiet rather than silently ignored, and
    /// the sentence says how long it has been quiet.
    func testAQuietInstrumentIsExplainedRatherThanDropped() throws {
        var samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        200..<240, value: 66)

        let row = try XCTUnwrap(panel(samples, windowDays: 365).rows.first)
        XCTAssertEqual(row.instruments.count, 2, "the quiet one is still listed")
        XCTAssertEqual(row.instruments.filter(\.isFresh).count, 1)
        XCTAssertTrue(row.readingReason.contains("only one still reporting"),
                      row.readingReason)
        XCTAssertTrue(row.readingReason.contains("days ago"), row.readingReason)
    }

    /// The headline gap must not be invented out of a device that stopped
    /// reporting last year — `SourceBreakdown` already makes this point about
    /// current averages and the same trap applies here.
    func testTheSpreadIgnoresAnInstrumentThatHasGoneQuiet() throws {
        var samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        200..<240, value: 66)

        let row = try XCTUnwrap(panel(samples, windowDays: 365).rows.first)
        XCTAssertNil(row.spread,
                     "a 14 bpm gap against a device that stopped reporting is not today's gap")
        XCTAssertNil(row.relativeSpread)
    }

    // MARK: - What is not a row

    /// One instrument is the answer for most signals, and it is a reassuring
    /// answer rather than a missing one — so it is listed, not dropped.
    func testASingleInstrumentSignalIsListedRatherThanDropped() {
        let samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        let out = panel(samples, [.restingHeartRate, .vo2Max])
        XCTAssertTrue(out.rows.isEmpty)
        XCTAssertEqual(out.single, [.restingHeartRate])
        XCTAssertEqual(out.silent, [.vo2Max])
    }

    /// A card declaring the same metric through both its contributors and its
    /// requirements must not produce two rows — two identical rows read as two
    /// instruments' worth of evidence.
    func testADuplicatedMetricProducesOneRow() {
        var samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<40, value: 66)
        let out = panel(samples, [.restingHeartRate, .restingHeartRate])
        XCTAssertEqual(out.rows.count, 1)
    }

    /// Rows are ranked by *relative* spread, so a 14 bpm heart-rate gap and a
    /// 0.4 kg weight gap can be ordered against each other at all. Ranking on
    /// the raw gap would just sort by which metric has the largest units.
    func testRowsAreRankedByRelativeDisagreementNotRawUnits() throws {
        // Heart rate: 52 vs 54 — 2 bpm on ~53, about 3.8%.
        var samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<40, value: 54)
        // Body mass: 80 vs 88 kg — a much bigger disagreement in proportion,
        // and a smaller one in raw units than it would be in grams.
        samples += days(.withings, .bodyMass, 0..<40, value: 80)
        samples += days(.appleHealthDevice("Apple Watch"), .bodyMass, 0..<40, value: 88)

        let out = panel(samples, [.restingHeartRate, .bodyMass])
        XCTAssertEqual(out.rows.count, 2)
        XCTAssertEqual(out.rows.first?.metric, .bodyMass)
    }

    /// The closed section's one line has to stand alone — for most readers it
    /// is the whole of this section they will ever see.
    func testThePreviewNamesTheSignalAndTheGap() {
        var samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        samples += days(.appleHealthDevice("Apple Watch"), .restingHeartRate,
                        0..<40, value: 66)
        let line = InstrumentAgreementWording.preview(panel(samples))
        XCTAssertTrue(line.contains(MetricType.restingHeartRate.displayName), line)
        XCTAssertFalse(line.isEmpty)
    }

    /// And it says something true when there is nothing to say, rather than
    /// nothing at all.
    func testThePreviewIsHonestWhenThereIsNoDisagreement() {
        let samples = days(.oura, .restingHeartRate, 0..<40, value: 52)
        let line = InstrumentAgreementWording.preview(panel(samples))
        XCTAssertTrue(line.contains("One instrument each"), line)
    }
}
