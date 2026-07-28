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
        let schema = Schema([GroundingRecord.self, ManualSampleRecord.self,
                             IntegrationRecord.self, SubstanceEventRecord.self])
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

    /// Log a full cuff blood-pressure reading at a chosen date. Stores the
    /// systolic + diastolic as dated manual samples (so they trend and feed the
    /// estimator's calibration), and refreshes the latest cuff grounding when
    /// this is the newest reading.
    func saveBloodPressureReading(systolic: Double, diastolic: Double, at date: Date) {
        context.insert(ManualSampleRecord(metricRaw: MetricType.bloodPressureSystolic.rawValue,
                                          value: systolic, date: date, sourceID: MetricSource.manual.id))
        context.insert(ManualSampleRecord(metricRaw: MetricType.bloodPressureDiastolic.rawValue,
                                          value: diastolic, date: date, sourceID: MetricSource.manual.id))
        // Keep the profile's "latest cuff reading" in sync for the risk model.
        let latestExisting = mostRecentGrounding(.cuffSystolic)?.recordedAt ?? .distantPast
        if date >= latestExisting {
            context.insert(GroundingRecord(kindRaw: GroundingKind.cuffSystolic.rawValue, value: systolic, recordedAt: date))
            context.insert(GroundingRecord(kindRaw: GroundingKind.cuffDiastolic.rawValue, value: diastolic, recordedAt: date))
        }
        try? context.save()
    }

    private func mostRecentGrounding(_ kind: GroundingKind) -> GroundingRecord? {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<GroundingRecord>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        return (try? context.fetch(descriptor))?.first
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

    // MARK: - Substance events

    func loadSubstanceEvents() -> [SubstanceEvent] {
        let descriptor = FetchDescriptor<SubstanceEventRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap(\.event)
    }

    func addSubstanceEvent(_ event: SubstanceEvent) {
        context.insert(SubstanceEventRecord(
            id: event.id, substanceRaw: event.substance.rawValue,
            timestamp: event.timestamp, units: event.units, note: event.note))
        try? context.save()
    }

    func deleteSubstanceEvent(id: UUID) {
        let descriptor = FetchDescriptor<SubstanceEventRecord>(
            predicate: #Predicate { $0.id == id })
        if let record = (try? context.fetch(descriptor))?.first {
            context.delete(record)
            try? context.save()
        }
    }
}
