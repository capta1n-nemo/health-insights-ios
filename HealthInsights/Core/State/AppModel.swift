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
        scoreChangeCache = nil
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
        didSet {
            substanceLoadCache = nil
            substanceWindowCache = nil
        }
    }

    /// Decaying daily cardiovascular load from the substance log.
    ///
    /// Cached for the same reason the overlay is: a detail view re-evaluates its
    /// body on every pan frame, and this walks the whole log once per day of
    /// history. Invalidated by `substanceEvents` above rather than by
    /// `invalidateDerivedCaches()` — it is a function of the log, not of samples.
    @ObservationIgnored private var substanceLoadCache: [SubstanceLoadPoint]?

    @ObservationIgnored private var substanceWindowCache: [SubstanceWindow]?

    /// The after-windows to shade behind a vital's chart.
    ///
    /// Empty for a metric the analyzer doesn't compare, because a shaded stretch
    /// behind a weight chart would assert a relationship nothing here has
    /// looked for. `comparedMetrics` is derived from the analyzer's own watched
    /// table, so the two can't drift apart.
    func substanceWindows(for metric: MetricType) -> [SubstanceWindow] {
        guard SubstanceResponseAnalyzer.comparedMetrics.contains(metric) else { return [] }
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

    func sleepRegularity() -> CircadianConsistencyModel.Output? {
        if let circadianCache { return circadianCache }
        let built = CircadianConsistencyModel.evaluate(samples: samples)
        circadianCache = built
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
                                                 profile: profile,
                                                 substanceEvents: substanceEvents)
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
    @ObservationIgnored private var scoreChangeCache: [InsightID: ScoreChange]?

    func scoreChange(for id: InsightID) -> ScoreChange? {
        if scoreChangeCache == nil {
            var built: [InsightID: ScoreChange] = [:]
            for result in results where result.score != nil {
                if let change = ScoreChangeReader.trend(
                    for: result.id, history: dataStore.scoreHistory(for: result.id)) {
                    built[result.id] = change
                }
            }
            scoreChangeCache = built
        }
        return scoreChangeCache?[id]
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
        seedIntegrationStatuses()
        // Small SwiftData reads only. `hydrate()` does the rest, off the main
        // actor and after the first frame — see the note on it.
        substanceEvents = dataStore.loadSubstanceEvents()
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

        // Main actor, because SwiftData's `mainContext` is. Both are small.
        let manual = dataStore.loadManualSamples()
        let store = dataStore
        let engineNow = engine.withSubstanceLog(substanceEvents)
        let profileNow = profile

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
            let samples = TemperatureReconstructor.withReconstructedTemperature(merged)
            let events = VitalEventReader.events(from: other)
            let results = engineNow.evaluateAll(samples: samples, events: events,
                                                profile: profileNow)
            return HydratedState(samples: samples, other: other, results: results)
        }.value

        otherSamples = loaded.other
        samples = loaded.samples
        engine = engineNow
        results = loaded.results

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

    func refresh(force: Bool = false) async {
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
        launchPhase = .summarising
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
        recordScores(results)
        // Grounding and substance edits reach here without touching `samples`,
        // so the sample-set invalidation hook won't have fired.
        invalidateDerivedCaches()
    }

    /// Today's scores become tomorrow's history. `recordScore` upserts by day,
    /// so this costs one row per insight per day rather than one per call.
    ///
    /// Split out of `recompute()` so `hydrate()` can share it: SwiftData writes
    /// are main-actor-only and cannot travel with the rest of the insight pass.
    private func recordScores(_ results: [InsightResult]) {
        for result in results {
            guard let score = result.score else { continue }
            dataStore.recordScore(result.id, score: score, confidence: result.confidence,
                                  contributorCount: result.contributors.count)
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
    func scoreHistory(for id: InsightID, days: Int = 90) -> [ScorePoint] {
        if let cached = scoreHistories[id] { return cached }
        guard !scoreHistoryTasks.contains(id), !scoreHistoryQueue.contains(id) else { return [] }
        guard engine.models.contains(where: { $0.id == id }) else { return [] }
        scoreHistoryQueue.append(id)
        drainScoreHistoryQueue(days: days)
        return []
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
                let replayed = ScoreHistory.replay(model: model, samples: samples,
                                                   events: events,
                                                   profile: profile, days: days)
                let merged = ScoreHistory.merging(replayed: replayed, stored: stored)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.scoreHistoryTasks.remove(id)
                    if self.scoreHistoryGeneration == generation {
                        self.scoreHistories[id] = merged
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

    func heartAgeProjections() -> [HeartAgeModel.Projection] {
        if !riskProjections.isEmpty { return riskProjections }
        guard !riskProjectionsRunning else { return [] }
        riskProjectionsRunning = true

        let samples = self.samples
        let profile = self.profile
        let generation = scoreHistoryGeneration
        Task.detached(priority: .userInitiated) {
            let analysis = HeartAgeAnalyser().analyse(samples: samples, profile: profile,
                                                      now: Date())
            await MainActor.run { [weak self] in
                guard let self, self.scoreHistoryGeneration == generation else { return }
                self.riskProjections = analysis.projections
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
            dataStore.recordScore(.substanceImpact, score: score,
                                  confidence: updated.confidence,
                                  contributorCount: updated.contributors.count)
        }
        // Suggestions read `results`, so one changed result invalidates them.
        suggestionCache = nil
        // And this card's own replayed history is drawn from the log, so it has
        // to be rebuilt — but only this card's.
        scoreHistories[.substanceImpact] = nil
        scoreHistoryTasks.remove(.substanceImpact)
        scoreHistoryQueue.removeAll { $0 == .substanceImpact }
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
