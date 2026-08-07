import Foundation
import InsightKit

#if DEBUG

/// **The four connector failures backlog D10 names, made walkable.** Debug builds only.
///
/// ## Why this exists
///
/// D10 asks what the reader sees when a source stops working. Two of its four
/// paths were walked on 2026-08-07 by tapping *Don't Allow* on the real Health
/// sheet. The other two could not be, and the reason was recorded honestly:
///
/// > *"All three need real Oura/Withings credentials and a live account; the
/// > simulator has none and there is no injection point (tokens live in the
/// > Keychain behind `ProviderCredentialStore`)."*
///
/// That is a true statement about the app as it stood, and it is also a
/// permanent one — no future session gets Oura credentials either, so *"cannot
/// be walked"* would have been the answer forever. **The missing thing was not
/// an account. It was the injection point.** This is it.
///
/// ## What it is not
///
/// It does not simulate a provider's *data*. Nothing here invents a heart rate.
/// It stands in for the **failure**, at the one place the failure enters the
/// app — the return value of a sync — so that everything downstream of it is
/// the shipped code reacting to a real error value. `IntegrationRegistry`'s
/// catch, `OAuthIntegration.sync`'s `status = .error`, `syncWarning`, the
/// Settings row, the Troubleshooting log and the Today surface are all the ones
/// the reader would get. Only the cause is manufactured.
///
/// It is `#if DEBUG`, so it cannot ship. There is no in-app switch on purpose:
/// arming is a launch-time decision, which keeps it out of every screen a
/// reader can reach and makes the armed state a property of the process rather
/// than of stored state somebody could leave behind.
///
/// ## How to walk one
///
/// ```bash
/// ./scripts/simulator.sh run                      # build, boot, install
/// udid=$(xcrun simctl list devices booted -j | …)
/// xcrun simctl terminate "$udid" com.jasonsalway.healthinsights
/// SIMCTL_CHILD_CONNECTOR_FAULTS=token-expired \
///     xcrun simctl launch "$udid" com.jasonsalway.healthinsights
/// ./scripts/simulator.sh shot
/// ```
///
/// Several can be armed at once, comma-separated. The armed set is written to
/// the diagnostics log on the first sync, so a screenshot of Troubleshooting —
/// or `./scripts/simulator.sh logs` — proves which build was on screen and what
/// it was pretending had gone wrong. A walk whose evidence cannot name its own
/// fault is the same trap `simulator.sh` fixed for screenshots.
enum ConnectorFault: String, CaseIterable, Sendable {

    /// A provider token that expires mid-sync and cannot be refreshed.
    ///
    /// The real shape: the access token is past `expiresAt`, the single-use
    /// refresh token was already spent (or the grant was revoked at the
    /// provider's end), so `refreshedAccessToken` returns `nil` and the
    /// original 401 stands. `sync()` throws.
    case tokenExpired = "token-expired"

    /// A connector that stopped syncing **silently**.
    ///
    /// The real shape and the nastiest of the four: every collection 401s
    /// individually, `fetchData` records each one and returns normally — one
    /// bad scope must not take the other eight down — so nothing throws and the
    /// sync *succeeds* with nothing in it. Before D10 that stamped
    /// `.connected(lastSync: Date())` and the reader read "Synced just now", in
    /// green, over an empty result.
    case silentStall = "silent-stall"

    /// No network.
    ///
    /// `URLSession` fails the request with `URLError.notConnectedToInternet`
    /// before any HTTP status exists. Distinct from `tokenExpired` in exactly
    /// the way that matters to a reader: **nothing is wrong with the
    /// connection and there is nothing to reconnect** — the app must not tell
    /// them to sign in again over a flight-mode toggle.
    case noNetwork = "no-network"

    /// HealthKit **partially** denied: some read types allowed, some refused.
    ///
    /// ⚠️ **The worst failure this app has, and the only one of the four with
    /// no error value anywhere in it.** HealthKit hides read refusal by design
    /// — a denied type returns the same empty array as a type the reader has
    /// never recorded — so a partially-denied phone reports success, returns
    /// data, and is indistinguishable from a healthy one at the point of sync.
    /// The full-denial case at least came back empty and could be noticed;
    /// this one cannot be noticed at the connector at all.
    ///
    /// So it is walked one level down, where it is actually visible: the
    /// synthetic seed is filled with a **hole** the exact shape of a declined
    /// Heart and Sleep category (`deniedMetrics`), and the question becomes the
    /// one the backlog row asks — *does a card read 100 because its instrument
    /// is absent?* That is a question about the cards, and the cards are on the
    /// simulator.
    case healthPartialDenial = "health-partial-denial"

    /// What a reader would have done to cause this, in one line. Logged so the
    /// evidence says what was being pretended rather than only that something was.
    var walkDescription: String {
        switch self {
        case .tokenExpired:
            return "The provider sign-in expired mid-sync and could not be refreshed (HTTP 401, refresh token spent)."
        case .silentStall:
            return "Every collection was refused individually; the sync completed with nothing in it."
        case .noNetwork:
            return "The phone has no network — the request never reached the provider."
        case .healthPartialDenial:
            return "Apple Health read access allowed for some categories and declined for others."
        }
    }

    /// The read types a declined **Heart** and **Sleep** category would hide.
    ///
    /// Chosen because they are the two categories a reader most plausibly
    /// switches off, and because between them they feed most of what the daily
    /// cards score. Everything else — steps, weight, body composition,
    /// nutrition — is left present, which is what makes this a *partial*
    /// denial and not the full one already walked: the app has plenty of data
    /// and is still blind in the place the scores come from.
    /// ⚠️ **The first version of this list was too small, and the walk said so.**
    /// It withheld `heartRateVariabilitySDNN` and left
    /// `heartRateVariabilityRMSSD` in, so the Last Night card read *"47 ms
    /// HRV"* over a supposedly-denied Heart category and the walk nearly
    /// recorded a defect that was really a hole in the fixture. A category the
    /// Health app switches off as **one** switch must be withheld as one
    /// switch, or the fault is not the fault it claims to be.
    static let deniedMetrics: Set<MetricType> = [
        // Heart, as the Health app groups it.
        .heartRate, .restingHeartRate, .walkingHeartRateAverage,
        .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD,
        .vo2Max, .heartRateRecovery, .atrialFibrillationBurden,
        // Respiratory.
        .respiratoryRate, .oxygenSaturation,
        // Sleep.
        .sleepDurationHours, .sleepEfficiency, .sleepDeepMinutes,
        .sleepRemMinutes, .sleepOnset, .sleepLatencyMinutes
    ]
}

/// The armed set for this process, read once at launch.
///
/// A `let` on a static, not a mutable store: arming is a property of the launch
/// and nothing in the running app may change it. That is what keeps a walk
/// reproducible — the screenshot, the log line and the behaviour all come from
/// the same decision, made before any of them.
enum ConnectorFaultInjection {

    /// Comma-separated raw values in `CONNECTOR_FAULTS`, or `-connector-faults
    /// <list>` in the launch arguments (which is how Xcode's scheme editor
    /// would set it).
    static let armed: Set<ConnectorFault> = {
        let env = ProcessInfo.processInfo.environment["CONNECTOR_FAULTS"]
        let args = ProcessInfo.processInfo.arguments
        let fromArgs = args.firstIndex(of: "-connector-faults").flatMap { i in
            i + 1 < args.count ? args[i + 1] : nil
        }
        let raw = env ?? fromArgs ?? ""
        return Set(raw.split(separator: ",")
                      .map { $0.trimmingCharacters(in: .whitespaces) }
                      .compactMap(ConnectorFault.init(rawValue:)))
    }()

    static func isArmed(_ fault: ConnectorFault) -> Bool { armed.contains(fault) }

    /// The one that stands in for an OAuth provider's sync, if any.
    ///
    /// Ordered rather than arbitrary, so arming two and getting one is a
    /// documented outcome instead of a set's iteration order.
    static var oauthFault: ConnectorFault? {
        for candidate in [ConnectorFault.noNetwork, .tokenExpired, .silentStall]
        where armed.contains(candidate) { return candidate }
        return nil
    }

    /// Say — once — what this process is pretending has gone wrong.
    ///
    /// ⚠️ Deliberately loud. A screenshot cannot show you that the build behind
    /// it was armed, which is precisely the trap `simulator.sh` fixed by
    /// printing the installed binary's mtime beside every shot. Evidence that
    /// cannot name its own conditions is evidence pointing somewhere unknown.
    @MainActor
    static func announceOnce() {
        guard !armed.isEmpty, !didAnnounce else { return }
        didAnnounce = true
        for fault in ConnectorFault.allCases where armed.contains(fault) {
            DiagnosticsLog.shared.info(
                "Fault injection",
                "ARMED: \(fault.rawValue)",
                detail: """
                    \(fault.walkDescription)

                    This is a DEBUG-only stand-in for a failure the simulator has no \
                    account to produce (backlog D10). No data below it is invented — \
                    everything downstream of the failure is the shipped code reacting \
                    to it. Nothing here can be armed in a release build.
                    """)
        }
    }

    @MainActor private static var didAnnounce = false

    /// The failure an armed OAuth provider's sync should produce instead of
    /// calling out.
    ///
    /// Throws for the two that throw, and returns an empty `SyncedData` for the
    /// one that does not — because *not throwing* is the entire character of a
    /// silent stall, and a stand-in that threw would walk a different bug.
    @MainActor
    static func standInForSync(displayName: String) async throws -> SyncedData? {
        guard let fault = oauthFault else { return nil }
        let diag = DiagnosticsLog.shared
        switch fault {
        case .noNetwork:
            diag.fail(displayName, "Request failed before it reached the provider",
                      detail: "URLError.notConnectedToInternet — the phone has no route out. Nothing is wrong with the saved sign-in.")
            throw URLError(.notConnectedToInternet)
        case .tokenExpired:
            diag.fail(displayName, "Token refresh failed: the refresh token is spent",
                      detail: "The access token was past its expiry and the single-use refresh token no longer works. Only reconnecting can fix this.")
            throw IntegrationError.http(status: 401,
                                        detail: "token expired and could not be refreshed")
        case .silentStall:
            for collection in ["daily_sleep", "daily_readiness", "daily_activity",
                               "heartrate", "workout", "session", "tag",
                               "daily_spo2", "sleep"] {
                diag.fail(displayName, "\(collection) refused (HTTP 401)",
                          detail: "The saved sign-in no longer covers this collection.")
            }
            return SyncedData()
        case .healthPartialDenial:
            return nil   // not an OAuth fault; handled at the seed
        }
    }
}

#endif
