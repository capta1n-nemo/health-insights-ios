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
    /// Pull the latest data — canonical samples plus any unmodelled "other" data.
    func sync() async throws -> SyncedData

    /// **What this source could not say, last time it was asked.**
    ///
    /// `status` answers *is it connected*. That is a different question from
    /// *did the last sync actually bring anything back*, and until backlog D10
    /// walked the unhappy paths nothing in the app asked the second one.
    ///
    /// Both of the failures that matter leave `status` reading
    /// `.connected(lastSync: <now>)`:
    ///
    /// - **Apple Health with reads denied.** `requestAuthorization` succeeds
    ///   whether the reader taps Allow or Don't Allow — HealthKit hides read
    ///   refusal by design, so a denied type is indistinguishable from an empty
    ///   one. Walked on the simulator: tapping *Don't Allow* produced a green
    ///   tick and *"Synced 22 seconds ago"*.
    /// - **An OAuth provider whose grant no longer covers anything.**
    ///   `OuraProvider.fetchData` records per-collection failures and returns
    ///   normally, so nine 401s in a row still ended in a green "Synced".
    ///
    /// This is the sentence that goes next to the status when that happens.
    /// `nil` when the last sync brought something back, and `nil` before the
    /// first sync — an unasked source is not a failing one.
    var syncWarning: String? { get }

    /// **Whether this source fetches for itself, or only ever receives.**
    ///
    /// Added for the notification pass (backlog `Q11`), which watches connected
    /// sources for the failure this app is least able to see on its own: still
    /// connected, still green, and bringing nothing back. That warning is only
    /// honest about a source the app *pulls from*. Shotsy has no API and
    /// Shortcuts is an automation the reader owns — telling somebody a
    /// push-only source "has stopped syncing" would blame the app's plumbing
    /// for a file they simply have not exported yet.
    ///
    /// ⚠️ **The default is `true`, and that is the safe direction rather than
    /// the tidy one.** A new pulling connector is watched without anybody
    /// having to remember to opt it in; a new push-only one has to say so, and
    /// the cost of forgetting is one wrong sentence rather than a stall that is
    /// never reported.
    var syncsOnItsOwn: Bool { get }
}

extension HealthIntegration {
    /// Sources that cannot come back silent (a file import, a Shortcut) get
    /// this and say nothing.
    var syncWarning: String? { nil }

    var syncsOnItsOwn: Bool { true }
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

    /// Sync all connected integrations, merging their data. Failures on one
    /// source don't abort the others.
    ///
    /// ⚠️ **The failure is logged, not swallowed.** This was `try?` until D10:
    /// a provider that threw — an expired token whose refresh had already been
    /// spent, a phone with no network — vanished without a trace, and the only
    /// evidence left anywhere was whatever the provider itself had happened to
    /// log on the way past. A discarded error is how a source stops syncing
    /// silently.
    func syncAllConnected() async -> SyncedData {
        var all = SyncedData()
        for integration in integrations {
            guard case .connected = integration.status else { continue }
            do {
                all.append(try await integration.sync())
            } catch {
                DiagnosticsLog.shared.fail(
                    integration.displayName,
                    "Sync failed: \(error.localizedDescription)",
                    detail: """
                        Nothing was fetched from \(integration.displayName) this time, so \
                        every card that leans on it is working from whatever was already \
                        stored. The readings already on this phone are untouched.
                        """)
            }
        }
        return all
    }
}
