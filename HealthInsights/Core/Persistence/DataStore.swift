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
                             MedicationRecord.self, DoseLogRecord.self,
                             SideEffectRecord.self, BodyScanRecord.self,
                             // ⚠️ A @Model not listed here silently never persists.
                             CycleDayRecord.self,
                             CalendarEventRecord.self, CalendarJudgementRecord.self])
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

    // MARK: - Body scans

    /// Every scan, newest first.
    ///
    /// A row whose payload will not decode is skipped rather than fatal — see
    /// `BodyScanRecord.scan`.
    func bodyScans() -> [BodyScan] {
        let records = (try? context.fetch(FetchDescriptor<BodyScanRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        return records.compactMap(\.scan)
    }

    /// Save a scan, replacing any row with the same id.
    ///
    /// An upsert rather than an append, so re-deriving an existing scan with a
    /// newer parser updates it in place instead of leaving two versions of one
    /// capture for the reader to tell apart.
    func saveBodyScan(_ scan: BodyScan, assetFolder: String? = nil) {
        let id = scan.id
        let existing = (try? context.fetch(FetchDescriptor<BodyScanRecord>(
            predicate: #Predicate { $0.id == id }))) ?? []
        for record in existing { context.delete(record) }
        context.insert(BodyScanRecord(scan: scan, assetFolder: assetFolder))
        try? context.save()
    }

    func deleteBodyScan(id: UUID) {
        let records = (try? context.fetch(FetchDescriptor<BodyScanRecord>(
            predicate: #Predicate { $0.id == id }))) ?? []
        for record in records { context.delete(record) }
        try? context.save()
    }

    /// Scans a newer parser could improve — behind the current version and still
    /// holding the assets to re-derive from.
    ///
    /// The sweep itself belongs to the capture layer, which owns the assets;
    /// this only answers which rows are candidates.
    func bodyScansAwaitingReparse(currentVersion: Int) -> [BodyScan] {
        bodyScans().filter { $0.parserVersion < currentVersion && $0.isReparseable }
    }

    // MARK: - Manual samples

    func loadManualSamples() -> [HealthMetricSample] {
        let records = (try? context.fetch(FetchDescriptor<ManualSampleRecord>())) ?? []
        return records.compactMap(\.sample)
    }

    /// Record one day's screen time **only if it outranks what is already
    /// stored** for that day.
    ///
    /// The reader's rule: a screenshot is the device's own accounting and beats
    /// a typed figure, *unless* they have since typed over it on purpose. And an
    /// exact Day screenshot is never demoted by a week-split estimate, even a
    /// newer one — which happens the moment an old week screenshot is imported
    /// after a precise day. `ScreenTimePrecedence` owns the whole rule and is
    /// tested in InsightKit; this is the write path that obeys it.
    ///
    /// - Returns: whether the entry was written. False means something better
    ///   was already there, which is a successful no-op rather than a failure —
    ///   re-importing the same screenshot twice must change nothing.
    @discardableResult
    func recordScreenTime(_ entry: ScreenTimeEntry,
                          calendar: Calendar = .current) -> Bool {
        let raw = MetricType.screenTimeMinutes.rawValue
        let day = calendar.startOfDay(for: entry.day)
        let all = (try? context.fetch(FetchDescriptor<ManualSampleRecord>(
            predicate: #Predicate { $0.metricRaw == raw }))) ?? []
        let sameDay = all.filter { calendar.isDate($0.date, inSameDayAs: day) }

        guard ScreenTimePrecedence.wouldWin(entry, over: sameDay.map(\.screenTimeEntry)) else {
            return false
        }
        for record in sameDay { context.delete(record) }
        context.insert(ManualSampleRecord(
            metricRaw: raw, value: entry.minutes, date: day,
            sourceID: entry.provenance == .manual ? MetricSource.manual.id
                                                  : MetricSource.screenshot.id,
            provenance: entry.provenance, recordedAt: entry.recordedAt))
        try? context.save()
        return true
    }

    /// Every stored screen-time figure with its provenance, newest day first —
    /// so a data page can say which days are estimates.
    func screenTimeEntries(calendar: Calendar = .current) -> [ScreenTimeEntry] {
        let raw = MetricType.screenTimeMinutes.rawValue
        let all = (try? context.fetch(FetchDescriptor<ManualSampleRecord>(
            predicate: #Predicate { $0.metricRaw == raw }))) ?? []
        return all.map(\.screenTimeEntry).sorted { $0.day > $1.day }
    }

    /// Replace whatever manual samples exist for one metric on one day.
    ///
    /// An **upsert**, unlike `saveBloodPressureReading`, and deliberately: a
    /// day's screen time is one figure, so re-entering it is a correction, not
    /// a second reading. Inserting instead would leave two values for the day
    /// to be averaged into a number the reader never saw.
    func replaceManualSamples(of metric: MetricType, on day: Date,
                              with samples: [HealthMetricSample],
                              calendar: Calendar = .current) {
        let raw = metric.rawValue
        let existing = (try? context.fetch(FetchDescriptor<ManualSampleRecord>(
            predicate: #Predicate { $0.metricRaw == raw }))) ?? []
        for record in existing where calendar.isDate(record.date, inSameDayAs: day) {
            context.delete(record)
        }
        for sample in samples {
            context.insert(ManualSampleRecord(metricRaw: sample.type.rawValue,
                                              value: sample.value, date: sample.start,
                                              sourceID: sample.source.id))
        }
        try? context.save()
    }

    #if DEBUG
    /// Delete every manual sample of one metric that came from a given source.
    ///
    /// Debug builds only, and it exists for exactly one job: undoing
    /// `AppModel.seedSyntheticData`, so the empty state stays reachable on a
    /// seeded simulator without erasing the device. Scoped by **source** so it
    /// can only remove what the seeder wrote (`.shortcuts`) — a blanket delete
    /// by metric would take the reader's own typed entries with it, and on a
    /// real phone that is their data.
    func deleteManualSamples(of metric: MetricType, from source: MetricSource) {
        let raw = metric.rawValue
        let sourceID = source.id
        let existing = (try? context.fetch(FetchDescriptor<ManualSampleRecord>(
            predicate: #Predicate { $0.metricRaw == raw }))) ?? []
        for record in existing where record.sourceID == sourceID {
            context.delete(record)
        }
        try? context.save()
    }
    #endif

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

    /// The compact raw cache — the same treatment `compactCacheURL` gives the
    /// canonical samples, applied to the file that actually dominates launch.
    /// On the reader's record `synced_other.json` is **109 MB** against the
    /// canonical cache's 6.6 MB, and it was still on plain `Codable`.
    nonisolated private var compactOtherCacheURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("synced_other.hirc")
    }

    nonisolated func loadCachedOther() -> [RawMetricSample] {
        if let data = try? Data(contentsOf: compactOtherCacheURL),
           let samples = RawCacheCodec.decode(data) {
            return samples
        }
        // Legacy JSON cache, from builds before the compact format — read once
        // and retired by the next save.
        guard let data = try? Data(contentsOf: otherCacheURL) else { return [] }
        return (try? JSONDecoder().decode([RawMetricSample].self, from: data)) ?? []
    }

    nonisolated func saveCachedOther(_ samples: [RawMetricSample]) {
        // `encode` fails only on a set it cannot represent (>65k distinct
        // sources); keep the legacy path for that never-case rather than
        // silently dropping the cache.
        guard let data = RawCacheCodec.encode(samples) else {
            guard let json = try? JSONEncoder().encode(samples) else { return }
            try? json.write(to: otherCacheURL, options: .atomic)
            return
        }
        do {
            try data.write(to: compactOtherCacheURL, options: .atomic)
            // Superseded: leaving it would double disk use — and on this record
            // that is a hundred megabytes — and serve stale rows if the compact
            // file were ever lost.
            try? FileManager.default.removeItem(at: otherCacheURL)
        } catch {}
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

    // MARK: - Calendar

    func loadCalendarEvents() -> [CalendarEvent] {
        let descriptor = FetchDescriptor<CalendarEventRecord>(
            sortBy: [SortDescriptor(\.start, order: .forward)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.event)
    }

    /// Upsert a fetched batch.
    ///
    /// ⚠️ **Events are updated and never deleted here.** A meeting removed from
    /// the calendar still *happened*, and the cards read history — deleting it
    /// would silently rewrite last month's workload every time somebody tidied
    /// their diary. Removing them is `forgetCalendar()`, which is deliberate.
    func mergeCalendarEvents(_ events: [CalendarEvent]) {
        guard !events.isEmpty else { return }
        let existing = Dictionary(
            ((try? context.fetch(FetchDescriptor<CalendarEventRecord>())) ?? [])
                .map { ($0.eventID, $0) },
            uniquingKeysWith: { first, _ in first })
        for event in events {
            if let record = existing[event.id] {
                record.update(from: event)
            } else {
                context.insert(CalendarEventRecord(event: event))
            }
        }
        try? context.save()
    }

    func loadCalendarJudgements() -> [CalendarEventJudgement] {
        ((try? context.fetch(FetchDescriptor<CalendarJudgementRecord>())) ?? [])
            .compactMap(\.judgement)
    }

    /// Store the app's own classification, **without touching a correction the
    /// reader has already made.**
    ///
    /// This is the rule that makes re-classification safe: running the model
    /// again must never overwrite somebody's answer, and the only way to
    /// guarantee that is for the write path not to have the correction in hand.
    func recordClassification(_ classification: CalendarEventClassification,
                              for eventID: String) {
        guard let data = try? JSONEncoder().encode(classification) else { return }
        let descriptor = FetchDescriptor<CalendarJudgementRecord>(
            predicate: #Predicate { $0.eventID == eventID })
        if let existing = try? context.fetch(descriptor).first {
            existing.classificationData = data
        } else {
            context.insert(CalendarJudgementRecord(eventID: eventID,
                                                   classificationData: data))
        }
        try? context.save()
    }

    /// The reader's answer. `correction == nil` with `confirmed == true` is
    /// "you got it right" — a label in its own right, and different from never
    /// having been looked at.
    func recordReview(eventID: String, correction: CalendarEventClassification?,
                      confirmed: Bool, now: Date = Date()) {
        let descriptor = FetchDescriptor<CalendarJudgementRecord>(
            predicate: #Predicate { $0.eventID == eventID })
        guard let record = try? context.fetch(descriptor).first else { return }
        record.correctionData = correction.flatMap { try? JSONEncoder().encode($0) }
        record.isConfirmed = confirmed
        record.reviewedAt = now
        try? context.save()
    }

    /// Disconnecting the calendar forgets everything it brought — including the
    /// reader's corrections, because a correction about an event the app can no
    /// longer see is not something it should keep.
    func forgetCalendar() {
        for record in (try? context.fetch(FetchDescriptor<CalendarEventRecord>())) ?? [] {
            context.delete(record)
        }
        for record in (try? context.fetch(FetchDescriptor<CalendarJudgementRecord>())) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }

    // MARK: - Cycle log

    /// Every logged bleeding day, oldest first.
    func loadCycleDays() -> [CycleDay] {
        let descriptor = FetchDescriptor<CycleDayRecord>(
            sortBy: [SortDescriptor(\.day, order: .forward)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.cycleDay)
    }

    /// Record or update one day.
    ///
    /// **Upsert on the day, never append.** `CycleDayRecord.day` is unique, so
    /// tapping the same square twice changes the flow rather than producing two
    /// rows for one date — and every length in `CycleModel` is computed from the
    /// gaps between days, so a duplicated date would be a silent corruption of
    /// the arithmetic rather than a visible duplicate.
    func setCycleDay(_ day: Date, flow: MenstrualFlowLevel, calendar: Calendar = .current) {
        let key = calendar.startOfDay(for: day)
        let descriptor = FetchDescriptor<CycleDayRecord>(
            predicate: #Predicate { $0.day == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.flowRaw = flow.rawValue
        } else {
            context.insert(CycleDayRecord(day: key, flowRaw: flow.rawValue))
        }
        try? context.save()
    }

    /// Remove a logged day — the reader tapped it off.
    func clearCycleDay(_ day: Date, calendar: Calendar = .current) {
        let key = calendar.startOfDay(for: day)
        let descriptor = FetchDescriptor<CycleDayRecord>(
            predicate: #Predicate { $0.day == key })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        try? context.save()
    }

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

    /// Every regimen ever started, newest first — including the ones
    /// `startMedication` deactivated.
    ///
    /// The scoring models are right to read only the active regimen: two GLP-1
    /// compounds on board at once is not a situation this app describes. **The
    /// export is not scoring**, and it was using the same accessor, so a reader
    /// who switched compounds handed back a file with the earlier course and
    /// every dose on it missing — while the records sat intact on the phone.
    /// Found by audit 2026-08-04.
    func loadAllMedications() -> [MedicationRecord] {
        let descriptor = FetchDescriptor<MedicationRecord>(
            sortBy: [SortDescriptor(\.startedOn, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
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

    // MARK: - Side effects

    func loadSideEffects() -> [SideEffectRecord] {
        let descriptor = FetchDescriptor<SideEffectRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Store imported side effects, skipping any already held. Idempotent on
    /// the source's own id, for the same reason the samples are.
    func mergeSideEffects(_ effects: [ShotsyImport.SideEffect]) -> Int {
        let existing = Set(loadSideEffects().compactMap(\.externalID))
        var added = 0
        for effect in effects {
            let key = "\(effect.name)|\(Int(effect.date.timeIntervalSince1970))"
            guard !existing.contains(key) else { continue }
            context.insert(SideEffectRecord(name: effect.name, severity: effect.severity,
                                            date: effect.date, externalID: key))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    /// Record a side effect the reader entered themselves.
    ///
    /// No `externalID`: that key exists to make *re-importing the same backup*
    /// idempotent, and a hand-entered record has no upstream to be a duplicate
    /// of. Logging the same nausea twice on purpose is the reader's business.
    func logSideEffect(name: String, severity: Int, at date: Date) {
        context.insert(SideEffectRecord(name: name, severity: severity, date: date))
        try? context.save()
    }

    func deleteSideEffect(_ record: SideEffectRecord) {
        context.delete(record)
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
