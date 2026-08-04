import XCTest
@testable import InsightKit

/// **A sleep session is dated by when it began, never by the date it ended on.**
///
/// Oura stamps a session with both `bedtime_start` (a real instant, with the
/// reader's UTC offset on it) and `day` (the *wake* date, no time at all). Until
/// 2026-08-04 `day` came first in `EnvelopeSpec.oura.startDateKeys`, so every
/// session — the five-minute stage string included — was dated at midnight UTC.
/// All 15,604 Oura raw rows in the reader's own export sit at exactly
/// `T00:00:00Z`, and on their UTC+8 phone the sleep chart drew a night starting
/// at 08:00.
///
/// The tests below fail on the old order and pass on the new one. They are
/// written in UTC — the suite's convention — but the defect they pin is
/// *timezone-invisible from UTC*, which is why it survived: midnight UTC looks
/// like a plausible bedtime when you are in UTC, so a UTC-pinned test of the
/// old behaviour asserted nothing. Hence `testTheInstantIsTheOneOuraStamped`,
/// which checks the absolute instant rather than any local rendering.
final class OuraSessionDatingTests: XCTestCase {

    /// The real pipeline with the real `EnvelopeSpec.oura` — not a local spec.
    /// A test that builds its own spec cannot catch a key-order defect in the
    /// shipped one, which is exactly how this survived.
    private func parse(_ json: String, endpoint: String = "sleep") throws -> [RawMetricSample] {
        let pipeline = IngestionPipeline(
            ingestors: [GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: .oura)],
            rules: PromotionRuleSet(rules: [], aliases: [:]),
            calendar: TestClock.utc)
        var catalogue = FieldCatalogue()
        let payload = IngestPayload(source: .oura, endpoint: endpoint, data: Data(json.utf8))
        return pipeline.ingest([payload], into: &catalogue).raw
    }

    /// A session carrying a real bedtime is dated at that instant, not at
    /// midnight on its wake date.
    func testASessionIsDatedByItsBedtimeNotItsWakeDate() throws {
        let json = """
        {"data":[{"day":"2026-07-20",
                  "bedtime_start":"2026-07-19T23:30:00+08:00",
                  "average_hrv":58}]}
        """
        let sample = try XCTUnwrap(parse(json).first)
        // 23:30 at +08:00 is 15:30Z on the 19th — the night *before* the wake
        // date. Under the old key order this was 2026-07-20T00:00:00Z.
        // Built from components rather than an epoch literal: a hand-computed
        // constant is a second thing that can be wrong, and this one was.
        let expected = try XCTUnwrap(TestClock.utc.date(
            from: DateComponents(year: 2026, month: 7, day: 19, hour: 15, minute: 30)))
        XCTAssertEqual(sample.start, expected,
                       "the session is dated by `day`, so it lands on the wrong night entirely")
    }

    /// The absolute instant, stated without reference to any calendar — the
    /// assertion the old UTC-only tests could not make.
    func testTheInstantIsTheOneOuraStamped() throws {
        let json = """
        {"data":[{"day":"2026-07-20","bedtime_start":"2026-07-19T23:30:00+08:00","average_hrv":58}]}
        """
        let sample = try XCTUnwrap(parse(json).first)
        XCTAssertNotEqual(TestClock.utc.startOfDay(for: sample.start), sample.start,
                          "a session dated at exactly midnight UTC is the defect's signature")
    }

    /// Daily summaries genuinely have only a `day`, and must keep dating from
    /// it. Moving `day` to the back of the list must not orphan them.
    func testADailySummaryWithOnlyADayStillDates() throws {
        let json = """
        {"data":[{"day":"2026-07-20","score":74}]}
        """
        let sample = try XCTUnwrap(parse(json).first)
        XCTAssertEqual(TestClock.utc.startOfDay(for: sample.start), sample.start,
                       "a day-only record should still date at that day's midnight")
    }

    /// Two sessions on one `day` — a night and a morning re-sleep — must get
    /// distinct instants. They used to collapse onto one, which is how 58 of
    /// 178 records in the reader's export came to share a start: hypnograms
    /// overdrew, and a join by instant kept whichever record it saw first.
    func testTwoSessionsOnOneDayGetDistinctInstants() throws {
        let json = """
        {"data":[{"day":"2026-07-20","bedtime_start":"2026-07-19T23:30:00+00:00","average_hrv":58},
                 {"day":"2026-07-20","bedtime_start":"2026-07-20T08:20:00+00:00","average_hrv":61}]}
        """
        let starts = Set(try parse(json).map(\.start))
        XCTAssertEqual(starts.count, 2,
                       "both periods of one night collapsed onto a single instant")
    }

    /// A session that ends after it starts. 125 of 178 spans in the reader's
    /// export ended *before* they began, because the start was forced to
    /// midnight on the wake date while the end kept its true instant.
    func testASpanEndsAfterItStarts() throws {
        let json = """
        {"data":[{"day":"2026-07-20",
                  "bedtime_start":"2026-07-19T23:30:00+00:00",
                  "bedtime_end":"2026-07-20T07:10:00+00:00",
                  "average_hrv":58}]}
        """
        let sample = try XCTUnwrap(parse(json).first)
        XCTAssertGreaterThan(sample.end, sample.start,
                             "the span is inverted, so every duration derived from it is negative")
    }
}
