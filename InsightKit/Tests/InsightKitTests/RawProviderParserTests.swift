import XCTest
@testable import InsightKit

final class RawProviderParserTests: XCTestCase {
    func testOuraRawCapturesUnmappedAndNestedFields() {
        let json = """
        {"data":[{
          "day":"2026-01-10",
          "score":78,
          "average_hrv":45,
          "contributors":{"activity_balance":81,"resting_heart_rate":90},
          "tags":["a","b"],
          "active":true
        }]}
        """.data(using: .utf8)!
        let raw = OuraResponseParser.parseRawDaily(json, endpoint: "daily_readiness")
        let ids = Set(raw.map(\.identifier))
        // Top-level unmapped numeric captured.
        XCTAssertTrue(ids.contains("oura.daily_readiness.score"))
        // Nested contributor captured.
        XCTAssertTrue(ids.contains("oura.daily_readiness.contributors.activity_balance"))
        // Already-mapped field skipped.
        XCTAssertFalse(ids.contains("oura.daily_readiness.average_hrv"))
        // Booleans and arrays are not numeric → skipped.
        XCTAssertFalse(ids.contains("oura.daily_readiness.active"))
        XCTAssertFalse(ids.contains("oura.daily_readiness.tags"))
        // Value is correct.
        XCTAssertEqual(raw.first(where: { $0.identifier == "oura.daily_readiness.score" })?.value, 78)
    }

    func testWithingsOtherMeasuresCapturesUnknownTypes() {
        // Type 12 (temperature) isn't in our canonical map → should be "other".
        let json = """
        {"status":0,"body":{"measuregrps":[
          {"date":1736500000,"measures":[
            {"value":365,"type":12,"unit":-1},
            {"value":70,"type":1,"unit":0}
          ]}
        ]}}
        """.data(using: .utf8)!
        let other = WithingsResponseParser.parseOtherMeasures(json)
        XCTAssertEqual(other.count, 1)                  // only the unknown type
        XCTAssertEqual(other.first?.identifier, "withings.measure.12")
        XCTAssertEqual(other.first?.value ?? 0, 36.5, accuracy: 1e-9)
    }
}
