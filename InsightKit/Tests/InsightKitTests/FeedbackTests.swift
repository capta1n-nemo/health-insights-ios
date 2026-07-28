import XCTest
@testable import InsightKit

final class FeedbackTests: XCTestCase {
    func testAgeBanding() {
        XCTAssertEqual(Telemetry.ageBand(34), "30-39")
        XCTAssertEqual(Telemetry.ageBand(40), "40-49")
        XCTAssertEqual(Telemetry.ageBand(8), "0-9")
    }

    func testSignedPercentErrorMatchesTheUsersExample() {
        // Predicted 120/80, actual 112/91 (the user's worked example).
        let cohort = Cohort(sex: "male", ageBand: "30-39", ethnicity: "white_or_other", region: "low")
        let sys = PredictionOutcome(insightID: .bloodPressure, metric: .bloodPressureSystolic,
                                    predicted: 120, actual: 112, modelVersion: "bp-estimator-v2", cohort: cohort)
        let dia = PredictionOutcome(insightID: .bloodPressure, metric: .bloodPressureDiastolic,
                                    predicted: 80, actual: 91, modelVersion: "bp-estimator-v2", cohort: cohort)
        XCTAssertEqual(sys.signedPercentError, 7.14, accuracy: 0.05)   // over-predicted
        XCTAssertEqual(dia.signedPercentError, -12.09, accuracy: 0.05) // under-predicted
    }

    func testLaplaceIsZeroAtMedian() {
        XCTAssertEqual(Telemetry.laplace(scale: 2, u: 0.5), 0, accuracy: 1e-9)
    }

    func testEventCarriesOnlyCohortAndCoarseError() {
        let cohort = Cohort(sex: "male", ageBand: "30-39", ethnicity: "white_or_other", region: "low")
        let outcome = PredictionOutcome(insightID: .bloodPressure, metric: .bloodPressureSystolic,
                                        predicted: 120, actual: 112, modelVersion: "bp-estimator-v2",
                                        cohort: cohort, recordedAt: Date(timeIntervalSince1970: 1_771_200_000))
        let e = Telemetry.event(from: outcome, noiseScale: 0, u: 0.5)  // no noise → exact
        XCTAssertEqual(e.kind, "prediction_error")
        XCTAssertEqual(e.signedErrorPercent, 7)          // round(7.14)
        XCTAssertEqual(e.sex, "male")
        XCTAssertEqual(e.ageBand, "30-39")
        XCTAssertEqual(e.metric, "bloodPressureSystolic")
        XCTAssertNil(e.rating)
        // The event type has no field for the raw predicted/actual value — the
        // JSON that would be sent literally cannot contain them.
        let json = String(data: try! JSONEncoder().encode(e), encoding: .utf8)!
        XCTAssertFalse(json.contains("120"))
        XCTAssertFalse(json.contains("112"))
    }

    func testFeedbackEvent() {
        let cohort = Cohort(sex: "female", ageBand: "40-49", ethnicity: "unspecified", region: "unspecified")
        let e = Telemetry.event(insightID: .heartHealth, cohort: cohort,
                                modelVersion: "hearthealth-v1", rating: .inaccurate,
                                at: Date(timeIntervalSince1970: 1_771_200_000))
        XCTAssertEqual(e.kind, "feedback")
        XCTAssertEqual(e.rating, "inaccurate")
        XCTAssertNil(e.signedErrorPercent)
        XCTAssertNil(e.metric)
    }

    func testCohortFromProfileIsCoarse() {
        var p = UserHealthProfile()
        let now = Date()
        p.set(.init(kind: .dateOfBirth, value: now.addingTimeInterval(-34 * 365.2425 * 86400).timeIntervalSince1970, recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now)) // male
        let c = Cohort.from(profile: p, now: now)
        XCTAssertEqual(c.sex, "male")
        XCTAssertEqual(c.ageBand, "30-39")
        XCTAssertEqual(c.ethnicity, "unspecified")  // not provided → not guessed
    }
}
