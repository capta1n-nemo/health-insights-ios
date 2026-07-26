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
    private(set) var profile: UserHealthProfile
    private(set) var results: [InsightResult] = []
    private(set) var todaySummary: String = ""
    private(set) var isSyncing = false
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

    var outstandingGrounding: [(requirement: GroundingRequirement, status: RequirementStatus)] {
        engine.outstandingGrounding(profile: profile)
    }

    // MARK: - Sync

    /// Refresh all data: fetch from connected integrations + local samples, then
    /// recompute insights and the summary.
    func refresh() async {
        isSyncing = true
        defer { isSyncing = false }

        var merged = dataStore.loadManualSamples()
        let fromIntegrations = await registry.syncAllConnected()
        merged.append(contentsOf: fromIntegrations)
        samples = merged
        profile = dataStore.loadProfile()
        recompute()
        todaySummary = await summarizer.summarize(results: results)
    }

    private func recompute() {
        results = engine.evaluateAll(samples: samples, profile: profile)
    }

    func result(for id: InsightID) -> InsightResult? {
        results.first { $0.id == id }
    }

    // MARK: - Integrations

    func connect(_ integration: any HealthIntegration) async {
        try? await integration.connect()
        if case .connected = integration.status {
            dataStore.setIntegration(id: integration.id, connected: true, lastSync: nil)
            await refresh()
        }
    }

    func disconnect(_ integration: any HealthIntegration) async {
        await integration.disconnect()
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
