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

    init(service: HealthKitService) {
        self.service = service
        self.status = service.isAvailable ? .notConnected
            : .unavailable(reason: "Apple Health isn't available on this device.")
    }

    func connect() async throws {
        guard service.isAvailable else {
            status = .unavailable(reason: "Apple Health isn't available on this device.")
            return
        }
        status = .connecting
        do {
            try await service.requestAuthorization()
            status = .connected(lastSync: nil)
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func disconnect() async {
        // iOS doesn't let apps revoke HealthKit read access programmatically;
        // we simply stop syncing and mark disconnected.
        status = .notConnected
    }

    func sync() async throws -> [HealthMetricSample] {
        let samples = await service.fetchRecentSamples()
        status = .connected(lastSync: Date())
        return samples
    }
}
