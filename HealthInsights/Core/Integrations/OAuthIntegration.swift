import Foundation
import CryptoKit
import InsightKit

/// Endpoints + flow options for an OAuth provider. Client ID/secret are NOT here
/// — they live in the Keychain (entered by the user in the setup screen).
struct OAuthConfig {
    let authorizeURL: URL
    let tokenURL: URL
    let consoleURL: URL          // where the user creates their developer app
    let redirectURI: String
    let scopes: [String]
    let usesPKCE: Bool

    var callbackScheme: String {
        URLComponents(string: redirectURI)?.scheme ?? "healthinsights"
    }
}

enum IntegrationError: LocalizedError {
    case missingCredentials
    case notConnected
    case http(status: Int, detail: String?)
    case tokenParse
    case provider(String)
    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Add your API keys first."
        case .notConnected: return "Not connected."
        case .http(let code, let detail):
            let base: String
            switch code {
            case 401:
                base = "The provider refused the request (HTTP 401) — the saved sign-in is expired, revoked, or missing a permission. Reconnect to grant it again."
            case 403:
                base = "The provider blocked the request (HTTP 403). This usually means the account's subscription has lapsed, so its data isn't served over the API."
            case 429:
                base = "The provider is rate-limiting us (HTTP 429). Wait a few minutes and sync again."
            default:
                base = "The provider returned an error (HTTP \(code)). Check your Client ID/Secret and redirect URL."
            }
            guard let detail = detail?.nilIfBlank else { return base }
            return "\(base) It said: \(detail)"
        case .tokenParse: return "Couldn't read the provider's sign-in response. Double-check your Client Secret."
        case .provider(let detail): return detail
        }
    }
}

/// A provider's error body, unpacked for the diagnostics log.
///
/// Oura answers errors with RFC7807 (`status` / `title` / `detail`) and puts the
/// actionable part — including *which scopes a token is missing* — in `detail`.
/// The app used to throw the body away and log a bare "HTTP 401", which is why
/// three endpoints failing every sync was impossible to diagnose from the log.
private struct ProviderAPIError {
    let status: Int
    let title: String?
    let detail: String?
    let traceID: String?
    let bodySnippet: String?

    init(status: Int, body: Data, response: HTTPURLResponse?) {
        struct Problem: Decodable {
            let title: String?
            let detail: String?
            let error: String?
            let error_description: String?
        }
        // A FastAPI validation error puts an array in `detail`, which fails this
        // decode — the raw snippet below is the fallback for those.
        let problem = try? JSONDecoder().decode(Problem.self, from: body)
        self.status = status
        self.title = problem?.title ?? problem?.error
        self.detail = (problem?.detail ?? problem?.error_description)?.nilIfBlank
        self.traceID = response?.value(forHTTPHeaderField: "x-trace-id")
        self.bodySnippet = self.detail == nil
            ? String(data: body.prefix(500), encoding: .utf8)?.nilIfBlank
            : nil
    }

    /// The multi-line block written under the log's one-line headline.
    func diagnosticDetail(url: URL, milliseconds: Int, provider: String) -> String {
        var lines = ["GET \(url.absoluteString)", "\(milliseconds) ms · HTTP \(status)"]
        if let title { lines.append("Title: \(title)") }
        if let detail { lines.append("\(provider) says: \(detail)") }
        if let bodySnippet { lines.append("Body: \(bodySnippet)") }
        if let traceID { lines.append("Trace ID: \(traceID)   (quote this to \(provider) support)") }
        if let hint = Self.remedy(for: status, provider: provider) { lines.append(hint) }
        return lines.joined(separator: "\n")
    }

    /// The scope named in a missing-scope rejection, if that's what this is.
    ///
    /// Oura phrases it as "Token is not authorized access heart_health scope."
    /// Recognising the shape matters: a scope 401 is permanent, so refreshing
    /// the token and retrying only spends a single-use refresh token, doubles
    /// the failures in the log, and fails again identically.
    static func missingScope(in detail: String?) -> String? {
        guard let detail else { return nil }
        let pattern = "not authorized (?:to )?access\\s+([A-Za-z0-9_.-]+)\\s+scope"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: detail, range: NSRange(detail.startIndex..., in: detail)),
              let range = Range(match.range(at: 1), in: detail)
        else { return nil }
        return String(detail[range])
    }

    static func remedy(for status: Int, provider: String) -> String? {
        switch status {
        case 401:
            return """
                What to do: a 401 on one endpoint while others succeed in the same \
                sync means the saved permission grant doesn't cover this collection — \
                \(provider) returns 401 (not 403) for missing scopes and names the one \
                it wants in the message above. Enable that permission on your \(provider) \
                developer application, then reconnect in Settings ▸ Data sources.
                """
        case 403:
            return "What to do: 403 from \(provider) means the account's subscription has lapsed — the data still shows in \(provider)'s own app but isn't served over the API."
        case 429:
            return "What to do: \(provider) is throttling us. Wait a few minutes and sync again — Oura's ceiling is 5000 requests per 5 minutes."
        default:
            return nil
        }
    }
}

/// PKCE pair for the authorization-code flow (used by Oura).
private struct PKCE {
    let verifier: String
    let challenge: String
    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        verifier = Data(bytes).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncodedString()
    }
}

/// Real, on-device OAuth 2.0 integration shared by Oura and Withings. Performs
/// the interactive consent, token exchange/refresh, and data sync entirely on
/// the phone using credentials the user stored in the Keychain — no backend.
///
/// Provider-specific bits (token-response shape and the data endpoints) are
/// overridden by the `OuraProvider` / `WithingsProvider` subclasses.
@MainActor
class OAuthIntegration: HealthIntegration, ObservableObject {
    let id: String
    let displayName: String
    let iconSystemName: String
    let capabilities: IntegrationCapabilities
    let config: OAuthConfig
    let credentials: ProviderCredentialStore
    private let webFlow: OAuthWebFlow

    @Published private(set) var status: IntegrationStatus

    /// Coalesces token refreshes. Oura's refresh tokens are single-use, so nine
    /// endpoints each reacting to their own 401 by refreshing would revoke the
    /// grant instead of repairing it. Not `@Published` — it's plumbing, not state
    /// any view renders.
    private var refreshInFlight: Task<String?, Never>?
    /// Set when a refresh has already failed this sync — don't burn the (now
    /// probably consumed) refresh token again on every remaining endpoint.
    private var refreshFailedThisSync = false

    init(id: String, displayName: String, iconSystemName: String,
         capabilities: IntegrationCapabilities, config: OAuthConfig,
         credentials: ProviderCredentialStore, webFlow: OAuthWebFlow) {
        self.id = id
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.capabilities = capabilities
        self.config = config
        self.credentials = credentials
        self.webFlow = webFlow
        self.status = OAuthIntegration.initialStatus(id: id, credentials: credentials)
    }

    static func initialStatus(id: String, credentials: ProviderCredentialStore) -> IntegrationStatus {
        if credentials.tokens(for: id) != nil { return .connected(lastSync: nil) }
        return .notConnected
    }

    // MARK: Setup helpers (used by the in-app guide)

    var hasCredentials: Bool { credentials.hasCredentials(for: id) }
    var currentCredentials: ProviderCredentials? { credentials.credentials(for: id) }
    var redirectURI: String { config.redirectURI }
    var consoleURL: URL { config.consoleURL }

    func saveCredentials(clientID: String, clientSecret: String) {
        credentials.setCredentials(.init(clientID: clientID, clientSecret: clientSecret), for: id)
        if credentials.tokens(for: id) == nil { status = .notConnected }
    }

    func forget() {
        credentials.clearAll(for: id)
        status = .notConnected
    }

    // MARK: HealthIntegration

    func connect() async throws {
        DiagnosticsLog.shared.info(displayName, "Connect started")
        guard let creds = credentials.credentials(for: id) else {
            status = .error("Add your \(displayName) API keys first.")
            DiagnosticsLog.shared.fail(displayName, "No API keys entered")
            throw IntegrationError.missingCredentials
        }
        status = .connecting
        do {
            let state = UUID().uuidString
            let pkce = config.usesPKCE ? PKCE() : nil
            let authURL = buildAuthorizeURL(clientID: creds.clientID, state: state, challenge: pkce?.challenge)
            let callback = try await webFlow.start(authorizeURL: authURL, callbackScheme: config.callbackScheme)
            guard let code = Self.queryValue(callback, "code") else { throw IntegrationError.tokenParse }
            // The callback carries the scopes the user actually granted, which
            // the provider warns may differ from the ones we asked for. Capture
            // them: without this the app can never tell "permission withheld"
            // from "token broken", and both look like a bare 401 at sync time.
            let granted = Self.grantedScopes(from: callback)
            var tokens = try await exchangeCode(code, credentials: creds, verifier: pkce?.verifier)
            // Empty means the provider didn't say, not that it granted nothing.
            tokens.grantedScopes = granted.isEmpty ? nil : granted
            credentials.setTokens(tokens, for: id)
            status = .connected(lastSync: nil)
            logScopeGrant(granted, callback: callback)
            DiagnosticsLog.shared.ok(displayName, "Connected")
        } catch {
            status = .error(error.localizedDescription)
            DiagnosticsLog.shared.fail(displayName, "Connect failed: \(error.localizedDescription)")
            throw error
        }
    }

    func disconnect() async {
        credentials.clearTokens(for: id)
        status = .notConnected
    }

    func sync() async throws -> SyncedData {
        refreshFailedThisSync = false
        let started = Date()
        let token = try await validAccessToken()
        // Pull a long history so trends and future insights have depth to work with.
        let since = Calendar.current.date(byAdding: .day, value: -730, to: Date()) ?? Date()
        logSyncPreamble(since: since)
        let data = try await fetchData(accessToken: token, since: since)
        status = .connected(lastSync: Date())
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        DiagnosticsLog.shared.ok(displayName,
                                 "Sync finished in \(seconds)s — \(data.samples.count) vital sample(s), \(data.other.count) other value(s)")
        return data
    }

    /// Everything needed to interpret the API calls that follow: the window we
    /// asked for, and the permissions the token actually carries.
    private func logSyncPreamble(since: Date) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        var lines = ["Requested permissions at sign-in: \(config.scopes.joined(separator: " "))"]
        if let tokens = credentials.tokens(for: id) {
            lines.append("Permissions the provider granted: \(tokens.scopeSummary)")
            lines.append("Access token expires: \(tokens.expiresAt?.formatted(date: .abbreviated, time: .standard) ?? "not reported by provider")")
            lines.append("Refresh token stored: \(tokens.refreshToken == nil ? "no — a rejected token can only be fixed by reconnecting" : "yes")")
        }
        DiagnosticsLog.shared.info(displayName,
                                   "Sync started — window \(df.string(from: since)) → \(df.string(from: Date()))",
                                   detail: lines.joined(separator: "\n"))
    }

    /// Record what the consent screen handed back, and flag anything withheld —
    /// a withheld scope shows up much later as a 401 on just the endpoints that
    /// needed it, which reads like a broken token unless you know this.
    private func logScopeGrant(_ granted: [String], callback: URL) {
        let diag = DiagnosticsLog.shared
        let withheld = config.scopes.filter { !granted.contains($0) }
        let lists = "Requested: \(config.scopes.joined(separator: " "))\nGranted: \(granted.isEmpty ? "(not reported)" : granted.joined(separator: " "))"
        if granted.isEmpty {
            // Name the parameters the callback *did* carry — never their values,
            // one of them is the authorization code.
            let params = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.map(\.name).sorted().joined(separator: ", ") ?? "(none)"
            diag.null(displayName, "Sign-in didn't report which permissions were granted",
                      detail: """
                          \(lists)
                          The callback carried only: \(params) — no `scope`, so the grant can't be \
                          verified up front. This is not evidence that anything was refused: the \
                          app attempts every collection regardless and lets \(displayName) answer.
                          """)
        } else if withheld.isEmpty {
            diag.ok(displayName, "Granted all \(granted.count) requested permission(s)", detail: lists)
        } else {
            diag.null(displayName, "\(withheld.count) requested permission(s) were not granted",
                      detail: """
                          \(lists)
                          Withheld: \(withheld.joined(separator: " "))
                          Endpoints needing a withheld permission will fail with HTTP 401. \
                          Reconnect and tick every box on the \(displayName) consent screen. \
                          (A provider may also rename a scope, so a name listed here can be \
                          a rename rather than a refusal — check the 401s below.)
                          """)
        }
    }

    // MARK: Token flow

    private func buildAuthorizeURL(clientID: String, state: String, challenge: String?) -> URL {
        var comps = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]
        if let challenge {
            items.append(URLQueryItem(name: "code_challenge", value: challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        comps.queryItems = items
        return comps.url!
    }

    private func exchangeCode(_ code: String, credentials creds: ProviderCredentials, verifier: String?) async throws -> OAuthTokens {
        var params = [
            "grant_type": "authorization_code",
            "client_id": creds.clientID,
            "code": code,
            "redirect_uri": config.redirectURI
        ]
        // PKCE providers (Oura) don't need the single-use secret; only send it
        // when the user actually provided one.
        if !creds.clientSecret.isEmpty { params["client_secret"] = creds.clientSecret }
        if let verifier { params["code_verifier"] = verifier }
        params.merge(tokenExtraParameters()) { _, new in new }
        return try await requestTokens(params: params)
    }

    private func refreshTokens(_ refreshToken: String, credentials creds: ProviderCredentials) async throws -> OAuthTokens {
        var params = [
            "grant_type": "refresh_token",
            "client_id": creds.clientID,
            "refresh_token": refreshToken
        ]
        if !creds.clientSecret.isEmpty { params["client_secret"] = creds.clientSecret }
        params.merge(tokenExtraParameters()) { _, new in new }
        return try await requestTokens(params: params)
    }

    private func requestTokens(params: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if let code = http?.statusCode, code >= 400 {
            let failure = ProviderAPIError(status: code, body: data, response: http)
            DiagnosticsLog.shared.fail(displayName, "Token exchange → HTTP \(code)",
                                       detail: failure.diagnosticDetail(url: config.tokenURL,
                                                                        milliseconds: 0,
                                                                        provider: displayName))
            throw IntegrationError.http(status: code, detail: failure.detail)
        }
        DiagnosticsLog.shared.ok(displayName, "Token exchange OK",
                                 detail: "grant_type=\(params["grant_type"] ?? "?") · \(data.count) bytes back")
        return try parseTokenResponse(data)
    }

    func validAccessToken() async throws -> String {
        guard var tokens = credentials.tokens(for: id) else { throw IntegrationError.notConnected }
        if tokens.isExpired, let refresh = tokens.refreshToken,
           let creds = credentials.credentials(for: id) {
            DiagnosticsLog.shared.info(displayName, "Access token expired — refreshing before sync")
            let grants = tokens.grantedScopes
            tokens = try await refreshTokens(refresh, credentials: creds)
            // The refresh reply carries no scope list; carry the grant forward
            // so the log doesn't forget what the user consented to.
            tokens.grantedScopes = grants
            credentials.setTokens(tokens, for: id)
        }
        return tokens.accessToken
    }

    /// Exchange a rejected access token for a fresh one, at most once per sync.
    ///
    /// `validAccessToken()` alone isn't enough: it trusts the locally-stored
    /// expiry, and `isExpired` is `false` whenever the provider omitted
    /// `expires_in`. A token revoked (or aged out) server-side therefore looked
    /// permanently valid and every call 401'd forever with no self-repair.
    /// Returns `nil` when no refresh is possible — the caller then reports the
    /// original 401 rather than pretending it recovered.
    private func refreshedAccessToken(replacing stale: String) async -> String? {
        // Another endpoint in this same sync may have refreshed already.
        if let current = credentials.tokens(for: id)?.accessToken, current != stale {
            return current
        }
        if refreshFailedThisSync { return nil }
        if let refreshInFlight { return await refreshInFlight.value }

        let task = Task { @MainActor () -> String? in
            guard let tokens = self.credentials.tokens(for: self.id),
                  let refresh = tokens.refreshToken,
                  let creds = self.credentials.credentials(for: self.id) else {
                DiagnosticsLog.shared.fail(self.displayName, "Can't refresh the sign-in — no refresh token stored",
                                           detail: "Reconnect \(self.displayName) in Settings ▸ Data sources to get a new one.")
                return nil
            }
            do {
                var fresh = try await self.refreshTokens(refresh, credentials: creds)
                fresh.grantedScopes = tokens.grantedScopes
                self.credentials.setTokens(fresh, for: self.id)
                return fresh.accessToken
            } catch {
                DiagnosticsLog.shared.fail(self.displayName, "Token refresh failed: \(error.localizedDescription)",
                                           detail: "The refresh token is single-use and is now spent. Reconnect \(self.displayName) in Settings ▸ Data sources.")
                return nil
            }
        }
        refreshInFlight = task
        let result = await task.value
        refreshInFlight = nil
        if result == nil { refreshFailedThisSync = true }
        return result
    }

    // MARK: Overridable provider specifics

    /// Extra token-endpoint parameters (Withings needs `action=requesttoken`).
    func tokenExtraParameters() -> [String: String] { [:] }

    /// Parse the provider's token response. Default is the standard OAuth shape.
    func parseTokenResponse(_ data: Data) throws -> OAuthTokens {
        struct Standard: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        guard let t = try? JSONDecoder().decode(Standard.self, from: data) else {
            throw IntegrationError.tokenParse
        }
        return OAuthTokens(accessToken: t.access_token, refreshToken: t.refresh_token,
                           expiresAt: t.expires_in.map { Date().addingTimeInterval($0) })
    }

    /// Fetch + normalise the provider's data (canonical samples + raw "other").
    /// Must be overridden.
    func fetchData(accessToken: String, since: Date) async throws -> SyncedData {
        SyncedData()
    }

    // MARK: Helpers

    static func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// The scopes an OAuth callback reports as granted. Space-separated per the
    /// spec, but tolerate commas too.
    static func grantedScopes(from callback: URL) -> [String] {
        guard let raw = queryValue(callback, "scope") else { return [] }
        return raw.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "+" }).map(String.init)
    }

    /// GET a JSON endpoint, refreshing the access token once and retrying if the
    /// provider answers 401.
    ///
    /// A 401 has two very different causes that look identical in a log: a token
    /// the provider no longer accepts, and a token whose grant doesn't cover
    /// this particular collection. Retrying after a refresh separates them —
    /// if the retry also 401s, it's the grant, and the logged detail says so.
    func getJSON(_ url: URL, accessToken: String) async throws -> Data {
        do {
            return try await send(url, accessToken: accessToken)
        } catch IntegrationError.http(401, let detail) {
            // A missing scope is not something a fresh token fixes — it carries
            // exactly the same grant. Retrying would just log the failure twice.
            if let scope = ProviderAPIError.missingScope(in: detail) {
                DiagnosticsLog.shared.info(displayName,
                                           "Not retrying \(Self.endpointLabel(url)) — it needs the \u{201C}\(scope)\u{201D} permission, which a new token won't add",
                                           detail: "Only re-consenting with that scope enabled can fix this, so the sync moves on to the next collection.")
                throw IntegrationError.http(status: 401, detail: detail)
            }
            guard let retryToken = await refreshedAccessToken(replacing: accessToken) else {
                throw IntegrationError.http(status: 401, detail: detail)
            }
            DiagnosticsLog.shared.info(displayName,
                                       "Retrying \(Self.endpointLabel(url)) with a refreshed access token")
            return try await send(url, accessToken: retryToken)
        }
    }

    private func send(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let endpoint = Self.endpointLabel(url)
        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if code >= 400 {
                let failure = ProviderAPIError(status: code, body: data, response: http)
                DiagnosticsLog.shared.fail(displayName, "GET \(endpoint) → HTTP \(code)",
                                           detail: failure.diagnosticDetail(url: url,
                                                                            milliseconds: ms,
                                                                            provider: displayName))
                throw IntegrationError.http(status: code, detail: failure.detail)
            }
            DiagnosticsLog.shared.ok(displayName, "GET \(endpoint) → \(data.count) bytes",
                                     detail: "\(url.absoluteString)\n\(ms) ms · HTTP \(code)")
            return data
        } catch let e as IntegrationError {
            throw e   // HTTP failure already logged above
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let ns = error as NSError
            DiagnosticsLog.shared.fail(displayName, "GET \(endpoint) failed: \(error.localizedDescription)",
                                       detail: "\(url.absoluteString)\n\(ms) ms\n\(ns.domain) code \(ns.code)")
            throw error
        }
    }

    /// The collection name, which is what the log is about — never the token or
    /// the full query string.
    static func endpointLabel(_ url: URL) -> String { url.lastPathComponent }
}

// MARK: - Oura

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
        if let d = await fetch("sleep") {
            out.samples += (try? OuraResponseParser.parseSleep(d)) ?? []
            out.other += OuraResponseParser.parseRawDaily(d, endpoint: "sleep")
        }
        if let d = await fetch("daily_readiness") {
            out.samples += (try? OuraResponseParser.parseDailyReadiness(d)) ?? []
            out.other += OuraResponseParser.parseRawDaily(d, endpoint: "daily_readiness")
        }
        if let d = await fetch("daily_spo2") {
            out.samples += (try? OuraResponseParser.parseDailySpo2(d)) ?? []
            out.other += OuraResponseParser.parseRawDaily(d, endpoint: "daily_spo2")
        }
        if let d = await fetch("daily_activity") {
            out.samples += (try? OuraResponseParser.parseDailyActivity(d)) ?? []
            out.other += OuraResponseParser.parseRawDaily(d, endpoint: "daily_activity")
        }
        for endpoint in Self.rawCollections {
            if let d = await fetch(endpoint) {
                out.other += OuraResponseParser.parseRawDaily(d, endpoint: endpoint)
            }
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

// MARK: - Withings

@MainActor
final class WithingsProvider: OAuthIntegration {
    init(credentials: ProviderCredentialStore, webFlow: OAuthWebFlow) {
        super.init(
            id: MetricSource.withings.id,
            displayName: "Withings",
            iconSystemName: "scalemass",
            capabilities: .init(
                metrics: [.bodyMass, .bodyFatPercentage, .leanBodyMass,
                          .bloodPressureSystolic, .bloodPressureDiastolic],
                requiresBackend: false),
            config: .init(
                authorizeURL: URL(string: "https://account.withings.com/oauth2_user/authorize2")!,
                tokenURL: URL(string: "https://wbsapi.withings.net/v2/oauth2")!,
                consoleURL: URL(string: "https://developer.withings.com/dashboard/")!,
                redirectURI: "healthinsights://oauth/withings",
                scopes: ["user.metrics"],
                usesPKCE: false),
            credentials: credentials, webFlow: webFlow)
    }

    override func tokenExtraParameters() -> [String: String] {
        ["action": "requesttoken"]
    }

    override func parseTokenResponse(_ data: Data) throws -> OAuthTokens {
        struct Response: Decodable {
            let status: Int
            let error: String?
            let body: Body?
            struct Body: Decodable {
                let access_token: String
                let refresh_token: String?
                let expires_in: Double?
            }
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else {
            throw IntegrationError.tokenParse
        }
        // Withings signals problems with a non-zero status inside an HTTP 200.
        guard r.status == 0, let b = r.body else {
            let detail = r.error ?? "Withings error status \(r.status)"
            throw IntegrationError.provider("Withings didn't accept the sign-in (\(detail)). Check your Client ID/Secret and that the callback URL is registered.")
        }
        return OAuthTokens(accessToken: b.access_token, refreshToken: b.refresh_token,
                           expiresAt: b.expires_in.map { Date().addingTimeInterval($0) })
    }

    override func fetchData(accessToken: String, since: Date) async throws -> SyncedData {
        var comps = URLComponents(string: "https://wbsapi.withings.net/measure")!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "getmeas"),
            // A broad set of measure types; the ones we don't model yet are
            // captured as raw "other" data rather than dropped.
            URLQueryItem(name: "meastypes",
                         value: "1,4,5,6,8,9,10,11,12,54,71,73,76,77,88,91,123,130,135,136,137,138,139,155,167,168,169,170,174,196,197,198,226,227,229"),
            URLQueryItem(name: "category", value: "1"),
            URLQueryItem(name: "startdate", value: String(Int(since.timeIntervalSince1970)))
        ]
        let data = try await getJSON(comps.url!, accessToken: accessToken)
        var out = SyncedData()
        out.samples += (try? WithingsResponseParser.parseMeasures(data)) ?? []
        out.other += WithingsResponseParser.parseOtherMeasures(data)
        return out
    }
}

// MARK: - Whoop

@MainActor
final class WhoopProvider: OAuthIntegration {
    init(credentials: ProviderCredentialStore, webFlow: OAuthWebFlow) {
        super.init(
            id: MetricSource.whoop.id,
            displayName: "Whoop",
            iconSystemName: "bolt.heart",
            capabilities: .init(
                metrics: [.restingHeartRate, .heartRateVariabilityRMSSD,
                          .oxygenSaturation, .bodyTemperature, .dayStrain],
                requiresBackend: false),
            config: .init(
                authorizeURL: URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!,
                tokenURL: URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!,
                consoleURL: URL(string: "https://developer.whoop.com/")!,
                redirectURI: "healthinsights://oauth/whoop",
                scopes: ["read:recovery", "read:cycles", "read:sleep",
                         "read:workout", "read:body_measurement", "read:profile", "offline"],
                usesPKCE: false),
            credentials: credentials, webFlow: webFlow)
    }

    override func fetchData(accessToken: String, since: Date) async throws -> SyncedData {
        func fetch(_ path: String) async -> Data? {
            guard let url = URL(string: "https://api.prod.whoop.com/developer/v2/\(path)?limit=25") else { return nil }
            return try? await getJSON(url, accessToken: accessToken)
        }
        var out = SyncedData()
        if let d = await fetch("recovery") { out.samples += (try? WhoopResponseParser.parseRecovery(d)) ?? [] }
        if let d = await fetch("cycle") { out.samples += (try? WhoopResponseParser.parseCycles(d)) ?? [] }
        if let d = await fetch("activity/sleep") { out.samples += (try? WhoopResponseParser.parseSleep(d)) ?? [] }
        return out
    }
}

extension OAuthIntegration: Identifiable {}

/// Base64URL without padding, for PKCE.
private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
