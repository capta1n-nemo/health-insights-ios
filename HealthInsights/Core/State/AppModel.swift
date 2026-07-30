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
    @ObservationIgnored private var otherGroupCache: [RawMetricGroup]?
    @ObservationIgnored private var bloodPressureCache: [BloodPressureEstimator.Reading]?

    /// What a Vitals row needs, without building a full breakdown per row.
    struct VitalsSummary {
        let latest: HealthMetricSample
        let sourceCount: Int
    }

    private func invalidateDerivedCaches() {
        breakdownCache.removeAll(keepingCapacity: true)
        vitalsSummaryCache = nil
        bloodPressureCache = nil
        scoreHistories.removeAll()
        scoreHistoryTasks.removeAll()
        scoreHistoryGeneration &+= 1
        ageHistory.removeAll()
        ageHistoryRunning = false
        overlayCache.removeAll()
        suggestionCache = nil
    }
    /// Imported data we don't yet model as canonical metrics (new HealthKit types,
    /// extra provider fields). Surfaced in Vitals ▸ "Other data" for review.
    private(set) var otherSamples: [RawMetricSample] = [] {
        didSet {
            otherGroupCache = nil
            vitalEventCache = nil
        }
    }
    /// Everything the app has learned about provider schemas — every field ever
    /// ingested, its type, whether it feeds a vital, and what it might map to.
    private(set) var fieldCatalogue = FieldCatalogue()
    private(set) var substanceEvents: [SubstanceEvent] = [] {
        didSet { substanceLoadCache = nil }
    }

    /// Decaying daily cardiovascular load from the substance log.
    ///
    /// Cached for the same reason the overlay is: a detail view re-evaluates its
    /// body on every pan frame, and this walks the whole log once per day of
    /// history. Invalidated by `substanceEvents` above rather than by
    /// `invalidateDerivedCaches()` — it is a function of the log, not of samples.
    @ObservationIgnored private var substanceLoadCache: [SubstanceLoadPoint]?

    /// The load series the Substance Impact detail screen charts.
    func substanceLoadSeries(days: Int = 90) -> [SubstanceLoadPoint] {
        if let substanceLoadCache { return substanceLoadCache }
        let built = SubstanceLoad.series(events: substanceEvents, days: days)
        substanceLoadCache = built
        return built
    }

    /// "Improve your health", recomputed with the results and cached.
    ///
    /// Cached because it re-runs `VO2Trajectory` and the whole vitals scan, and
    /// the Insights list asks for it on every redraw.
    @ObservationIgnored private var suggestionCache: [Suggestion]?

    var suggestions: [Suggestion] {
        if let suggestionCache { return suggestionCache }
        let built = SuggestionEngine.suggestions(results: results, samples: samples,
                                                 profile: profile)
        suggestionCache = built
        return built
    }
    private(set) var profile: UserHealthProfile
    private(set) var results: [InsightResult] = []
    private(set) var todaySummary: String = ""
    private(set) var isSyncing = false
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
        seedIntegrationStatuses()
        hydrateFromCache()
    }

    /// Populate state from persisted data on launch — manual readings plus the
    /// last-synced Apple Health / wearable samples cached to disk — so the app
    /// shows your data immediately, before (or without) a fresh network sync.
    private func hydrateFromCache() {
        let manual = dataStore.loadManualSamples()
        let cached = dataStore.loadCachedSamples()
        let merged = (manual + cached).sanitizedVitals()
        samples = TemperatureReconstructor.withReconstructedTemperature(merged)
        otherSamples = dataStore.loadCachedOther()
        substanceEvents = dataStore.loadSubstanceEvents()
        recompute()
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

    // MARK: - Feedback & model-improvement telemetry (on-device, opt-in, transmit-disabled)

    /// Whether the user has opted in to sharing anonymised model-error metrics.
    /// Off by default. Transmission is not implemented yet regardless — this only
    /// governs whether the outbox would be eligible to send in future.
    var telemetryOptIn: Bool {
        get { UserDefaults.standard.bool(forKey: "telemetryOptIn") }
        set { UserDefaults.standard.set(newValue, forKey: "telemetryOptIn") }
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
        for sample in samples {
            if let current = latest[sample.type] {
                if sample.start > current.start { latest[sample.type] = sample }
            } else {
                latest[sample.type] = sample
            }
            families[sample.type, default: []].insert(sample.source.deviceFamily)
        }
        let built = latest.mapValues { sample in
            VitalsSummary(latest: sample,
                          sourceCount: families[sample.type]?.count ?? 1)
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

    var outstandingGrounding: [(requirement: GroundingRequirement, status: RequirementStatus)] {
        engine.outstandingGrounding(profile: profile)
    }

    // MARK: - Sync

    /// Refresh all data: fetch from connected integrations + local samples, then
    /// recompute insights and the summary.
    /// - Parameter force: bypass the manual-refresh floor. Used by the paths that
    ///   *know* something changed — logging a substance, saving a grounding value
    ///   — where waiting thirty seconds would be nonsense.
    func refresh(force: Bool = false) async {
        let startedAt = Date()
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

        let manual = dataStore.loadManualSamples()
        let synced = await registry.syncAllConnected()
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

        // Cache-merge: a source that returned data this sync replaces its cached
        // copy; sources that returned nothing (disconnected/offline) keep their
        // last-known cache, so their data never disappears from the app.
        let freshSamples = synced.samples + ingested.promoted
        let cached = dataStore.loadCachedSamples()
        let freshSourceIDs = Set(freshSamples.map { $0.source.id })
        let retained = cached.filter { !freshSourceIDs.contains($0.source.id) }
        let nonManual = freshSamples + retained
        dataStore.saveCachedSamples(nonManual)
        if !retained.isEmpty {
            diag.info("Cache", "Kept \(retained.count) cached sample(s) from idle sources")
        }

        // Same cache-merge for the raw "other" data.
        let freshOther = synced.other + ingested.raw
        let cachedOther = dataStore.loadCachedOther()
        let freshOtherSourceIDs = Set(freshOther.map { $0.source.id })
        let retainedOther = cachedOther.filter { !freshOtherSourceIDs.contains($0.source.id) }
        otherSamples = freshOther + retainedOther
        dataStore.saveCachedOther(otherSamples)
        if !freshOther.isEmpty {
            diag.ok("Import", "\(freshOther.count) other data point(s) imported")
        }

        // Drop placeholder zeros (e.g. an Oura day with no HR → 0 bpm) so they
        // don't render as "0 bpm" tiles or poison multi-source averages/graphs.
        let (merged, dropped) = (manual + nonManual).partitionedVitals()
        logSanitiserDrops(dropped, diag: diag)
        // Creative reconstruction: turn wearable skin-temperature *deviations*
        // (Oura/Hume) into absolute *skin*-temperature samples so they can be
        // trended and charted. Deliberately not body temperature: these are skin
        // readings, and labelling them as core is what had Vitals Check judging
        // them against fever and hypothermia bounds.
        samples = TemperatureReconstructor.withReconstructedTemperature(merged)
        logMetricCounts(diag)
        profile = dataStore.loadProfile()
        substanceEvents = dataStore.loadSubstanceEvents()
        recompute()
        await refreshSummaryIfChanged(now: startedAt, diag: diag)
        lastRefreshedAt = Date()
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        let bySource = Dictionary(grouping: samples, by: { $0.source.displayName })
            .map { "· \($0.key): \($0.value.count) sample(s)" }
            .sorted()
        let failures = diag.entries
            .prefix { $0.date >= startedAt }
            .filter { $0.status == .fail }
        diag.info("Sync", "Refresh complete in \(elapsed)s — \(samples.count) samples, \(results.count) insights",
                  detail: (bySource + [
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

    private func recompute() {
        // The substance model reads a log that isn't in `samples`, so it is
        // rebound before every evaluation. Idempotent — it replaces rather than
        // appends — and it is what puts Substance Impact in front of score
        // recording, score replay and the cross-insight comparison chart, all of
        // which iterate `engine.models` and so had been skipping it silently.
        engine = engine.withSubstanceLog(substanceEvents)
        results = engine.evaluateAll(samples: samples, events: vitalEvents, profile: profile)

        // Today's scores become tomorrow's history. `recordScore` upserts by
        // day, so running this on every recompute costs one row per insight per
        // day rather than one per call.
        for result in results {
            guard let score = result.score else { continue }
            dataStore.recordScore(result.id, score: score, confidence: result.confidence,
                                  contributorCount: result.contributors.count)
        }
        // Grounding and substance edits reach here without touching `samples`,
        // so the sample-set invalidation hook won't have fired.
        invalidateDerivedCaches()
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
    /// Replays already in flight, so a view that re-renders while one is running
    /// doesn't start a second.
    @ObservationIgnored private var scoreHistoryTasks: Set<InsightID> = []
    /// Bumped whenever the sample set changes. A replay that started before the
    /// bump is discarded on arrival rather than writing a chart built from data
    /// that has since been replaced.
    @ObservationIgnored private var scoreHistoryGeneration = 0

    /// Score over time for one insight — stored days where we have them, laid
    /// over days reconstructed from the raw samples.
    ///
    /// Returns empty and computes off the main actor on first request. Vitals
    /// Check is why: its baseline is now built per source from daily buckets,
    /// which means de-duplicating tens of thousands of heart-rate samples once
    /// per replayed day. Correct, but far too slow to run inside a view body.
    func scoreHistory(for id: InsightID, days: Int = 90) -> [ScorePoint] {
        if let cached = scoreHistories[id] { return cached }
        guard !scoreHistoryTasks.contains(id) else { return [] }
        guard let model = engine.models.first(where: { $0.id == id }) else { return [] }
        scoreHistoryTasks.insert(id)

        let samples = self.samples
        let events = self.vitalEvents
        let profile = self.profile
        let stored = dataStore.scoreHistory(for: id)
        let generation = scoreHistoryGeneration
        Task.detached(priority: .userInitiated) {
            let replayed = ScoreHistory.replay(model: model, samples: samples,
                                               events: events,
                                               profile: profile, days: days)
            let merged = ScoreHistory.merging(replayed: replayed, stored: stored)
            await MainActor.run { [weak self] in
                guard let self, self.scoreHistoryGeneration == generation else { return }
                self.scoreHistories[id] = merged
                self.scoreHistoryTasks.remove(id)
            }
        }
        return []
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
        recompute()
    }

    /// Move a logged entry to when it actually happened.
    func updateSubstanceEvent(id: UUID, timestamp: Date) {
        dataStore.updateSubstanceEvent(id: id, timestamp: timestamp)
        substanceEvents = dataStore.loadSubstanceEvents()
        recompute()
    }

    func deleteSubstanceEvent(id: UUID) {
        dataStore.deleteSubstanceEvent(id: id)
        substanceEvents = dataStore.loadSubstanceEvents()
        recompute()
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
