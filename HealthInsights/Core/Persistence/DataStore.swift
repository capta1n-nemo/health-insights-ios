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
                             IntegrationRecord.self, SubstanceEventRecord.self,
                             PredictionOutcomeRecord.self, FeedbackRecord.self,
                             InsightScoreRecord.self, SuggestionDismissalRecord.self,
                             MedicationRecord.self, DoseLogRecord.self])
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

    // MARK: - Synced-sample cache
    //
    // HealthKit and wearable samples are fetched live and held in memory. So the
    // app still shows your data on launch — and when a source is temporarily
    // disconnected or offline — we cache the last-synced non-manual samples to
    // disk (JSON) and reload them immediately at startup.

    // These four are `nonisolated` because they touch a JSON file and nothing
    // else — no SwiftData, no `context`. That matters: decoding a six-figure
    // sample array is the most expensive thing that happens on launch, and
    // while it stayed pinned to the main actor it was pure blank-screen time.
    // The SwiftData-backed accessors above and below cannot follow, because
    // `mainContext` is main-actor by construction.
    nonisolated private var syncedCacheURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("synced_samples.json")
    }

    /// The compact binary cache (`SampleCacheCodec`). Decoding the JSON file
    /// above was measured at ~1 s on a real history — the largest single cost
    /// left on a cold launch — against single-digit milliseconds for this
    /// format. The JSON path survives below only to migrate: first launch
    /// after the update reads the old file, the next save writes this one and
    /// deletes it.
    nonisolated private var compactCacheURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("synced_samples.hisc")
    }

    nonisolated private var otherCacheURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("synced_other.json")
    }

    nonisolated func loadCachedSamples() -> [HealthMetricSample] {
        if let data = try? Data(contentsOf: compactCacheURL),
           let samples = SampleCacheCodec.decode(data) {
            return samples
        }
        // Legacy JSON cache, from builds before the compact format — read once
        // and retired by the next save.
        guard let data = try? Data(contentsOf: syncedCacheURL) else { return [] }
        return (try? JSONDecoder().decode([HealthMetricSample].self, from: data)) ?? []
    }

    nonisolated func saveCachedSamples(_ samples: [HealthMetricSample]) {
        // `encode` only fails on a set it cannot represent (>65k distinct
        // sources or types); keep the legacy path for that never-case rather
        // than silently dropping the cache.
        guard let data = SampleCacheCodec.encode(samples) else {
            guard let json = try? JSONEncoder().encode(samples) else { return }
            try? json.write(to: syncedCacheURL, options: .atomic)
            return
        }
        do {
            try data.write(to: compactCacheURL, options: .atomic)
            // Superseded: leaving it would double disk use, and serve stale
            // samples if the compact file were ever lost.
            try? FileManager.default.removeItem(at: syncedCacheURL)
        } catch {}
    }

    nonisolated func loadCachedOther() -> [RawMetricSample] {
        guard let data = try? Data(contentsOf: otherCacheURL) else { return [] }
        return (try? JSONDecoder().decode([RawMetricSample].self, from: data)) ?? []
    }

    nonisolated func saveCachedOther(_ samples: [RawMetricSample]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: otherCacheURL, options: .atomic)
    }

    /// Throw away every cached provider sample, so the next sync rebuilds from
    /// what the providers actually serve rather than merging into what is here.
    ///
    /// The cache-merge in `AppModel.refresh` deliberately *keeps* the samples of
    /// any source that returned nothing this sync, so a disconnected or offline
    /// device's history doesn't vanish from the app. That is right almost always
    /// and wrong in one case: when a parser has been fixed and the stale copy is
    /// the thing being replaced. Then a source that quietly fails to sync keeps
    /// serving the old, wrong values indefinitely and no amount of pulling to
    /// refresh dislodges them.
    ///
    /// **Only the provider cache.** Manual entries, grounding, substance logs,
    /// feedback and score history are SwiftData and are not touched — this
    /// deletes two JSON files that exist purely so the app has something to draw
    /// before the first sync of a launch returns.
    ///
    /// Returns what was discarded, because a rebuild that silently did nothing
    /// looks exactly like a rebuild that worked.
    nonisolated func clearSyncedCaches() -> (samples: Int, other: Int) {
        let discarded = (samples: loadCachedSamples().count, other: loadCachedOther().count)
        try? FileManager.default.removeItem(at: compactCacheURL)
        try? FileManager.default.removeItem(at: syncedCacheURL)
        try? FileManager.default.removeItem(at: otherCacheURL)
        return discarded
    }

    // MARK: - Today summary

    private var summaryURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL.temporaryDirectory
        return base.appendingPathComponent("today_summary.json")
    }

    private struct StoredSummary: Codable {
        let text: String
        let fingerprint: SummaryFingerprint
    }

    /// The last summary and what it was written from, so a cold launch on
    /// unchanged data doesn't pay for a fresh model round-trip either.
    func loadSummary() -> (text: String, fingerprint: SummaryFingerprint)? {
        guard let data = try? Data(contentsOf: summaryURL),
              let stored = try? JSONDecoder().decode(StoredSummary.self, from: data)
        else { return nil }
        return (stored.text, stored.fingerprint)
    }

    func saveSummary(_ text: String, fingerprint: SummaryFingerprint) {
        guard let data = try? JSONEncoder().encode(
            StoredSummary(text: text, fingerprint: fingerprint)) else { return }
        try? data.write(to: summaryURL, options: .atomic)
    }

    // MARK: - Discovered provider schema

    private var fieldCatalogueURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL.temporaryDirectory
        return base.appendingPathComponent("field_catalogue.json")
    }

    /// The catalogue of every provider field ever ingested. Persisted so that
    /// "newly discovered" means new to the app rather than new to this launch —
    /// which is what makes a provider's schema change visible in the log.
    func loadFieldCatalogue() -> FieldCatalogue {
        guard let data = try? Data(contentsOf: fieldCatalogueURL) else { return FieldCatalogue() }
        return (try? JSONDecoder().decode(FieldCatalogue.self, from: data)) ?? FieldCatalogue()
    }

    func saveFieldCatalogue(_ catalogue: FieldCatalogue) {
        guard let data = try? JSONEncoder().encode(catalogue) else { return }
        try? data.write(to: fieldCatalogueURL, options: .atomic)
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

    // MARK: - Insight score history

    /// Every stored day for one insight, oldest → newest.
    func scoreHistory(for id: InsightID) -> [ScorePoint] {
        let raw = id.rawValue
        let descriptor = FetchDescriptor<InsightScoreRecord>(
            predicate: #Predicate { $0.insightRaw == raw },
            sortBy: [SortDescriptor(\.day)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.point)
    }

    /// Record today's score, replacing any row already written for today.
    ///
    /// Upsert rather than append: `recompute()` runs on every launch, refresh,
    /// grounding save and substance log, and appending would write a dozen rows
    /// for the same day and turn the chart into a vertical smear.
    func recordScore(_ id: InsightID, score: Double, confidence: InsightConfidence,
                     contributorCount: Int, on date: Date = Date(),
                     calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let raw = id.rawValue
        let descriptor = FetchDescriptor<InsightScoreRecord>(
            predicate: #Predicate { $0.insightRaw == raw && $0.day == day })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.score = score
            existing.confidenceRaw = confidence.rawValue
            existing.contributorCount = contributorCount
        } else {
            context.insert(InsightScoreRecord(
                insightRaw: raw, day: day, score: score,
                confidenceRaw: confidence.rawValue, contributorCount: contributorCount))
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

    // MARK: - Medication

    /// The active medication regimen, if there is one. Only one at a time:
    /// modelling two GLP-1 compounds on board at once is a clinical situation
    /// this app has no business describing.
    func loadActiveMedication() -> MedicationRecord? {
        let descriptor = FetchDescriptor<MedicationRecord>(
            sortBy: [SortDescriptor(\.startedOn, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).first { $0.isActive }
    }

    /// Start a regimen, optionally seeding the titration history the engine
    /// proposes. **Every seeded dose is stored unconfirmed** — the reader
    /// reviews them, and until they do the curve draws dashed.
    func startMedication(compound: GLPCompound, brandName: String?,
                         startedOn: Date, inferredDoses: [AdministeredDose]) {
        for existing in ((try? context.fetch(FetchDescriptor<MedicationRecord>())) ?? []) {
            existing.isActive = false
        }
        let record = MedicationRecord(compoundRaw: compound.rawValue,
                                      brandName: brandName, startedOn: startedOn)
        record.doses = inferredDoses.map {
            DoseLogRecord(takenAt: $0.takenAt, milligrams: $0.milligrams,
                          isInferred: $0.isInferred)
        }
        context.insert(record)
        try? context.save()
    }

    /// Replace the regimen's dose history with an imported one.
    ///
    /// **Wholesale, not merged.** An imported backup is the complete record
    /// from the app the reader actually logs in; merging it with our own
    /// inferred ladder would leave guesses interleaved with facts and no way
    /// to tell which was which. Anything the app estimated goes.
    func replaceMedicationHistory(compound: GLPCompound, brandName: String?,
                                  startedOn: Date, doses: [DoseLogRecord]) {
        for existing in ((try? context.fetch(FetchDescriptor<MedicationRecord>())) ?? []) {
            existing.isActive = false
        }
        let record = MedicationRecord(compoundRaw: compound.rawValue,
                                      brandName: brandName, startedOn: startedOn)
        record.doses = doses
        context.insert(record)
        try? context.save()
    }

    /// Store imported measurements, skipping any already held.
    ///
    /// Identity is (metric, source, instant): re-sharing the same backup is the
    /// expected way to update, so it has to be idempotent or a reader's weight
    /// history doubles every time they send it.
    func mergeImportedSamples(_ samples: [HealthMetricSample]) -> Int {
        let existing = Set(loadManualSamples().map(Self.sampleKey))
        var added = 0
        for sample in samples where !existing.contains(Self.sampleKey(sample)) {
            context.insert(ManualSampleRecord(metricRaw: sample.type.rawValue,
                                              value: sample.value, date: sample.start,
                                              sourceID: sample.source.id))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    private static func sampleKey(_ sample: HealthMetricSample) -> String {
        "\(sample.type.rawValue)|\(sample.source.id)|\(Int(sample.start.timeIntervalSince1970))"
    }

    func logDose(_ milligrams: Double, at date: Date, site: String? = nil) {
        guard let medication = loadActiveMedication() else { return }
        medication.doses.append(DoseLogRecord(takenAt: date, milligrams: milligrams,
                                              injectionSite: site))
        try? context.save()
    }

    /// Accept the proposed history as it stands. The doses stop being estimates
    /// and the curve stops drawing dashed.
    func confirmInferredDoses(at date: Date = Date()) {
        guard let medication = loadActiveMedication() else { return }
        for dose in medication.doses where dose.isInferred && dose.confirmedAt == nil {
            dose.confirmedAt = date
        }
        try? context.save()
    }

    /// Throw the proposal away — the reader says it did not happen that way.
    func discardInferredDoses() {
        guard let medication = loadActiveMedication() else { return }
        for dose in medication.doses where dose.isInferred && dose.confirmedAt == nil {
            context.delete(dose)
        }
        medication.doses.removeAll { $0.isInferred && $0.confirmedAt == nil }
        try? context.save()
    }

    func stopMedication() {
        loadActiveMedication()?.isActive = false
        try? context.save()
    }

    func addSubstanceEvent(_ event: SubstanceEvent) {
        context.insert(SubstanceEventRecord(
            id: event.id, substanceRaw: event.substance.rawValue,
            timestamp: event.timestamp, units: event.units, note: event.note))
        try? context.save()
    }

    /// Correct a mis-timed entry.
    ///
    /// A genuine mutation rather than a delete-and-reinsert, so the row keeps its
    /// identity — the before/after analysis is keyed on timestamps, and an entry
    /// that vanished and reappeared would churn every derived figure. There was
    /// no update path at all before this, so a log entered at the wrong time
    /// could only be deleted.
    func updateSubstanceEvent(id: UUID, timestamp: Date) {
        let descriptor = FetchDescriptor<SubstanceEventRecord>(
            predicate: #Predicate { $0.id == id })
        guard let record = (try? context.fetch(descriptor))?.first else { return }
        record.timestamp = timestamp
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

    // MARK: - Suggestion dismissals

    func loadSuggestionDismissals() -> [SuggestionDismissal] {
        let descriptor = FetchDescriptor<SuggestionDismissalRecord>()
        return ((try? context.fetch(descriptor)) ?? []).map(\.dismissal)
    }

    /// Upsert, so dismissing something twice extends the silence rather than
    /// leaving two rows for `SuggestionVisibility` to reconcile.
    func dismissSuggestion(id: String, at date: Date = Date()) {
        let descriptor = FetchDescriptor<SuggestionDismissalRecord>(
            predicate: #Predicate { $0.suggestionID == id })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.dismissedAt = date
        } else {
            context.insert(SuggestionDismissalRecord(suggestionID: id, dismissedAt: date))
        }
        try? context.save()
    }

    func undismissSuggestions(ids: [String]) {
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        let descriptor = FetchDescriptor<SuggestionDismissalRecord>()
        for record in (try? context.fetch(descriptor)) ?? []
        where wanted.contains(record.suggestionID) {
            context.delete(record)
        }
        try? context.save()
    }

    // MARK: - Feedback & prediction outcomes (model-improvement ledger)

    func addPredictionOutcome(_ outcome: PredictionOutcome) {
        context.insert(PredictionOutcomeRecord(
            id: outcome.id, insightRaw: outcome.insightID.rawValue, metricRaw: outcome.metric.rawValue,
            predicted: outcome.predicted, actual: outcome.actual, modelVersion: outcome.modelVersion,
            cohort: outcome.cohort, recordedAt: outcome.recordedAt))
        try? context.save()
    }

    func loadPredictionOutcomes() -> [PredictionOutcome] {
        let descriptor = FetchDescriptor<PredictionOutcomeRecord>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.outcome)
    }

    func addFeedback(insightID: InsightID, rating: FeedbackRating, cohort: Cohort) {
        context.insert(FeedbackRecord(
            insightRaw: insightID.rawValue, ratingRaw: rating.rawValue,
            modelVersion: insightID.modelVersion, cohort: cohort))
        try? context.save()
    }

    func loadFeedback() -> [(insight: InsightID, rating: FeedbackRating, cohort: Cohort, modelVersion: String, at: Date)] {
        let descriptor = FetchDescriptor<FeedbackRecord>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap { r in
            guard let id = InsightID(rawValue: r.insightRaw),
                  let rating = FeedbackRating(rawValue: r.ratingRaw) else { return nil }
            return (id, rating, r.cohort, r.modelVersion, r.recordedAt)
        }
    }
}
