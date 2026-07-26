import Foundation
import SwiftData
import InsightKit

/// Thin persistence facade over SwiftData for the app's local data. Keeps
/// SwiftData details out of the view layer.
@MainActor
final class DataStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) {
        let schema = Schema([GroundingRecord.self, ManualSampleRecord.self, IntegrationRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Grounding

    /// Build a `UserHealthProfile` from the most recent value per grounding kind.
    func loadProfile() -> UserHealthProfile {
        let records = (try? context.fetch(FetchDescriptor<GroundingRecord>())) ?? []
        var latest: [GroundingKind: GroundingRecord] = [:]
        for r in records {
            guard let kind = r.kind else { continue }
            if let existing = latest[kind], existing.recordedAt >= r.recordedAt { continue }
            latest[kind] = r
        }
        var profile = UserHealthProfile()
        for (kind, r) in latest {
            profile.set(.init(kind: kind, value: r.value, recordedAt: r.recordedAt))
        }
        return profile
    }

    /// Record a grounding value. Cuff BP values are also mirrored into
    /// `ManualSampleRecord`s so they show up in trends and calibrate the estimator.
    func saveGrounding(kind: GroundingKind, value: Double, at date: Date = Date()) {
        context.insert(GroundingRecord(kindRaw: kind.rawValue, value: value, recordedAt: date))
        switch kind {
        case .cuffSystolic:
            context.insert(ManualSampleRecord(metricRaw: MetricType.bloodPressureSystolic.rawValue,
                                              value: value, date: date, sourceID: MetricSource.manual.id))
        case .cuffDiastolic:
            context.insert(ManualSampleRecord(metricRaw: MetricType.bloodPressureDiastolic.rawValue,
                                              value: value, date: date, sourceID: MetricSource.manual.id))
        default:
            break
        }
        try? context.save()
    }

    // MARK: - Manual samples

    func loadManualSamples() -> [HealthMetricSample] {
        let records = (try? context.fetch(FetchDescriptor<ManualSampleRecord>())) ?? []
        return records.compactMap(\.sample)
    }

    // MARK: - Integration state

    func integrationRecord(_ id: String) -> IntegrationRecord? {
        let descriptor = FetchDescriptor<IntegrationRecord>(
            predicate: #Predicate { $0.integrationID == id })
        return (try? context.fetch(descriptor))?.first
    }

    func setIntegration(id: String, connected: Bool, lastSync: Date?) {
        if let existing = integrationRecord(id) {
            existing.connected = connected
            existing.lastSync = lastSync
        } else {
            context.insert(IntegrationRecord(integrationID: id, connected: connected, lastSync: lastSync))
        }
        try? context.save()
    }
}
