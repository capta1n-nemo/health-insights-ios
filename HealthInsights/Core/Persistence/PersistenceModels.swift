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

    /// How this figure got here — see `ScreenTimeProvenance`. Optional so
    /// SwiftData migrates the rows written before provenance existed; nil reads
    /// as `.manual`, which is what every one of them was.
    var provenanceRaw: String?
    /// When the row was **written**, as opposed to the day it describes.
    ///
    /// What makes "a screenshot beats manual, unless I manually override it
    /// again" decidable. Optional for the same migration reason, and a nil
    /// reads as `.distantPast` — deliberately, so a figure entered before this
    /// existed loses to a screenshot imported now, which is the right answer:
    /// the reader had not seen the screenshot when they typed it.
    var recordedAt: Date?

    init(metricRaw: String, value: Double, date: Date, sourceID: String,
         provenance: ScreenTimeProvenance = .manual, recordedAt: Date = Date()) {
        self.metricRaw = metricRaw
        self.value = value
        self.date = date
        self.sourceID = sourceID
        self.provenanceRaw = provenance.rawValue
        self.recordedAt = recordedAt
    }

    var provenance: ScreenTimeProvenance {
        provenanceRaw.flatMap(ScreenTimeProvenance.init(rawValue:)) ?? .manual
    }

    /// This row as a precedence candidate.
    var screenTimeEntry: ScreenTimeEntry {
        ScreenTimeEntry(day: date, minutes: value, provenance: provenance,
                        recordedAt: recordedAt ?? .distantPast)
    }

    var sample: HealthMetricSample? {
        guard let metric = MetricType(rawValue: metricRaw) else { return nil }
        let source = MetricSource(id: sourceID, displayName: sourceID == "manual" ? "Manual entry" : sourceID)
        return HealthMetricSample(type: metric, value: value, start: date, end: date, source: source)
    }
}

/// One body scan — the derived measurements, and where its raw assets live.
///
/// **The measurements are stored as encoded JSON, not as columns.** A scan's
/// shape is `(site, side, value)` triples precisely so a later parser can find
/// sites this one did not, and a column per site would defeat that on the first
/// schema change — which is the failure the reader asked to design around.
///
/// `assetFolder` is nil for a tape measurement, which has no raw data to keep.
/// The camera and LiDAR captures fill it, and `BodyScan.isReparseable` already
/// answers whether a given scan can take part in a re-derivation.
@Model
final class BodyScanRecord {
    var id: UUID = UUID()
    var capturedAt: Date = Date()
    var modeRaw: String = BodyScan.CaptureMode.tape.rawValue
    /// Which parser produced the stored measurements. A later build sweeps
    /// every scan behind its own version and re-derives from the assets.
    var parserVersion: Int = 1
    /// A `BodyScan`, JSON-encoded.
    var payload: Data?
    /// Folder name under Application Support/BodyScans, when assets were kept.
    var assetFolder: String?

    init(scan: BodyScan, assetFolder: String? = nil) {
        self.id = scan.id
        self.capturedAt = scan.capturedAt
        self.modeRaw = scan.mode.rawValue
        self.parserVersion = scan.parserVersion
        self.payload = try? JSONEncoder().encode(scan)
        self.assetFolder = assetFolder
    }

    /// The scan, or nil if the payload cannot be decoded.
    ///
    /// Decoding failure is survivable rather than fatal: a row written by a
    /// future build and read by an older one is exactly the case where losing
    /// the whole history would be worse than losing one row.
    var scan: BodyScan? {
        payload.flatMap { try? JSONDecoder().decode(BodyScan.self, from: $0) }
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

/// **One logged bleeding day.**
///
/// Backlog #31. One row per day rather than one row per period, and the reason
/// is the same one `CycleModel` groups on: a period is *derived* from
/// consecutive days, so storing periods would mean storing a derivation, and a
/// reader correcting one day in the middle would have to be re-derived into a
/// shape the store already committed to.
///
/// `day` is unique, so re-logging a day updates its flow rather than producing
/// two rows for one date — which is the only sane behaviour when the reader taps
/// the same square twice, and it is enforced here rather than in the view.
@Model
final class CycleDayRecord {
    @Attribute(.unique) var day: Date
    var flowRaw: String

    init(day: Date, flowRaw: String) {
        self.day = day
        self.flowRaw = flowRaw
    }

    var cycleDay: CycleDay? {
        guard let flow = MenstrualFlowLevel(rawValue: flowRaw) else { return nil }
        return CycleDay(day: day, flow: flow)
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

    /// The value the symptom radar is bound with. `nil` when the compound
    /// string is unrecognised — an unknown drug must not be named as an
    /// explanation.
    var schedule: MedicationSchedule? {
        compound.map { MedicationSchedule(compound: $0, doses: doses.map(\.administered)) }
    }
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
