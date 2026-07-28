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

final class WhoopSleepParserTests: XCTestCase {
    func testSleepHoursAndRespiratoryRate() throws {
        let json = """
        { "records": [ { "start": "2026-07-25T23:10:00.000Z", "score": {
            "respiratory_rate": 14.3,
            "stage_summary": { "total_in_bed_time_milli": 28800000, "total_awake_time_milli": 1800000 }
        } } ] }
        """
        let s = try WhoopResponseParser.parseSleep(Data(json.utf8))
        XCTAssertEqual(s.latestValue(.respiratoryRate)!, 14.3, accuracy: 1e-6)
        // (28,800,000 − 1,800,000) ms = 27,000,000 ms = 7.5 h
        XCTAssertEqual(s.latestValue(.sleepDurationHours)!, 7.5, accuracy: 1e-6)
        XCTAssertTrue(s.allSatisfy { $0.source == .whoop })
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
