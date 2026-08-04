import XCTest
@testable import InsightKit

/// Recorded-payload tests: the provider JSON shapes are pinned here so the
/// mapping to canonical samples is verified in CI without any live credentials.
final class OuraParserTests: XCTestCase {
    // Trimmed but structurally-real Oura v2 `usercollection/sleep` payload.
    let json = """
    {
      "data": [
        {
          "day": "2026-07-20",
          "bedtime_start": "2026-07-19T23:10:00+10:00",
          "lowest_heart_rate": 48,
          "average_heart_rate": 55.4,
          "average_hrv": 62,
          "average_breath": 14.2,
          "total_sleep_duration": 27000
        },
        {
          "day": "2026-07-21",
          "lowest_heart_rate": 50,
          "average_hrv": 58,
          "average_breath": 13.9,
          "total_sleep_duration": 25200
        }
      ],
      "next_token": null
    }
    """

    func testParsesSleepIntoCanonicalSamples() throws {
        let samples = try OuraResponseParser.parseSleepUTC(Data(json.utf8))
        // 2 nights × 4 metrics = 8 samples.
        XCTAssertEqual(samples.count, 8)
        XCTAssertTrue(samples.allSatisfy { $0.source == .oura })

        let restingHR = samples.samples(of: .restingHeartRate)
        XCTAssertEqual(restingHR.count, 2)
        XCTAssertEqual(restingHR.first?.value, 48)          // lowest_heart_rate wins

        let hrv = samples.latestValue(.heartRateVariabilityRMSSD)
        XCTAssertEqual(hrv, 58)                              // most recent night

        let sleep = samples.latest(.sleepDurationHours)
        XCTAssertEqual(sleep?.value ?? 0, 7.0, accuracy: 1e-9) // 25200s = 7h

        XCTAssertEqual(samples.latestValue(.respiratoryRate), 13.9)
    }

    func testFallsBackToAverageHeartRateWhenNoLowest() throws {
        let j = """
        { "data": [ { "day": "2026-07-22", "average_heart_rate": 60, "total_sleep_duration": 3600 } ] }
        """
        let samples = try OuraResponseParser.parseSleepUTC(Data(j.utf8))
        XCTAssertEqual(samples.latestValue(.restingHeartRate), 60)
    }
}

final class WithingsParserTests: XCTestCase {
    // Real-shaped Withings getmeas payload: weight (type 1), fat % (6),
    // systolic (10) + diastolic (9).
    let json = """
    {
      "status": 0,
      "body": {
        "updatetime": 1771200000,
        "measuregrps": [
          {
            "date": 1771200000,
            "measures": [
              { "value": 82150, "type": 1, "unit": -3 },
              { "value": 184,   "type": 6, "unit": -1 }
            ]
          },
          {
            "date": 1771100000,
            "measures": [
              { "value": 128, "type": 10, "unit": 0 },
              { "value": 82,  "type": 9,  "unit": 0 }
            ]
          }
        ]
      }
    }
    """

    func testParsesMeasuresIntoCanonicalSamples() throws {
        let samples = try WithingsResponseParser.parseMeasures(Data(json.utf8))
        XCTAssertTrue(samples.allSatisfy { $0.source == .withings })

        // 82150 × 10^-3 = 82.15 kg
        XCTAssertEqual(samples.latestValue(.bodyMass) ?? 0, 82.15, accuracy: 1e-6)
        // 184 × 10^-1 = 18.4 %
        XCTAssertEqual(samples.latestValue(.bodyFatPercentage) ?? 0, 18.4, accuracy: 1e-6)
        XCTAssertEqual(samples.latestValue(.bloodPressureSystolic), 128)
        XCTAssertEqual(samples.latestValue(.bloodPressureDiastolic), 82)
    }

    func testThrowsOnApiError() {
        let j = """
        { "status": 401, "body": null }
        """
        XCTAssertThrowsError(try WithingsResponseParser.parseMeasures(Data(j.utf8)))
    }

    func testUnknownTypesAreIgnored() throws {
        let j = """
        { "status": 0, "body": { "measuregrps": [
          { "date": 1771200000, "measures": [ { "value": 700, "type": 999, "unit": -1 } ] }
        ] } }
        """
        let samples = try WithingsResponseParser.parseMeasures(Data(j.utf8))
        XCTAssertTrue(samples.isEmpty)
    }
}
