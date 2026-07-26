import Foundation
import InsightKit

/// Connection state of an integration, surfaced in Settings.
enum IntegrationStatus: Equatable {
    case notConnected
    case connecting
    case connected(lastSync: Date?)
    case unavailable(reason: String)     // e.g. requires backend not yet configured
    case error(String)
}

/// What an integration can provide, so the UI can describe it.
struct IntegrationCapabilities: Equatable {
    let metrics: [MetricType]
    /// True if hooking it up needs the OAuth backend (Oura/Withings) vs. purely
    /// on-device (Apple Health).
    let requiresBackend: Bool
}

/// The extension point for every data source. A new wearable = one type
/// conforming here, registered in `IntegrationRegistry`. Insights never depend
/// on a concrete integration — only on the canonical samples it returns.
@MainActor
protocol HealthIntegration: AnyObject {
    var id: String { get }                 // stable, matches MetricSource.id
    var displayName: String { get }
    var iconSystemName: String { get }     // SF Symbol
    var capabilities: IntegrationCapabilities { get }
    var status: IntegrationStatus { get }

    /// Begin authentication / permission flow.
    func connect() async throws
    /// Tear down credentials.
    func disconnect() async
    /// Pull the latest data as canonical samples.
    func sync() async throws -> [HealthMetricSample]
}

/// Holds the set of available integrations and exposes them to Settings + sync.
/// Order here is the order shown in the UI.
@MainActor
final class IntegrationRegistry: ObservableObject {
    @Published private(set) var integrations: [any HealthIntegration]

    init(integrations: [any HealthIntegration]) {
        self.integrations = integrations
    }

    func integration(withID id: String) -> (any HealthIntegration)? {
        integrations.first { $0.id == id }
    }

    /// Sync all connected integrations, merging their samples. Failures on one
    /// source don't abort the others.
    func syncAllConnected() async -> [HealthMetricSample] {
        var all: [HealthMetricSample] = []
        for integration in integrations {
            if case .connected = integration.status {
                if let samples = try? await integration.sync() {
                    all.append(contentsOf: samples)
                }
            }
        }
        return all
    }
}
