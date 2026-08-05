import XCTest
@testable import InsightKit

/// Covers the four guarantees the ingestion pipeline exists to make: everything
/// is captured, non-numeric values survive, new fields are discovered without
/// code changes, and mapping to canonical vitals is data-driven.
final class IngestionPipelineTests: XCTestCase {

    private func payload(_ json: String, source: MetricSource = .oura, endpoint: String) -> IngestPayload {
        IngestPayload(source: source, endpoint: endpoint, data: Data(json.utf8))
    }

    // MARK: Complete capture

    func testCapturesStringsBooleansAndNestedObjects() {
        let json = """
        {"data":[{
          "id":"abc",
          "day":"2026-01-10",
          "score":78,
          "level":"solid",
          "active":true,
          "contributors":{"sleep_recovery":81,"stress":66}
        }]}
        """
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest([payload(json, endpoint: "daily_resilience")],
                                                      into: &catalogue)
        let byID = Dictionary(uniqueKeysWithValues: result.raw.map { ($0.identifier, $0.value) })

        XCTAssertEqual(byID["oura.daily_resilience.score"], .number(78))
        // The headline of the whole endpoint — a string, previously discarded.
        XCTAssertEqual(byID["oura.daily_resilience.level"], .text("solid"))
        // Booleans keep their type rather than becoming 1.
        XCTAssertEqual(byID["oura.daily_resilience.active"], .flag(true))
        XCTAssertEqual(byID["oura.daily_resilience.contributors.sleep_recovery"], .number(81))
        // `id` carries no measurement; `day` became the timestamp.
        XCTAssertNil(byID["oura.daily_resilience.id"])
        XCTAssertNil(byID["oura.daily_resilience.day"])
    }

    /// A bare `day` field dates the record to **that day in the reader's own
    /// zone** — not to midnight UTC.
    ///
    /// This test used to build a UTC calendar and assert the day component in
    /// it, which passed for exactly one reason: the ingestion formatter was
    /// pinned to UTC too, so the test and the code shared a mistake. A reader
    /// at UTC+8 got Oura samples eight hours off their own day boundary while
    /// every Apple-derived night sat exactly on it, and nothing could see the
    /// disagreement because the only two `TimeZone(identifier: "UTC")` in the
    /// codebase were both on the ingestion side.
    ///
    /// Asserted at two zones on opposite sides of the meridian, because the old
    /// behaviour is correct at UTC and only at UTC — a single-zone assertion is
    /// how this survived. See `DayStamp`.
    func testABareDayFieldIsThatDayInTheReadersOwnZone() throws {
        func day(inZone identifier: String) throws -> (Date, Calendar) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: identifier)!
            let pipeline = IngestionPipeline(
                ingestors: [GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: .oura)],
                rules: PromotionRuleSet(rules: [], aliases: [:]),
                calendar: calendar)
            var catalogue = FieldCatalogue()
            let json = #"{"data":[{"day":"2026-01-10","score":1}]}"#
            let result = pipeline.ingest([payload(json, endpoint: "daily_sleep")], into: &catalogue)
            return (try XCTUnwrap(result.raw.first).start, calendar)
        }

        let (tokyo, tokyoCalendar) = try day(inZone: "Asia/Tokyo")          // UTC+9
        let (newYork, newYorkCalendar) = try day(inZone: "America/New_York") // UTC−5

        for (instant, calendar) in [(tokyo, tokyoCalendar), (newYork, newYorkCalendar)] {
            XCTAssertEqual(calendar.component(.year, from: instant), 2026)
            XCTAssertEqual(calendar.component(.month, from: instant), 1)
            XCTAssertEqual(calendar.component(.day, from: instant), 10,
                           "a bare day field landed on a different day than the one it names")
            XCTAssertEqual(calendar.startOfDay(for: instant), instant,
                           "a day must land on its own zone's midnight, not eight hours off it")
        }

        // The two are genuinely different instants — 10 January began earlier in
        // Tokyo. If these were equal the rule would be zone-blind, which is the
        // defect this replaces.
        XCTAssertLessThan(tokyo, newYork)
    }

    func testNumericArraysAreSummarisedNotExploded() {
        // Oura's 5-minute night series. Summarising is what keeps a 200-value
        // array from becoming 200 stored samples per night.
        let json = #"{"data":[{"day":"2026-01-10","heart_rate":{"interval":300,"items":[50,60,null,70]}}]}"#
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest([payload(json, endpoint: "sleep")], into: &catalogue)
        let byID = Dictionary(uniqueKeysWithValues: result.raw.map { ($0.identifier, $0.value) })

        XCTAssertEqual(byID["oura.sleep.heart_rate.items.count"], .number(4))
        XCTAssertEqual(byID["oura.sleep.heart_rate.items.min"], .number(50))
        XCTAssertEqual(byID["oura.sleep.heart_rate.items.max"], .number(70))
        XCTAssertEqual(byID["oura.sleep.heart_rate.items.mean"], .number(60))
        XCTAssertEqual(byID["oura.sleep.heart_rate.interval"], .number(300))
        // The null inside the series is reported, not silently absorbed.
        XCTAssertFalse(result.skipped.isEmpty)
    }

    func testLongEncodedStringsAreKeptVerbatim() throws {
        let hypnogram = String(repeating: "4321", count: 40)
        let json = #"{"data":[{"day":"2026-01-10","sleep_phase_5_min":"\#(hypnogram)"}]}"#
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest([payload(json, endpoint: "sleep")], into: &catalogue)
        let stage = try XCTUnwrap(result.raw.first { $0.identifier == "oura.sleep.sleep_phase_5_min" })
        XCTAssertEqual(stage.value, .text(hypnogram))
    }

    // MARK: Discovery

    func testNewFieldsAreDiscoveredOnceAndRememberedAfter() {
        let json = #"{"data":[{"day":"2026-01-10","score":80}]}"#
        var catalogue = FieldCatalogue()
        let first = IngestionPipeline.shipped.ingest([payload(json, endpoint: "daily_sleep")], into: &catalogue)
        XCTAssertEqual(first.newFields.count, 1)

        // A field already in the catalogue is not "new" on the next sync, which
        // is what makes a genuine schema change stand out in the log.
        let second = IngestionPipeline.shipped.ingest([payload(json, endpoint: "daily_sleep")], into: &catalogue)
        XCTAssertTrue(second.newFields.isEmpty)
        XCTAssertEqual(catalogue.fields["oura.daily_sleep.score"]?.observationCount, 2)
    }

    func testAProviderAddingAFieldNeedsNoCodeChange() {
        var catalogue = FieldCatalogue()
        let before = #"{"data":[{"day":"2026-01-10","score":80}]}"#
        _ = IngestionPipeline.shipped.ingest([payload(before, endpoint: "daily_sleep")], into: &catalogue)

        // Same endpoint, provider has shipped two new fields overnight.
        let after = #"{"data":[{"day":"2026-01-11","score":81,"algorithm_version":"v3","nap":false}]}"#
        let result = IngestionPipeline.shipped.ingest([payload(after, endpoint: "daily_sleep")], into: &catalogue)

        XCTAssertEqual(Set(result.newFields.map(\.identifier)),
                       ["oura.daily_sleep.algorithm_version", "oura.daily_sleep.nap"])
        XCTAssertEqual(catalogue.fields["oura.daily_sleep.algorithm_version"]?.kind, .text)
        XCTAssertEqual(catalogue.fields["oura.daily_sleep.nap"]?.kind, .flag)
    }

    func testCategoricalTextIsRecognised() {
        var catalogue = FieldCatalogue()
        for (day, level) in [("2026-01-10", "solid"), ("2026-01-11", "strong"), ("2026-01-12", "solid")] {
            let json = #"{"data":[{"day":"\#(day)","level":"\#(level)"}]}"#
            _ = IngestionPipeline.shipped.ingest([payload(json, endpoint: "daily_resilience")], into: &catalogue)
        }
        let field = catalogue.fields["oura.daily_resilience.level"]
        XCTAssertEqual(field?.observedTextValues, ["solid", "strong"])
        XCTAssertEqual(field?.isCategorical, true)
    }

    // MARK: Data-driven promotion

    func testRuleMatchedFieldBecomesACanonicalVital() throws {
        let json = #"{"data":[{"day":"2026-01-10","vo2_max":42.5}]}"#
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest([payload(json, endpoint: "vO2_max")], into: &catalogue)

        let promoted = try XCTUnwrap(result.promoted.first)
        XCTAssertEqual(promoted.type, .vo2Max)
        XCTAssertEqual(promoted.value, 42.5, accuracy: 1e-9)
        XCTAssertEqual(promoted.source.id, MetricSource.oura.id)
        // It stays in the raw layer too — promotion is an addition, not a move.
        XCTAssertTrue(result.raw.contains { $0.identifier == "oura.vO2_max.vo2_max" })
    }

    func testUnmappedLookalikeIsProposedNotPromoted() throws {
        // No rule authorises this path, but the leaf names a metric we model.
        let json = #"{"data":[{"day":"2026-01-10","resting_heart_rate":48}]}"#
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest([payload(json, endpoint: "daily_experimental")],
                                                      into: &catalogue)
        XCTAssertTrue(result.promoted.isEmpty)
        let proposal = try XCTUnwrap(result.proposals.first)
        XCTAssertEqual(proposal.proposedMetric, .restingHeartRate)
    }

    func testPromotionAppliesUnitConversion() throws {
        let rules = PromotionRuleSet(
            rules: [PromotionRule(match: .leaf("height_cm"), metric: .height, scale: 0.01)],
            aliases: [:])
        let pipeline = IngestionPipeline(
            ingestors: [GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: .oura)],
            rules: rules)
        var catalogue = FieldCatalogue()
        let result = pipeline.ingest([payload(#"{"data":[{"day":"2026-01-10","height_cm":183}]}"#,
                                              endpoint: "personal_info")], into: &catalogue)
        XCTAssertEqual(try XCTUnwrap(result.promoted.first).value, 1.83, accuracy: 1e-9)
    }

    // MARK: Promotion from a timestamp

    /// A connector whose spec does *not* spend `bedtime_start` on the record
    /// date, which is the only shape a sleep-onset rule can ever fire on —
    /// `EnvelopeSpec.oura` lists it in `startDateKeys`, and the ingestor excludes
    /// date keys from the field sweep.
    private var bedtimeSpec: EnvelopeSpec {
        EnvelopeSpec(recordsKeyPath: ["data"], startDateKeys: ["day"], ignoredKeys: ["id"])
    }

    private func bedtimePipeline(_ interpretation: PromotionRule.Interpretation) -> IngestionPipeline {
        IngestionPipeline(
            ingestors: [GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: bedtimeSpec)],
            rules: PromotionRuleSet(
                rules: [PromotionRule(match: .leaf("bedtime_start"), metric: .sleepOnset,
                                      interpretation: interpretation)],
                aliases: [:]),
            // Pinned rather than inherited: whether 23:30 is last night or
            // tonight is a question about the reader's zone, not the data's.
            calendar: TestClock.utc)
    }

    private func ingestBedtime(_ value: String,
                               interpretation: PromotionRule.Interpretation = .sleepOnsetTimestamp)
        -> IngestionResult {
        var catalogue = FieldCatalogue()
        return bedtimePipeline(interpretation).ingest(
            [payload(#"{"data":[{"day":"2026-01-10","bedtime_start":"\#(value)"}]}"#,
                     endpoint: "sleep")],
            into: &catalogue)
    }

    /// The whole point of `Interpretation`. A bedtime is text, and promotion
    /// used to be numeric by definition — so this rule matched and promoted
    /// nothing at all, with no error raised anywhere.
    func testATextTimestampPromotesToSleepOnset() throws {
        let promoted = try XCTUnwrap(ingestBedtime("2026-01-10T23:30:00+00:00").promoted.first)
        XCTAssertEqual(promoted.type, .sleepOnset)
        // Signed hours from midnight with the cut at midday: 23:30 is −0.5.
        XCTAssertEqual(promoted.value, -0.5, accuracy: 1e-9)
    }

    /// The trap, pinned. Exactly the same field and rule, read as a number:
    /// nothing promotes, and nothing complains. This is what the old pipeline
    /// did to *every* text field a rule pointed at.
    func testTheSameFieldReadAsANumberPromotesNothing() {
        XCTAssertTrue(ingestBedtime("2026-01-10T23:30:00+00:00", interpretation: .numeric)
            .promoted.isEmpty)
    }

    /// The detail most likely to be got wrong. A promoted sample is normally
    /// stamped at the document's own date; `SleepOnset` dates a night by the
    /// morning it ends on. Left alone, one night's bedtime would arrive on two
    /// different days depending on which route it took in, and `VitalReader`
    /// would read it as two nights rather than de-duplicating it as one.
    func testAPromotedOnsetLandsOnTheSameNightAsAParserBuiltOne() throws {
        let instant = try XCTUnwrap(PayloadDate.parse("2026-01-10T23:30:00+00:00"))
        let promoted = try XCTUnwrap(ingestBedtime("2026-01-10T23:30:00+00:00").promoted.first)
        let parserBuilt = try XCTUnwrap(SleepOnset.samples(fromSegmentStarts: [instant],
                                                           source: .oura,
                                                           calendar: TestClock.utc).first)
        XCTAssertEqual(promoted.start, parserBuilt.start)
        XCTAssertEqual(promoted.value, parserBuilt.value, accuracy: 1e-9)
        // And specifically *not* the record's own day, which is the bug.
        XCTAssertNotEqual(promoted.start, try XCTUnwrap(PayloadDate.parse("2026-01-10")))
    }

    /// The nap filter belongs to `SleepOnset` and is reused rather than
    /// reimplemented, so promotion declines exactly where the parsers decline.
    func testAnAfternoonTimestampIsNotPromoted() {
        XCTAssertTrue(ingestBedtime("2026-01-10T15:00:00+00:00").promoted.isEmpty)
    }

    /// `PayloadDate` reads a bare `2026-01-10` as midnight, and midnight is a
    /// perfectly ordinary bedtime — so a date-only field would promote a
    /// plausible 00:00 every night with nothing in the data to reveal it was
    /// invented. Declined instead.
    func testADateWithNoTimeOfDayIsNotPromotedAsMidnight() {
        XCTAssertTrue(ingestBedtime("2026-01-10").promoted.isEmpty)
    }

    /// A connector with no rule gets its bedtime catalogued and *proposed*,
    /// never promoted — the same guarantee every other lookalike field has.
    func testAnUnruledBedtimeIsProposedNotPromoted() throws {
        var catalogue = FieldCatalogue()
        let pipeline = IngestionPipeline(
            ingestors: [GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: bedtimeSpec)],
            calendar: TestClock.utc)
        let result = pipeline.ingest(
            [payload(#"{"data":[{"day":"2026-01-10","sleep_start":"2026-01-10T23:30:00+00:00"}]}"#,
                     endpoint: "sleep")],
            into: &catalogue)
        XCTAssertTrue(result.promoted.isEmpty)
        XCTAssertEqual(try XCTUnwrap(result.proposals.first).proposedMetric, .sleepOnset)
    }

    // MARK: Withings

    /// This test used to pin the opposite: every measure type, metadata and
    /// all. The first data export reversed that — ~80 of its 232 "unmodelled
    /// signals" were Withings bookkeeping, and the numbered copies of
    /// already-promoted types could only agree with or contradict the Vitals
    /// row for the same reading.
    func testWithingsMeasuresKeepDataAndDropBookkeeping() {
        let json = """
        {"status":0,"body":{"measuregrps":[
          {"date":1736500000,"category":1,"comment":"after run",
           "deviceid":"abc123","grpid":9812734,"created":1736500100,
           "modified":1736500100,"timezone":"Europe/London","measures":[
            {"value":365,"type":12,"unit":-1,"algo":3,"fm":131},
            {"value":70,"type":1,"unit":0}
          ]}
        ]}}
        """
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest(
            [payload(json, source: .withings, endpoint: "measure")], into: &catalogue)
        let byID = Dictionary(uniqueKeysWithValues: result.raw.map { ($0.identifier, $0.value) })

        // An unmapped type survives with its exponent applied, and its
        // promotion rule still fires — the rule reads this raw field, so
        // dropping it here would break the promotion silently.
        XCTAssertEqual(byID["withings.measure.12"], .number(36.5))
        XCTAssertTrue(result.promoted.contains { $0.type == .bodyTemperature })
        // A type the canonical parser promotes (1 = weight) must NOT also
        // arrive raw: the same reading was showing once in Vitals and again
        // in Other data.
        XCTAssertNil(byID["withings.measure.1"])
        // Facts about the measurement stay: attrib/category semantics and the
        // user's own words.
        XCTAssertEqual(byID["withings.measure.comment"], .text("after run"))
        XCTAssertEqual(byID["withings.measure.category"], .number(1))
        // Bookkeeping about the sync does not.
        for gone in ["withings.measure.deviceid", "withings.measure.grpid",
                     "withings.measure.created", "withings.measure.modified",
                     "withings.measure.timezone", "withings.measure.12.algo",
                     "withings.measure.12.fm"] {
            XCTAssertNil(byID[gone], "\(gone) is device metadata, not a signal")
        }
    }

    // MARK: Robustness

    func testUnknownSourceIsReportedRatherThanDroppedSilently() {
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest(
            [IngestPayload(source: .hume, endpoint: "x", data: Data(#"{"data":[]}"#.utf8))],
            into: &catalogue)
        XCTAssertTrue(result.raw.isEmpty)
        XCTAssertEqual(result.unreadablePayloads.count, 1)
    }

    func testMalformedPayloadDoesNotThrow() {
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest(
            [payload("not json at all", endpoint: "sleep")], into: &catalogue)
        XCTAssertTrue(result.raw.isEmpty)
        XCTAssertEqual(result.unreadablePayloads.count, 1)
    }

    func testRecordWithNoRecognisableDateIsSkipped() {
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest(
            [payload(#"{"data":[{"score":5}]}"#, endpoint: "daily_sleep")], into: &catalogue)
        XCTAssertTrue(result.raw.isEmpty)
    }
}
