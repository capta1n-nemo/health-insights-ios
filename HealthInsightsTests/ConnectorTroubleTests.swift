import XCTest
import InsightKit
@testable import HealthInsights

/// **The four connector failures, and the one distinction that matters between
/// them.** Backlog D10.
///
/// The three provider paths were walked on the simulator on 2026-08-07 with
/// `ConnectorFaultInjection` standing in for accounts this project will never
/// have. A walk proves the app does the right thing *once*; these hold the part
/// a walk cannot re-run on every push.
///
/// The rule every test here defends is the same one: **the app must not tell a
/// reader to fix something that is not broken.** An expired grant and a train
/// tunnel arrive as two errors one sentence apart, and only one of them has
/// anything for the reader to do. Getting that backwards makes them re-authorise
/// a working connection — which also destroys the evidence of what the old grant
/// was doing.
@MainActor
final class ConnectorTroubleTests: XCTestCase {

    // MARK: - Nothing to do must render as nothing

    /// Every transport failure: named, and with **no action**.
    ///
    /// `URLError` is checked before any HTTP branch because no HTTP status ever
    /// existed for these — reading one would be inventing it.
    func testTransportFailuresOfferNoAction() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
            .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff,
            .timedOut, .dnsLookupFailed, .secureConnectionFailed
        ]
        for code in codes {
            let trouble = OAuthIntegration.trouble(for: URLError(code), displayName: "Oura")
            XCTAssertNil(trouble.action,
                         "\(code) is not something the reader can act on — an action here is an "
                         + "instruction to reconnect a connection that was never broken.")
            XCTAssertTrue(trouble.summary.contains("Oura"),
                          "The source has to be named; three can fail at once.")
            XCTAssertFalse(trouble.cause.isEmpty)
        }
    }

    /// A rate limit clears itself, so waiting is not an instruction worth
    /// printing next to a button.
    func testRateLimitOffersNoAction() {
        let trouble = OAuthIntegration.trouble(
            for: IntegrationError.http(status: 429, detail: nil), displayName: "Withings")
        XCTAssertNil(trouble.action)
    }

    // MARK: - Something to do must say what

    /// A 401 is the one case where silence costs the reader weeks of dark data,
    /// and reconnecting is genuinely the only repair — the refresh token is
    /// single-use, so the app cannot fix it from here.
    func testExpiredGrantSaysToReconnect() {
        let trouble = OAuthIntegration.trouble(
            for: IntegrationError.http(status: 401, detail: "token expired"),
            displayName: "Oura")
        let action = try? XCTUnwrap(trouble.action)
        XCTAssertNotNil(action)
        XCTAssertTrue(trouble.action?.contains("Reconnect") == true,
                      "A 401 must name reconnecting; nothing else repairs a spent grant.")
    }

    /// 403 is a lapsed subscription, not a broken sign-in — so it must **not**
    /// send the reader to reconnect, which would change nothing.
    func testBlockedRequestDoesNotSayToReconnect() {
        let trouble = OAuthIntegration.trouble(
            for: IntegrationError.http(status: 403, detail: nil), displayName: "Whoop")
        XCTAssertEqual(trouble.action?.contains("Reconnect"), false)
        XCTAssertTrue(trouble.action?.contains("subscription") == true)
    }

    /// An error the app has never seen is reported as itself. A guessed cause
    /// is worse than an unhelpful one, because it is actionable and wrong.
    func testUnknownErrorIsNotDressedUp() {
        struct Odd: LocalizedError { var errorDescription: String? { "something odd" } }
        let trouble = OAuthIntegration.trouble(for: Odd(), displayName: "Oura")
        XCTAssertNil(trouble.action)
        XCTAssertEqual(trouble.cause, "something odd")
    }

    // MARK: - The Settings row keeps both halves

    /// `SyncWarningLine(trouble:)` appends the action when there is one and
    /// stays quiet when there is not — the Settings-row half of the same rule.
    func testSyncWarningLineHonoursASilentAction() {
        let actionable = SyncTrouble(summary: "Oura refused the sign-in.",
                                     cause: "…", action: "Reconnect Oura.")
        XCTAssertEqual(SyncWarningLine(trouble: actionable).warning,
                       "Oura refused the sign-in. Reconnect Oura.")

        let silent = SyncTrouble(summary: "Couldn't reach Oura.", cause: "…", action: nil)
        XCTAssertEqual(SyncWarningLine(trouble: silent).warning, "Couldn't reach Oura.")

        XCTAssertNil(SyncWarningLine(trouble: nil).warning,
                     "A healthy row draws nothing at all.")
    }

    /// A source that cannot go silent says nothing, and `syncWarning` follows
    /// `syncTrouble` rather than being stored beside it — so a provider cannot
    /// warn on one surface and stay quiet on the other.
    func testWarningIsDerivedFromTrouble() {
        XCTAssertNil(ShortcutsIntegration().syncTrouble)
        XCTAssertNil(ShortcutsIntegration().syncWarning)
    }

    // MARK: - The fixture itself

    #if DEBUG
    /// **The fixture has to be the failure it claims to be.**
    ///
    /// The first `deniedMetrics` withheld SDNN and left rMSSD in, so the walk
    /// showed an HRV figure on a screen where the Heart category was supposedly
    /// off — and nearly recorded a defect that was really a hole in the
    /// fixture. A category the Health app switches off as one switch has to be
    /// withheld as one switch.
    func testDeniedMetricsWithholdsBothHRVChannels() {
        XCTAssertTrue(ConnectorFault.deniedMetrics.contains(.heartRateVariabilitySDNN))
        XCTAssertTrue(ConnectorFault.deniedMetrics.contains(.heartRateVariabilityRMSSD))
        XCTAssertTrue(ConnectorFault.deniedMetrics.contains(.heartRate))
        XCTAssertTrue(ConnectorFault.deniedMetrics.contains(.restingHeartRate))
        // Steps and weight stay, or it is a full denial and not a partial one —
        // the full one was already walked and is not what this fault is for.
        XCTAssertFalse(ConnectorFault.deniedMetrics.contains(.stepCount))
        XCTAssertFalse(ConnectorFault.deniedMetrics.contains(.bodyMass))
    }

    /// Nothing is armed unless the launch said so. A fixture that armed itself
    /// from stored state could survive into a session that was not walking.
    func testNothingIsArmedByDefault() {
        XCTAssertTrue(ConnectorFaultInjection.armed.isEmpty,
                      "The test runner passes no CONNECTOR_FAULTS, so nothing may be armed.")
        XCTAssertNil(ConnectorFaultInjection.oauthFault)
    }
    #endif
}
