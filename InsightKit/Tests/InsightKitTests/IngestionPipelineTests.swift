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

    func testRecordIsDatedFromDayField() throws {
        let json = #"{"data":[{"day":"2026-01-10","score":1}]}"#
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest([payload(json, endpoint: "daily_sleep")], into: &catalogue)
        let sample = try XCTUnwrap(result.raw.first)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.year, from: sample.start), 2026)
        XCTAssertEqual(utc.component(.month, from: sample.start), 1)
        XCTAssertEqual(utc.component(.day, from: sample.start), 10)
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

    // MARK: Withings

    func testWithingsMeasuresKeepEveryTypeAndTheirMetadata() {
        let json = """
        {"status":0,"body":{"measuregrps":[
          {"date":1736500000,"category":1,"comment":"after run","measures":[
            {"value":365,"type":12,"unit":-1},
            {"value":70,"type":1,"unit":0}
          ]}
        ]}}
        """
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest(
            [payload(json, source: .withings, endpoint: "measure")], into: &catalogue)
        let byID = Dictionary(uniqueKeysWithValues: result.raw.map { ($0.identifier, $0.value) })

        // Both types, not only the unmapped one, and the exponent is applied.
        XCTAssertEqual(byID["withings.measure.12"], .number(36.5))
        XCTAssertEqual(byID["withings.measure.1"], .number(70))
        // Free text that the old Double-only raw layer had nowhere to put.
        XCTAssertEqual(byID["withings.measure.comment"], .text("after run"))
        // Type 12 has a rule mapping it to body temperature.
        XCTAssertTrue(result.promoted.contains { $0.type == .bodyTemperature })
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
