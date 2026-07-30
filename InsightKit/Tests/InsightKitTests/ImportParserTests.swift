import XCTest
@testable import InsightKit

final class WhoopParserTests: XCTestCase {
    func testParsesRecovery() throws {
        let json = """
        { "records": [
          { "cycle_id": 93845, "created_at": "2026-07-20T11:25:44.774Z", "score_state": "SCORED",
            "score": { "recovery_score": 66, "resting_heart_rate": 52, "hrv_rmssd_milli": 64.2,
                       "spo2_percentage": 96.0, "skin_temp_celsius": 33.6 } }
        ], "next_token": null }
        """
        let samples = try WhoopResponseParser.parseRecovery(Data(json.utf8))
        XCTAssertEqual(samples.count, 4)
        XCTAssertTrue(samples.allSatisfy { $0.source == .whoop })
        XCTAssertEqual(samples.latestValue(.restingHeartRate), 52)
        XCTAssertEqual(samples.latestValue(.heartRateVariabilityRMSSD), 64.2)
        XCTAssertEqual(samples.latestValue(.oxygenSaturation), 96.0)
        // 33.6 °C is a *skin* figure. As `.bodyTemperature` it sat below the
        // 35.5 °C core floor on every sync, which held Vitals Check at zero for
        // anyone wearing a Whoop.
        XCTAssertEqual(samples.latestValue(.skinTemperature), 33.6)
        XCTAssertNil(samples.latestValue(.bodyTemperature))
    }

    func testParsesCyclesStrain() throws {
        let json = """
        { "records": [ { "start": "2026-07-20T06:00:00.000Z", "score": { "strain": 14.7 } } ] }
        """
        let samples = try WhoopResponseParser.parseCycles(Data(json.utf8))
        XCTAssertEqual(samples.latestValue(.dayStrain), 14.7)
    }
}

final class LabReportParserTests: XCTestCase {
    func testExtractsAustralianReportMmol() {
        let text = """
        LIPID STUDIES
        Total Cholesterol      5.2 mmol/L      (<5.5)
        HDL Cholesterol        1.3 mmol/L      (>1.0)
        LDL Cholesterol        3.1 mmol/L
        Triglycerides          1.1 mmol/L
        """
        let out = LabReportParser.extract(from: text)
        let total = out.first { $0.kind == .totalCholesterol }
        let hdl = out.first { $0.kind == .hdlCholesterol }
        XCTAssertEqual(total?.value ?? 0, 5.2, accuracy: 1e-6)
        XCTAssertEqual(hdl?.value ?? 0, 1.3, accuracy: 1e-6)
    }

    func testConvertsUSReportMgdl() {
        let text = "Cholesterol, Total 200 mg/dL\nHDL Cholesterol 50 mg/dL"
        let out = LabReportParser.extract(from: text)
        let total = out.first { $0.kind == .totalCholesterol }
        let hdl = out.first { $0.kind == .hdlCholesterol }
        XCTAssertEqual(total?.value ?? 0, 200 / 38.67, accuracy: 1e-4)   // ≈5.17 mmol/L
        XCTAssertEqual(hdl?.value ?? 0, 50 / 38.67, accuracy: 1e-4)      // ≈1.29 mmol/L
    }

    func testDoesNotReadHDLAsTotal() {
        // Only an HDL line present — must not be misfiled as total cholesterol.
        let out = LabReportParser.extract(from: "HDL Cholesterol 1.4 mmol/L")
        XCTAssertNil(out.first { $0.kind == .totalCholesterol })
        XCTAssertEqual(out.first { $0.kind == .hdlCholesterol }?.value ?? 0, 1.4, accuracy: 1e-6)
    }
}
