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

/// A suggestion the user has waved away, and when.
///
/// Only the id and the instant are stored. The suggestion's own text is
/// regenerated from live data every time, so persisting a copy would let a
/// stale sentence outlive the numbers behind it — and the id is content-derived
/// (`grounding-cuffSystolic`, `departure-restingHeartRate`), which is what makes
/// "the same suggestion" mean the same thing across a regeneration.
@Model
final class SuggestionDismissalRecord {
    @Attribute(.unique) var suggestionID: String
    var dismissedAt: Date

    init(suggestionID: String, dismissedAt: Date) {
        self.suggestionID = suggestionID
        self.dismissedAt = dismissedAt
    }

    var dismissal: SuggestionDismissal {
        SuggestionDismissal(suggestionID: suggestionID, dismissedAt: dismissedAt)
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

/// A medication the reader is taking, with the doses they have logged.
///
/// **This app describes; it does not prescribe.** These records exist so the
/// reader can see what they took and what the pharmacology implies is still on
/// board. Nothing here recommends a dose, advances a titration, or suggests a
/// change — see `GLPCompound`.
@Model
final class MedicationRecord {
    var compoundRaw: String
    /// Display only. The same compound is sold under several names, so the
    /// pharmacology is keyed on `compoundRaw` and never on this.
    var brandName: String?
    var startedOn: Date
    var isActive: Bool
    @Relationship(deleteRule: .cascade) var doses: [DoseLogRecord]

    init(compoundRaw: String, brandName: String? = nil, startedOn: Date,
         isActive: Bool = true, doses: [DoseLogRecord] = []) {
        self.compoundRaw = compoundRaw
        self.brandName = brandName
        self.startedOn = startedOn
        self.isActive = isActive
        self.doses = doses
    }

    var compound: GLPCompound? { GLPCompound(rawValue: compoundRaw) }
}

/// One dose. `isInferred` is the safety flag the whole medication module turns
/// on: a dose the app extrapolated is stored as a **proposal**, drawn dashed,
/// and never counted as the reader's word until they confirm it.
@Model
final class DoseLogRecord {
    var takenAt: Date
    var milligrams: Double
    var injectionSite: String?
    var isInferred: Bool
    var confirmedAt: Date?

    init(takenAt: Date, milligrams: Double, injectionSite: String? = nil,
         isInferred: Bool = false, confirmedAt: Date? = nil) {
        self.takenAt = takenAt
        self.milligrams = milligrams
        self.injectionSite = injectionSite
        self.isInferred = isInferred
        self.confirmedAt = confirmedAt
    }

    /// The value type the pharmacokinetics model reads. A confirmed dose stops
    /// being an estimate, which is what makes the curve stop being dashed.
    var administered: AdministeredDose {
        AdministeredDose(takenAt: takenAt, milligrams: milligrams,
                         isInferred: isInferred && confirmedAt == nil,
                         site: injectionSite)
    }
}

/// A side effect the reader recorded, with how strongly they felt it.
///
/// Imported from Shotsy, which tracks these against a 1–10 severity. They were
/// parsed and then **thrown away** for a day — counted in the import summary
/// and stored nowhere — which is precisely the gap `DataDomain` exists to
/// close: data the app takes in and then cannot show you is data it has lost.
@Model
final class SideEffectRecord {
    var name: String
    /// Shotsy's own 1–10 scale, kept as recorded rather than rescaled — a
    /// severity the reader chose means what they meant by it.
    var severity: Int
    var date: Date
    /// Stable across re-imports, so sharing the same backup twice does not
    /// double the record.
    var externalID: String?

    init(name: String, severity: Int, date: Date, externalID: String? = nil) {
        self.name = name
        self.severity = severity
        self.date = date
        self.externalID = externalID
    }
}
