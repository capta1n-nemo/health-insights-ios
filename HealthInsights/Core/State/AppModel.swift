import Foundation
import SwiftUI
import Observation
import InsightKit

/// The app's single source of truth. It wires together persistence, the
/// integrations, the insight engine and the on-device summariser, and exposes
/// ready-to-render state to the SwiftUI views.
@MainActor
@Observable
final class AppModel {
    // Injected collaborators
    let dataStore: DataStore
    let healthService: HealthKitService
    let registry: IntegrationRegistry
    /// The insight registry. A `var` because `SubstanceImpactInsight` is bound
    /// to the user's substance log, which changes without `samples` changing.
    private(set) var engine: InsightEngine
    let summarizer: FoundationModelSummarizer

    // Rendered state
    private(set) var samples: [HealthMetricSample] = [] {
        didSet { invalidateDerivedCaches() }
    }

    /// Per-metric breakdowns, built once and reused.
    ///
    /// Building one scans, de-duplicates and groups every sample of that metric.
    /// The Vitals list asks for one per row and the detail screens ask again on
    /// every redraw and every scroll, so recomputing was making large histories
    /// unusable. Ignored by @Observable: these are derived from `samples`, and
    /// filling them mid-render must not invalidate the view that asked.
    @ObservationIgnored private var breakdownCache: [MetricType: MultiSourceBreakdown] = [:]
    @ObservationIgnored private var vitalsSummaryCache: [MetricType: VitalsSummary]?
    /// The refresh currently running, if any — what `refresh()` coalesces onto.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Results of the pure model passes detail screens run at render time,
    /// keyed by call site. SwiftUI re-evaluates `body` on every scrub, pan and
    /// timeframe change, and each evaluation was re-running whole models
    /// (`VitalSignsCheck`, `HeartResponseModel`, `PeriodContrast`, …) over the
    /// full sample set — the "opening a card hangs" report of 2026-08-02.
    ///
    /// `RenderMemo` rather than a bare dictionary because of what a bare
    /// dictionary did on its first day: a `nil` computed during a transient
    /// empty-data window stuck until the next sample change, and two sections
    /// spent the morning claiming the user had no scale and no date of birth
    /// beside sections showing both. The type refuses to cache `nil`, and that
    /// rule is tested in InsightKit.
    @ObservationIgnored private var renderMemo = RenderMemo()
    @ObservationIgnored private var otherGroupCache: [RawMetricGroup]?
    @ObservationIgnored private var bloodPressureCache: [BloodPressureEstimator.Reading]?

    /// What a Vitals row needs, without building a full breakdown per row.
    ///
    /// `displayValue`/`displayDate` are what the row shows. For point-in-time
    /// vitals they are the newest sample; for cumulative metrics
    /// (`bucketStatistic == .sum`) they are the newest day's *total* — the
    /// newest sample alone is whatever sliver the phone last wrote, and the
    /// list shipped reading "Steps: 10" mid-afternoon.
    struct VitalsSummary {
        let latest: HealthMetricSample
        let sourceCount: Int
        let displayValue: Double
        let displayDate: Date
    }

    private func invalidateDerivedCaches() {
        breakdownCache.removeAll(keepingCapacity: true)
        renderMemo.removeAll(keepingCapacity: true)
        vitalsSummaryCache = nil
        bloodPressureCache = nil
        scoreHistories.removeAll()
        scoreHistoryTasks.removeAll()
        // The derived series were computed from the samples that just changed,
        // so they go the way the score histories do — rebuilt by the next
        // replay rather than left describing data that no longer exists.
        derivedSeries = DerivedSeriesStore()
        // The queue holds requests for data that has just been superseded, so
        // it goes with them. Anything still wanted is asked for again on the
        // next render — which is the same contract `scoreHistories` has always
        // had, and is why dropping it here cannot lose a chart.
        scoreHistoryQueue.removeAll()
        scoreHistoryGeneration &+= 1
        ageHistory.removeAll()
        ageHistoryRunning = false
        overlayCache.removeAll()
        suggestionCache = nil
        energyCache = nil
        circadianCache = nil
        sleepNightsCache = nil
        sleepOnsetCache = nil
        scoreChangeCache = nil
    }
    /// Imported data we don't yet model as canonical metrics (new HealthKit types,
    /// extra provider fields). Surfaced in Vitals ▸ "Other data" for review.
    private(set) var otherSamples: [RawMetricSample] = [] {
        didSet {
            otherGroupCache = nil
            vitalEventCache = nil
            // Every ingest path funnels through here, so the stored `symptoms`
            // can never lag the raw catalogue it is promoted from.
            symptoms = SymptomPromotion.events(from: otherSamples)
            // Same contract as `symptoms`: promoted here so the stored list can
            // never lag the catalogue it is read from. Deterministic only — the
            // on-device model is asked afterwards, by
            // `refreshTagApplicability()`, because this is a synchronous
            // observer and a `didSet` is the wrong place to start an inference.
            tags = TagPromotion.tags(from: otherSamples, resolved: tagMappings)
        }
    }
    /// Everything the app has learned about provider schemas — every field ever
    /// ingested, its type, whether it feeds a vital, and what it might map to.
    private(set) var fieldCatalogue = FieldCatalogue()

    /// **When the app first met each kind of data, and when it last saw it.**
    ///
    /// The reader's idea, 2026-08-05: *"remember that idea of how we can point
    /// out new data points synced, and point out now deprecated data?"*
    ///
    /// ⚠️ **It cannot be derived from the samples, which is why it is stored.**
    /// A sample carries the date the *reading* was taken, and every connector
    /// backfills — plug in a new ring and two years of history arrives at once.
    /// Deriving "new" from the earliest sample date would have been wrong for
    /// 202 of this reader's 203 identifiers. What makes a type new is when the
    /// **app** first saw it, and nothing else records that.
    private(set) var sightingLedger = TypeSightingLedger()

    private static let sightingLedgerKey = "typeSightingLedger"

    private func loadSightingLedger() {
        guard let data = UserDefaults.standard.data(forKey: Self.sightingLedgerKey),
              let ledger = try? JSONDecoder().decode(TypeSightingLedger.self, from: data)
        else { return }
        sightingLedger = ledger
    }

    private func saveSightingLedger() {
        if let data = try? JSONEncoder().encode(sightingLedger) {
            UserDefaults.standard.set(data, forKey: Self.sightingLedgerKey)
        }
    }

    /// Every kind of data the app currently holds, in the vocabulary the ledger
    /// speaks. Canonical metrics as well as raw fields: a scale arriving and
    /// body fat appearing for the first time is exactly the event the reader
    /// asked to be told about, and it is not a raw identifier.
    private var heldTypeIdentifiers: Set<String> {
        Set(otherSamples.map(\.identifier))
            .union(samples.map { $0.type.rawValue })
    }

    /// ⚠️ **The debut this feature must not have.** On the first launch after
    /// shipping it, every identifier the reader already holds would look brand
    /// new — 158 "new data type" announcements for data they have had for years.
    /// Seeding writes them all in as pre-existing, and `seed` is idempotent so a
    /// migration that runs twice cannot rewrite a genuine first sighting.
    private func seedSightingLedgerIfNeeded(now: Date = Date()) {
        guard sightingLedger.sightings.isEmpty else { return }
        let held = heldTypeIdentifiers
        guard !held.isEmpty else { return }   // nothing yet: seed on a later run
        sightingLedger.seed(held, at: now)
        saveSightingLedger()
        DiagnosticsLog.shared.info(
            "Data", "Recorded \(held.count) existing data types as pre-existing")
    }

    /// Record what actually arrived in this sync.
    ///
    /// **Only what arrived**, never the retained cache — a type kept alive from
    /// last week's cache did not arrive today, and observing it would make the
    /// "no longer arriving" half permanently silent.
    ///
    /// ⚠️ **This runs *before* `partitionedVitals()` sanitises, on purpose**
    /// (backlog D43, ruled 2026-08-07). A reading outside its metric's
    /// `plausibleRange` really did arrive, and announcing it is the honest
    /// signal that a source has started sending something. Observing after
    /// sanitising would make a metric arriving persistently out of range look
    /// identical to nothing arriving at all — which hides a real device fault.
    /// What the order used to cost was a "New since you last looked" row for
    /// data the app then threw away with no explanation; `recordArrivalOutcomes`
    /// below closes that by storing *why* it was dropped, so the row can say so.
    private func observeArrivals(_ identifiers: some Sequence<String>,
                                 now: Date = Date()) {
        var changed = false
        for identifier in identifiers {
            sightingLedger.observe(identifier, at: now)
            changed = true
        }
        if changed { saveSightingLedger() }
    }

    /// The second half of D43: what became of what we just announced.
    ///
    /// **Partitioned over the freshly-arrived samples only**, deliberately, and
    /// not over the `(manual + nonManual)` set the store is built from. That set
    /// carries the retained cache and the reader's own entries; a cached sample
    /// rejected on this run was not an arrival, and letting it write the note
    /// would put "arrived, but outside the plausible range" on a type that
    /// delivered perfectly good data this morning.
    ///
    /// Only canonical metrics get a verdict. Nothing sanitises the raw
    /// catalogue, so a raw field's sighting keeps a `nil` outcome — which is the
    /// difference between "not judged" and "judged fine", and the Data-tab row
    /// prints a qualifier for neither.
    private func recordArrivalOutcomes(of fresh: [HealthMetricSample]) {
        guard !fresh.isEmpty else { return }
        let (kept, dropped) = fresh.partitionedVitals()
        sightingLedger.recordSanitisation(kept: kept, dropped: dropped)
        saveSightingLedger()
    }
    private(set) var substanceEvents: [SubstanceEvent] = [] {
        didSet {
            substanceLoadCache = nil
            substanceWindowCache = nil
        }
    }

    /// **The reader's supplement stack** — backlog Q8 / B3-25.
    ///
    /// Stored and observed rather than computed off the store, which is the rule
    /// `activeMedication` below states at length: a view reading only
    /// `model.supplementEntries` establishes no SwiftUI dependency on a
    /// `dataStore.load…()` call, so a bottle added on one screen would leave
    /// every other screen stale until something unrelated happened to change.
    private(set) var supplementEntries: [SupplementEntry] = []

    /// The active medication regimen and its doses, if the reader has one.
    ///
    /// **Stored and observed, not computed off the store.** It used to be a
    /// computed `dataStore.loadActiveMedication()`, and that is invisible to
    /// SwiftUI's observation: a view reading only `model.activeMedication` (the
    /// Data tab's medication row, the medication section) establishes no
    /// dependency on any `@Observable` stored property, so logging a dose left
    /// it showing stale counts until some *other* observed change happened to
    /// redraw it. Reloaded by `reloadLoggedData()` on every mutation, so the
    /// count the reader just changed is the count they see.
    private(set) var activeMedication: MedicationRecord?

    /// Side effects the reader has recorded, newest first. Stored and observed
    /// for the same reason as `activeMedication` — a computed read off the store
    /// is not tracked, which is why a side effect logged from the `+` menu did
    /// not appear on a Data tab that was already on screen.
    private(set) var sideEffects: [SideEffectRecord] = []

    /// Every regimen ever started, newest first — what the *export* needs.
    ///
    /// Stored and observed for the same reason as `activeMedication`. Nothing
    /// that scores reads this: the models take the active regimen only, on
    /// purpose. It exists so "export my data" stops silently dropping the
    /// courses the reader has finished.
    private(set) var allMedications: [MedicationRecord] = []

    /// Symptoms the reader has tagged, newest first.
    ///
    /// **Promoted, not ingested.** These have been arriving in the raw
    /// catalogue since `HealthKitService.otherCategoryIdentifiers` gained the
    /// fourteen symptom categories, and nothing read them — the state
    /// `progress.md` calls "already being scraped into the raw pile and read by
    /// nothing". `SymptomPromotion` lifts them out; the raw rows stay exactly
    /// where they are, so a bug here cannot cost data the reader already had.
    ///
    /// **Stored and observed, not computed off the raw catalogue.** The
    /// computed version read through `otherDataGroups`, whose
    /// `@ObservationIgnored` cache means a view whose first read lands on a
    /// cache hit registers no dependency on `otherSamples` and never redraws —
    /// the order-dependent form of the trap that made `activeMedication` and
    /// `sideEffects` stored properties. Repopulated in `otherSamples.didSet`,
    /// which every ingest path funnels through. (Promotion still *reads*
    /// rather than moves — see `SymptomPromotion`.)
    private(set) var symptoms: [SymptomEvent] = []

    /// **Tags the reader put on a day** — imported from Oura, newest first
    /// (backlog B12-1).
    ///
    /// Promoted rather than ingested, and stored rather than computed, for
    /// exactly the two reasons `symptoms` above is: the raw rows stay in the
    /// catalogue so a promotion bug cannot cost data, and a computed read
    /// through `otherDataGroups` would register no observation dependency.
    ///
    /// The applicability on each one comes from `TagLexicon` unless
    /// `tagMappings` holds a better-evidenced answer — the on-device model's or
    /// the reader's own. See `refreshTagApplicability()`.
    private(set) var tags: [HealthTag] = []

    /// Applicabilities that beat the deterministic classifier: what the
    /// on-device model worked out, and what the reader corrected.
    ///
    /// ⚠️ **Persisted, and that is not an optimisation.** A model answer is
    /// non-deterministic, so re-asking on every launch would quietly move a tag
    /// between headings; and a reader's correction is data they typed. Held in
    /// `UserDefaults` beside `TypeSightingLedger` rather than in SwiftData
    /// because it is a small keyed cache, not a log.
    private(set) var tagMappings = TagMappingStore() {
        didSet { saveTagMappings() }
    }

    private static let tagMappingsKey = "tagApplicabilityMappings"

    private func loadTagMappings() {
        guard let data = UserDefaults.standard.data(forKey: Self.tagMappingsKey),
              let store = try? JSONDecoder().decode(TagMappingStore.self, from: data)
        else { return }
        // Assigned through the backing store directly would re-save what was
        // just read; harmless, and not worth a second property to avoid.
        tagMappings = store
    }

    private func saveTagMappings() {
        if let data = try? JSONEncoder().encode(tagMappings) {
            UserDefaults.standard.set(data, forKey: Self.tagMappingsKey)
        }
    }

    /// The on-device model. Held rather than built per call so `isAvailable` is
    /// asked once per session rather than once per tag.
    private let tagModel = TagApplicabilityModel()

    /// **Ask the on-device model about the tags nothing else could place.**
    ///
    /// Called after a sync, never during one: the deterministic answer is
    /// already on screen by then, so this only ever *improves* a heading and can
    /// never be the reason the section is empty. On a device with no model it
    /// returns immediately having done nothing, which is the common case.
    ///
    /// Most-used tags first — see `TagApplicabilityModel.perPassLimit` for why
    /// the order matters.
    func refreshTagApplicability() async {
        let summaries = tags.distinctTags().sorted { $0.count > $1.count }
        let resolved = await tagModel.resolve(summaries)
        guard !resolved.isEmpty else { return }
        var store = tagMappings
        for (key, mapping) in resolved { store.record(mapping, for: key) }
        tagMappings = store
        // Re-promote so the new answers are on the rows the reader is looking
        // at, rather than waiting for the next sync to redraw them.
        tags = TagPromotion.tags(from: otherSamples, resolved: tagMappings)
    }

    /// The reader overruling the app about one of their own words.
    ///
    /// Ranked above every other method (`TagMappingRank`), so a later sync
    /// re-classifying the same word cannot undo it.
    func setTagApplicability(_ applicability: TagApplicability, forTagKey key: String) {
        var store = tagMappings
        store.record(TagApplicabilityMapping(
            applicability: applicability, method: .reader, confidence: 1,
            rationale: "You said this tag is about \(applicability.rawValue.lowercased())."),
                     for: key)
        tagMappings = store
        tags = TagPromotion.tags(from: otherSamples, resolved: tagMappings)
    }

    /// Reload the logged data that lives in SwiftData rather than in `samples`,
    /// so every observed reader of it redraws. Called from `hydrate()` and at
    /// the top of `recompute()`, which every mutation funnels through — the one
    /// place freshness has to be guaranteed.
    private func reloadLoggedData() {
        activeMedication = dataStore.loadActiveMedication()
        allMedications = dataStore.loadAllMedications()
        sideEffects = dataStore.loadSideEffects()
        bodyScans = dataStore.bodyScans()
        // ⚠️ Every SwiftData-backed log must be reloaded *here*. The substance
        // log was left out once and the import reported "16 substances" while
        // the card still read "Log to see effects" — see activeContext.
        cycleDays = dataStore.loadCycleDays()
        calendarEvents = dataStore.loadCalendarEvents()
        calendarJudgements = dataStore.loadCalendarJudgements()
        holidayEntries = dataStore.loadHolidayEntries()
        labResults = dataStore.labResults()
        ecgRecords = dataStore.ecgRecords()
    }

    // MARK: - Calendar

    /// Stored, reloaded properties — never computed reads from the store, which
    /// are invisible to observation (`data-conventions.md`).
    private(set) var calendarEvents: [CalendarEvent] = []
    private(set) var calendarJudgements: [CalendarEventJudgement] = []

    /// **Events that changed since the app judged them, waiting to be re-judged.**
    ///
    /// Ids rather than events, so a meeting renamed three times before the flush
    /// is judged once, against whatever it finally says.
    ///
    /// `@ObservationIgnored` on purpose: nothing on screen reads the queue — the
    /// review row reads `CalendarEventJudgement.needsRereview`, which is stored —
    /// and an observed set would redraw both calendar cards on every sync that
    /// found a renamed meeting.
    ///
    /// It does not survive a relaunch, and does not need to: re-judgement is what
    /// refreshes the snapshot, so anything not flushed is simply found again by
    /// the next sync's comparison.
    @ObservationIgnored private var calendarReclassificationQueue: Set<String> = []

    private let interpreter = CalendarEventInterpreter()

    /// Every event with whatever the app and the reader between them concluded,
    /// newest first.
    var calendarReview: [(event: CalendarEvent, judgement: CalendarEventJudgement)] {
        let byID = Dictionary(uniqueKeysWithValues: calendarJudgements.map { ($0.eventID, $0) })
        return calendarEvents.reversed().compactMap { event in
            byID[event.id].map { (event, $0) }
        }
    }

    var calendarAccuracy: CalendarClassifierAccuracy {
        CalendarClassifierAccuracy.measure(calendarJudgements)
    }

    var calendarBuckets: [CalendarEventBucket: [CalendarEvent]] {
        CalendarEventClassifier.bucket(calendarJudgements, events: calendarEvents,
                                       identity: readerIdentity)
    }

    // MARK: - Reader identity (B7 H1)

    /// Who the reader is, to their calendar. Loaded in `init` beside the
    /// profile — one small JSON read — and stored so every surface that shows
    /// standing ("Name & emails" rows, the Work impact route) observes it.
    private(set) var readerIdentity = ReaderIdentity()

    /// Persist the identity and re-read the one axis it informs.
    ///
    /// ⚠️ **Occasion only, and corrections survive by construction.** Entering
    /// a name retroactively resolves every OOO-shaped block already classified
    /// — an "Annual leave" filed as ambiguous last week is the reader's leave
    /// now — but the stored classifications may carry model-decided context,
    /// and the reader's own corrections live beside the guesses. So this walks
    /// the judgements through `CalendarEventClassifier.reoccasioned`, which
    /// moves the occasion, preserves everything else, and skips the write when
    /// nothing changed. No on-device model call: identity is a rules input.
    func saveReaderIdentity(_ identity: ReaderIdentity) {
        dataStore.saveReaderIdentity(identity)
        readerIdentity = identity
        let byID = Dictionary(uniqueKeysWithValues: calendarEvents.map { ($0.id, $0) })
        for judgement in dataStore.loadCalendarJudgements() {
            guard let event = byID[judgement.eventID],
                  let updated = CalendarEventClassifier.reoccasioned(
                      judgement.classification, for: event, identity: identity)
            else { continue }
            // The event goes in, not just its id: a re-classification refreshes
            // the artifact snapshot alongside the guess, so the pair stays
            // self-consistent (backlog B8 R3). The reader's correction is
            // untouched either way — `recordClassification` cannot see it.
            dataStore.recordClassification(updated, for: event)
        }
        reloadCalendar()
        recompute()
    }

    // MARK: - Holidays (B7 H4/H5)

    /// Hand-entered leave, newest first. Stored and observed, per the
    /// convention every SwiftData-backed log follows (`data-conventions.md`) —
    /// a computed read off the store is invisible to observation.
    private(set) var holidayEntries: [HolidayEntry] = []

    /// The one record of leave — detected blocks and entered periods, merged
    /// and deduplicated. This is what the Data tab shows, what the export
    /// carries, and what H6 will hand the cards. Derived rather than stored,
    /// so a correction on a calendar event moves it with no migration.
    var holidayLedger: HolidayLedger {
        HolidayLedger(
            detected: HolidayLedger.detected(events: calendarEvents,
                                             judgements: calendarJudgements),
            entered: holidayEntries.compactMap(\.period))
    }

    // MARK: - Sick days (§B11-4)

    /// **The one record of when the reader was ill** — every calendar block the
    /// classifier read as a sick day, merged and deduplicated.
    ///
    /// Derived rather than stored, exactly like `holidayLedger` and for the same
    /// reason: a correction on a calendar event moves it with no migration, so
    /// the reader retagging a day on the Work impact review list changes what
    /// the Data tab shows on the next pass.
    ///
    /// ⚠️ **Detected only, today.** There is no hand-entered half yet — no
    /// `InputKind`, no sheet — so a sick day the reader never put in a calendar
    /// cannot be recorded. That is a real gap and it is written down as one
    /// rather than papered over; the `entered:` half of `SickDayLedger` exists
    /// and takes the second source the day an input surface does.
    var sickDayLedger: SickDayLedger {
        SickDayLedger(
            detected: SickDayLedger.detected(events: calendarEvents,
                                             judgements: calendarJudgements))
    }

    /// Record one period of leave, past or planned.
    func logHoliday(firstDay: Date, lastDay: Date, label: String?) {
        dataStore.logHoliday(firstDay: firstDay, lastDay: lastDay, label: label)
        recompute()
    }

    func deleteHoliday(_ entry: HolidayEntry) {
        dataStore.deleteHolidayEntry(entry)
        recompute()
    }

    /// Pull from EventKit, store, and classify anything not yet judged.
    ///
    /// ⚠️ **Only unjudged events are classified.** Re-running over everything
    /// would spend the on-device model on events the reader has already
    /// corrected — and while `recordClassification` cannot overwrite a
    /// correction, doing the work to throw it away is how a launch gets slow for
    /// no benefit. (Identity *changes* re-read stored occasions separately and
    /// cheaply — see `saveReaderIdentity`.)
    func syncCalendar() async {
        // ⚠️ **The backstop, not the boundary.** The boundary is leaving the
        // card — see `flushCalendarReclassification()`. This is here so a reader
        // who never opens either calendar card does not accumulate stale guesses
        // for ever, and it is bounded by what actually moved rather than by the
        // size of the calendar: on the overwhelmingly common sync, where nothing
        // changed, it returns immediately having done nothing.
        await flushCalendarReclassification()

        guard let integration = registry.integration(withID: "calendar")
                as? CalendarIntegration,
              let fetched = try? integration.fetchEvents(identity: readerIdentity)
        else { return }
        dataStore.mergeCalendarEvents(fetched)

        let stored = dataStore.loadCalendarJudgements()
        let judged = Set(stored.map(\.eventID))
        for event in fetched where !judged.contains(event.id) {
            let base = CalendarEventClassifier.classify(event, identity: readerIdentity)
            // The on-device model settles the two interpretive axes where it is
            // available; `refined` refuses to let it touch anything else.
            let reading = await interpreter.interpret(event)
            let final = CalendarEventClassifier.refined(
                base, modelContext: reading?.context, modelFormality: reading?.formality)
            dataStore.recordClassification(final, for: event)
        }

        // MARK: what changed since it was judged (backlog B8 R3, C4)
        //
        // Detection only. A pure struct comparison against each stored snapshot,
        // costing a dictionary lookup per event — cheap enough to run every sync,
        // which is the whole reason judging and noticing were separated. What it
        // finds is queued and judged on a boundary, below.
        //
        // ⚠️ `stored` is read *before* the loop above deliberately: an event just
        // classified for the first time cannot have drifted from a snapshot taken
        // one line ago, and including it would re-judge every new event twice.
        let drifted = CalendarEventClassifier.drifted(stored, events: fetched)
        calendarReclassificationQueue.formUnion(drifted.map(\.id))
        // Where the reader has already answered and the event moved underneath
        // them, the row is flagged rather than silently re-decided. Their
        // correction is untouched either way — `recordClassification` cannot see
        // one — but an answer about words that no longer exist deserves saying so.
        dataStore.markCalendarJudgementsChanged(drifted.map(\.id))

        reloadCalendar()
        recompute()
    }

    /// **Re-judge everything that changed, on the way out of the card.**
    ///
    /// The reader's instruction, 2026-08-06: *"I want it to re-write the model,
    /// and re-calculate, maybe only do it once they leave the card, or just
    /// whatever is the most efficient way, that also will not completely slow
    /// down or break the app."*
    ///
    /// ## The boundary chosen, and why it is this one
    ///
    /// **Leaving the insight detail view** (`InsightDetailView`'s body-level
    /// `.onDisappear`), with the next sync as a backstop. Noticing a change is
    /// free and happens on every sync; *judging* one is not — it is an on-device
    /// language-model call per event — and the two calendar cards are the only
    /// surface where the answer is visible. Doing the work as the reader walks
    /// out means it is already done when they walk back in, and it happens with
    /// nothing on screen waiting on it.
    ///
    /// ⚠️ **The trigger must be at body level, never on a section.**
    /// `InsightDetailView.body` is a `ScrollView { LazyVStack { … } }` — lazy on
    /// purpose, because a card is eleven-plus sections and several run real
    /// models — so an `.onDisappear` attached to the calendar review section
    /// fires every time that section scrolls out of view. That is a view update,
    /// which is the first of the two alternatives rejected below.
    ///
    /// The two alternatives were both worse, and both are named because both were
    /// nearly taken:
    ///
    /// - **Inside a view update.** It would run on every redraw, against a list
    ///   the reader is in the middle of reading, and relabel rows under their
    ///   thumb.
    /// - **On the sync tick.** It would land inside the "Syncing your devices"
    ///   pass the reader has already told us hangs their phone (2026-08-06), and
    ///   for a card they may not be looking at.
    ///
    /// Either trigger empties the queue, so **nothing happens when nothing
    /// moved** — which is what makes this a debounce rather than a schedule.
    ///
    /// ## ⚠️ The invariant
    ///
    /// This rewrites the **guess** and the **snapshot** and cannot reach the
    /// reader's correction: `DataStore.recordClassification` does not take one
    /// and has never had one in hand (backlog C4), and
    /// `CalendarEventJudgement.reclassified(as:artifact:)` states the same thing
    /// at value level, where it is tested. Where a correction exists and the
    /// event moved under it, `markCalendarJudgementsChanged` has already flagged
    /// the row, so the reader is told rather than overruled.
    func flushCalendarReclassification() async {
        guard !calendarReclassificationQueue.isEmpty else { return }
        // Taken and cleared up front, so a sync landing mid-flush queues into an
        // empty set rather than having its work dropped by the clear at the end.
        let pending = calendarReclassificationQueue
        calendarReclassificationQueue = []
        let byID = Dictionary(dataStore.loadCalendarEvents().map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        var rejudged = 0
        for id in pending {
            guard let event = byID[id] else { continue }
            let base = CalendarEventClassifier.classify(event, identity: readerIdentity)
            let reading = await interpreter.interpret(event)
            let final = CalendarEventClassifier.refined(
                base, modelContext: reading?.context, modelFormality: reading?.formality)
            // Guess and snapshot together, so the stored pair stays each other's.
            dataStore.recordClassification(final, for: event)
            rejudged += 1
        }
        guard rejudged > 0 else { return }
        reloadCalendar()
        // Both calendar cards read `loadHours`, which a re-judged occasion or
        // formality moves. This is the existing path — the insight pass runs off
        // the main actor behind its generation guard (`dab5399`); nothing
        // synchronous is reintroduced here.
        recompute()
    }

    func reloadCalendar() {
        calendarEvents = dataStore.loadCalendarEvents()
        calendarJudgements = dataStore.loadCalendarJudgements()
    }

    /// The reader's answer on one event.
    func reviewCalendarEvent(_ eventID: String,
                             correction: CalendarEventClassification?,
                             confirmed: Bool) {
        dataStore.recordReview(eventID: eventID, correction: correction,
                               confirmed: confirmed)
        reloadCalendar()
        // Both cards read `loadHours`, which a correction changes, so they have
        // to be recomputed rather than left showing the old shape.
        recompute()
    }

    func forgetCalendar() {
        dataStore.forgetCalendar()
        reloadCalendar()
        recompute()
    }

    // MARK: - Cycle log

    /// Every logged bleeding day. **A stored, reloaded property** — never a
    /// computed read from the store, which is invisible to observation and is
    /// the "toggle that doesn't move when tapped" trap `data-conventions.md`
    /// records.
    private(set) var cycleDays: [CycleDay] = []

    /// The cycles those days form, and the range they fall in.
    var cycleSummary: CycleSummary { CycleModel.summarise(days: cycleDays) }

    /// The next period, ovulation and the fertile window — **or the stated
    /// reason there is none.** Never an optional the view has to invent an
    /// empty state for: `CycleForecastRefusal` carries its own sentence.
    var cycleForecast: CycleForecast { CyclePhaseModel.forecast(cycleSummary) }

    /// Today's phase, when the log can support one.
    var currentCyclePhase: CyclePhaseEstimate? {
        CyclePhaseModel.phase(on: Date(), summary: cycleSummary)
    }

    /// Per-phase baselines for the radar's own channels.
    ///
    /// **A stored, reloaded property** rather than a computed one, for two
    /// reasons. The first is `data-conventions.md`'s observation trap — a
    /// computed read is invisible to `@Observable` and the card would not
    /// redraw when a day is logged. The second is cost: building it reads a
    /// year of daily series for seven metrics and places every day in a phase,
    /// which is not something a SwiftUI `body` may do on every scroll frame.
    ///
    /// ⚠️ **Read by the cycle tab only.** `HealthWatchModel` and the symptom
    /// radar deliberately do not consume it yet — see the TODO on
    /// `PhaseAwareBaseline`, which cannot be closed without redoing the radar's
    /// calibration.
    private(set) var cyclePhaseProfile = PhaseAwareBaseline.Profile(baselines: [:],
                                                                    cyclesObserved: 0)

    func setCycleDay(_ day: Date, flow: MenstrualFlowLevel) {
        dataStore.setCycleDay(day, flow: flow)
        cycleDays = dataStore.loadCycleDays()
        refreshCyclePhaseProfile()
    }

    func clearCycleDay(_ day: Date) {
        dataStore.clearCycleDay(day)
        cycleDays = dataStore.loadCycleDays()
        refreshCyclePhaseProfile()
    }

    /// Rebuild the per-phase baselines. Called from `recompute()` and from both
    /// cycle mutators — the mutators do **not** go through `recompute()`, so
    /// leaving it to that would have left the shifts card a day stale after
    /// every tap, which is the same shape as the substance-log bug recorded in
    /// `reloadLoggedData`.
    private func refreshCyclePhaseProfile() {
        cyclePhaseProfile = PhaseAwareBaseline.profile(samples: samples,
                                                       summary: cycleSummary)
    }

    /// The active-compound curve for the visible window, or empty when there
    /// is no regimen. Memoised per window, since a chart re-evaluates its body
    /// on every pan frame.
    func medicationCurve(days: Int = 90, now: Date = Date()) -> [ActiveCompoundPoint] {
        guard let medication = activeMedication, let compound = medication.compound,
              !medication.doses.isEmpty else { return [] }
        let doses = medication.doses.map(\.administered)
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return PharmacokineticsModel.curve(doses: doses, compound: compound,
                                           from: max(start, medication.startedOn),
                                           to: now)
    }

    /// The medication read against the body — dose steps, injection sites and
    /// the overall change since the first dose.
    ///
    /// Not cached: it walks the dose list and the weight record once, and both
    /// change only when the reader logs something or an import lands. Caching it
    /// would need invalidating from four places, which is how a stale figure
    /// gets shipped.
    var medicationResponse: MedicationResponse.Analysis {
        guard let medication = activeMedication else {
            return MedicationResponse.Analysis(overall: nil, byDose: [],
                                               bySite: [], periods: [])
        }
        return MedicationResponse.analyze(doses: medication.doses.map(\.administered),
                                          weights: samples)
    }

    /// The three standardised series behind "is it working".
    func medicationOverlay(days: Int, now: Date = Date()) -> [MedicationResponse.ResponseSeries] {
        let curve = medicationCurve(days: days, now: now)
        guard let first = curve.first?.date else { return [] }
        return MedicationResponse.overlay(curve: curve, weights: samples,
                                          range: first...now)
    }

    // MARK: - Build

    /// The reader's own read of their build, if they set one.
    ///
    /// `@AppStorage`-backed rather than a grounding fact: nothing scores off it,
    /// which is exactly why it can be a free choice. Read here rather than only
    /// inside the somatotype card so that "View & add" and the master input list
    /// can show where the reader stands on it — the input was reachable from one
    /// picker inside one chart, which is the bug this whole change is about.
    var buildOverride: Somatotype.Component? {
        Somatotype.Component(
            rawValue: UserDefaults.standard.string(forKey: Self.buildOverrideKey) ?? "")
    }

    func setBuildOverride(_ component: Somatotype.Component?) {
        if let component {
            UserDefaults.standard.set(component.rawValue, forKey: Self.buildOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.buildOverrideKey)
        }
    }

    /// The same key `InsightDetailView`'s `@AppStorage` uses. Declared once here
    /// so the two cannot drift into writing different keys for one setting.
    static let buildOverrideKey = "somatotypeOverride"

    var buildOverrideName: String? { buildOverride?.displayName }

    /// What the app itself makes of the reader's build.
    var estimatedBuildName: String? {
        SomatotypeModel.estimate(
            bodyFatPercentage: samples.latestValue(.bodyFatPercentage),
            leanMassKg: samples.latestValue(.leanBodyMass),
            weightKg: samples.latestValue(.bodyMass) ?? 0,
            heightMetres: samples.latestValue(.height) ?? 0,
            dimensions: nil,
            age: profile.age() ?? 35,
            sex: profile.sex ?? .male)?.dominant.displayName
    }

    /// **Which inputs the reader has ever used.**
    ///
    /// Feeds `SuggestionEngine.unusedInputs`, which is the fourth clause of the
    /// user's rule: an input never used earns a dismissible row in "Improve your
    /// health", and Today shows the top one. Exhaustive over `InputKind`, so a
    /// new input has to say how "used" is decided for it rather than defaulting
    /// to never-prompted (silently) or always-prompted (annoyingly).
    var usedInputs: Set<InputKind> {
        var used: Set<InputKind> = []
        for kind in InputKind.allCases {
            let hasBeenUsed: Bool
            switch kind {
            case .profileFacts:
                hasBeenUsed = GroundingKind.directlyEntered.contains {
                    profile.value($0) != nil
                }
            case .cuffBloodPressure:
                hasBeenUsed = !bloodPressureReadings.isEmpty
            case .substanceEvent:
                hasBeenUsed = !substanceEvents.isEmpty
            case .medicationRegimen:
                hasBeenUsed = activeMedication != nil
            case .medicationDose:
                hasBeenUsed = !(activeMedication?.doses.isEmpty ?? true)
            case .sideEffect:
                hasBeenUsed = !sideEffects.isEmpty
            // Since Q7 there *is* a record of how a value arrived — every
            // `LabResult` carries its `source` — so this is no longer the
            // hard-coded `true` it was when nothing was stored. It still never
            // prompts (`.settingsOnly`), so the answer is only ever read as
            // "stop suggesting".
            case .bloodTestPhoto:
                hasBeenUsed = labResults.contains { $0.source.isMachineRead }
            case .labResultManual:
                hasBeenUsed = labResults.contains { $0.source == .typed }
            case .ecgImport:
                hasBeenUsed = !ecgRecords.isEmpty
            case .fileImport:
                hasBeenUsed = ShotsyIntegration.lastImportDate != nil
            case .bodyType:
                hasBeenUsed = buildOverride != nil
            // Any measured site counts as having used it. Not "a waist",
            // deliberately: the prompt asks whether the reader has ever tried
            // this input, and somebody who measured their chest has.
            case .bodyMeasurements:
                hasBeenUsed = !bodyScans.isEmpty
            case .screenTime:
                hasBeenUsed = !samples.samples(of: .screenTimeMinutes).isEmpty
            // Saying anything — a name or one email — is using it. It never
            // prompts (`.offeredOnly`), so this is only ever read as "stop
            // suggesting"; demanding completeness here would change nothing.
            case .readerIdentity:
                hasBeenUsed = readerIdentity.isConfigured
            // Entered leave only, deliberately: a *detected* holiday is the
            // calendar's doing, and the question this answers is whether the
            // reader has ever tried the input.
            case .holiday:
                hasBeenUsed = !holidayEntries.isEmpty
            // Having answered one flagged event counts. Never prompts through
            // this route (`.settingsOnly`) — `SuggestionEngine.eventsAwaitingReview`
            // raises the queue itself, carrying a count, which is a better-founded
            // row than "a feature you have not tried" — so this is only ever read
            // as "stop suggesting".
            case .eventConfirmation:
                hasBeenUsed = EventFeedModel.shared.feed.accuracy.scored > 0
                    || EventFeedModel.shared.feed.accuracy.answeredWithoutAGuess > 0
            // One bottle counts. The question this answers is whether the reader
            // has ever tried the input, and somebody who entered a multivitamin
            // has — the sum across a stack is what the card is *for*, not what
            // decides whether to keep nudging them about the feature.
            case .supplement:
                hasBeenUsed = !supplementEntries.isEmpty
            }
            if hasBeenUsed { used.insert(kind) }
        }
        return used
    }

    /// The same records tallied by symptom, worst average first.
    var sideEffectTally: [MedicationResponse.SideEffectTally] {
        MedicationResponse.sideEffectTally(
            sideEffects.map { (name: $0.name, severity: $0.severity, date: $0.date) })
    }

    /// Record a side effect by hand.
    ///
    /// Until this existed a side effect could only arrive inside a Shotsy
    /// backup, so the app held a kind of data with no way to give it one —
    /// which is exactly what the master input list is meant to make impossible.
    func logSideEffect(name: String, severity: Int, at date: Date = Date()) {
        dataStore.logSideEffect(name: name, severity: severity, at: date)
        recompute()
    }

    func deleteSideEffect(_ record: SideEffectRecord) {
        dataStore.deleteSideEffect(record)
        recompute()
    }

    // MARK: - Screen time

    /// How many days of screen time the reader has supplied.
    var screenTimeDaysRecorded: Int {
        Set(samples.samples(of: .screenTimeMinutes)
            .map { Calendar.current.startOfDay(for: $0.start) }).count
    }

    var lastScreenTimeEntry: Date? {
        samples.samples(of: .screenTimeMinutes).map(\.start).max()
    }

    /// Record a day's screen time.
    ///
    /// Stored as a manual sample like a cuff reading, because that is what it
    /// is — the reader's own figure, read off Settings ▸ Screen Time or handed
    /// over by a Shortcut. Apple gives an app no way to sense it; see
    /// `MetricType.screenTimeMinutes`.
    ///
    /// **Upserts by day**: re-entering a date replaces that day rather than
    /// adding to it, so correcting a typo cannot leave two figures for one day
    /// averaging into a number the reader never saw.
    func logScreenTime(minutes: Double, on date: Date) {
        recordScreenTime([ScreenTimeEntry(day: date, minutes: minutes,
                                          provenance: .manual, recordedAt: Date())])
    }

    /// File screen-time figures read off a screenshot, at whatever days they
    /// belong to — which is very often not today.
    ///
    /// - Returns: how many days were actually written. Days already carrying
    ///   something better are skipped, so importing the same screenshot twice
    ///   reports zero rather than churning the store.
    @discardableResult
    func importScreenTime(_ entries: [ScreenTimeEntry]) -> Int {
        recordScreenTime(entries)
    }

    /// The one write path, so precedence is applied exactly once.
    @discardableResult
    private func recordScreenTime(_ entries: [ScreenTimeEntry]) -> Int {
        var written = 0
        for entry in entries where dataStore.recordScreenTime(entry) { written += 1 }
        guard written > 0 else { return 0 }

        // Reload the whole metric rather than patching the days that changed:
        // a rejected entry leaves the old row in place, so a per-day splice
        // would have to know which of them were skipped to stay in step.
        samples = (samples.filter { $0.type != .screenTimeMinutes }
                   + dataStore.loadManualSamples().filter { $0.type == .screenTimeMinutes })
            .partitionedVitals().kept
        recompute()
        return written
    }

    // MARK: - Body scans

    /// Every scan, newest first. Reloaded rather than computed off the store —
    /// a computed property reading SwiftData is invisible to SwiftUI observation,
    /// which is the defect `sideEffects` and `activeMedication` were fixed for.
    private(set) var bodyScans: [BodyScan] = []

    /// Every blood-test analyte the reader has given the app — backlog `Q7`.
    ///
    /// A **stored** property reloaded in `reloadLoggedData()`, never a computed
    /// property reading SwiftData: a computed one is invisible to SwiftUI
    /// observation, which is the defect `sideEffects` and `activeMedication`
    /// were both fixed for and the trap `docs/data-conventions.md` names.
    private(set) var labResults: [LabResult] = []

    /// Every imported ECG — backlog `I7`. Metadata and a file name; the trace
    /// itself is in `DocumentAttachmentStore`.
    private(set) var ecgRecords: [ECGRecord] = []

    /// Store confirmed lab results.
    ///
    /// ⚠️ **The two lipids also become grounding facts**, and only when the
    /// reading is not doubtful. That duplication is deliberate — SCORE2 and
    /// ASCVD read the profile, this store is the history — and the confidence
    /// gate is the point: a value the parser flagged goes into the reader's
    /// record where they can see it beside its warning, and does not go into a
    /// ten-year risk estimate that will never ask.
    func saveLabResults(_ results: [LabResult]) {
        guard !results.isEmpty else { return }
        dataStore.saveLabResults(results)
        for result in results {
            guard let kind = result.analyte.groundingKind else { continue }
            guard result.confidence != .doubtful else { continue }
            saveGrounding(kind: kind, value: result.value)
        }
        labResults = dataStore.labResults()
        recompute()
    }

    func deleteLabResult(id: UUID) {
        dataStore.deleteLabResult(id: id)
        labResults = dataStore.labResults()
        recompute()
    }

    /// Store an imported ECG.
    ///
    /// ⚠️ Nothing is computed from it and nothing scores it — see `ECGRecord`.
    /// `recompute()` is still called so the Data tab's row count refreshes,
    /// which is the only thing downstream of this.
    func saveECGRecord(_ record: ECGRecord) {
        dataStore.saveECGRecord(record)
        ecgRecords = dataStore.ecgRecords()
        recompute()
    }

    func deleteECGRecord(id: UUID) {
        dataStore.deleteECGRecord(id: id)
        ecgRecords = dataStore.ecgRecords()
        recompute()
    }

    /// What a scan may use, and separately what it may keep.
    ///
    /// A **stored** property, deliberately: `UserDefaults` is invisible to
    /// SwiftUI observation exactly as SwiftData is, and a settings screen whose
    /// toggles do not move when tapped is the same defect one layer over. The
    /// defaults are the durable copy; this is the one the views read.
    ///
    /// `UserDefaults`-backed rather than a store row because it is a preference
    /// and nothing scores off it — the same reasoning as `buildOverride`. Held
    /// as the type's own `Codable` form, so a build that adds a
    /// `BodyScanAsset` case cannot half-decode an older policy: it either
    /// decodes whole or falls back to `.standard`, which is what a fresh
    /// install gets anyway.
    private(set) var bodyScanPolicy: BodyScanPolicy = AppModel.storedBodyScanPolicy()

    static let bodyScanPolicyKey = "bodyScanPolicy"

    private static func storedBodyScanPolicy() -> BodyScanPolicy {
        guard let data = UserDefaults.standard.data(forKey: bodyScanPolicyKey),
              let decoded = try? JSONDecoder().decode(BodyScanPolicy.self, from: data)
        else { return .standard }
        return decoded
    }

    /// The screen hands back a whole policy rather than a toggle, because
    /// `BodyScanPolicy` normalises `retained ⊆ captured` in its initialiser and
    /// a per-toggle setter here would be a second place for that rule to live.
    func setBodyScanPolicy(_ policy: BodyScanPolicy) {
        bodyScanPolicy = policy
        if let data = try? JSONEncoder().encode(policy) {
            UserDefaults.standard.set(data, forKey: Self.bodyScanPolicyKey)
        }
    }

    /// Save a scan and fold its measurements into the canonical series.
    ///
    /// The promoted sites become samples so they trend, chart and export through
    /// the machinery every other metric already uses; the full set stays on the
    /// scan for its own page.
    func saveBodyScan(_ scan: BodyScan) {
        dataStore.saveBodyScan(scan)
        bodyScans = dataStore.bodyScans()
        // **A scan's figures are worked out, not read.** `.screenshot` means
        // "read off a screenshot of the reader's own device" — the Screen Time
        // route — and a LiDAR capture is not that. `.calculated` is what the
        // overlay legend, the per-source breakdown and the export then say,
        // which is the honest description of a circumference fitted to depth.
        let source: MetricSource = scan.mode == .tape ? .manual : .calculated
        let calendar = Calendar.current
        let typed = dataStore.loadManualSamples()
            .filter { $0.source.id == MetricSource.manual.id }
        for sample in scan.samples(source: source) {
            let day = calendar.startOfDay(for: sample.start)
            // ⚠️ **A scan never overwrites a measured figure.** Scan and tape on
            // the same day used to collide here and the scan won, purely because
            // it was written second — backwards, since
            // `BodyMeasurementProvenance` ranks a tape above both scan modes and
            // `BodyMeasurementReconciliation` would have chosen the tape if it
            // had still been there to choose. Skipping keeps the scan on its own
            // page and in `bodyScans`; only the promoted canonical series defers.
            if scan.mode != .tape,
               typed.contains(where: { $0.type == sample.type
                                       && calendar.isDate($0.start, inSameDayAs: day) }) {
                continue
            }
            dataStore.replaceManualSamples(of: sample.type, on: day, with: [sample])
        }
        reloadScanSamples()
        recompute()
    }

    func deleteBodyScan(id: UUID) {
        dataStore.deleteBodyScan(id: id)
        bodyScans = dataStore.bodyScans()
        recompute()
    }

    /// Pull the scan-derived metrics back out of the store into `samples`.
    private func reloadScanSamples() {
        let scanMetrics = Set(BodySite.allCases.compactMap(\.metricType))
        samples = (samples.filter { !scanMetrics.contains($0.type) }
                   + dataStore.loadManualSamples().filter { scanMetrics.contains($0.type) })
            .partitionedVitals().kept
    }

    /// Every body measurement the app holds, from every source, reconciled.
    ///
    /// This is what makes a reader with Apple Health well populated get a body
    /// model without ever opening the scanner: Health's own waist arrives as a
    /// sample, a scan arrives as a scan, and `BodyMeasurementReconciliation`
    /// ranks them by **method** rather than by which app they came through.
    func reconciledMeasurements(now: Date = Date()) -> BodyMeasurements {
        BodyMeasurementReconciliation.merge(measurementCandidates(), now: now)
    }

    /// Every measurement the app holds, from every source, unreconciled.
    ///
    /// One list feeding both the merge and the dispute report, so the two cannot
    /// disagree about what was on the table.
    private func measurementCandidates() -> [SourcedMeasurement] {
        var candidates: [SourcedMeasurement] = []
        for scan in bodyScans {
            let provenance: BodyMeasurementProvenance
            switch scan.mode {
            case .lidarDepth: provenance = .lidarScan
            case .cameraSegmentation: provenance = .cameraScan
            case .tape: provenance = .tape
            }
            for value in scan.measurements.values {
                candidates.append(SourcedMeasurement(site: value.site,
                                                     centimetres: value.centimetres,
                                                     provenance: provenance,
                                                     measuredAt: scan.capturedAt))
            }
        }
        // Anything the same site arrived as through Apple Health or a provider.
        for site in BodySite.allCases {
            guard let metric = site.metricType else { continue }
            // Everything this app produced itself is excluded, or a scan would
            // come back round as an "Apple Health" candidate and argue with
            // itself. `.calculated` is the scan source since 2026-08-07;
            // `.screenshot` stays in the list because scans written by earlier
            // builds are still on disk under it.
            let external = samples.samples(of: metric)
                .filter { $0.source.id != MetricSource.manual.id
                          && $0.source.id != MetricSource.calculated.id
                          && $0.source.id != MetricSource.screenshot.id }
            if let latest = external.max(by: { $0.start < $1.start }) {
                candidates.append(SourcedMeasurement(site: site, centimetres: latest.value,
                                                     provenance: .externalHealthApp,
                                                     measuredAt: latest.start))
            }
        }
        return candidates
    }

    /// Sites where two sources disagree beyond the noise — shown rather than
    /// silently resolved.
    func measurementDisputes(now: Date = Date()) -> [BodyMeasurementReconciliation.Outcome] {
        BodyMeasurementReconciliation.disputes(measurementCandidates(), now: now)
    }

    /// Stored screen-time figures with their provenance, newest first.
    func screenTimeEntries() -> [ScreenTimeEntry] { dataStore.screenTimeEntries() }

    /// Doses the app proposed and the reader has not yet confirmed.
    var unconfirmedDoseCount: Int {
        activeMedication?.doses.filter { $0.isInferred && $0.confirmedAt == nil }.count ?? 0
    }

    // MARK: - File import

    /// Take in a file the OS handed us — from the share sheet, "Open With", or
    /// the in-app picker.
    ///
    /// **Async, and the reason is what the user saw.** The first version did
    /// all of this synchronously on the main actor: read, parse, several
    /// hundred SwiftData inserts, then a full re-evaluation of every insight
    /// over the whole sample set. The app simply stopped for several seconds
    /// and the result alert appeared afterwards, so the only feedback was a
    /// freeze. Parsing now happens off the actor and `isImporting` drives a
    /// progress overlay, so the wait is visible and explained rather than
    /// looking like a hang.
    ///
    /// Returns the sentence to show the reader, always. An import that fails
    /// silently is indistinguishable from one that did nothing, and somebody
    /// who has just shared a backup out of another app is owed an answer.
    func importSharedFile(at url: URL) async -> String {
        isImporting = true
        defer { isImporting = false }
        // One turn of the run loop so the overlay is on screen before the work
        // starts — without it the first frame the reader sees is the finished
        // one, which is the freeze all over again.
        await Task.yield()

        let parsed: ShotsyImport.Result
        do {
            let data = try ShotsyImportService.read(url)
            // `parse` is pure and `Sendable`, so it can leave the main actor —
            // and it is the only part of this that can.
            parsed = try await Task.detached(priority: .userInitiated) {
                try ShotsyImport.parse(data)
            }.value
        } catch ShotsyImport.Failure.notAShotsyExport {
            return "That JSON file isn't a Shotsy backup — nothing was imported. In Shotsy, use Settings ▸ Manage My Data ▸ Export JSON, then share the file to this app."
        } catch ShotsyImport.Failure.notJSON {
            return "That file isn't JSON, so there was nothing to read."
        } catch {
            return "Couldn't read that file: \(error.localizedDescription)"
        }

        // Persistence and the re-evaluation are main-actor bound (SwiftData and
        // the engine both), so they stay here — but the reader is now watching
        // a spinner rather than a frozen screen.
        let summary = ShotsyImportService(dataStore: dataStore).persist(parsed)
        if !summary.isEmpty {
            samples = (samples + dataStore.loadManualSamples()).partitionedVitals().kept
            recompute()
            // The integration's only honest freshness claim is when a file
            // last arrived, so this is what writes it.
            ShotsyIntegration.recordImport(summary: summary.sentence)
        }
        return summary.sentence
    }

    /// Take readings handed over by the reader's Shortcuts automation.
    ///
    /// Returns the sentence to show them, which names anything it refused —
    /// a mistyped metric or a value outside its plausible range. A shortcut is
    /// a hand-built thing and silently dropping half of it would leave the
    /// reader believing they are collecting something they are not.
    #if DEBUG
    /// Fill the store with generated data so a simulator can show a chart.
    ///
    /// Debug builds only — see `SettingsView.syntheticDataSection` for why this
    /// exists and why it is not the URL scheme. **Writes through
    /// `replaceManualSamples`, exactly as `ingestShortcut` does**, so the
    /// per-day upsert, the reload and the recompute are the shipped ones rather
    /// than a parallel path that could drift from them.
    func seedSyntheticData(days: Int) {
        let calendar = Calendar.current
        // The cycle log first, because the vitals are shaped by it: with a log
        // present the four phase-structured channels go biphasic, which is what
        // gives the phase-aware shifts card something measured to render. The
        // fifth tab is otherwise only ever screenshot in its refusal state.
        let cycleLog = SyntheticSeed.seededCycleDays(calendar: calendar)
        for entry in cycleLog {
            dataStore.setCycleDay(entry.day, flow: entry.flow, calendar: calendar)
        }
        let generated = SyntheticSeed.samples(days: days, endingOn: Date(),
                                              cycleDays: cycleLog, calendar: calendar)
        let byDayAndType = Dictionary(grouping: generated) { sample in
            "\(sample.type.rawValue)|\(calendar.startOfDay(for: sample.start).timeIntervalSince1970)"
        }
        for (_, group) in byDayAndType {
            guard let first = group.first else { continue }
            dataStore.replaceManualSamples(of: first.type,
                                           on: calendar.startOfDay(for: first.start),
                                           with: group)
        }
        // **The grounding facts, or several cards stay empty with full vitals.**
        // A cardiovascular risk needs an age, a sex and a lipid panel; a
        // biological age needs an age to compare against; a weight rate has no
        // meaning without a goal. None of that can be sensed, so a simulator
        // with every metric seeded and an empty profile still shows a row of
        // cards asking for details — which is the "cards where there is no
        // data" the reader reported on 2026-08-07.
        // `GroundingKind.syntheticSeedFact` is exhaustive, so a new fact cannot
        // be forgotten here.
        for (kind, value) in SyntheticSeed.profileFacts() {
            dataStore.saveGrounding(kind: kind, value: value)
        }
        profile = dataStore.loadProfile()
        samples = dataStore.loadManualSamples().partitionedVitals().kept
        recompute()
    }

    /// Replay the score history from a loaded export, so the balance web's
    /// reference shape can be seen.
    ///
    /// **Debug only, and it exists because a file copy cannot reach this.**
    /// `scripts/load-real-export.sh` writes samples straight into the sample
    /// cache, which is JSON — but score rows live in SwiftData, so they need
    /// code. Without them the web's grey "usual" polygon and its legend are
    /// invisible on any simulator: both read stored score rows, and neither
    /// generated data nor a fresh install has any.
    ///
    /// Goes through `recordScore`, the same per-day upsert a real day uses, so
    /// the rows land exactly as they would have — no parallel write path that
    /// could drift from the shipped one.
    @discardableResult
    func importScoreHistory() -> Int {
        struct Card: Decodable {
            let card: String
            let history: [Point]
            struct Point: Decodable { let date: Date; let score: Double }
        }
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: false),
              let data = try? Data(contentsOf: base.appendingPathComponent("score_history_import.json")),
              let cards = try? JSONDecoder().decode([Card].self, from: data)
        else { return 0 }

        var written = 0
        for card in cards {
            guard let id = InsightID(rawValue: card.card) else { continue }
            for point in card.history {
                dataStore.recordScore(id, score: point.score, confidence: .moderate,
                                      contributorCount: 0, on: point.date)
                written += 1
            }
        }
        recompute()
        return written
    }

    /// Import the parts of an export that **live in SwiftData and therefore
    /// cannot be restored by copying a file**.
    ///
    /// The reader, 2026-08-05: *"the master export feature didn't seem to
    /// correctly export EVERYTHING… didn't import substances, didn't import all
    /// the things that populated the cards… so therefore your emulator doesn't
    /// look like my app, and you can't validate everything"*.
    ///
    /// Half of that was a **loader** gap rather than an export one, and this
    /// closes it. Their export already carried 16 substance events, their
    /// medication history, side effects, symptom tags and every grounding fact;
    /// `scripts/load-real-express.sh` writes only the two JSON sample caches,
    /// so none of it reached the simulator. What that cost, concretely:
    /// Substance Impact showed its invite state rather than the real analysis,
    /// Cardiovascular Risk could not run at all without age and sex, and Blood
    /// Pressure read as uncalibrated because the cuff readings are grounding
    /// facts.
    ///
    /// Every write goes through the **shipped** store API — `addSubstanceEvent`,
    /// `saveGrounding`, `logSideEffect`, `replaceMedicationHistory` — for the
    /// same reason `importScoreHistory` uses `recordScore`: a parallel write
    /// path is one that can drift from the real one and then validate nothing.
    ///
    /// Returns a per-kind count so a silent no-op is distinguishable from a
    /// successful import of an export that happened to be empty.
    @discardableResult
    func importExportedRecords() -> [String: Int] {
        struct SideEffectRow: Decodable {
            let name: String; let severity: Int; let date: Date
        }
        struct ProfileRow: Decodable { let inputs: [String: Double]? }

        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: false),
              let data = try? Data(contentsOf: base.appendingPathComponent("records_import.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // ⚠️ **Each section decodes on its own.** The first version decoded one
        // `Payload` covering all four, and a single shape mismatch — the
        // profile's `inputs`, which Swift encodes as an alternating key/value
        // *array* because its key is not a `String` — threw and silently lost
        // the substances and side effects with it. The button reported "Nothing
        // to import" while sixteen events sat in the file. One bad section must
        // cost only that section.
        func section<T: Decodable>(_ key: String, as type: T.Type) -> T? {
            guard let part = root[key],
                  let data = try? JSONSerialization.data(withJSONObject: part) else { return nil }
            return try? decoder.decode(type, from: data)
        }

        var counts: [String: Int] = [:]

        // Substance events, skipped by id so a second import cannot duplicate.
        let existing = Set(dataStore.loadSubstanceEvents().map(\.id))
        for event in section("substances", as: [SubstanceEvent].self) ?? []
        where !existing.contains(event.id) {
            dataStore.addSubstanceEvent(event)
            counts["substances", default: 0] += 1
        }

        for effect in section("sideEffects", as: [SideEffectRow].self) ?? [] {
            dataStore.logSideEffect(name: effect.name, severity: effect.severity, at: effect.date)
            counts["sideEffects", default: 0] += 1
        }

        // Grounding facts — the ones without which whole cards cannot score.
        for (raw, value) in section("profile", as: ProfileRow.self)?.inputs ?? [:] {
            guard let kind = GroundingKind(rawValue: raw) else { continue }
            dataStore.saveGrounding(kind: kind, value: value)
            counts["grounding", default: 0] += 1
        }

        // ⚠️ **`reloadLoggedData` does not touch the substance log**, which is
        // why the first version of this reported "16 substances" and left the
        // card reading "Log to see effects": the rows were in SwiftData and the
        // engine still held the empty log it was bound to at launch. Reload it
        // and the grounding profile explicitly.
        substanceEvents = dataStore.loadSubstanceEvents()
        supplementEntries = dataStore.loadSupplementEntries()
        profile = dataStore.loadProfile()
        reloadLoggedData()
        recompute()
        return counts
    }

    /// Remove everything `seedSyntheticData` wrote, so the empty state — the one
    /// every reader sees first, and the one the invisible-cards defect lived in
    /// — is still reachable without erasing the whole simulator.
    func clearSyntheticData() {
        for type in MetricType.allCases {
            dataStore.deleteManualSamples(of: type, from: .shortcuts)
        }
        // ⚠️ The seeded cycle log too, or "clear seeded data" leaves the fifth
        // tab still full and a later screenshot of its empty state is of a tab
        // that is not empty. Cycle days carry no `MetricSource`, so the loop
        // above cannot reach them — every generated day has to be named.
        let calendar = Calendar.current
        for entry in SyntheticSeed.seededCycleDays(calendar: calendar) {
            dataStore.clearCycleDay(entry.day, calendar: calendar)
        }
        // ⚠️ And the seeded grounding facts, for the same reason: a grounding
        // row carries no provenance, so the loop above cannot find it either.
        // Leaving them behind would mean "clear seeded data" produced a
        // simulator with no readings and a full profile — a state no reader has
        // ever been in, and the wrong thing to screenshot an empty state from.
        for kind in SyntheticSeed.profileFacts().keys {
            dataStore.deleteGrounding(kind: kind)
        }
        profile = dataStore.loadProfile()
        samples = dataStore.loadManualSamples().partitionedVitals().kept
        recompute()
    }
    #endif

    @discardableResult
    func ingestShortcut(_ url: URL) -> String? {
        guard let result = ShortcutIngest.parse(url) else { return nil }

        if !result.samples.isEmpty {
            // Upsert per metric per day: an automation that runs twice, or is
            // re-run to correct a figure, must not leave two readings for one
            // day to be averaged into a number nobody saw.
            let calendar = Calendar.current
            for sample in result.samples {
                dataStore.replaceManualSamples(of: sample.type,
                                               on: calendar.startOfDay(for: sample.start),
                                               with: [sample])
            }
            samples = (samples.filter { existing in
                !result.samples.contains {
                    $0.type == existing.type
                        && calendar.isDate($0.start, inSameDayAs: existing.start)
                }
            } + dataStore.loadManualSamples()).partitionedVitals().kept
            recompute()
        }

        let summary = Self.shortcutSummary(result)
        ShortcutsIntegration.recordRun(summary: summary)
        return summary
    }

    static func shortcutSummary(_ result: ShortcutIngest.Result) -> String {
        var parts: [String] = []
        if result.samples.isEmpty {
            parts.append("Nothing was recorded")
        } else {
            let names = result.samples.map(\.type.displayName).sorted()
            parts.append("Recorded \(names.joined(separator: ", "))")
        }
        if !result.unknownKeys.isEmpty {
            parts.append("didn't recognise \(result.unknownKeys.joined(separator: ", "))")
        }
        if !result.rejectedKeys.isEmpty {
            parts.append("couldn't read a sensible value for "
                         + result.rejectedKeys.joined(separator: ", "))
        }
        return parts.joined(separator: " — ") + "."
    }

    /// True while a shared file is being read, so the UI can say so.
    private(set) var isImporting = false

    func logDose(_ milligrams: Double, at date: Date = Date(), site: String? = nil) {
        dataStore.logDose(milligrams, at: date, site: site)
        recompute()
    }

    /// Injection sites already in the record, so a hand-logged dose reuses the
    /// vocabulary an import brought in rather than inventing a parallel one.
    ///
    /// Shotsy's own site names are free text and this app has no way to know
    /// them in advance; offering "Stomach — upper left" beside an imported
    /// "Stomach Upper Left" would split one site into two rows in the response
    /// table and neither would be wrong. The standard six are the fallback for
    /// a reader who has imported nothing.
    var knownInjectionSites: [String] {
        let used = Set((activeMedication?.doses ?? []).compactMap(\.injectionSite))
        guard used.isEmpty else { return used.sorted() }
        return ["Stomach Upper Left", "Stomach Upper Mid", "Stomach Upper Right",
                "Stomach Lower Left", "Stomach Lower Mid", "Stomach Lower Right",
                "Left Thigh", "Right Thigh", "Left Arm", "Right Arm"]
    }

    func confirmInferredDoses() {
        dataStore.confirmInferredDoses()
        recompute()
    }

    func discardInferredDoses() {
        dataStore.discardInferredDoses()
        recompute()
    }

    func startMedication(compound: GLPCompound, brandName: String?,
                         currentDose: Double, startedOn: Date) {
        let inferred = TitrationEngine.inferHistory(
            currentDose: currentDose, compound: compound, startedOn: startedOn)
        dataStore.startMedication(compound: compound, brandName: brandName,
                                  startedOn: startedOn, inferredDoses: inferred)
        recompute()
    }

    /// Decaying daily cardiovascular load from the substance log.
    ///
    /// Cached for the same reason the overlay is: a detail view re-evaluates its
    /// body on every pan frame, and this walks the whole log once per day of
    /// history. Invalidated by `substanceEvents` above rather than by
    /// `invalidateDerivedCaches()` — it is a function of the log, not of samples.
    @ObservationIgnored private var substanceLoadCache: [SubstanceLoadPoint]?

    @ObservationIgnored private var substanceWindowCache: [SubstanceWindow]?

    /// The after-windows shaded behind **every** chart in the app.
    ///
    /// **Ungated since 2026-08-03, at the user's instruction.** It used to be
    /// empty for any metric `SubstanceResponseAnalyzer` does not compare — the
    /// reasoning being that a shaded stretch behind a weight chart would assert
    /// a relationship nothing had looked for. The rule that replaces it is
    /// narrower: the shading marks *when something was logged*, which is a fact
    /// about the timeline and true on every chart, and the caption says it
    /// claims nothing about the metric underneath. See `SubstanceShading`.
    var allSubstanceWindows: [SubstanceWindow] {
        if let substanceWindowCache { return substanceWindowCache }
        let built = SubstanceResponseAnalyzer.affectedWindows(events: substanceEvents)
        substanceWindowCache = built
        return built
    }

    /// The load series the Substance Impact detail screen charts.
    func substanceLoadSeries(days: Int = 90) -> [SubstanceLoadPoint] {
        if let substanceLoadCache { return substanceLoadCache }
        let built = SubstanceLoad.series(events: substanceEvents, days: days)
        substanceLoadCache = built
        return built
    }

    /// Today's energy curve, for the chart on the Energy detail screen.
    ///
    /// Cached like the others: a detail view re-evaluates its body on every
    /// scrub frame, and this walks the day's heart-rate samples once per hour of
    /// elapsed day. Invalidated with `samples`, which is what it reads.
    @ObservationIgnored private var energyCache: EnergyModel.Output?

    func energyToday() -> EnergyModel.Output? {
        if let energyCache { return energyCache }
        let built = EnergyModel.evaluate(samples: samples)
        energyCache = built
        return built
    }

    /// The fortnight of bedtimes the Sleep Regularity detail screen charts.
    ///
    /// Cached for the same reason as the two above: a detail view re-evaluates
    /// its body on every redraw, and this walks the whole sample set to pick out
    /// one metric. Invalidated with `samples`, which is what it reads.
    @ObservationIgnored private var circadianCache: CircadianConsistencyModel.Output?

    /// Every bedtime read, over a long window, for the strip that re-fits per
    /// visible range. Cached alongside the fortnight's fit because it is the
    /// expensive half — a filter and a daily bucket over the whole sample set —
    /// and the chart asks for it on every scroll.
    func sleepOnsetNights(days: Int = 365) -> [VitalReader.DailyValue] {
        if let sleepNightsCache, sleepNightsCache.days == days {
            return sleepNightsCache.nights
        }
        let built = CircadianConsistencyModel.nights(from: samples, days: days)
        sleepNightsCache = (days, built)
        return built
    }

    @ObservationIgnored
    private var sleepNightsCache: (days: Int, nights: [VitalReader.DailyValue])?

    func sleepRegularity() -> CircadianConsistencyModel.Output? {
        if let circadianCache { return circadianCache }
        let built = CircadianConsistencyModel.evaluate(samples: samples)
        circadianCache = built
        return built
    }

    /// The sleep-onset deep-dive: how long you take to fall asleep, whether that
    /// is drifting, and which of the four things the app can see moves it.
    ///
    /// Assembles the latency series and the driver series it holds against it —
    /// substances logged that evening, the medication curve, skin temperature
    /// deviation (the too-hot/too-cold question), and the day's active energy —
    /// and hands them to the tested `SleepOnsetModel`. Cached as a double
    /// optional: the outer `nil` means "not computed", the inner means "computed,
    /// and there isn't enough to say" — so a card without enough nights doesn't
    /// rebuild the analysis on every redraw.
    func sleepOnsetAnalysis() -> SleepOnsetModel.Output? {
        if let cached = sleepOnsetCache { return cached }
        let cal = Calendar.current

        let latency = samples.samples(of: .sleepLatencyMinutes)
            .map { SleepOnsetModel.Sample(date: $0.start, value: $0.value) }
        guard !latency.isEmpty else { sleepOnsetCache = .some(nil); return nil }

        let substances = substanceLoadSeries()
            .map { SleepOnsetModel.Sample(date: $0.date, value: $0.load) }
        let medication = medicationCurve()
            .map { SleepOnsetModel.Sample(date: $0.date, value: $0.level) }
        let temperature = samples.samples(of: .skinTemperatureDeviation)
            .map { SleepOnsetModel.Sample(date: $0.start, value: $0.value) }
        // Active energy is cumulative, so the day's total is its sum — the same
        // reading the Data tab shows for it.
        var energyByDay: [Date: Double] = [:]
        for s in samples.samples(of: .activeEnergyBurned) {
            energyByDay[cal.startOfDay(for: s.start), default: 0] += s.value
        }
        let exertion = energyByDay.map { SleepOnsetModel.Sample(date: $0.key, value: $0.value) }

        var factors: [(SleepOnsetModel.Factor, [SleepOnsetModel.Sample])] = []
        if !substances.isEmpty { factors.append((.substances, substances)) }
        if !medication.isEmpty { factors.append((.medication, medication)) }
        if !temperature.isEmpty { factors.append((.temperature, temperature)) }
        if !exertion.isEmpty { factors.append((.eveningExertion, exertion)) }
        // "Is it tech time?" — only once the reader has been entering it, which
        // is why `unseenFactors` keeps naming it until then.
        let screen = samples.samples(of: .screenTimeMinutes)
            .map { SleepOnsetModel.Sample(date: $0.start, value: $0.value) }
        if !screen.isEmpty { factors.append((.screenTime, screen)) }

        let out = SleepOnsetModel.analyse(latency: latency, factors: factors, calendar: cal)
        sleepOnsetCache = .some(out)
        return out
    }

    @ObservationIgnored private var sleepOnsetCache: SleepOnsetModel.Output??

    /// "Improve your health", recomputed with the results and cached.
    ///
    /// Cached because it re-runs `VO2Trajectory` and the whole vitals scan, and
    /// the Insights list asks for it on every redraw.
    @ObservationIgnored private var suggestionCache: [Suggestion]?

    var suggestions: [Suggestion] {
        if let suggestionCache { return suggestionCache }
        let built = SuggestionEngine.suggestions(results: results, samples: samples,
                                                 profile: profile,
                                                 substanceEvents: substanceEvents,
                                                 usedInputs: usedInputs,
                                                 // `max` rather than `.first`:
                                                 // the reminder is wrong in the
                                                 // direction that nags if the
                                                 // ordering ever changes, and a
                                                 // scan can be entered for a
                                                 // date after the newest row.
                                                 lastBodyScan: bodyScans.map(\.capturedAt).max(),
                                                 // P32 — the queue of flagged
                                                 // moments nobody has answered.
                                                 pendingEventCount: EventFeedModel.shared.pendingCount,
                                                 // Q6 — the reader's own
                                                 // condition on this feature was
                                                 // a dismissible front-page row
                                                 // while the permission is
                                                 // absent. This is what feeds it.
                                                 locationAccess: EventFeedModel.shared.access)
        suggestionCache = built
        return built
    }

    /// Which way each card's score has been going.
    ///
    /// Read from the *stored* daily score rows rather than from the replayed
    /// histories in `scoreHistories`: a replay walks the whole sample set per
    /// day of history and is filled lazily per insight in the background, which
    /// is right for a chart and far too slow for a chip that has to be on every
    /// card the moment the list draws. The stored rows are one small fetch each,
    /// and `recompute()` has already written today's before this is read.
    ///
    /// Built for every insight at once and cached, because the alternative is a
    /// fetch per card per redraw.
    /// ⚠️ **The state, not the change.** This used to cache `ScoreChange` and
    /// drop everything else on the floor, so *never scored*, *not scored today*
    /// and *not scored enough* all arrived at `InsightCard` as one `nil` — which
    /// it rendered as an empty space, because there was nothing left to render.
    /// Backlog B15-2. The reason now survives the cache.
    @ObservationIgnored private var scoreChangeCache: [InsightID: ScoreChangeState]?

    /// Which way a card's score has gone, **or why that cannot be said**.
    ///
    /// `nil` only for a card with no score at all, whose absence is already
    /// explained by its own empty state — a "Learning trends" chip beside "Tap
    /// to add the details needed" would be a second answer to a question the
    /// card has already answered.
    func scoreChangeState(for id: InsightID) -> ScoreChangeState? {
        if scoreChangeCache == nil {
            var built: [InsightID: ScoreChangeState] = [:]
            for result in results where result.score != nil {
                built[result.id] = ScoreChangeReader.state(
                    for: result.id, history: dataStore.scoreHistory(for: result.id))
            }
            scoreChangeCache = built
        }
        return scoreChangeCache?[id]
    }

    func scoreChange(for id: InsightID) -> ScoreChange? {
        scoreChangeState(for: id)?.change
    }

    /// Dismissals, loaded once and kept in memory. Small by construction — there
    /// can never be more of them than there are suggestions.
    private(set) var suggestionDismissals: [SuggestionDismissal] = []

    /// What each surface may show, after dismissals.
    ///
    /// Recomputed rather than cached: it depends on `now` (a dismissal expires),
    /// and it is a filter over a list that is already capped at five.
    var suggestionVisibility: SuggestionVisibility.Resolved {
        SuggestionVisibility.resolve(suggestions: suggestions,
                                     dismissals: suggestionDismissals)
    }

    func dismissSuggestion(id: String) {
        dataStore.dismissSuggestion(id: id)
        suggestionDismissals = dataStore.loadSuggestionDismissals()
    }

    func restoreSuggestion(id: String) {
        dataStore.undismissSuggestions(ids: [id])
        suggestionDismissals = dataStore.loadSuggestionDismissals()
    }

    /// Delete dismissals for suggestions the engine has stopped making.
    ///
    /// This is the whole of "hide it once the associated tasks are completed".
    /// The engine only emits a suggestion while its condition holds, so a
    /// grounding fact being entered, a signal returning to baseline and an
    /// observation ceasing to be true are indistinguishable from here — the id
    /// simply stops appearing, and the row it left behind is dead.
    ///
    /// Called from the Insights list rather than from `recompute()`, because
    /// `suggestions` is lazy and forcing it on every recompute would run the
    /// whole vitals scan on launch for a screen the user may not open.
    func pruneResolvedSuggestions() {
        let dead = suggestionVisibility.resolvedDismissals
        guard !dead.isEmpty else { return }
        dataStore.undismissSuggestions(ids: dead)
        suggestionDismissals = dataStore.loadSuggestionDismissals()
    }
    private(set) var profile: UserHealthProfile
    private(set) var results: [InsightResult] = []
    private(set) var todaySummary: String = ""
    private(set) var isSyncing = false

    /// Which part of the refresh is running, for the launch screen to narrate.
    ///
    /// `isSyncing` is one flag over two waits that feel nothing alike — the
    /// provider round-trip and the on-device summariser — and the launch copy
    /// exists to tell them apart. Kept up to date on every refresh, not just the
    /// first, because it costs an assignment and a future caller may want it.
    private(set) var launchPhase: LaunchPhase = .connecting

    /// Whether the cache has been read and the insights evaluated — i.e. whether
    /// there is a real Today to show.
    ///
    /// This, not "the refresh finished", is what the launch screen waits for.
    /// The first version waited for the whole of `refresh()`, which put the
    /// network round-trip and the on-device summary *in front of* the app
    /// instead of behind it and turned an eight-second launch into a
    /// thirty-second one.
    private(set) var isHydrated = false

    /// Whether the launch screen is on screen.
    ///
    /// Set once, here, and only ever cleared — `RootView.task` runs again when
    /// the app returns to the foreground, and a splash over a warm app would be
    /// a worse bug than the blank white screen this replaces. False from the
    /// start for a first run, where onboarding owns the window instead.
    private(set) var isLaunching = false

    /// Called by the launch screen once it has both a finished refresh and its
    /// minimum time on screen. See `LaunchNarration.shouldDismiss`.
    func finishLaunch() { isLaunching = false }

    /// When the last refresh actually completed. Shown on the Today card, which
    /// is what keeps a floored pull-to-refresh from reading as a broken one.
    private(set) var lastRefreshedAt: Date?

    /// What the stored summary was written from. Compared against the current
    /// results so an app open that changed nothing skips the model round-trip.
    @ObservationIgnored private var summaryFingerprint: SummaryFingerprint?

    /// Regenerate the Today summary only when the results behind it have moved.
    ///
    /// `RootView` refreshes on every appearance, so this used to run a full
    /// on-device model pass each time the app came to the foreground, whether or
    /// not anything had changed.
    private func refreshSummaryIfChanged(now: Date, diag: DiagnosticsLog) async {
        let fingerprint = SummaryFingerprint.of(results: results, now: now)
        if fingerprint == summaryFingerprint, !todaySummary.isEmpty {
            diag.info("Summary", "Unchanged since the last pass — reused")
            return
        }
        todaySummary = await summarizer.summarize(results: results)
        summaryFingerprint = fingerprint
        dataStore.saveSummary(todaySummary, fingerprint: fingerprint)
    }
    /// Observable copy of each integration's status so the UI updates live when a
    /// provider connects, fails or syncs (the providers themselves aren't tracked
    /// by @Observable). Keyed by integration id.
    private(set) var integrationStatuses: [String: IntegrationStatus] = [:]
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    init(dataStore: DataStore,
         healthService: HealthKitService,
         registry: IntegrationRegistry,
         engine: InsightEngine = InsightEngine(),
         summarizer: FoundationModelSummarizer) {
        self.dataStore = dataStore
        self.healthService = healthService
        self.registry = registry
        self.engine = engine
        self.summarizer = summarizer
        self.profile = dataStore.loadProfile()
        // Beside the profile, and for the same reason: one small file read,
        // and the classifier needs it before the first calendar sync.
        self.readerIdentity = dataStore.loadReaderIdentity()
        seedIntegrationStatuses()
        // Small SwiftData reads only. `hydrate()` does the rest, off the main
        // actor and after the first frame — see the note on it.
        substanceEvents = dataStore.loadSubstanceEvents()
        supplementEntries = dataStore.loadSupplementEntries()
        reloadLoggedData()
        suggestionDismissals = dataStore.loadSuggestionDismissals()
        // Decided here rather than in the view so there is no first frame where
        // the answer is still unknown — a `@State` default cannot read the
        // environment, and one blank frame is the thing being fixed.
        isLaunching = hasCompletedOnboarding
    }

    /// Populate state from persisted data — manual readings plus the last-synced
    /// Apple Health / wearable samples cached to disk — so the app shows your
    /// data before (or without) a fresh network sync.
    ///
    /// **This used to run inside `init`, and that was the blank white screen.**
    /// `HealthInsightsApp` builds the model as a `@State` default, so every line
    /// of it ran before SwiftUI could draw a single frame: a JSON decode of a
    /// six-figure sample array, a full sanitiser pass, the temperature
    /// reconstruction and then all seventeen insights. On a real history that is
    /// several seconds during which the app is not white *by choice* — it simply
    /// has not reached its first frame, and no launch screen written in SwiftUI
    /// can appear in front of it. (What covers that gap now is the static
    /// `UILaunchScreen` in `Support/Info.plist`, which needs no code at all.)
    ///
    /// Now it is `async`, called from `RootView` after the first frame, and the
    /// expensive half runs off the main actor. What is left on the main actor is
    /// only what cannot leave it: SwiftData reads, which are small.
    func hydrate() async {
        guard !isHydrated else { return }
        launchPhase = .reading

        // ⚠️ **Before `otherSamples` is assigned, not after.** Its `didSet`
        // promotes the tags, and promotion consults `tagMappings` — so loading
        // the store later would classify the reader's whole tag history with the
        // model's and their own answers missing, then quietly leave it that way
        // until the next sync.
        loadTagMappings()

        // Main actor, because SwiftData's `mainContext` is. Both are small.
        let manual = dataStore.loadManualSamples()
        let store = dataStore
        let engineNow = engine.withSubstanceLog(substanceEvents)
            .withSupplements(supplementEntries)
            .withCalendar(events: calendarEvents, judgements: calendarJudgements)
        let profileNow = profile
        // The schedule is read here — a `Sendable` value, never the `@Model`
        // record — because the symptoms it is bound beside only exist once the
        // detached task has loaded the raw catalogue.
        let schedule = dataStore.loadActiveMedication()?.schedule

        // Off the main actor: the JSON decode, the sanitiser, the temperature
        // reconstruction and the whole insight pass. Every input is `Sendable`
        // and every one of these is pure, which is why this hop is safe — the
        // engine and the sample types were built platform-free for testing, and
        // that turns out to be the same property that lets them leave the main
        // thread.
        let loaded = await Task.detached(priority: .userInitiated) { () -> HydratedState in
            let cached = store.loadCachedSamples()
            let other = store.loadCachedOther()
            let merged = (manual + cached).sanitizedVitals()
            // Two derivations on the ingest path, same shape: raw or partial
            // provider data in, canonical calculated samples out, both
            // idempotent. The sound doses read the raw audio-exposure pile
            // (`other`) because their inputs were never canonical metrics —
            // dBA levels cannot be averaged, so only the derived daily LEQ
            // earns a `MetricType` (see `SoundDoseModel`).
            let samples = SoundDoseModel.withSoundDose(
                TemperatureReconstructor.withReconstructedTemperature(merged),
                raw: other)
            let events = VitalEventReader.events(from: other)
            // The radar is bound to the tags promoted from the catalogue this
            // task just loaded — binding `engineNow` on the main actor would
            // have raced the load it depends on.
            let engineBound = engineNow.withSymptoms(
                SymptomPromotion.events(from: other), medication: schedule)
            let results = engineBound.evaluateAll(samples: samples, events: events,
                                                  profile: profileNow)
            return HydratedState(samples: samples, other: other, results: results,
                                 engine: engineBound)
        }.value

        otherSamples = loaded.other
        samples = loaded.samples
        engine = loaded.engine
        results = loaded.results
        // Today's derived figures, from the evaluation that just ran. The
        // launch path evaluates here rather than through `refreshInsights`, so
        // recording only there left the store empty until the first refresh —
        // measured on the simulator: the Data tab's Generated-insights row was
        // absent on a cold launch with 237k samples loaded.
        for result in loaded.results {
            derivedSeries.record(result, on: Date())
        }
        DiagnosticsLog.shared.info(
            "Derived",
            "\(derivedSeries.seriesIDs.count) series, \(derivedSeries.pointCount) points recorded from \(loaded.results.count) results")

        // After the samples are in, so the first-run seed sees the whole
        // catalogue rather than an empty one and announces nothing.
        loadSightingLedger()
        seedSightingLedgerIfNeeded()

        // A stored summary written from *these* results is the real thing and is
        // worth showing immediately. Only fall back to the template when there
        // isn't one, or when the results have moved since it was written — the
        // refresh that follows will replace it either way.
        if let stored = dataStore.loadSummary(),
           stored.fingerprint == SummaryFingerprint.of(results: results, now: Date()) {
            todaySummary = stored.text
            summaryFingerprint = stored.fingerprint
        } else {
            todaySummary = FoundationModelSummarizer.templateSummary(from: results)
        }

        recordScores(results)
        invalidateDerivedCaches()
        // The launch screen waits on this and nothing else. Everything after it
        // — the provider sync, the ingest, the on-device summary — belongs
        // behind an app the user can already see and use.
        isHydrated = true
    }

    /// What `hydrate()` computes off the main actor, in one `Sendable` parcel.
    private struct HydratedState: Sendable {
        let samples: [HealthMetricSample]
        let other: [RawMetricSample]
        let results: [InsightResult]
        /// The registry the results were evaluated by — carried back so score
        /// replay iterates the same bound models that produced them.
        let engine: InsightEngine
    }

    /// Unmodelled imported data, grouped by identifier for the "Other data" browser.
    /// Grouped "other data", cached — the Vitals list reads this on every redraw
    /// and regrouping the whole raw import each time was needless work.
    var otherDataGroups: [RawMetricGroup] {
        if let cached = otherGroupCache { return cached }
        let built = otherSamples.groupedByIdentifier()
        otherGroupCache = built
        return built
    }

    /// On launch, reflect each provider's status — and if a previous connection
    /// attempt failed, restore that error message so the user sees "there was an
    /// issue" instead of a silent "tap to set up".
    private func seedIntegrationStatuses() {
        for integration in registry.integrations {
            if case .notConnected = integration.status,
               let lastError = UserDefaults.standard.string(forKey: "lastError.\(integration.id)") {
                integrationStatuses[integration.id] = .error(lastError)
            } else {
                integrationStatuses[integration.id] = integration.status
            }
        }
    }

    /// The one production model, so anything outside the SwiftUI tree reaches
    /// the same store the screens do.
    ///
    /// **This is not a convenience.** An `AppIntent` invoked from Shortcuts runs
    /// outside the view hierarchy and has no environment to read, so it needs a
    /// way to the model — and building a second `AppModel` would build a second
    /// `DataStore` over the same file. Two writers, no coordination, and a
    /// reading logged by Shortcuts would be invisible to the screens until a
    /// relaunch.
    ///
    /// `@MainActor` makes the lazy initialisation safe without a lock: every
    /// access is already on the main actor, which is also where `DataStore` and
    /// every `@Observable` mutation here have to happen anyway.
    static let shared = makeDefault()

    /// Convenience factory building the default production graph.
    static func makeDefault() -> AppModel {
        let dataStore = DataStore()
        let healthService = HealthKitService()
        let apple = AppleHealthProvider(service: healthService)
        // Oura/Withings authenticate on-device using credentials the user enters
        // in the app's setup screen (stored in the Keychain) — no backend.
        let credentials = ProviderCredentialStore()
        let webFlow = OAuthWebFlow()
        let registry = IntegrationRegistry(integrations: [
            apple,
            OuraProvider(credentials: credentials, webFlow: webFlow),
            WhoopProvider(credentials: credentials, webFlow: webFlow),
            // File-based rather than API-based, and listed here anyway: from
            // the reader's side "where does my data come from" has one answer
            // and this is where it lives. See `ShotsyIntegration`.
            ShotsyIntegration(),
            // The reader's own automation, collecting what iOS won't hand an
            // app directly. See `ShortcutsIntegration`.
            ShortcutsIntegration(),
            // On-device permission rather than OAuth, and listed here for the
            // same reason Shotsy is: "where does my data come from" has one
            // answer. It is the only blocker on two requested cards — travel
            // drain and work impact. See `CalendarIntegration`.
            CalendarIntegration(),
            WithingsProvider(credentials: credentials, webFlow: webFlow)
        ])
        return AppModel(dataStore: dataStore, healthService: healthService,
                        registry: registry, summarizer: FoundationModelSummarizer())
    }

    // MARK: - Grounding

    func saveGrounding(kind: GroundingKind, value: Double) {
        dataStore.saveGrounding(kind: kind, value: value)
        profile = dataStore.loadProfile()
        recompute()
    }

    /// Log a dated cuff blood-pressure reading, then re-sync so it appears in
    /// the log, trends and calibration immediately.
    func logBloodPressure(systolic: Double, diastolic: Double, at date: Date) {
        // Before saving the new truth, grade the previous estimate against it —
        // this is the "predicted X, actual Y" signal for model improvement.
        captureBloodPressureOutcome(actualSystolic: systolic, actualDiastolic: diastolic)
        dataStore.saveBloodPressureReading(systolic: systolic, diastolic: diastolic, at: date)
        // Reflect the new reading immediately so the log re-renders on first save
        // (previously it only appeared after the *next* async refresh completed).
        samples.append(HealthMetricSample(type: .bloodPressureSystolic, value: systolic,
                                          start: date, source: .manual))
        samples.append(HealthMetricSample(type: .bloodPressureDiastolic, value: diastolic,
                                          start: date, source: .manual))
        // Forced: a reading was just logged, so waiting out the manual floor
        // would leave the card showing the state before it.
        Task { await refresh(force: true) }
    }

    private func captureBloodPressureOutcome(actualSystolic: Double, actualDiastolic: Double) {
        guard let restHR = samples.meanValue(.restingHeartRate) else { return }
        let calibration = BloodPressureEstimator.buildCalibration(from: samples)
        guard let est = BloodPressureEstimator.estimate(currentRestingHR: restHR, calibration: calibration) else { return }
        let cohort = Cohort.from(profile: profile)
        let version = InsightID.bloodPressure.modelVersion
        dataStore.addPredictionOutcome(.init(insightID: .bloodPressure, metric: .bloodPressureSystolic,
            predicted: est.systolic, actual: actualSystolic, modelVersion: version, cohort: cohort))
        dataStore.addPredictionOutcome(.init(insightID: .bloodPressure, metric: .bloodPressureDiastolic,
            predicted: est.diastolic, actual: actualDiastolic, modelVersion: version, cohort: cohort))
    }

    // MARK: - Feedback, corrections & model improvement (transmit-disabled)

    /// Whether the user has opted in to sharing anonymised model-error metrics.
    /// Off by default. Transmission is not implemented yet regardless — this only
    /// governs whether the outbox would be eligible to send in future.
    ///
    /// **This is the older, narrower toggle** and it stays: it governs the
    /// cohort-and-DP-noise `TelemetryEvent` stream, which answers *"is the model
    /// getting better?"* and carries no values at all. `sharingPreferences`
    /// below governs a differently shaped thing — the reader's own corrections
    /// with the artifact behind them. Widening one to cover both is what
    /// `docs/norms-and-telemetry.md` says not to do.
    var telemetryOptIn: Bool {
        get { UserDefaults.standard.bool(forKey: "telemetryOptIn") }
        set { UserDefaults.standard.set(newValue, forKey: "telemetryOptIn") }
    }

    /// **Two-tier sharing of corrections, both tiers on by default** — backlog
    /// B8 R5, at the reader's explicit instruction (*"both opted in by
    /// default"*).
    ///
    /// ⚠️ `UserDefaults.bool(forKey:)` answers `false` for a key nobody has
    /// written, so reading it directly would default both tiers **off** and look
    /// exactly like a reader who had turned them off — an error that never
    /// complains. `object(forKey:)` is checked first for precisely that reason.
    ///
    /// ⚠️ **Nothing is transmitted in this build.** There is no endpoint, no
    /// upload and no networking behind this preference; it decides the *shape*
    /// of what would go, and the Settings screen shows that shape.
    var sharingPreferences: SharingPreferences {
        get {
            let defaults = UserDefaults.standard
            func flag(_ key: String) -> Bool {
                defaults.object(forKey: key) as? Bool ?? true
            }
            return SharingPreferences(
                isFullEnabled: flag(Self.sharingFullKey),
                isMetadataOnlyEnabled: flag(Self.sharingMetadataKey))
        }
        set {
            UserDefaults.standard.set(newValue.isFullEnabled, forKey: Self.sharingFullKey)
            UserDefaults.standard.set(newValue.isMetadataOnlyEnabled,
                                      forKey: Self.sharingMetadataKey)
        }
    }

    private static let sharingFullKey = "sharing.tier.full"
    private static let sharingMetadataKey = "sharing.tier.metadataOnly"

    /// Every correction the reader has actually made, shaped by whichever tier
    /// is in force — the exact payload that would leave the phone if a network
    /// step existed.
    ///
    /// Nil tier means both switched off, and the empty array is the refusal
    /// rather than an absence of corrections.
    func correctionOutbox() -> [SharedRecord] {
        guard let tier = sharingPreferences.effectiveTier else { return [] }
        var records = calendarJudgements.compactMap { $0.sharedRecord(under: tier) }
        records.append(contentsOf: dataStore.loadPredictionOutcomes()
            .compactMap { $0.sharedRecord(under: tier) })
        return records
    }

    /// Record a discreet "was this accurate?" tap for an insight.
    func recordFeedback(_ insightID: InsightID, accurate: Bool) {
        dataStore.addFeedback(insightID: insightID, rating: accurate ? .accurate : .inaccurate,
                              cohort: Cohort.from(profile: profile))
    }

    /// Exactly what *would* be sent if sharing were enabled — coarse cohort,
    /// model version, and a DP-noised rounded error or a rating. Nothing is
    /// transmitted; this is a local, inspectable preview.
    func telemetryOutbox() -> [TelemetryEvent] {
        var events: [TelemetryEvent] = []
        for outcome in dataStore.loadPredictionOutcomes() {
            events.append(Telemetry.event(from: outcome, u: Telemetry.stableUniform(outcome.id)))
        }
        for f in dataStore.loadFeedback() {
            events.append(Telemetry.event(insightID: f.insight, cohort: f.cohort,
                                          modelVersion: f.modelVersion, rating: f.rating, at: f.at))
        }
        return events
    }

    /// Memoise a pure render-time computation against the current sample set.
    ///
    /// The key names the call site (plus anything the result varies by, e.g.
    /// the insight id); the cache clears with every other derived cache when
    /// the samples change, so a hit can never be stale data — only a saved
    /// re-run. A failed cast falls through to recompute, so the worst case is
    /// the old behaviour. A `nil` result is never cached — see `RenderMemo`.
    ///
    /// ## ⚠️ Why this is three lines and not `renderMemo.value(key, compute)`
    ///
    /// **Backlog `D58`: that one line crashed the app with `SIGABRT`,** and the
    /// crash report said nothing about why — no exception, no subtype, no `asi`
    /// payload, just `swift_beginAccess → swift::fatalError → abort` above
    /// `AppModel.memoized`.
    ///
    /// `RenderMemo.value` is `mutating`, so `renderMemo.value(key, compute)`
    /// holds an exclusive access to the `renderMemo` **property** for the entire
    /// duration of `compute()`. Any `compute` that memoises something itself
    /// asks for a second access to the same property while the first is open,
    /// and Swift's exclusivity enforcement traps rather than corrupting the
    /// dictionary.
    ///
    /// It was not hypothetical and it was not rare. `SettlingSection` memoises
    /// `"overnightCardiac"`, and `OvernightCardiacReading.build` memoises
    /// `"nightSleepAllNights"` — so **every render of that section aborted the
    /// process.** Two crash reports an hour and forty minutes apart, from
    /// different builds, carry the identical stack.
    ///
    /// The fix is to hold no access across the compute: a **read** that ends at
    /// the lookup, the compute with nothing held, then a **short** write. A
    /// re-entrant call for the same key now computes twice and stores twice,
    /// which is a wasted pass rather than a dead process.
    ///
    /// **The rule for anything else that caches behind a stored property: never
    /// run a caller's closure inside a `mutating` method of it.**
    func memoized<T>(_ key: String, _ compute: () -> T) -> T {
        if let hit: T = renderMemo.cached(key) { return hit }
        let value = compute()
        renderMemo.store(key, value)
        return value
    }

    /// A source-split breakdown of a metric across all connected devices, cached
    /// until the sample set changes.
    func breakdown(_ metric: MetricType) -> MultiSourceBreakdown {
        if let cached = breakdownCache[metric] { return cached }
        let built = MultiSource.breakdown(metric, from: samples)
        breakdownCache[metric] = built
        return built
    }

    /// A breakdown restricted to a timeframe, so "what each source says" and the
    /// per-source averages reflect only the selected window — a source with no
    /// data in that window is dropped rather than shown with a stale latest value.
    func breakdown(_ metric: MetricType, within timeframe: Timeframe) -> MultiSourceBreakdown {
        guard let start = timeframe.startDate() else { return breakdown(metric) }
        return breakdown(metric, in: start...Date.distantFuture)
    }

    /// A breakdown restricted to an explicit window — used by the metric detail
    /// screen so the read-outs describe the span the chart is actually showing
    /// after a pan, rather than a window anchored to now.
    ///
    /// Narrows the cached per-metric breakdown instead of re-scanning every
    /// sample, which matters because panning changes the range continuously.
    func breakdown(_ metric: MetricType, in range: ClosedRange<Date>) -> MultiSourceBreakdown {
        breakdown(metric).restricted(to: range)
    }

    /// Latest value and source count for every metric that has data, built in one
    /// pass and cached. The Vitals list needs this for each row; asking for a
    /// full breakdown per row was the main reason that screen crawled.
    var vitalsSummaries: [MetricType: VitalsSummary] {
        if let cached = vitalsSummaryCache { return cached }
        var latest: [MetricType: HealthMetricSample] = [:]
        var families: [MetricType: Set<String>] = [:]
        // Newest day's running total for cumulative metrics, tracked in the
        // same pass — the day it belongs to, and the sum of that day's samples.
        var dayTotals: [MetricType: (day: Date, perSource: [String: Double])] = [:]
        let calendar = Calendar.current
        for sample in samples {
            if let current = latest[sample.type] {
                if sample.start > current.start { latest[sample.type] = sample }
            } else {
                latest[sample.type] = sample
            }
            families[sample.type, default: []].insert(sample.source.deviceFamily)
            // Newest day's total **per source**, never across sources. Two
            // phones and a ring all count the same walk, and one device's
            // direct feed plus its Apple Health mirror count it twice over
            // again — so this row read a multiple of the steps actually taken.
            // The winner is picked below, once every source's own total is in.
            if sample.type.bucketStatistic == .sum {
                let day = calendar.startOfDay(for: sample.start)
                let known = dayTotals[sample.type]?.day
                if known == nil || day > known! {
                    dayTotals[sample.type] = (day, [sample.source.id: sample.value])
                } else if day == known! {
                    dayTotals[sample.type]?.perSource[sample.source.id, default: 0] += sample.value
                }
            }
        }
        let built = latest.mapValues { sample in
            let total = dayTotals[sample.type]
            return VitalsSummary(latest: sample,
                                 sourceCount: families[sample.type]?.count ?? 1,
                                 displayValue: total?.perSource.values.max() ?? sample.value,
                                 displayDate: total?.day ?? sample.start)
        }
        vitalsSummaryCache = built
        return built
    }

    /// Every paired blood-pressure reading across all sources (logged in-app,
    /// already in Apple Health, or synced from Withings), newest first.
    ///
    /// Cached like the breakdowns: pairing is O(systolic × diastolic), and the
    /// blood-pressure screen reads this several times per redraw.
    var bloodPressureReadings: [BloodPressureEstimator.Reading] {
        if let cached = bloodPressureCache { return cached }
        let built = BloodPressureEstimator.pairedReadings(from: samples)
        bloodPressureCache = built
        return built
    }

    /// Where the user is in the BP calibration journey (5 to start, ~2/month).
    var bloodPressureCalibration: BloodPressureEstimator.CalibrationStatus {
        BloodPressureEstimator.calibrationStatus(from: samples)
    }

    // `outstandingGrounding` was here, and went with the Today banner that was
    // its only reader — the same gaps reach the screen as `.unlockAnInsight`
    // suggestions. `InsightEngine.outstandingGrounding` itself stays: it is the
    // union across models, it is tested, and it is what `unlocks` is derived
    // from one step removed.

    // MARK: - Sync

    /// Refresh all data: fetch from connected integrations + local samples, then
    /// recompute insights and the summary.
    /// - Parameter force: bypass the manual-refresh floor. Used by the paths that
    ///   *know* something changed — logging a substance, saving a grounding value
    ///   — where waiting thirty seconds would be nonsense.
    /// Discard every cached provider sample and re-sync from scratch.
    ///
    /// Pull-to-refresh cannot do this, and the reason is the cache-merge in
    /// `refresh`: a source that returns nothing keeps its cached samples, so a
    /// provider that quietly fails to sync serves the same stale values forever.
    /// That behaviour is right — it stops a disconnected ring wiping its own
    /// history from the app — but it means "refresh" and "replace" are different
    /// requests, and only the first had a gesture.
    ///
    /// It is also the only way to be *certain* a parser fix has taken effect. A
    /// fix changes what the raw payload turns into; it cannot change samples
    /// that were parsed months ago and are being merged forward untouched.
    ///
    /// Nothing the user typed is at risk: manual readings, grounding, substance
    /// logs and feedback are SwiftData and are not part of this cache.
    func rebuildFromProviders() async {
        let diag = DiagnosticsLog.shared
        let discarded = dataStore.clearSyncedCaches()
        diag.info("Rebuild",
                  "Discarded \(discarded.samples) cached sample(s) and \(discarded.other) other reading(s)",
                  detail: "Every connected provider will be re-read from its own API and "
                        + "re-parsed by the current build. A provider that fails to respond "
                        + "contributes nothing rather than its previous cached copy, so its "
                        + "signals will be missing until it syncs successfully.")
        // In-memory too, or the insight pass would keep evaluating the samples
        // that were just deleted from disk and the rebuild would look like a
        // no-op until the next launch.
        samples = []
        otherSamples = []
        await refresh(force: true)
        diag.ok("Rebuild", "Rebuilt \(samples.count) sample(s) from \(registry.integrations.filter { if case .connected = $0.status { return true } else { return false } }.count) connected provider(s)")
    }

    /// Coalesces every caller onto one running pipeline.
    ///
    /// `RefreshGate` cannot do this: it compares against `lastRefreshedAt`,
    /// which is set when a refresh *completes* — so a pull-to-refresh three
    /// seconds into the launch sync passed the gate and ran the whole pipeline
    /// concurrently: every provider fetched twice, double ingest, double
    /// insight pass. (Seen in the user's diagnostics on 2026-08-02: two
    /// "Refresh started" three seconds apart, every Oura GET duplicated.)
    /// A second caller means "make sure the data is fresh", so it joins the
    /// refresh already doing that. A forced caller (the rebuild path, which
    /// has just cleared the caches) waits the running one out and then runs
    /// in full.
    func refresh(force: Bool = false) async {
        while let inFlight = refreshTask {
            if !force {
                DiagnosticsLog.shared.info("Sync", "Refresh request joined the one already running")
                await inFlight.value
                return
            }
            await inFlight.value
        }
        let task = Task { await performRefresh(force: force) }
        refreshTask = task
        defer { refreshTask = nil }
        await task.value
    }

    private func performRefresh(force: Bool) async {
        let startedAt = Date()
        // Above the refresh gate on purpose: a refresh skipped as too-soon must
        // still land on `.ready`, so nothing is left narrating a step that is
        // not running. The launch screen no longer *waits* on this — it waits on
        // `isHydrated` — but the phase still drives what the copy says.
        defer { launchPhase = .ready }
        launchPhase = .connecting
        // Three pull-to-refresh gestures in three seconds used to pay for three
        // full syncs and three model round-trips. The gesture isn't ignored
        // silently — `lastRefreshedAt` is on the Today card, so a suppressed pull
        // still shows when the data last moved.
        if !force, case .tooSoon = RefreshGate.decide(lastRefreshAt: lastRefreshedAt,
                                                      now: startedAt) {
            DiagnosticsLog.shared.info("Sync", "Refresh skipped — less than \(Int(RefreshGate.manualFloor))s since the last one")
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        let diag = DiagnosticsLog.shared
        diag.info("Sync", "Refresh started",
                  detail: "Build \(BuildInfo.summary), built \(BuildInfo.formattedDate)")

        // ⚠️ **One number for a dozen phases is not a measurement** — backlog
        // `D57`. "Refresh complete in 15.5s" said nothing about *which* of the
        // steps below was the fifteen seconds, and the row that recorded it
        // guessed at the insight pass. The pass was then measured at ~1 s over
        // the reader's whole record (`InsightPassBenchmarkTests`), so the guess
        // was wrong and the time is in one of the other laps. Every phase is
        // named from here down; see `RefreshPhaseTimer`.
        var timer = RefreshPhaseTimer()

        let manual = dataStore.loadManualSamples()
        timer.lap("manual samples")
        let synced = await registry.syncAllConnected()
        timer.lap("provider sync (network)")
        // The calendar is pulled here rather than inside `syncAllConnected`,
        // because its output is not `SyncedData` — a meeting is not a sample,
        // and pretending otherwise would put events in the vitals layer. See
        // `CalendarIntegration.sync`.
        await syncCalendar()
        timer.lap("calendar sync")
        for integration in registry.integrations {   // reflect fresh sync status
            integrationStatuses[integration.id] = integration.status
            switch integration.status {
            case .connected(let last):
                diag.ok(integration.displayName, last == nil ? "Connected" : "Synced")
            case .error(let msg): diag.fail(integration.displayName, msg)
            case .unavailable(let reason): diag.null(integration.displayName, reason)
            default: break
            }
        }
        // Ingest every captured payload before anything else looks at the data.
        // This is what guarantees the vitals layer holds 100% of what the
        // providers sent — including fields nobody has written code for — and it
        // has to finish before the cache merge and the insight pass, not after.
        let ingested = ingestPayloads(synced.payloads, diag: diag)
        timer.lap("ingest payloads")

        // Cache-merge: a source that returned data this sync replaces its cached
        // copy; sources that returned nothing (disconnected/offline) keep their
        // last-known cache, so their data never disappears from the app.
        let freshSamples = synced.samples + ingested.promoted
        let cached = dataStore.loadCachedSamples()
        timer.lap("load sample cache")
        let freshSourceIDs = Set(freshSamples.map { $0.source.id })
        let retained = cached.filter { !freshSourceIDs.contains($0.source.id) }
        let nonManual = freshSamples + retained
        dataStore.saveCachedSamples(nonManual)
        timer.lap("save sample cache")
        if !retained.isEmpty {
            diag.info("Cache", "Kept \(retained.count) cached sample(s) from idle sources")
        }

        // Same cache-merge for the raw "other" data.
        let freshOther = synced.other + ingested.raw
        let cachedOther = dataStore.loadCachedOther()
        timer.lap("load raw cache")
        let freshOtherSourceIDs = Set(freshOther.map { $0.source.id })
        let retainedOther = cachedOther.filter { !freshOtherSourceIDs.contains($0.source.id) }
        otherSamples = freshOther + retainedOther
        dataStore.saveCachedOther(otherSamples)
        timer.lap("save raw cache")
        if !freshOther.isEmpty {
            diag.ok("Import", "\(freshOther.count) other data point(s) imported")
        }
        // What genuinely arrived this sync — raw fields and canonical metrics
        // both, and neither from the retained cache.
        observeArrivals(Set(freshOther.map(\.identifier))
                            .union(freshSamples.map { $0.type.rawValue }))
        timer.lap("observe arrivals")

        // Drop placeholder zeros (e.g. an Oura day with no HR → 0 bpm) so they
        // don't render as "0 bpm" tiles or poison multi-source averages/graphs.
        let (merged, dropped) = (manual + nonManual).partitionedVitals()
        timer.lap("sanitiser")
        logSanitiserDrops(dropped, diag: diag)
        // …and record the same verdict against the sightings written above, so
        // an arrival that became nothing says so instead of sitting in "New
        // since you last looked" with no data behind it (D43).
        recordArrivalOutcomes(of: freshSamples)
        // Creative reconstruction: turn wearable skin-temperature *deviations*
        // (Oura/Hume) into absolute *skin*-temperature samples so they can be
        // trended and charted. Deliberately not body temperature: these are skin
        // readings, and labelling them as core is what had Vitals Check judging
        // them against fever and hypothermia bounds.
        //
        // Then the daily sound doses from the raw audio-exposure samples that
        // arrived in `otherSamples` just above — same shape of derivation,
        // same idempotence (both strip-or-replace rather than append), so the
        // ingest path may run any number of times without stacking either.
        samples = SoundDoseModel.withSoundDose(
            TemperatureReconstructor.withReconstructedTemperature(merged),
            raw: otherSamples)
        timer.lap("derived series (temperature, sound dose)")
        logMetricCounts(diag)
        timer.lap("per-metric counts")
        profile = dataStore.loadProfile()
        substanceEvents = dataStore.loadSubstanceEvents()
        supplementEntries = dataStore.loadSupplementEntries()
        timer.lap("profile + substance log + supplements")
        recompute()
        // The summary is written from `results`, so this one caller waits for
        // the pass it just started. The interface is free during the wait —
        // that is the difference from running it inline, and it is the whole
        // fix for the reader's "Syncing your devices" hang.
        await recomputeSettled()
        timer.lap("insight pass (19 models, off the main actor)")
        launchPhase = .summarising
        await refreshSummaryIfChanged(now: startedAt, diag: diag)
        timer.lap("daily summary")
        // **After the sync has otherwise finished, and NOT awaited.** Every tag
        // is already promoted and already carries a deterministic applicability,
        // so this can only improve a heading.
        //
        // ⚠️ **It was `await`ed until 2026-08-07 and that made it the reason the
        // whole refresh never finished.** The reader, from their phone: *"Data
        // no longer showing in the app"* — with a diagnostics log that had
        // `Refresh started` and **no `Refresh complete` at all**, five minutes
        // later, plus a 12.75 s main-thread block.
        //
        // `TagApplicabilityModel.resolve` loops **serially** over up to
        // `perPassLimit` (12) tags, building a fresh `LanguageModelSession` and
        // awaiting a full on-device response for each — deliberately, so one bad
        // answer costs one tag rather than the batch. That is right for the
        // classifier and fatal in front of the completion marker: twelve
        // sequential model round trips, the first including model load, all
        // before `lastRefreshedAt` and before the cards are told the sync ended.
        //
        // **The comment above was true and the code did not honour it.** It said
        // this can never be the reason the Tags section is late; nothing said it
        // could not be the reason *everything else* was. Detached now, so the
        // sync completes and the headings improve when they improve.
        Task { [weak self] in await self?.refreshTagApplicability() }
        timer.lap("tag applicability (detached — not awaited)")
        // **After the sync has otherwise finished, deliberately.** Every tag is
        // already promoted and already carries a deterministic applicability, so
        // this can only improve a heading — it can never be the reason the Tags
        // section is empty or late. On a device with no on-device model it
        // returns having done nothing.
        await refreshTagApplicability()
        timer.lap("tag applicability")
        // **Last, and after `results` is settled** — the pass compares this
        // refresh's cards against the ones it saw before, so it must see the
        // finished ones. It is also what the background wake-up exists to
        // reach: this same function now runs from a `BGAppRefreshTask`
        // (`BackgroundRefresh`), which is what lets a finding made at 3am be
        // held until morning rather than wait for somebody to open the app.
        // Everything it decides lives in `NotificationCoordinator`.
        await NotificationCoordinator.shared.evaluate(self, now: Date())
        timer.lap("notification pass")
        lastRefreshedAt = Date()
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        let bySource = Dictionary(grouping: samples, by: { $0.source.displayName })
            .map { "· \($0.key): \($0.value.count) sample(s)" }
            .sorted()
        let failures = diag.entries
            .prefix { $0.date >= startedAt }
            .filter { $0.status == .fail }
        diag.info("Sync", "Refresh complete in \(elapsed)s — \(samples.count) samples, \(results.count) insights",
                  detail: ([timer.summary(), ""] + bySource + [
                    "Other (unmodelled) values held: \(otherSamples.count)",
                    failures.isEmpty
                        ? "No failures this sync."
                        : "\(failures.count) failure(s) this sync — see the red entries above."
                  ]).joined(separator: "\n"))
    }

    /// Run every captured provider payload through the ingestion pipeline,
    /// updating the persisted field catalogue and reporting what changed.
    ///
    /// Deliberately loud about schema drift: a provider adding, renaming or
    /// retyping a field is the single most common cause of data quietly going
    /// missing, and the log is where that has to become visible.
    private func ingestPayloads(_ payloads: [IngestPayload], diag: DiagnosticsLog) -> IngestionResult {
        guard !payloads.isEmpty else { return IngestionResult() }
        var catalogue = dataStore.loadFieldCatalogue()
        let knownBefore = catalogue.fields.count
        let result = IngestionPipeline.shipped.ingest(payloads, into: &catalogue)
        dataStore.saveFieldCatalogue(catalogue)
        fieldCatalogue = catalogue

        diag.ok("Ingestion",
                "\(result.fieldCount) field value(s) from \(result.documentCount) record(s) across \(result.payloadCount) payload(s)",
                detail: """
                    Known fields: \(knownBefore) → \(catalogue.fields.count)
                    Promoted to canonical vitals: \(result.promoted.count) sample(s)
                    Kept as raw values: \(result.raw.count)
                    """)

        if !result.newFields.isEmpty {
            let listing = result.newFields.prefix(40).map { "· \($0.identifier)  [\($0.kind.rawValue)]" }
            let overflow = result.newFields.count > 40 ? ["…and \(result.newFields.count - 40) more"] : []
            diag.ok("Ingestion", "Discovered \(result.newFields.count) new provider field(s)",
                    detail: (listing + overflow).joined(separator: "\n"))
        }

        if !result.proposals.isEmpty {
            let listing = result.proposals.map { "· \($0.identifier) → looks like \($0.proposedMetric?.displayName ?? "?")" }
            diag.null("Ingestion", "\(result.proposals.count) field(s) look like known vitals but aren't mapped",
                      detail: (listing + [
                        "",
                        "These are catalogued and stored, but not feeding insights. Promoting one is a rule in PromotionRuleSet.default — no parser or store changes."
                      ]).joined(separator: "\n"))
        }

        if !result.promoted.isEmpty {
            let byMetric = Dictionary(grouping: result.promoted, by: { $0.type.displayName })
                .map { "· \($0.value.count) × \($0.key)" }
                .sorted()
            diag.ok("Ingestion", "Promoted \(result.promoted.count) raw value(s) into canonical vitals",
                    detail: byMetric.joined(separator: "\n"))
        }

        if !result.skipped.isEmpty {
            let summary = result.skipSummary.map { "· \($0.count) × \($0.reason.rawValue)" }
            diag.null("Ingestion", "\(result.skipped.count) payload node(s) not stored",
                      detail: (summary + [
                        "",
                        "null: the provider sent no value. emptyArray: nothing to summarise. arrayTruncated / stringTruncated: kept the leading elements. depthLimit: nested deeper than the flatten policy allows."
                      ]).joined(separator: "\n"))
        }

        for problem in result.unreadablePayloads {
            diag.fail("Ingestion", "Couldn't read a payload — \(problem)")
        }
        return result
    }

    /// Record how many samples of each metric were imported this sync — the
    /// per-field pass/fail the Troubleshooting view surfaces.
    ///
    /// Each metric also carries its per-source split as detail: "66185 × Heart
    /// Rate" doesn't say whether Oura contributed any, and "which device stopped
    /// reporting" is the question the log usually gets opened for.
    private func logMetricCounts(_ diag: DiagnosticsLog) {
        let byType = Dictionary(grouping: samples, by: { $0.type })
        for type in MetricType.allCases {
            guard let ofType = byType[type], !ofType.isEmpty else {
                diag.null("Import", "0 × \(type.displayName)",
                          detail: "No source produced this metric in this sync.")
                continue
            }
            let bySource = Dictionary(grouping: ofType, by: { $0.source.displayName })
                .map { "\($0.key): \($0.value.count)" }
                .sorted()
            let newest = ofType.map(\.start).max()
            var lines = ["By source — \(bySource.joined(separator: ", "))"]
            if let newest {
                lines.append("Most recent: \(newest.formatted(date: .abbreviated, time: .shortened))")
            }
            diag.ok("Import", "\(ofType.count) × \(type.displayName)",
                    detail: lines.joined(separator: "\n"))
        }
    }

    /// Say *what* the sanitiser dropped, not just how many. A bare count can't
    /// distinguish "a provider sent placeholder zeros" from "a metric vanished".
    private func logSanitiserDrops(_ dropped: [HealthMetricSample], diag: DiagnosticsLog) {
        guard !dropped.isEmpty else { return }
        let breakdown = Dictionary(grouping: dropped) {
            "\($0.type.displayName) from \($0.source.displayName)"
        }
        .map { "· \($0.value.count) × \($0.key)" }
        .sorted()
        let span = dropped.map(\.start)
        var lines = ["A source sent a non-positive value for a metric that can't legitimately be zero (usually a missing-data placeholder), so it was dropped rather than charted as 0."]
        lines += breakdown
        if let first = span.min(), let last = span.max() {
            lines.append("Dates affected: \(first.formatted(date: .abbreviated, time: .omitted)) → \(last.formatted(date: .abbreviated, time: .omitted))")
        }
        diag.null("Sanitiser", "Dropped \(dropped.count) empty/invalid vital sample(s)",
                  detail: lines.joined(separator: "\n"))
    }

    /// Fold the modelled medication level into `samples` as a real series.
    ///
    /// It has to be *in* `samples` rather than passed to the engine separately,
    /// because the overlay chart, the baseline machinery and the contributor
    /// pipeline all read that one array — see
    /// `PharmacokineticsModel.dailySamples` for why it earns a `MetricType`.
    ///
    /// Idempotent: the previous derivation is stripped before the new one goes
    /// in, so recomputing twice does not stack two curves. It is rebuilt rather
    /// than cached because it ends at *now*, and a level that stopped updating
    /// would be the one thing on this card that silently went stale.
    private func refreshMedicationLevelSamples(now: Date = Date()) {
        var derived: [HealthMetricSample] = []
        if let medication = activeMedication, let compound = medication.compound,
           !medication.doses.isEmpty {
            let start = max(medication.startedOn,
                            now.addingTimeInterval(-365 * 86_400))
            derived = PharmacokineticsModel.dailySamples(
                doses: medication.doses.map(\.administered), compound: compound,
                from: start, to: now)
        }
        let hadDerived = samples.contains { $0.type == .activeMedicationLevel }
        guard hadDerived || !derived.isEmpty else { return }
        samples = samples.filter { $0.type != .activeMedicationLevel } + derived
    }

    private func recompute() {
        // The logged data that lives in SwiftData rather than in `samples` —
        // the regimen and the side effects — reloaded first, so both the models
        // that read them and every observed view redraw with what the reader
        // just changed.
        reloadLoggedData()
        // Before the evaluation, so the card that reads it sees it in the same
        // pass rather than one recompute later.
        refreshMedicationLevelSamples()
        // The substance model reads a log that isn't in `samples`, so it is
        // rebound before every evaluation. Idempotent — it replaces rather than
        // appends — and it is what puts Substance Impact in front of score
        // recording, score replay and the cross-insight comparison chart, all of
        // which iterate `engine.models` and so had been skipping it silently.
        // The symptom radar's tags and regimen are the same shape of input —
        // `reloadLoggedData()` above has just refreshed `activeMedication`, so
        // the schedule the radar sees is the one the reader sees.
        engine = engine.withSubstanceLog(substanceEvents)
            .withSupplements(supplementEntries)
            .withSymptoms(symptoms, medication: activeMedication?.schedule)
            // Both calendar cards, in one call — see `withCalendar`.
            .withCalendar(events: calendarEvents, judgements: calendarJudgements)

        // The flagged-event feed moves with the data rather than only when
        // somebody opens it — otherwise the dismissible suggestion below would
        // be counting a queue nothing had refreshed. Cheap next to the insight
        // pass: one filter and one grouping over the heart-rate series.
        EventFeedModel.shared.detect(samples: samples, substanceEvents: substanceEvents)

        // ⚠️ **The insight pass is off the main actor, and the reader found
        // out the hard way.** *"When it says 'Syncing your devices' it hangs
        // the UI/UX and the app becomes unresponsive"* — 2026-08-06, on their
        // own phone.
        //
        // Measured before changing anything: `evaluateAll` over 379,990
        // samples and eighteen models takes **2.36 s on an M-series Mac**, so
        // several seconds on a phone, and `recompute()` is called from
        // thirty-three places. Every one of them froze the interface for the
        // duration.
        //
        // The evidence was already in this file. `hydrate()` detaches this
        // exact work with a comment explaining that the engine and the sample
        // types were built platform-free for testing, and that the same
        // property is what lets them leave the main thread. **The sync path
        // simply never got the same treatment** — an optimisation applied to
        // one of two symmetrical paths, which this repo has already named as
        // "a bug with a good comment on it" once (`RawCacheCodec`, 2026-08-05).
        //
        // What stays on the main actor above: the SwiftData reads, the
        // medication-level rebuild and the engine binding. All three are cheap
        // and all three mutate state the pass then reads. What moves is the
        // pure function of `(engine, samples, events, profile)`.
        let engineNow = engine
        let samplesNow = samples
        let eventsNow = vitalEvents
        let profileNow = profile
        recomputeGeneration &+= 1
        let generation = recomputeGeneration
        // Kept so `recomputeSettled()` can await it — `performRefresh` writes
        // the daily summary from `results` and must not read the previous
        // pass's.
        recomputeTask = Task.detached(priority: .userInitiated) {
            let evaluated = engineNow.evaluateAll(samples: samplesNow,
                                                  events: eventsNow,
                                                  profile: profileNow)
            await MainActor.run { [weak self] in
                self?.applyRecomputed(evaluated, generation: generation)
            }
        }
    }

    /// Bumped on every `recompute()`, so a pass that lands after a newer one
    /// started is discarded rather than overwriting fresher results. Same
    /// guard, and the same reason, as `scoreHistoryGeneration`.
    @ObservationIgnored private var recomputeGeneration = 0
    @ObservationIgnored private var recomputeTask: Task<Void, Never>?

    /// Wait for the in-flight evaluation to land.
    ///
    /// Only the sync path needs this: it writes the Today summary from
    /// `results` immediately afterwards, and without the await it would
    /// summarise the *previous* pass. The thirty-two UI-mutation call sites
    /// deliberately do **not** wait — `results` is `@Observable`, so the cards
    /// redraw when the pass lands, which is the whole point of moving it.
    func recomputeSettled() async {
        await recomputeTask?.value
    }

    /// Everything that must happen on the main actor once the pass is in.
    ///
    /// Ordering is identical to what `recompute()` used to do inline; only the
    /// thread changed. In particular `invalidateDerivedCaches()` still runs
    /// *before* the derived-series record loop — see the note on that loop for
    /// what happens when it does not.
    private func applyRecomputed(_ evaluated: [InsightResult], generation: Int) {
        // A pass built from samples that have since been replaced is not
        // merely stale, it is wrong: it would put the old record's scores on
        // screen under the new record's data.
        guard generation == recomputeGeneration else { return }
        results = evaluated
        recordScores(evaluated)
        // Grounding and substance edits reach here without touching `samples`,
        // so the sample-set invalidation hook won't have fired.
        invalidateDerivedCaches()
        // Today's derived figures, from the evaluation that just ran — the
        // backfilled history arrives from the score replays as each finishes.
        // Same store either way, and `record` is last-write-wins per day, so
        // the live value simply supersedes the replayed one for today.
        //
        // ⚠️ **After the invalidation, not before.** `invalidateDerivedCaches`
        // resets the derived store along with the score histories, and the
        // first version of this loop sat above that call — every sync recorded
        // eighteen results and wiped them a line later. Found on the simulator:
        // "Refresh complete — 18 insights" in the diagnostics log while the
        // Data tab's Generated-insights row stayed absent.
        for result in evaluated {
            derivedSeries.record(result, on: Date())
        }
        // After `reloadLoggedData()` above has refreshed `cycleDays`, so the
        // phase split sees the log the reader just changed rather than the one
        // before it.
        //
        // ⚠️ **The merge that brought this in also carried a second
        // `invalidateDerivedCaches()` call, and it was dropped deliberately.**
        // The cycle branch predates the fix directly above — on that branch the
        // invalidation legitimately came *after* the record loop. Taking its
        // side verbatim would have invalidated twice, and the second call would
        // have wiped the derived series the loop had just recorded, silently
        // reinstating the exact defect the comment above documents.
        //
        // The general shape, and this is the second time today: **a merge
        // conflict resolved by picking a side inherits that side's assumptions
        // about everything around it.** Neither half was wrong on its own
        // branch.
        refreshCyclePhaseProfile()
        prewarmBreakdowns()
    }

    /// Build every metric's source breakdown off the main thread, ahead of the
    /// first screen that asks for one.
    ///
    /// `breakdown(_:)` fills its cache lazily, which meant the first open of
    /// each card or vitals row paid a full-sample filter-dedup-sort *on the
    /// main thread* — tens of thousands of readings for the busy metrics, and
    /// several metrics per card. Warming the cache in the background turns
    /// that first open into a dictionary hit. The generation counter guards
    /// against a refresh landing mid-warm: results built from superseded
    /// samples are discarded rather than merged.
    private func prewarmBreakdowns() {
        let snapshot = samples
        let generation = scoreHistoryGeneration
        Task.detached(priority: .utility) {
            let metrics = Set(snapshot.map(\.type))
            let built = MultiSource.withMemo(for: snapshot) {
                Dictionary(uniqueKeysWithValues: metrics.map {
                    ($0, MultiSource.breakdown($0, from: snapshot))
                })
            }
            await MainActor.run {
                guard self.scoreHistoryGeneration == generation else { return }
                // Keep anything the UI built in the meantime — it is identical
                // data and already referenced.
                self.breakdownCache.merge(built) { current, _ in current }
            }
        }
    }

    /// Today's scores become tomorrow's history. `recordScore` upserts by day,
    /// so this costs one row per insight per day rather than one per call.
    ///
    /// Split out of `recompute()` so `hydrate()` can share it: SwiftData writes
    /// are main-actor-only and cannot travel with the rest of the insight pass.
    private func recordScores(_ results: [InsightResult]) {
        for result in results {
            guard let score = result.score else { continue }
            // The same "used" arithmetic the replay stores, so a stored day and
            // a reconstructed one mean the same thing by their count — weighted
            // contributors where any carry weight, the full list otherwise.
            let weighted = result.contributors.filter { $0.weight > 0 }.count
            dataStore.recordScore(result.id, score: score, confidence: result.confidence,
                                  contributorCount: weighted > 0 ? weighted
                                                                 : result.contributors.count)
        }
    }

    /// Device-raised notifications (irregular rhythm, high/low heart rate…)
    /// lifted out of the untyped imported layer.
    ///
    /// Derived rather than stored: `otherSamples` is already persisted, and these
    /// are a reading of it. Cached because `recompute()` runs on every launch,
    /// refresh, grounding save and substance log.
    var vitalEvents: [VitalEvent] {
        if let cached = vitalEventCache { return cached }
        let built = VitalEventReader.events(from: otherSamples)
        vitalEventCache = built
        return built
    }
    @ObservationIgnored private var vitalEventCache: [VitalEvent]?

    // MARK: - Score history

    /// Replayed-and-merged score history per insight, filled in the background.
    ///
    /// Not computed in `recompute()`: a replay walks the sample set once per day
    /// of history, and doing that for eleven insights on every refresh would
    /// cost far more than the two or three screens the user actually opens.
    ///
    /// Observable, unlike the other derived caches, because it is written from a
    /// background task *after* the view body has returned rather than during it
    /// — so publishing the result is what makes the chart appear, and there is
    /// no mid-render mutation to guard against.
    private(set) var scoreHistories: [InsightID: [ScorePoint]] = [:]

    /// **Every figure the app has derived, day by day** — the reader's
    /// instruction, 2026-08-06. See `DerivedSeries` in InsightKit.
    ///
    /// Filled from two directions and one rule reconciles them: the live
    /// evaluation records *today* each time it runs, and each card's score
    /// replay harvests its *history* through `ScoreHistory.replay(observing:)`
    /// as it completes — so the backfill costs nothing the score charts were
    /// not already paying. `record` is last-write-wins per day, which makes
    /// both paths idempotent however often either runs.
    ///
    /// In memory only, like `scoreHistories`, and recomputed the same way: the
    /// models are pure functions of the samples, so persisting their output
    /// would be caching something the replay reconstructs anyway — and a model
    /// improvement would leave stale figures behind.
    private(set) var derivedSeries = DerivedSeriesStore()
    /// Replays already in flight, so a view that re-renders while one is running
    /// doesn't start a second.
    @ObservationIgnored private var scoreHistoryTasks: Set<InsightID> = []
    /// Bumped whenever the sample set changes. A replay that started before the
    /// bump is discarded on arrival rather than writing a chart built from data
    /// that has since been replaced.
    @ObservationIgnored private var scoreHistoryGeneration = 0

    /// Requested replays not yet started, oldest request first.
    @ObservationIgnored private var scoreHistoryQueue: [InsightID] = []

    /// How many replays may run at once.
    ///
    /// Being off the main actor is not the same as being free. The Insights tab
    /// asks for a history for *every* scored insight the moment it opens — one
    /// call per card, plus the comparison chart asking for all of them — and
    /// each was starting its own `Task.detached` at `.userInitiated`. Seventeen
    /// CPU-bound replays across a six-core phone does not block the main thread
    /// in the actor sense; it starves it of a core, which looks exactly the
    /// same from the outside. On the user's recording the list froze solid for
    /// four to six seconds at a time while scrolling.
    ///
    /// Two at `.utility` leaves the interface a clear run of the CPU. The
    /// charts still fill in progressively, which is what they were designed to
    /// do — `scoreHistory(for:)` has always returned `[]` on first ask.
    private static let maxConcurrentReplays = 2

    /// Score over time for one insight — stored days where we have them, laid
    /// over days reconstructed from the raw samples.
    ///
    /// Returns empty and computes off the main actor on first request. Vitals
    /// Check is why: its baseline is now built per source from daily buckets,
    /// which means de-duplicating tens of thousands of heart-rate samples once
    /// per replayed day. Correct, but far too slow to run inside a view body.
    /// `prioritise` jumps this card to the front of the queue. The Insights tab
    /// asks for all nine histories the moment it opens, and with two running at
    /// once the card the reader actually taps into can otherwise sit seventh in
    /// line behind eight it isn't looking at — its chart the last to appear on
    /// the one screen where it is the whole point. The card in view passes
    /// `true`; the export and the comparison strip, which want all of them
    /// equally, do not.
    func scoreHistory(for id: InsightID, days: Int = 90,
                      prioritise: Bool = false) -> [ScorePoint] {
        if let cached = scoreHistories[id] { return cached }
        guard engine.models.contains(where: { $0.id == id }) else { return [] }
        if scoreHistoryTasks.contains(id) { return [] }   // already running
        if let queued = scoreHistoryQueue.firstIndex(of: id) {
            // Already waiting: promote it if asked, otherwise leave it be.
            if prioritise && queued != 0 {
                scoreHistoryQueue.remove(at: queued)
                scoreHistoryQueue.insert(id, at: 0)
            }
            return []
        }
        if prioritise { scoreHistoryQueue.insert(id, at: 0) }
        else { scoreHistoryQueue.append(id) }
        drainScoreHistoryQueue(days: days)
        return []
    }

    /// **Every stored day, straight from SwiftData — no cache, no queue.**
    ///
    /// ⚠️ **The export must use this, never `scoreHistory(for:)`.** That one is a
    /// lazy view cache: it returns `[]` and queues a background replay when a
    /// card's chart has not been drawn, which is correct for a view getting to
    /// a first frame and wrong for an export that asks about all eighteen cards
    /// at once and waits for nothing.
    ///
    /// Found 2026-08-07 in the reader's own export: **all 18 cards carried
    /// `history: []`** while the rows were sitting in SwiftData. Same class as
    /// D39 — the key existed, the data existed, the payload was empty — and no
    /// InsightKit test could catch it, because the export's tests build their
    /// own bundle instead of going through `DataExportView`.
    func storedScoreHistory(for id: InsightID) -> [ScorePoint] {
        dataStore.scoreHistory(for: id)
    }

    /// Whether the 90-day replay for this card is still running.
    ///
    /// `scoreHistory(for:)` returns `[]` on first ask and fills in behind the
    /// view, so an empty history is two different states. "Score over time" now
    /// renders on every card and has to say which one it is in — announcing "no
    /// scored days yet" during the second the replay takes is a false statement
    /// that corrects itself after the reader has read it.
    ///
    /// A card the engine doesn't know is never pending: nothing will ever run
    /// for it, and reporting it as computing would hang that section forever.
    func scoreHistoryIsPending(for id: InsightID) -> Bool {
        guard engine.models.contains(where: { $0.id == id }) else { return false }
        return scoreHistories[id] == nil
    }

    /// Start queued replays up to the concurrency limit.
    private func drainScoreHistoryQueue(days: Int) {
        while scoreHistoryTasks.count < Self.maxConcurrentReplays,
              !scoreHistoryQueue.isEmpty {
            let id = scoreHistoryQueue.removeFirst()
            guard scoreHistories[id] == nil,
                  let model = engine.models.first(where: { $0.id == id }) else { continue }
            scoreHistoryTasks.insert(id)

            let samples = self.samples
            let events = self.vitalEvents
            let profile = self.profile
            let stored = dataStore.scoreHistory(for: id)
            let generation = scoreHistoryGeneration
            // `.utility`, not `.userInitiated`: nobody is waiting on this — the
            // chart it fills is already on screen and already correct without
            // it. Whoever is scrolling *is* waiting, and should win the CPU.
            Task.detached(priority: .utility) {
                // The derived harvest rides the replay the chart already pays
                // for — one observer call per evaluated day, no second sweep.
                var harvested = DerivedSeriesStore()
                let replayed = ScoreHistory.replay(model: model, samples: samples,
                                                   events: events,
                                                   profile: profile, days: days,
                                                   observing: { day, result in
                                                       harvested.record(result, on: day)
                                                   })
                let merged = ScoreHistory.merging(replayed: replayed, stored: stored)
                let derived = harvested
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.scoreHistoryTasks.remove(id)
                    if self.scoreHistoryGeneration == generation {
                        self.scoreHistories[id] = merged
                        self.derivedSeries.merge(derived)
                    }
                    // Whatever the generation, a slot just freed up.
                    self.drainScoreHistoryQueue(days: days)
                }
            }
        }
    }

    /// Heart age and fitness age over time. Same shape and same reasons as
    /// `scoreHistories`: a replay, off the main actor, discarded if the samples
    /// changed under it.
    private(set) var ageHistory: [AgePoint] = []
    @ObservationIgnored private var ageHistoryRunning = false

    /// Returns empty and computes in the background on first request. Fifty-two
    /// weekly replays of the risk equations is not a view-body cost.
    func heartAgeHistory(days: Int = 365) -> [AgePoint] {
        if !ageHistory.isEmpty { return ageHistory }
        guard !ageHistoryRunning else { return [] }
        ageHistoryRunning = true

        let samples = self.samples
        let profile = self.profile
        let generation = scoreHistoryGeneration
        Task.detached(priority: .userInitiated) {
            let points = HeartAgeHistory.replay(samples: samples, profile: profile, days: days)
            await MainActor.run { [weak self] in
                guard let self, self.scoreHistoryGeneration == generation else { return }
                self.ageHistory = points
                self.ageHistoryRunning = false
            }
        }
        return []
    }

    /// Cardiovascular risk at future ages, on today's numbers.
    ///
    /// `HeartAgeAnalyser` has computed these since it shipped and
    /// `CardiovascularRiskInsight` read four other fields off the same value and
    /// let it fall out of scope — so the equations ran, every time, and nothing
    /// ever drew the result. The analyser's own `explanation` even wrote "the
    /// projections below", which was never true.
    ///
    /// Cached and computed off the main actor for `heartAgeHistory`'s reason:
    /// this re-runs SCORE2 and ASCVD at four ages, which is not a view-body cost.
    private(set) var riskProjections: [HeartAgeModel.Projection] = []
    @ObservationIgnored private var riskProjectionsRunning = false

    /// Every age estimate the app and its connectors produce, each with its own
    /// attribution and error. Filled by the same background pass as the
    /// projections — it comes off the same analysis, so running it twice would
    /// be two SCORE2/ASCVD solves for one screen.
    private(set) var ageEstimates: [AgeComparison.Estimate] = []

    func heartAgeProjections() -> [HeartAgeModel.Projection] {
        if !riskProjections.isEmpty { return riskProjections }
        guard !riskProjectionsRunning else { return [] }
        riskProjectionsRunning = true

        let samples = self.samples
        let profile = self.profile
        // The unmodelled catalogue, because a vendor age can arrive with no
        // `MetricType` behind it — Withings sends one as a numbered measure
        // type, and the section could not see it. Backlog D20; see
        // `AgeComparison.relayedRawAges`.
        let raw = self.otherSamples
        let generation = scoreHistoryGeneration
        Task.detached(priority: .userInitiated) {
            let analysis = HeartAgeAnalyser().analyse(samples: samples, profile: profile,
                                                      now: Date())
            // The app's own biological age joins the comparison — the reader's
            // request, 2026-08-06. Computed on this same detached pass rather
            // than read from the card, so the section cannot show a number the
            // card has since moved past.
            let biological = BiologicalAgeModel.evaluate(samples: samples, profile: profile,
                                                         now: Date())
            let estimates = AgeComparison.estimates(
                chronological: analysis.chronologicalAge,
                fitness: analysis.fitness, heart: analysis.heart,
                sex: profile.sex, samples: samples,
                biological: biological,
                // The risk-factor set, so the section can re-solve the heart age
                // once per blood-pressure instrument instead of printing the one
                // `VitalReader` picked. See `AgeComparison.heartEstimates`.
                heartSubject: analysis.subject, raw: raw, now: Date())
            await MainActor.run { [weak self] in
                guard let self, self.scoreHistoryGeneration == generation else { return }
                self.riskProjections = analysis.projections
                self.ageEstimates = estimates
                self.riskProjectionsRunning = false
            }
        }
        return []
    }

    /// The VO₂max trajectory, including the twelve-month projection and its
    /// residual spread — both computed since the card shipped and read by
    /// nothing outside `CardioTrajectory.swift`.
    ///
    /// Not cached: unlike the two above this is a single least-squares fit over
    /// one metric's dailies, and it already runs inside the insight pass every
    /// refresh. Caching it would add an invalidation path for no measured gain.
    func fitnessTrajectory() -> VO2Trajectory.Output? {
        guard let age = profile.age(), let sex = profile.sex else { return nil }
        return VO2Trajectory.evaluate(samples: samples, age: age, sex: sex)
    }

    /// Standardised daily series for an insight's inputs, cached per insight and
    /// timeframe.
    ///
    /// Cached for the same reason `vitalsSummaries` is: building these scans the
    /// whole sample set once per metric, and the detail view re-evaluates its
    /// body on every pan frame. Uncached, a seven-input card would rescan
    /// six figures of samples fourteen times a frame.
    ///
    /// Keyed on the timeframe rather than on the resolved date range, because
    /// the range ends at "now" and would mint a new key on every call.
    @ObservationIgnored private var overlayCache: [String: [NormalizedSeries]] = [:]

    func overlaySeries(for id: InsightID,
                       contributions: [MetricContribution],
                       timeframe: Timeframe) -> [NormalizedSeries] {
        let key = "\(id.rawValue)|\(timeframe.rawValue)"
        if let cached = overlayCache[key] { return cached }
        let built = SeriesNormalizer.series(for: contributions, samples: samples,
                                            range: overlayRange(for: contributions.metrics,
                                                                timeframe: timeframe))
        overlayCache[key] = built
        return built
    }

    /// The window an overlay standardises over.
    ///
    /// `.all` has no fixed length — `Timeframe.startDate` returns nil for it —
    /// so it falls back to the earliest relevant sample rather than to a default
    /// window, which would silently show one day and label it "All".
    func overlayRange(for metrics: [MetricType], timeframe: Timeframe) -> ClosedRange<Date> {
        let now = Date()
        if let start = timeframe.startDate(from: now) { return start...now }
        let wanted = Set(metrics)
        let earliest = samples.lazy.filter { wanted.contains($0.type) }.map(\.start).min()
        return (earliest ?? now.addingTimeInterval(-30 * 24 * 3600))...now
    }

    // MARK: - Substances

    func logSubstance(_ substance: SubstanceClass, at date: Date = Date(), units: Double? = nil, note: String? = nil) {
        dataStore.addSubstanceEvent(.init(substance: substance, timestamp: date, units: units, note: note))
        substanceEvents = dataStore.loadSubstanceEvents()
        recomputeSubstanceImpact()
    }

    /// Move a logged entry to when it actually happened.
    func updateSubstanceEvent(id: UUID, timestamp: Date) {
        dataStore.updateSubstanceEvent(id: id, timestamp: timestamp)
        substanceEvents = dataStore.loadSubstanceEvents()
        recomputeSubstanceImpact()
    }

    func deleteSubstanceEvent(id: UUID) {
        dataStore.deleteSubstanceEvent(id: id)
        substanceEvents = dataStore.loadSubstanceEvents()
        recomputeSubstanceImpact()
    }

    /// Re-evaluate only what a substance log can actually change.
    ///
    /// These three used to call `recompute()`, which evaluates **every**
    /// registered insight across the whole sample set and then throws away every
    /// derived cache — breakdowns, overlays, replayed score histories, age
    /// history. For a substance log almost all of that is wasted: exactly one
    /// model reads the log, and not one of those caches does. On a phone holding
    /// a hundred thousand samples it is the difference between a tap that lands
    /// and a tap that hangs, and the tap is the whole interaction — the grid
    /// exists so that logging is one gesture.
    ///
    /// The score row is still written, so Substance Impact keeps appearing in
    /// the history and the comparison chart.
    private func recomputeSubstanceImpact() {
        engine = engine.withSubstanceLog(substanceEvents)
        guard let updated = engine.result(for: .substanceImpact, samples: samples,
                                          profile: profile) else { return }
        if let index = results.firstIndex(where: { $0.id == .substanceImpact }) {
            results[index] = updated
        } else {
            results.append(updated)
        }
        if let score = updated.score {
            let weighted = updated.contributors.filter { $0.weight > 0 }.count
            dataStore.recordScore(.substanceImpact, score: score,
                                  confidence: updated.confidence,
                                  contributorCount: weighted > 0 ? weighted
                                                                 : updated.contributors.count)
        }
        // Suggestions read `results`, so one changed result invalidates them.
        suggestionCache = nil
        // And this card's own replayed history is drawn from the log, so it has
        // to be rebuilt — but only this card's.
        scoreHistories[.substanceImpact] = nil
        scoreHistoryTasks.remove(.substanceImpact)
        scoreHistoryQueue.removeAll { $0 == .substanceImpact }
    }

    // MARK: - Supplements

    /// Add a bottle, or replace the one already stored under this id.
    ///
    /// Upsert rather than insert, and the reason is arithmetic rather than
    /// tidiness: this card's whole job is a **sum across products**, so a second
    /// row for a corrected label would double every ingredient in it.
    func saveSupplementEntry(_ entry: SupplementEntry) {
        dataStore.saveSupplementEntry(entry)
        supplementEntries = dataStore.loadSupplementEntries()
        recomputeSupplementStack()
    }

    func deleteSupplementEntry(id: UUID) {
        dataStore.deleteSupplementEntry(id: id)
        supplementEntries = dataStore.loadSupplementEntries()
        recomputeSupplementStack()
    }

    /// Re-evaluate only what a supplement stack can change.
    ///
    /// The same shape as `recomputeSubstanceImpact` above and for the same
    /// reason: exactly one model reads the stack, and a full `recompute()` would
    /// re-evaluate every card and discard every derived cache to show the reader
    /// the bottle they just typed.
    private func recomputeSupplementStack() {
        engine = engine.withSupplements(supplementEntries)
        guard let updated = engine.result(for: .supplementStack, samples: samples,
                                          profile: profile) else { return }
        if let index = results.firstIndex(where: { $0.id == .supplementStack }) {
            results[index] = updated
        } else {
            results.append(updated)
        }
        if let score = updated.score {
            let weighted = updated.contributors.filter { $0.weight > 0 }.count
            dataStore.recordScore(.supplementStack, score: score,
                                  confidence: updated.confidence,
                                  contributorCount: weighted > 0 ? weighted
                                                                 : updated.contributors.count)
        }
        suggestionCache = nil
        scoreHistories[.supplementStack] = nil
        scoreHistoryTasks.remove(.supplementStack)
        scoreHistoryQueue.removeAll { $0 == .supplementStack }
    }

    /// The stack as the card sums it — one place, so the Data tab, the card's
    /// "View & add" row and the entry sheet cannot disagree about a total.
    var supplementStackSummary: SupplementStackModel.Output? {
        SupplementStackModel.evaluate(entries: supplementEntries, samples: samples,
                                      profile: profile)
    }

    func result(for id: InsightID) -> InsightResult? {
        results.first { $0.id == id }
    }

    // MARK: - Integrations

    /// Live status for a provider (observable), preferring the app-model copy.
    func status(for integration: any HealthIntegration) -> IntegrationStatus {
        integrationStatuses[integration.id] ?? integration.status
    }

    func connect(_ integration: any HealthIntegration) async {
        do {
            try await integration.connect()
        } catch {
            // Keep going — the provider records the failure in its own status,
            // which we surface below rather than swallowing it.
        }
        integrationStatuses[integration.id] = integration.status
        let key = "lastError.\(integration.id)"
        switch integration.status {
        case .connected:
            UserDefaults.standard.removeObject(forKey: key)
            dataStore.setIntegration(id: integration.id, connected: true, lastSync: nil)
            await refresh(force: true)
        case .error(let message):
            UserDefaults.standard.set(message, forKey: key)   // survive relaunch
        default:
            break
        }
    }

    func disconnect(_ integration: any HealthIntegration) async {
        await integration.disconnect()
        // Disconnecting the calendar forgets what it brought, including the
        // reader's corrections — a correction about an event the app can no
        // longer see is not something it should keep.
        if integration.id == "calendar" { forgetCalendar() }
        integrationStatuses[integration.id] = integration.status
        UserDefaults.standard.removeObject(forKey: "lastError.\(integration.id)")
        dataStore.setIntegration(id: integration.id, connected: false, lastSync: nil)
        await refresh(force: true)
    }

    /// Samples of a metric for charting, oldest → newest.
    func series(_ metric: MetricType) -> [HealthMetricSample] {
        samples.samples(of: metric)
    }

    /// Most recent value for a metric, if any (used by the vitals glance row).
    func latest(_ metric: MetricType) -> Double? {
        samples.latestValue(metric)
    }
}
