import Foundation
import InsightKit

/// Withings, on-device. Body-composition scales and blood-pressure cuffs, whose
/// `measuregrps` payload is a flat list of typed measures rather than a document
/// per collection.
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
        out.payloads.append(IngestPayload(source: .withings, endpoint: "measure", data: data))
        return out
    }
}
