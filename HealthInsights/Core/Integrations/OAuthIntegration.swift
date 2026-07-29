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
    case http(Int)
    case tokenParse
    case provider(String)
    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Add your API keys first."
        case .notConnected: return "Not connected."
        case .http(let code): return "The provider returned an error (HTTP \(code)). Check your Client ID/Secret and redirect URL."
        case .tokenParse: return "Couldn't read the provider's sign-in response. Double-check your Client Secret."
        case .provider(let detail): return detail
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
            let tokens = try await exchangeCode(code, credentials: creds, verifier: pkce?.verifier)
            credentials.setTokens(tokens, for: id)
            status = .connected(lastSync: nil)
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
        let token = try await validAccessToken()
        // Pull a long history so trends and future insights have depth to work with.
        let since = Calendar.current.date(byAdding: .day, value: -730, to: Date()) ?? Date()
        let data = try await fetchData(accessToken: token, since: since)
        status = .connected(lastSync: Date())
        return data
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
        if let code = (response as? HTTPURLResponse)?.statusCode, code >= 400 {
            DiagnosticsLog.shared.fail(displayName, "Token exchange → HTTP \(code)")
            throw IntegrationError.http(code)
        }
        DiagnosticsLog.shared.ok(displayName, "Token exchange OK")
        return try parseTokenResponse(data)
    }

    func validAccessToken() async throws -> String {
        guard var tokens = credentials.tokens(for: id) else { throw IntegrationError.notConnected }
        if tokens.isExpired, let refresh = tokens.refreshToken,
           let creds = credentials.credentials(for: id) {
            tokens = try await refreshTokens(refresh, credentials: creds)
            credentials.setTokens(tokens, for: id)
        }
        return tokens.accessToken
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

    func getJSON(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let endpoint = url.lastPathComponent
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code >= 400 {
                DiagnosticsLog.shared.fail(displayName, "GET \(endpoint) → HTTP \(code)")
                throw IntegrationError.http(code)
            }
            DiagnosticsLog.shared.ok(displayName, "GET \(endpoint) → \(data.count) bytes")
            return data
        } catch let e as IntegrationError {
            throw e   // HTTP failure already logged above
        } catch {
            DiagnosticsLog.shared.fail(displayName, "GET \(endpoint) failed: \(error.localizedDescription)")
            throw error
        }
    }
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
                consoleURL: URL(string: "https://cloud.ouraring.com/oauth/applications")!,
                redirectURI: "healthinsights://oauth/oura",
                scopes: ["daily", "heartrate", "workout", "session", "spo2", "personal"],
                usesPKCE: true),
            credentials: credentials, webFlow: webFlow)
    }

    override func fetchData(accessToken: String, since: Date) async throws -> SyncedData {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let start = df.string(from: since), end = df.string(from: Date())

        func fetch(_ endpoint: String) async -> Data? {
            var comps = URLComponents(string: "https://api.ouraring.com/v2/usercollection/\(endpoint)")!
            comps.queryItems = [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end)
            ]
            guard let url = comps.url else { return nil }
            return try? await getJSON(url, accessToken: accessToken)
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
        // Additional collections captured wholesale as raw "other" data.
        for endpoint in ["daily_sleep", "daily_stress", "daily_resilience",
                         "daily_cardiovascular_age", "vO2_max"] {
            if let d = await fetch(endpoint) {
                out.other += OuraResponseParser.parseRawDaily(d, endpoint: endpoint)
            }
        }
        return out
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
