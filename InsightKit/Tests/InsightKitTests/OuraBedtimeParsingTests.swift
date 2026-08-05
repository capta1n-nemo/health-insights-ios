import XCTest
@testable import InsightKit

/// **A date format the parser cannot read is reported as no date at all**, and
/// that is what made this defect invisible for the whole life of the feature.
///
/// `OuraResponseParser` read `bedtime_start` with a bare
/// `ISO8601DateFormatter()` in three places. That formatter accepts
/// `2026-07-19T23:30:00+08:00` and rejects `2026-07-19T23:30:00.000+08:00`,
/// returning `nil` — the same `nil` the code already uses to mean "this record
/// carries no bedtime". So the bedtime collector skipped the record, the
/// split-night filter returned false, nothing logged a failure, and every test
/// in this suite kept passing because every fixture was hand-written without
/// fractional seconds.
///
/// **The evidence is the reader's own export, not an argument**: 119 Oura
/// `sleepLatencyMinutes` samples and **zero** Oura `sleepOnset` samples. The
/// typed parser provably ran on 119 nights, and every bedtime it produced
/// evaporated. Two shipped consequences followed — circadian consistency had no
/// Oura input whatever, and `isMorningReSleep` (added 2026-08-02 for the
/// "7.5 h night reported as 4 h" defect) never fired on a real payload.
///
/// The tests below fail on the bare formatter and pass on `PayloadDate.parse`.
/// Each fixture is written **twice**, fractional and plain, because a fix that
/// only moves the failure from one form to the other would otherwise look like
/// a fix.
final class OuraBedtimeParsingTests: XCTestCase {

    /// Both spellings of the same instant, for the paired assertions below.
    private static let fractional = "2026-07-19T23:30:00.000+00:00"
    private static let plain = "2026-07-19T23:30:00+00:00"

    private func night(bedtime: String) -> Data {
        Data("""
        {"data":[{"day":"2026-07-20",
                  "bedtime_start":"\(bedtime)",
                  "type":"long_sleep",
                  "total_sleep_duration":27000,
                  "average_hrv":58}]}
        """.utf8)
    }

    // MARK: - The bedtime itself

    /// The defect, stated at its narrowest: fractional seconds must yield a
    /// bedtime. This is the assertion the reader's export already fails.
    func testAFractionalSecondsBedtimeProducesASleepOnsetSample() throws {
        let samples = try OuraResponseParser.parseSleepUTC(night(bedtime: Self.fractional))
        XCTAssertTrue(samples.contains { $0.type == .sleepOnset },
                      """
                      no .sleepOnset sample — the bedtime string was rejected and \
                      reported as an absent bedtime, which is exactly the shape that \
                      left the reader with 119 latencies and 0 onsets
                      """)
    }

    /// The other spelling, so the fix cannot be a swap of one intolerance for
    /// another. This one passed before the fix and must keep passing.
    func testAPlainSecondsBedtimeStillProducesASleepOnsetSample() throws {
        let samples = try OuraResponseParser.parseSleepUTC(night(bedtime: Self.plain))
        XCTAssertTrue(samples.contains { $0.type == .sleepOnset },
                      "the plain form regressed — the fix traded one format for the other")
    }

    /// Both spellings name one instant, so they must produce the same onset.
    /// Asserting equality rather than mere presence is what rules out the two
    /// forms parsing to *different* nights.
    func testBothSpellingsAgreeOnTheInstant() throws {
        func onset(_ bedtime: String) throws -> Double {
            let samples = try OuraResponseParser.parseSleepUTC(night(bedtime: bedtime))
            return try XCTUnwrap(samples.first { $0.type == .sleepOnset }).value
        }
        XCTAssertEqual(try onset(Self.fractional), try onset(Self.plain), accuracy: 0.0001,
                       "the same instant written two ways produced two different bedtimes")
    }

    // MARK: - The split-night fix, which the same nil silently disabled

    /// A `late_nap` beginning before noon is the second half of a broken night
    /// — the reader's own ruling, 2026-08-02 — and its sleep sums into the
    /// night's duration. `isMorningReSleep` proves it by reading the record's
    /// bedtime, so an unparseable bedtime disables the fix rather than
    /// misapplying it: the nap is dropped and the night reads half length.
    ///
    /// 7.5 h night + 1.0 h morning re-sleep = 8.5 h. Under the bare formatter
    /// this fixture reports 7.5 h, which is the shape of the original defect
    /// (Oura 4.3 h against Apple Health's 8.7 h on 2026-07-29).
    func testAMorningReSleepWithFractionalSecondsJoinsTheNight() throws {
        let json = Data("""
        {"data":[{"day":"2026-07-20",
                  "bedtime_start":"2026-07-19T23:30:00.000+00:00",
                  "type":"long_sleep",
                  "total_sleep_duration":27000},
                 {"day":"2026-07-20",
                  "bedtime_start":"2026-07-20T08:00:00.000+00:00",
                  "type":"late_nap",
                  "total_sleep_duration":3600}]}
        """.utf8)
        let duration = try XCTUnwrap(
            OuraResponseParser.parseSleepUTC(json).first { $0.type == .sleepDurationHours })
        XCTAssertEqual(duration.value, 8.5, accuracy: 0.001,
                       """
                       the morning re-sleep was dropped, so the night reads short — \
                       the split-night fix cannot fire when the bedtime it tests \
                       comes back nil
                       """)
    }

    /// An *afternoon* nap must still be excluded whichever way its bedtime is
    /// spelled. Tolerating a second date format must not widen what counts as a
    /// night — the nap filter is the reason `sleepDurationHours` had a 0.01 h
    /// minimum before it existed.
    func testAnAfternoonNapIsStillExcludedWithFractionalSeconds() throws {
        let json = Data("""
        {"data":[{"day":"2026-07-20",
                  "bedtime_start":"2026-07-19T23:30:00.000+00:00",
                  "type":"long_sleep",
                  "total_sleep_duration":27000},
                 {"day":"2026-07-20",
                  "bedtime_start":"2026-07-20T15:00:00.000+00:00",
                  "type":"late_nap",
                  "total_sleep_duration":3600}]}
        """.utf8)
        let duration = try XCTUnwrap(
            OuraResponseParser.parseSleepUTC(json).first { $0.type == .sleepDurationHours })
        XCTAssertEqual(duration.value, 7.5, accuracy: 0.001,
                       "a 3 pm nap was counted as part of the night")
    }

    // MARK: - Dating a record that has no `day`

    /// `day` is the primary date key and `bedtime_start` the fallback, so a
    /// record carrying only a fractional bedtime must still date. Under the bare
    /// formatter it produced no samples at all.
    func testARecordWithOnlyAFractionalBedtimeStillDates() throws {
        let json = Data("""
        {"data":[{"bedtime_start":"2026-07-19T23:30:00.000+00:00",
                  "type":"long_sleep",
                  "total_sleep_duration":27000}]}
        """.utf8)
        XCTAssertFalse(try OuraResponseParser.parseSleepUTC(json).isEmpty,
                       "a record with no `day` lost its only remaining date key")
    }

    // MARK: - The rule itself

    /// The one door, asserted directly: `PayloadDate.parse` is what the three
    /// connector parsers now share, and `verify.sh` bans the bare formatter that
    /// used to sit in each of them.
    func testPayloadDateAcceptsBothISOSpellings() {
        XCTAssertEqual(PayloadDate.parse(Self.fractional), PayloadDate.parse(Self.plain),
                       "the shared parser disagrees with itself across the two forms")
        XCTAssertNotNil(PayloadDate.parse(Self.fractional))
    }
}
