import Foundation
import InsightKit

/// Oura, on-device. The largest of the three providers and the reason
/// `OAuthIntegration` grew a refresh-coalescing, scope-aware error path at all:
/// Oura's refresh tokens are single-use, it answers a missing scope with 401
/// rather than 403, and it names the scope only in the RFC7807 `detail`.
///
/// Split out of `OAuthIntegration.swift`, which was the largest file in the app
/// at 858 lines and held three unrelated providers behind one base class.
@MainActor
final class OuraProvider: OAuthIntegration {
    init(credentials: ProviderCredentialStore, webFlow: OAuthWebFlow) {
        super.init(
            id: MetricSource.oura.id,
            displayName: "Oura",
            iconSystemName: "circle.circle",
            capabilities: .init(
                metrics: [.heartRateVariabilityRMSSD, .restingHeartRate,
                          .sleepDurationHours, .respiratoryRate],
                requiresBackend: false),
            config: .init(
                authorizeURL: URL(string: "https://cloud.ouraring.com/oauth/authorize")!,
                tokenURL: URL(string: "https://api.ouraring.com/oauth/token")!,
                // Oura moved the developer console off cloud.ouraring.com; the
                // OAuth endpoints above did not move with it.
                consoleURL: URL(string: "https://developer.ouraring.com/applications")!,
                redirectURI: "healthinsights://oauth/oura",
                // `spo2Daily` is the name in Oura's current OpenAPI spec; the
                // prose docs still say `spo2`. Ask for both — an unrecognised
                // scope is ignored, whereas guessing wrong silently loses the
                // SpO2 collection.
                //
                // `stress` and `heart_health` appear in neither the scope table
                // nor the OpenAPI spec (both stop at eight scopes) — they came
                // from Oura's own 401 bodies, which name the scope they want.
                // Without them Resilience, Cardiovascular Age and VO₂ Max are
                // permanently unreachable.
                scopes: ["daily", "heartrate", "workout", "session",
                         "spo2", "spo2Daily", "personal",
                         "stress", "heart_health"],
                usesPKCE: true),
            credentials: credentials, webFlow: webFlow)
    }

    /// Collections captured wholesale as raw "other" data. The four that also
    /// feed canonical metrics are fetched individually below, because each needs
    /// its own parser.
    private static let rawCollections = ["daily_sleep", "daily_stress", "daily_resilience",
                                         "daily_cardiovascular_age", "vO2_max"]
    private static let mappedCollections = ["sleep", "daily_readiness", "daily_spo2", "daily_activity"]
    private static var collectionCount: Int { rawCollections.count + mappedCollections.count }

    /// The scope Oura demands for a collection, where it isn't just `daily`.
    /// Learned from Oura's own 401 bodies — its published scope table and
    /// OpenAPI spec both stop at eight scopes and say nothing about which
    /// endpoint needs which. Used only to name the permission in the summary
    /// when a rejection didn't spell it out; never to pre-empt a call.
    private static let requiredScope: [String: String] = [
        "daily_resilience": "stress",
        "daily_cardiovascular_age": "heart_health",
        "vO2_max": "heart_health"
    ]

    override func fetchData(accessToken: String, since: Date) async throws -> SyncedData {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let start = df.string(from: since), end = df.string(from: Date())
        let diag = DiagnosticsLog.shared
        var failures: [(endpoint: String, status: Int?, detail: String?)] = []

        // Every collection is attempted, always. An earlier build skipped calls
        // whose scope looked absent from the recorded grant — but Oura doesn't
        // reliably return `scope` on the callback, so "didn't say" was read as
        // "granted nothing" and three collections were withheld without ever
        // being tried. Oura's own 401 is the only authority on this; guessing
        // ahead of it can only lose data.
        func fetch(_ endpoint: String) async -> Data? {
            var comps = URLComponents(string: "https://api.ouraring.com/v2/usercollection/\(endpoint)")!
            comps.queryItems = [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end)
            ]
            guard let url = comps.url else {
                failures.append((endpoint, nil, "Couldn't build the request URL."))
                return nil
            }
            do {
                let data = try await getJSON(url, accessToken: accessToken)
                describeResponse(endpoint, data)
                return data
            } catch IntegrationError.http(let status, let detail) {
                // Already logged in full by `send`; recorded here so the sync
                // can end with one summary line instead of leaving the user to
                // spot three unrelated-looking failures.
                failures.append((endpoint, status, detail))
                return nil
            } catch {
                failures.append((endpoint, nil, error.localizedDescription))
                return nil
            }
        }

        // Pull every collection we can; a single endpoint failing (e.g. a scope
        // the user didn't grant) must not abort the rest. Mapped endpoints feed
        // canonical metrics AND are raw-captured for any extra fields.
        var out = SyncedData()
        /// Every response is handed to the pipeline verbatim, whether or not a
        /// typed parser also reads it. The typed parsers contribute unit-aware
        /// canonical vitals; the pipeline contributes everything else in the
        /// document, including fields added since this code was written.
        func capture(_ endpoint: String, _ data: Data) {
            out.payloads.append(IngestPayload(source: .oura, endpoint: endpoint, data: data))
        }

        if let d = await fetch("sleep") {
            out.samples += (try? OuraResponseParser.parseSleep(d)) ?? []
            capture("sleep", d)
        }
        if let d = await fetch("daily_readiness") {
            out.samples += (try? OuraResponseParser.parseDailyReadiness(d)) ?? []
            capture("daily_readiness", d)
        }
        if let d = await fetch("daily_spo2") {
            out.samples += (try? OuraResponseParser.parseDailySpo2(d)) ?? []
            capture("daily_spo2", d)
        }
        if let d = await fetch("daily_activity") {
            out.samples += (try? OuraResponseParser.parseDailyActivity(d)) ?? []
            capture("daily_activity", d)
        }
        for endpoint in Self.rawCollections {
            if let d = await fetch(endpoint) { capture(endpoint, d) }
        }
        summarise(failures, of: Self.collectionCount, diag: diag)
        return out
    }

    /// Log what a successful collection actually contained. "538006 bytes" says
    /// the call worked; "314 record(s)" says whether the data is there.
    private func describeResponse(_ endpoint: String, _ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let records = (obj["data"] as? [[String: Any]])?.count ?? 0
        let nextToken = (obj["next_token"] as? String)?.nilIfBlank
        if records == 0 {
            DiagnosticsLog.shared.null(displayName, "\(endpoint): no records in the requested window",
                                       detail: "The call succeeded, so this is Oura reporting no data for \(endpoint) — not a permission problem.")
        } else {
            DiagnosticsLog.shared.ok(displayName, "\(endpoint): \(records) record(s)")
        }
        if let nextToken {
            DiagnosticsLog.shared.null(displayName, "\(endpoint): more pages available — only the first was read",
                                       detail: "Oura returned next_token=\(nextToken.prefix(12))…, meaning this collection is longer than one page and the app is not yet following pagination. History older than the first page is missing for \(endpoint).")
        }
    }

    /// One line the user can act on, instead of three scattered failures.
    private func summarise(_ failures: [(endpoint: String, status: Int?, detail: String?)],
                           of attempted: Int, diag: DiagnosticsLog) {
        guard !failures.isEmpty else {
            diag.ok(displayName, "All \(attempted) collections fetched")
            return
        }
        let names = failures.map(\.endpoint).joined(separator: ", ")
        var lines = failures.map { f in
            "· \(f.endpoint) → \(f.status.map { "HTTP \($0)" } ?? "not attempted"): \(f.detail ?? "no reason given")"
        }
        // Name the exact permissions to switch on, rather than "tick everything".
        // Oura usually names the scope in the rejection; the map covers the case
        // where a 401 arrives without one.
        let missing = Set(failures.compactMap { f -> String? in
            if let named = ProviderAPIError.missingScope(in: f.detail) { return named }
            return f.status == 401 ? Self.requiredScope[f.endpoint] : nil
        }).sorted()
        if !missing.isEmpty {
            let succeeded = attempted - failures.count
            let preamble = succeeded > 0
                ? "\(succeeded) other collections succeeded, so the token itself is fine — these \(failures.count) need permissions the saved grant doesn't include."
                : "These \(failures.count) collections need permissions the saved grant doesn't include."
            lines.append("")
            lines.append("""
                \(preamble)
                Missing: \(missing.joined(separator: ", ")).
                1. developer.ouraring.com/applications ▸ your app — confirm those scopes are \
                enabled, and save.
                2. Revoke this app's access in your Oura account's connected-apps list. This \
                step is the one that's easy to skip and usually the reason a reconnect changes \
                nothing: with an authorization already on file, Oura can reissue a token against \
                the *old* grant without ever showing the consent screen, so newly-enabled scopes \
                never get attached.
                3. Reconnect in Settings ▸ Data sources, and check the consent screen actually \
                appears and lists the new permissions.
                """)
        }
        lines.append("Permissions this token carries: \(credentials.tokens(for: id)?.scopeSummary ?? "no token stored")")
        diag.fail(displayName, "\(failures.count) of \(attempted) collections failed — \(names)",
                  detail: lines.joined(separator: "\n"))
    }
}
