import XCTest
@testable import InsightKit

/// The typed provider parsers keep the unit and semantic knowledge that turns
/// specific fields into canonical vitals. Everything *else* in a payload is the
/// ingestion pipeline's job — see `IngestionPipelineTests`.
final class RawProviderParserTests: XCTestCase {

    func testOuraSleepStillProducesCanonicalVitals() throws {
        let json = """
        {"data":[{
          "day":"2026-01-10",
          "lowest_heart_rate":48,
          "average_hrv":45,
          "average_breath":14.2,
          "total_sleep_duration":25200
        }]}
        """.data(using: .utf8)!
        let samples = try OuraResponseParser.parseSleep(json)
        let byType = Dictionary(grouping: samples, by: \.type).mapValues { $0.first!.value }

        XCTAssertEqual(byType[.restingHeartRate], 48)
        XCTAssertEqual(byType[.heartRateVariabilityRMSSD], 45)
        XCTAssertEqual(try XCTUnwrap(byType[.respiratoryRate]), 14.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(byType[.sleepDurationHours]), 7, accuracy: 1e-9)
    }

    func testWithingsCanonicalMeasuresAreConverted() throws {
        // value × 10^unit — 70.5 kg, and a systolic reading.
        let json = """
        {"status":0,"body":{"measuregrps":[
          {"date":1736500000,"measures":[
            {"value":705,"type":1,"unit":-1},
            {"value":118,"type":10,"unit":0}
          ]}
        ]}}
        """.data(using: .utf8)!
        let samples = try WithingsResponseParser.parseMeasures(json)
        let byType = Dictionary(grouping: samples, by: \.type).mapValues { $0.first!.value }

        XCTAssertEqual(try XCTUnwrap(byType[.bodyMass]), 70.5, accuracy: 1e-9)
        XCTAssertEqual(byType[.bloodPressureSystolic], 118)
    }

    func testWithingsRejectsNonZeroApiStatus() {
        let json = #"{"status":401,"body":null}"#.data(using: .utf8)!
        XCTAssertThrowsError(try WithingsResponseParser.parseMeasures(json))
    }
}
