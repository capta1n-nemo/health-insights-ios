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
/// Internal rather than file-private since the provider subclasses moved out to
/// their own files: `OuraProvider` reads `missingScope(in:)` off it to name the
/// permission a 401 is complaining about. Swift's `private` is file-scoped, so
/// splitting a file always widens whatever the moved code touched — this is the
/// only member that was touched.
///
/// Oura answers errors with RFC7807 (`status` / `title` / `detail`) and puts the
/// actionable part — including *which scopes a token is missing* — in `detail`.
/// The app used to throw the body away and log a bare "HTTP 401", which is why
/// three endpoints failing every sync was impossible to diagnose from the log.
struct ProviderAPIError {
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
