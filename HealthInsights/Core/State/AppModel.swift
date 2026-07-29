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
    let engine: InsightEngine
    let summarizer: FoundationModelSummarizer

    // Rendered state
    private(set) var samples: [HealthMetricSample] = []
    private(set) var substanceEvents: [SubstanceEvent] = []
    private(set) var profile: UserHealthProfile
    private(set) var results: [InsightResult] = []
    private(set) var todaySummary: String = ""
    private(set) var isSyncing = false
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
        Task { await refresh() }
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

    /// A source-split breakdown of a metric across all connected devices.
    func breakdown(_ metric: MetricType) -> MultiSourceBreakdown {
        MultiSource.breakdown(metric, from: samples)
    }

    var outstandingGrounding: [(requirement: GroundingRequirement, status: RequirementStatus)] {
        engine.outstandingGrounding(profile: profile)
    }

    // MARK: - Sync

    /// Refresh all data: fetch from connected integrations + local samples, then
    /// recompute insights and the summary.
    func refresh() async {
        isSyncing = true
        defer { isSyncing = false }
        let diag = DiagnosticsLog.shared
        diag.info("Sync", "Refresh started")

        var merged = dataStore.loadManualSamples()
        let fromIntegrations = await registry.syncAllConnected()
        merged.append(contentsOf: fromIntegrations)
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
        // Drop placeholder zeros (e.g. an Oura day with no HR → 0 bpm) so they
        // don't render as "0 bpm" tiles or poison multi-source averages/graphs.
        let beforeSanitise = merged.count
        merged = merged.sanitizedVitals()
        if beforeSanitise != merged.count {
            diag.null("Sanitiser", "Dropped \(beforeSanitise - merged.count) empty/invalid vital sample(s)")
        }
        // Creative reconstruction: turn wearable skin-temperature *deviations*
        // (Oura/Whoop/Hume) into absolute body-temperature samples so they can
        // be trended and fed to the insights.
        samples = TemperatureReconstructor.withReconstructedTemperature(merged)
        logMetricCounts(diag)
        profile = dataStore.loadProfile()
        substanceEvents = dataStore.loadSubstanceEvents()
        recompute()
        todaySummary = await summarizer.summarize(results: results)
        diag.info("Sync", "Refresh complete — \(samples.count) samples, \(results.count) insights")
    }

    /// Record how many samples of each metric were imported this sync — the
    /// per-field pass/fail the Troubleshooting view surfaces.
    private func logMetricCounts(_ diag: DiagnosticsLog) {
        let counts = Dictionary(grouping: samples, by: { $0.type }).mapValues(\.count)
        for type in MetricType.allCases {
            if let c = counts[type], c > 0 {
                diag.ok("Import", "\(c) × \(type.displayName)")
            }
        }
    }

    private func recompute() {
        var out = engine.evaluateAll(samples: samples, profile: profile)
        // Substance impact is data-shaped differently (needs the event log), so
        // it's computed alongside the engine and appended to the card list.
        out.append(SubstanceResponseAnalyzer.insightResult(events: substanceEvents, samples: samples))
        results = out
    }

    // MARK: - Substances

    func logSubstance(_ substance: SubstanceClass, at date: Date = Date(), units: Double? = nil, note: String? = nil) {
        dataStore.addSubstanceEvent(.init(substance: substance, timestamp: date, units: units, note: note))
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
            await refresh()
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
        await refresh()
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
