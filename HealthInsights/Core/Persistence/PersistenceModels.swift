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

/// One day's computed score for one insight.
///
/// Scores were never stored, so "how has my readiness been trending?" had no
/// answer at all. `ScoreHistory.replay` can reconstruct the past from the raw
/// samples, but a stored row is what the app *actually told the user* that day —
/// so it wins over a recomputation, which would otherwise quietly rewrite
/// history every time a scoring weight changed.
///
/// Keyed by `insightID` + start-of-day, upserted once per day.
@Model
final class InsightScoreRecord {
    var insightRaw: String
    var day: Date
    var score: Double
    var confidenceRaw: String
    var contributorCount: Int

    init(insightRaw: String, day: Date, score: Double,
         confidenceRaw: String, contributorCount: Int) {
        self.insightRaw = insightRaw
        self.day = day
        self.score = score
        self.confidenceRaw = confidenceRaw
        self.contributorCount = contributorCount
    }

    var insight: InsightID? { InsightID(rawValue: insightRaw) }

    var point: ScorePoint {
        ScorePoint(date: day, score: score,
                   confidence: InsightConfidence(rawValue: confidenceRaw) ?? .moderate,
                   contributorCount: contributorCount)
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

/// A logged recreational/everyday substance-use event (private, on-device).
@Model
final class SubstanceEventRecord {
    @Attribute(.unique) var id: UUID
    var substanceRaw: String
    var timestamp: Date
    var units: Double?
    var note: String?

    init(id: UUID = UUID(), substanceRaw: String, timestamp: Date, units: Double? = nil, note: String? = nil) {
        self.id = id
        self.substanceRaw = substanceRaw
        self.timestamp = timestamp
        self.units = units
        self.note = note
    }

    var event: SubstanceEvent? {
        guard let substance = SubstanceClass(rawValue: substanceRaw) else { return nil }
        return SubstanceEvent(id: id, substance: substance, timestamp: timestamp, units: units, note: note)
    }
}

/// A "the model predicted X, the truth was Y" pair, kept on device to power the
/// feedback loop and (only if the user opts in) the anonymised model-improvement
/// telemetry. Cohort fields are stored flat and are already coarse buckets.
@Model
final class PredictionOutcomeRecord {
    @Attribute(.unique) var id: UUID
    var insightRaw: String
    var metricRaw: String
    var predicted: Double
    var actual: Double
    var modelVersion: String
    var sex: String
    var ageBand: String
    var ethnicity: String
    var region: String
    var recordedAt: Date

    init(id: UUID = UUID(), insightRaw: String, metricRaw: String, predicted: Double,
         actual: Double, modelVersion: String, cohort: Cohort, recordedAt: Date = Date()) {
        self.id = id; self.insightRaw = insightRaw; self.metricRaw = metricRaw
        self.predicted = predicted; self.actual = actual; self.modelVersion = modelVersion
        self.sex = cohort.sex; self.ageBand = cohort.ageBand
        self.ethnicity = cohort.ethnicity; self.region = cohort.region
        self.recordedAt = recordedAt
    }

    var cohort: Cohort { Cohort(sex: sex, ageBand: ageBand, ethnicity: ethnicity, region: region) }

    var outcome: PredictionOutcome? {
        guard let insight = InsightID(rawValue: insightRaw), let metric = MetricType(rawValue: metricRaw) else { return nil }
        return PredictionOutcome(id: id, insightID: insight, metric: metric, predicted: predicted,
                                 actual: actual, modelVersion: modelVersion, cohort: cohort, recordedAt: recordedAt)
    }
}

/// A qualitative "was this accurate?" tap for an insight.
@Model
final class FeedbackRecord {
    @Attribute(.unique) var id: UUID
    var insightRaw: String
    var ratingRaw: String
    var modelVersion: String
    var sex: String
    var ageBand: String
    var ethnicity: String
    var region: String
    var recordedAt: Date

    init(id: UUID = UUID(), insightRaw: String, ratingRaw: String, modelVersion: String,
         cohort: Cohort, recordedAt: Date = Date()) {
        self.id = id; self.insightRaw = insightRaw; self.ratingRaw = ratingRaw
        self.modelVersion = modelVersion
        self.sex = cohort.sex; self.ageBand = cohort.ageBand
        self.ethnicity = cohort.ethnicity; self.region = cohort.region
        self.recordedAt = recordedAt
    }

    var cohort: Cohort { Cohort(sex: sex, ageBand: ageBand, ethnicity: ethnicity, region: region) }
}
