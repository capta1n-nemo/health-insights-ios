import XCTest
@testable import InsightKit

final class OuraDailyParserTests: XCTestCase {
    func testDailyReadinessTemperatureDeviation() throws {
        let json = """
        { "data": [ { "day": "2026-07-25", "temperature_deviation": 0.3 } ] }
        """
        let s = try OuraResponseParser.parseDailyReadiness(Data(json.utf8))
        XCTAssertEqual(s.latestValue(.skinTemperatureDeviation), 0.3)
        XCTAssertEqual(s.first?.source, .oura)
    }

    func testDailySpo2() throws {
        let json = """
        { "data": [ { "day": "2026-07-25", "spo2_percentage": { "average": 97.2 } } ] }
        """
        let s = try OuraResponseParser.parseDailySpo2(Data(json.utf8))
        XCTAssertEqual(s.latestValue(.oxygenSaturation)!, 97.2, accuracy: 1e-6)
    }

    func testDailyActivityStepsAndEnergy() throws {
        let json = """
        { "data": [ { "day": "2026-07-25", "steps": 8450, "active_calories": 512 } ] }
        """
        let s = try OuraResponseParser.parseDailyActivity(Data(json.utf8))
        XCTAssertEqual(s.latestValue(.stepCount), 8450)
        XCTAssertEqual(s.latestValue(.activeEnergyBurned), 512)
    }
}

/// Whoop's sleep records, including the half that depends on a calendar.
///
/// Respiratory rate and duration read the same in every timezone; `.sleepOnset`
/// does not — it is signed hours from *local* midnight, kept only within ±6 h of
/// it. Until 2026-08-07 this parser took no calendar, so its onset output was
/// both untested and untestable deterministically: exactly the shape that lost
/// every Oura bedtime before `parseSleep(_:calendar:)` landed there. Everything
/// asserting on nights or bedtimes below goes through `parseSleepUTC`.
final class WhoopSleepParserTests: XCTestCase {

    /// A single night. `start` is 23:10Z, so the onset is 50 minutes before
    /// midnight and the sample is stamped at the morning the night ends on.
    private static let oneNight = """
    { "records": [ { "start": "2026-07-25T23:10:00.000Z", "score": {
        "respiratory_rate": 14.3,
        "stage_summary": { "total_in_bed_time_milli": 28800000, "total_awake_time_milli": 1800000 }
    } } ] }
    """

    func testSleepHoursAndRespiratoryRate() throws {
        let s = try WhoopResponseParser.parseSleep(Data(Self.oneNight.utf8))
        XCTAssertEqual(s.latestValue(.respiratoryRate)!, 14.3, accuracy: 1e-6)
        // (28,800,000 − 1,800,000) ms = 27,000,000 ms = 7.5 h
        XCTAssertEqual(s.latestValue(.sleepDurationHours)!, 7.5, accuracy: 1e-6)
        XCTAssertTrue(s.allSatisfy { $0.source == .whoop })
    }

    func testTheBedtimeIsReadFromTheRecordStart() throws {
        let s = try WhoopResponseParser.parseSleepUTC(Data(Self.oneNight.utf8))
        let onset = try XCTUnwrap(s.first { $0.type == .sleepOnset },
                                  "Whoop emitted no bedtime at all")
        // 23:10 is 50 minutes before midnight: −0.8333 h, negative because the
        // branch cut sits at midday (SleepOnset's own encoding).
        XCTAssertEqual(onset.value, -50.0 / 60, accuracy: 1e-6)
        XCTAssertEqual(onset.source, .whoop)
        // Stamped at the morning the night ends on, not the evening it began.
        XCTAssertEqual(onset.start, TestClock.utc.startOfDay(
            for: try XCTUnwrap(PayloadDate.parse("2026-07-26T00:00:00.000Z"))))
    }

    /// The parser's own comment says a record with no score still carries a
    /// bedtime, which is why the onset is gathered before the score guard. That
    /// claim was untested.
    func testARecordWithNoScoreStillCarriesABedtime() throws {
        let json = """
        { "records": [ { "start": "2026-07-25T22:30:00.000Z" } ] }
        """
        let s = try WhoopResponseParser.parseSleepUTC(Data(json.utf8))
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.first?.type, .sleepOnset)
        XCTAssertEqual(try XCTUnwrap(s.first?.value), -1.5, accuracy: 1e-6)
    }

    /// An afternoon nap is not a bedtime. It must yield no onset while still
    /// yielding its duration — the honest failure `SleepOnset.plausibleHours`
    /// documents.
    func testAnAfternoonNapProducesNoBedtime() throws {
        let json = """
        { "records": [ { "start": "2026-07-25T14:00:00.000Z", "score": {
            "stage_summary": { "total_in_bed_time_milli": 3600000, "total_awake_time_milli": 0 }
        } } ] }
        """
        let s = try WhoopResponseParser.parseSleepUTC(Data(json.utf8))
        XCTAssertNil(s.first { $0.type == .sleepOnset })
        XCTAssertEqual(try XCTUnwrap(s.latestValue(.sleepDurationHours)), 1, accuracy: 1e-6)
    }

    /// Whoop splits a broken night into several records. One night must produce
    /// one bedtime, and it must be the earliest plausible segment — whatever
    /// order the API returned them in.
    func testABrokenNightYieldsOneBedtimeFromItsEarliestSegment() throws {
        let json = """
        { "records": [
            { "start": "2026-07-26T03:20:00.000Z" },
            { "start": "2026-07-25T22:45:00.000Z" }
        ] }
        """
        let onsets = try WhoopResponseParser.parseSleepUTC(Data(json.utf8))
            .filter { $0.type == .sleepOnset }
        XCTAssertEqual(onsets.count, 1, "one night must not become two bedtimes")
        XCTAssertEqual(try XCTUnwrap(onsets.first?.value), -1.25, accuracy: 1e-6)
    }

    /// **The calendar is genuinely threaded through, not defaulted inside.**
    ///
    /// The same 23:10Z fixture reads as 09:10 at UTC+10 and is discarded as a
    /// nap. That is the shipped behaviour — a reader's bedtime is local — and
    /// asserting it in both directions is what proves the injection point
    /// exists, which is the whole finding.
    func testTheBedtimeIsResolvedAgainstTheCalendarItIsGiven() throws {
        var east = Calendar(identifier: .gregorian)
        east.timeZone = TimeZone(secondsFromGMT: 10 * 3600)!

        let inUTC = try WhoopResponseParser.parseSleep(Data(Self.oneNight.utf8),
                                                       calendar: TestClock.utc)
        XCTAssertNotNil(inUTC.first { $0.type == .sleepOnset })

        let inEast = try WhoopResponseParser.parseSleep(Data(Self.oneNight.utf8), calendar: east)
        XCTAssertNil(inEast.first { $0.type == .sleepOnset },
                     "23:10Z is 09:10 at UTC+10 and cannot be a bedtime")
        // The zone-independent half is unchanged by the move.
        XCTAssertEqual(try XCTUnwrap(inEast.latestValue(.sleepDurationHours)), 7.5, accuracy: 1e-6)
    }
}

final class WithingsExtraTypesTests: XCTestCase {
    func testExtraMeasureTypesMap() {
        XCTAssertEqual(WithingsResponseParser.metricType(for: 11), .heartRate)
        XCTAssertEqual(WithingsResponseParser.metricType(for: 54), .oxygenSaturation)
        XCTAssertEqual(WithingsResponseParser.metricType(for: 76), .muscleMass)
        XCTAssertEqual(WithingsResponseParser.metricType(for: 77), .bodyWaterPercentage)
        XCTAssertEqual(WithingsResponseParser.metricType(for: 88), .boneMass)
    }

    func testParsesPulseAndSpo2FromMeasures() throws {
        let json = """
        { "status": 0, "body": { "measuregrps": [
          { "date": 1771200000, "measures": [
            { "value": 62, "type": 11, "unit": 0 },
            { "value": 970, "type": 54, "unit": -1 }
          ] }
        ] } }
        """
        let s = try WithingsResponseParser.parseMeasures(Data(json.utf8))
        XCTAssertEqual(s.latestValue(.heartRate), 62)
        XCTAssertEqual(s.latestValue(.oxygenSaturation)!, 97.0, accuracy: 1e-6) // 970×10^-1
    }
}
