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

    private let service: HealthKitService
    /// iOS deliberately doesn't expose HealthKit *read* authorization state, and
    /// it isn't revoked between launches — so we remember that the user opted in
    /// and restore "connected" on relaunch instead of asking them to reconnect
    /// every time.
    private let connectedKey = "integration.connected.apple_health"

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
        let data = await service.fetchAllData()
        status = .connected(lastSync: Date())
        return data
    }
}
