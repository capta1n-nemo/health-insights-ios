import Foundation
import SwiftData
import InsightKit

/// Persisted grounding fact (the user's most recent value per kind is what the
/// profile uses; we keep history so BP logs can be trended and the estimator
/// can calibrate).
@Model
final class GroundingRecord {
    var kindRaw: String
    var value: Double
    var recordedAt: Date

    init(kindRaw: String, value: Double, recordedAt: Date) {
        self.kindRaw = kindRaw
        self.value = value
        self.recordedAt = recordedAt
    }

    var kind: GroundingKind? { GroundingKind(rawValue: kindRaw) }
}

/// A manually-entered or imported measurement stored locally (e.g. a cuff BP
/// reading logged in-app), so it participates in trends and BP calibration
/// alongside HealthKit data.
@Model
final class ManualSampleRecord {
    var metricRaw: String
    var value: Double
    var date: Date
    var sourceID: String

    init(metricRaw: String, value: Double, date: Date, sourceID: String) {
        self.metricRaw = metricRaw
        self.value = value
        self.date = date
        self.sourceID = sourceID
    }

    var sample: HealthMetricSample? {
        guard let metric = MetricType(rawValue: metricRaw) else { return nil }
        let source = MetricSource(id: sourceID, displayName: sourceID == "manual" ? "Manual entry" : sourceID)
        return HealthMetricSample(type: metric, value: value, start: date, end: date, source: source)
    }
}

/// Remembers which integrations the user has connected.
@Model
final class IntegrationRecord {
    @Attribute(.unique) var integrationID: String
    var connected: Bool
    var lastSync: Date?

    init(integrationID: String, connected: Bool, lastSync: Date?) {
        self.integrationID = integrationID
        self.connected = connected
        self.lastSync = lastSync
    }
}
