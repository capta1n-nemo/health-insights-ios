import Foundation
import InsightKit

/// The Apple Health integration — the only fully-live provider in the MVP.
/// Delegates to `HealthKitService`; entirely on-device, no backend.
@MainActor
final class AppleHealthProvider: HealthIntegration, ObservableObject {
    let id = MetricSource.appleHealth.id
    let displayName = "Apple Health"
    let iconSystemName = "heart.fill"
    let capabilities = IntegrationCapabilities(
        metrics: [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
                  .respiratoryRate, .bloodPressureSystolic, .bloodPressureDiastolic,
                  .bodyMass, .bodyFatPercentage, .stepCount, .sleepDurationHours],
        requiresBackend: false)

    @Published private(set) var status: IntegrationStatus

    /// **Connected, and reading nothing.** Backlog D10.
    ///
    /// Walked on the simulator, 2026-08-07: tap *Don't Allow* on the Health
    /// permission sheet and `requestAuthorization` still succeeds — HealthKit
    /// reports refusal to nobody — so `connect()` stored "connected", Settings
    /// drew a green *"Synced 22 seconds ago"*, and four cards told the reader
    /// to *"Connect a wearable"* and *"Wear your watch to sleep"*: instructions
    /// for something they had already done, about a refusal the app had been
    /// told nothing about.
    ///
    /// The app cannot learn *why* it read nothing. It can notice **that** it
    /// did, which is enough to stop claiming a successful sync.
    @Published private(set) var syncTrouble: SyncTrouble?

    private let service: HealthKitService
    /// iOS deliberately doesn't expose HealthKit *read* authorization state, and
    /// it isn't revoked between launches — so we remember that the user opted in
    /// and restore "connected" on relaunch instead of asking them to reconnect
    /// every time.
    private let connectedKey = "integration.connected.apple_health"
    /// Re-request authorization once per launch so newly-added read types (e.g.
    /// after an app update that expands what we import) get surfaced. HealthKit
    /// only prompts for types the user hasn't decided yet, so this is silent once
    /// everything's been granted.
    private var didRequestAuthThisLaunch = false

    init(service: HealthKitService) {
        self.service = service
        if !service.isAvailable {
            self.status = .unavailable(reason: "Apple Health isn't available on this device.")
        } else if UserDefaults.standard.bool(forKey: connectedKey) {
            self.status = .connected(lastSync: nil)   // opted in on a previous launch
        } else {
            self.status = .notConnected
        }
    }

    func connect() async throws {
        guard service.isAvailable else {
            status = .unavailable(reason: "Apple Health isn't available on this device.")
            return
        }
        status = .connecting
        do {
            try await service.requestAuthorization()
            UserDefaults.standard.set(true, forKey: connectedKey)   // remember across launches
            status = .connected(lastSync: nil)
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func disconnect() async {
        // iOS doesn't let apps revoke HealthKit read access programmatically;
        // we simply stop syncing and mark disconnected.
        UserDefaults.standard.set(false, forKey: connectedKey)
        status = .notConnected
    }

    func sync() async throws -> SyncedData {
        // Ensure any read types added since the user first connected are authorized.
        if !didRequestAuthThisLaunch {
            didRequestAuthThisLaunch = true
            try? await service.requestAuthorization()
        }
        let data = await service.fetchAllData()
        // Said before the status is set, so a reader who opens Settings on the
        // next frame sees the two together rather than the green line alone.
        syncTrouble = (data.samples.isEmpty && data.other.isEmpty)
            // Short summary, because a Settings row has very little width left
            // beside its button. The long version — why a refusal and an empty
            // phone look identical from here — is the Troubleshooting entry
            // `HealthKitService.logReadOutcome` writes on the same pass.
            //
            // ⚠️ There **is** an action here and it is deliberately not
            // "reconnect": reconnecting cannot fix a declined read type, and
            // `disconnect()` already records that iOS gives an app no way to
            // ask again. The only thing that changes anything is the Health
            // app's own switch, so that is what it says.
            ? SyncTrouble(
                summary: "Read nothing this sync.",
                cause: "Apple Health returned no samples of any kind. Read access may have been "
                     + "declined, or there may genuinely be nothing recorded — HealthKit does not "
                     + "let an app tell those apart.",
                action: "Check Health \u{25B8} your profile \u{25B8} Apps & Services \u{25B8} Health Insights.")
            : nil
        status = .connected(lastSync: Date())
        return data
    }
}
