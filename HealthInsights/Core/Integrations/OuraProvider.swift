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
                //
                // `heartrate` is deliberately **not** requested. It was, for
                // months, and nothing ever called the endpoint — a permission
                // asked for and never used, which is the one kind of privacy
                // smell an on-device app has no excuse for. The endpoint serves
                // five-minute samples: roughly 288 a day, ~50k over a six-month
                // window, for a series Apple Health already mirrors in full
                // (53,717 of them, against zero from the direct pull). Ingesting
                // that is the same trade this app already refused when it chose
                // to summarise Oura's nightly `heart_rate.items` rather than
                // expand them.
                //
                // To reinstate: add "heartrate" back here, add a
                // `heartrate` case to `fetchPages` using `start_datetime` /
                // `end_datetime` (this endpoint does not take plain dates), and
                // decide what happens for a user whose Apple Health already
                // carries the same readings from the same ring.
                //
                // `tag` is Oura's published scope for the tag collections
                // (B12-1). Unlike `heartrate` above it is asked for *and* used:
                // `enhanced_tag` is fetched below, and tags exist nowhere else
                // — Apple Health has no tag concept, and the reader's whole
                // export contains not one tag row, so this scope is the only
                // route by which a tag can reach this app at all.
                scopes: ["daily", "workout", "session",
                         "spo2", "spo2Daily", "personal",
                         "stress", "heart_health", "tag"],
                usesPKCE: true),
            credentials: credentials, webFlow: webFlow)
    }

    /// Collections captured wholesale as raw "other" data. The four that also
    /// feed canonical metrics are fetched individually below, because each needs
    /// its own parser.
    ///
    /// `enhanced_tag` is here rather than in `mappedCollections` because a tag
    /// is not a measurement and has no typed parser: the pipeline captures the
    /// record's fields into the raw catalogue and `TagPromotion` reassembles
    /// them into `HealthTag`s from there — the same read-don't-move promotion
    /// `SymptomPromotion` uses.
    ///
    /// ⚠️ **`enhanced_tag` only, not the legacy `tag` endpoint.** Oura
    /// supersedes one with the other, and adding a deprecated endpoint that may
    /// answer 404 for every account would put a permanent red line in the sync
    /// summary — a diagnostic that always fails is a diagnostic nobody reads.
    /// `TagPromotion` still understands the legacy `tags: [...]` array shape, so
    /// a payload cached by an older build still promotes.
    private static let rawCollections = ["daily_sleep", "daily_stress", "daily_resilience",
                                         "daily_cardiovascular_age", "vO2_max",
                                         "enhanced_tag"]
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
        "vO2_max": "heart_health",
        "enhanced_tag": "tag"
    ]

    override func fetchData(accessToken: String, since: Date) async throws -> SyncedData {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let start = df.string(from: since), end = df.string(from: Date())
        let diag = DiagnosticsLog.shared
        var failures: [(endpoint: String, status: Int?, detail: String?)] = []

        /// Every page of one collection, oldest request first.
        ///
        /// Called for every collection, always. An earlier build skipped calls
        /// whose scope looked absent from the recorded grant — but Oura doesn't
        /// reliably return `scope` on the callback, so "didn't say" was read as
        /// "granted nothing" and three collections were withheld without ever
        /// being tried. Oura's own 401 is the only authority on this; guessing
        /// ahead of it can only lose data.
        ///
        /// Oura paginates with an opaque `next_token`, and this client read only
        /// the first page for its whole life. That was logged as a warning
        /// rather than fixed, on the reasoning that it had never fired — but a
        /// warning that has not fired is not evidence that it cannot, and the
        /// failure mode is silent history loss on exactly the long back-fill a
        /// first sync performs. Following the token costs one extra request in
        /// the case that has always held (no token, one page) and closes the
        /// hole in the case that hasn't.
        ///
        /// A page that fails takes the collection down with it rather than
        /// returning a truncated series, because a half-fetched history is
        /// indistinguishable downstream from a genuinely short one — the app
        /// would draw a gap it invented. The pages already retrieved are
        /// discarded and the endpoint is recorded as failed, which is what the
        /// summary line and the diagnostics are for.
        func fetchPages(_ endpoint: String) async -> [Data] {
            var pages: [Data] = []
            var token: String?
            var seenTokens: Set<String> = []

            while pages.count < Self.maxPages {
                var comps = URLComponents(string: "https://api.ouraring.com/v2/usercollection/\(endpoint)")!
                comps.queryItems = [
                    URLQueryItem(name: "start_date", value: start),
                    URLQueryItem(name: "end_date", value: end)
                ] + (token.map { [URLQueryItem(name: "next_token", value: $0)] } ?? [])
                guard let url = comps.url else {
                    failures.append((endpoint, nil, "Couldn't build the request URL."))
                    return []
                }
                do {
                    let data = try await getJSON(url, accessToken: accessToken)
                    pages.append(data)
                    guard let next = nextToken(in: data) else { break }
                    // A token that repeats means the server is handing back the
                    // same cursor, and following it would loop until `maxPages`
                    // fetching one page over and over. Stop and say so.
                    guard seenTokens.insert(next).inserted else {
                        DiagnosticsLog.shared.null(displayName,
                            "\(endpoint): pagination stopped — Oura repeated a page cursor",
                            detail: "The same next_token came back twice, so following it further would re-read a page already held. \(pages.count) page(s) kept.")
                        break
                    }
                    token = next
                } catch IntegrationError.http(let status, let detail) {
                    // Already logged in full by `send`; recorded here so the
                    // sync can end with one summary line instead of leaving the
                    // user to spot three unrelated-looking failures.
                    failures.append((endpoint, status, detail))
                    return []
                } catch {
                    failures.append((endpoint, nil, error.localizedDescription))
                    return []
                }
            }
            describeResponse(endpoint, pages)
            return pages
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

        /// One mapped collection: parse every page, capture every page.
        ///
        /// Both halves run per page rather than on a merged document. The typed
        /// parsers take Oura's `{"data": [...]}` envelope, and the ingestion
        /// pipeline is `EnvelopeSpec`-driven and expects the same shape — so
        /// stitching pages into a synthetic combined document would mean
        /// inventing a payload no endpoint ever returns. A page is a real
        /// response; that is what both sides should see.
        func pull(_ endpoint: String,
                  _ parse: (Data) throws -> [HealthMetricSample]) async {
            for page in await fetchPages(endpoint) {
                out.samples += (try? parse(page)) ?? []
                capture(endpoint, page)
            }
        }

        await pull("sleep", OuraResponseParser.parseSleep)
        await pull("daily_readiness", OuraResponseParser.parseDailyReadiness)
        await pull("daily_spo2", OuraResponseParser.parseDailySpo2)
        await pull("daily_activity", OuraResponseParser.parseDailyActivity)
        for endpoint in Self.rawCollections {
            for page in await fetchPages(endpoint) { capture(endpoint, page) }
        }
        summarise(failures, of: Self.collectionCount, diag: diag)
        return out
    }

    /// How many pages of one collection may be read before the client gives up.
    ///
    /// A backstop against a server that keeps handing out cursors, not a budget:
    /// Oura's own history has never exceeded one page in any observed sync, and
    /// twenty pages is far beyond anything the API has been seen to serve.
    private static let maxPages = 20

    /// Oura's opaque pagination cursor, or `nil` when this is the last page.
    private func nextToken(in data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (obj["next_token"] as? String)?.nilIfBlank
    }

    /// Log what a successful collection actually contained. "538006 bytes" says
    /// the call worked; "314 record(s)" says whether the data is there.
    ///
    /// Counts across every page, and says how many pages there were whenever
    /// there was more than one — the number that used to be a warning about
    /// data being dropped is now a statement about data being fetched.
    private func describeResponse(_ endpoint: String, _ pages: [Data]) {
        let records = pages.reduce(0) { total, page in
            guard let obj = try? JSONSerialization.jsonObject(with: page) as? [String: Any]
            else { return total }
            return total + ((obj["data"] as? [[String: Any]])?.count ?? 0)
        }
        let pageNote = pages.count > 1 ? " across \(pages.count) pages" : ""
        if records == 0 {
            DiagnosticsLog.shared.null(displayName, "\(endpoint): no records in the requested window",
                                       detail: "The call succeeded, so this is Oura reporting no data for \(endpoint) — not a permission problem.")
        } else {
            DiagnosticsLog.shared.ok(displayName, "\(endpoint): \(records) record(s)\(pageNote)")
        }
        if pages.count >= Self.maxPages {
            DiagnosticsLog.shared.null(displayName, "\(endpoint): stopped at the \(Self.maxPages)-page ceiling",
                                       detail: "Oura was still offering more pages for \(endpoint). History beyond \(records) records is not in this sync. Raise OuraProvider.maxPages if this is genuine rather than a repeating cursor.")
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
