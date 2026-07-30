import Foundation
import InsightKit

/// Whoop, on-device. Recovery, cycles and sleep.
@MainActor
final class WhoopProvider: OAuthIntegration {
    init(credentials: ProviderCredentialStore, webFlow: OAuthWebFlow) {
        super.init(
            id: MetricSource.whoop.id,
            displayName: "Whoop",
            iconSystemName: "bolt.heart",
            capabilities: .init(
                // Whoop's nightly figure is absolute *skin* temperature, so the
                // connect screen no longer promises a core reading it can't give.
                metrics: [.restingHeartRate, .heartRateVariabilityRMSSD,
                          .oxygenSaturation, .skinTemperature, .dayStrain],
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
        var out = SyncedData()
        func fetch(_ path: String, endpoint: String) async -> Data? {
            guard let url = URL(string: "https://api.prod.whoop.com/developer/v2/\(path)?limit=25") else { return nil }
            guard let data = try? await getJSON(url, accessToken: accessToken) else { return nil }
            // Whoop previously contributed nothing to the raw layer at all.
            out.payloads.append(IngestPayload(source: .whoop, endpoint: endpoint, data: data))
            return data
        }
        if let d = await fetch("recovery", endpoint: "recovery") {
            out.samples += (try? WhoopResponseParser.parseRecovery(d)) ?? []
        }
        if let d = await fetch("cycle", endpoint: "cycle") {
            out.samples += (try? WhoopResponseParser.parseCycles(d)) ?? []
        }
        if let d = await fetch("activity/sleep", endpoint: "sleep") {
            out.samples += (try? WhoopResponseParser.parseSleep(d)) ?? []
        }
        return out
    }
}
