import XCTest
@testable import InsightKit

private let gateNow = TestClock.now
private let gateCalendar = TestClock.utc

/// Nothing gated the Today summariser: every appearance of the root view, and
/// all three pull-to-refresh gestures, paid for a full on-device model
/// round-trip whether or not a single sample had landed.
final class SummaryFingerprintTests: XCTestCase {

    private func result(_ id: InsightID, score: Double?, headline: String = "Good",
                        driver: String = "Resting HR 55 bpm",
                        confidence: InsightConfidence = .high) -> InsightResult {
        InsightResult(id: id, title: id.rawValue, primaryValue: score, headline: headline,
                      score: score, confidence: confidence, explanation: "",
                      drivers: [driver], unmetRequirements: [])
    }

    private func fingerprint(_ results: [InsightResult],
                             at now: Date = gateNow) -> SummaryFingerprint {
        SummaryFingerprint.of(results: results, now: now, calendar: gateCalendar)
    }

    func testIdenticalResultsFingerprintIdentically() {
        let a = [result(.readiness, score: 72), result(.sleepQuality, score: 80)]
        let b = [result(.readiness, score: 72), result(.sleepQuality, score: 80)]
        XCTAssertEqual(fingerprint(a), fingerprint(b))
    }

    /// Sorted by id, so changing the engine's registration order doesn't silently
    /// invalidate every stored summary.
    func testRegistrationOrderDoesNotMatter() {
        let forwards = [result(.readiness, score: 72), result(.sleepQuality, score: 80)]
        XCTAssertEqual(fingerprint(forwards), fingerprint(forwards.reversed()))
    }

    func testAChangedScoreChangesTheFingerprint() {
        XCTAssertNotEqual(fingerprint([result(.readiness, score: 72)]),
                          fingerprint([result(.readiness, score: 61)]))
    }

    func testAChangedHeadlineChangesTheFingerprint() {
        XCTAssertNotEqual(fingerprint([result(.readiness, score: 72, headline: "Good")]),
                          fingerprint([result(.readiness, score: 72, headline: "Primed")]))
    }

    /// The leading driver is what the card previews and what the summariser leads
    /// on, so a change there has to invalidate.
    func testAChangedLeadDriverChangesTheFingerprint() {
        XCTAssertNotEqual(fingerprint([result(.readiness, score: 72, driver: "HRV up")]),
                          fingerprint([result(.readiness, score: 72, driver: "HRV down")]))
    }

    func testConfidenceIsPartOfTheFingerprint() {
        XCTAssertNotEqual(fingerprint([result(.readiness, score: 72, confidence: .high)]),
                          fingerprint([result(.readiness, score: 72, confidence: .moderate)]))
    }

    /// A dial can't render finer than a whole point and the summariser can't say
    /// anything finer, so floating-point noise must not defeat the gate.
    func testFloatingPointNoiseDoesNotInvalidate() {
        XCTAssertEqual(fingerprint([result(.readiness, score: 72.0001)]),
                       fingerprint([result(.readiness, score: 72.0002)]))
    }

    /// The copy says "today", so a summary must not survive midnight even when
    /// every number behind it is unchanged.
    func testTheSummaryDoesNotSurviveMidnight() {
        let results = [result(.readiness, score: 72)]
        let tomorrow = gateNow.addingTimeInterval(86_400)
        XCTAssertNotEqual(fingerprint(results), fingerprint(results, at: tomorrow))
    }

    /// But two passes on the same day do match — otherwise the gate never fires.
    func testTwoPassesOnOneDayMatch() {
        let results = [result(.readiness, score: 72)]
        XCTAssertEqual(fingerprint(results),
                       fingerprint(results, at: gateNow.addingTimeInterval(3600)))
    }

    func testAnInsightAppearingChangesTheFingerprint() {
        XCTAssertNotEqual(fingerprint([result(.readiness, score: 72)]),
                          fingerprint([result(.readiness, score: 72),
                                       result(.vitalSigns, score: 88)]))
    }
}

final class RefreshGateTests: XCTestCase {

    func testTheFirstRefreshAlwaysRuns() {
        XCTAssertEqual(RefreshGate.decide(lastRefreshAt: nil, now: gateNow), .run)
    }

    /// Three pull-to-refresh gestures in three seconds paid for three full syncs.
    func testASecondPullWithinTheFloorIsDeclined() {
        let decision = RefreshGate.decide(lastRefreshAt: gateNow.addingTimeInterval(-3),
                                          now: gateNow)
        guard case let .tooSoon(remaining) = decision else {
            return XCTFail("expected the gesture to be floored, got \(decision)")
        }
        XCTAssertEqual(remaining, RefreshGate.manualFloor - 3, accuracy: 1e-9)
    }

    func testAPullPastTheFloorRuns() {
        XCTAssertEqual(
            RefreshGate.decide(lastRefreshAt: gateNow.addingTimeInterval(-RefreshGate.manualFloor),
                               now: gateNow),
            .run)
    }

    /// A clock that has gone backwards — a timezone change, an NTP correction —
    /// must not lock refreshing out until it catches up.
    func testAClockGoingBackwardsDoesNotLockRefreshOut() {
        XCTAssertEqual(RefreshGate.decide(lastRefreshAt: gateNow.addingTimeInterval(600),
                                          now: gateNow),
                       .run)
    }
}
