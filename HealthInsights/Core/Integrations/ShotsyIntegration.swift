import Foundation
import InsightKit

/// Shotsy, as an integration — even though nothing about it is a connection.
///
/// **Why it belongs in the same list as Oura and Withings.** From the reader's
/// side, "where does my data come from" has one answer and it lives in
/// Settings ▸ Integrations. A source that behaves differently is still a
/// source, and hiding it somewhere else because its transport is a file rather
/// than an API would be organising the screen around our implementation
/// instead of around their question. The user asked for exactly this on
/// 2026-08-02.
///
/// What differs is honest and visible rather than papered over: there is no
/// Connect button, because there is nothing to authorise. `sync()` returns
/// nothing, because *we* cannot pull — Shotsy has no API, so the data only ever
/// arrives when the reader pushes it. The status line therefore reports **when
/// a file last arrived**, which is the only truthful thing this integration can
/// say about its own freshness.
@MainActor
final class ShotsyIntegration: HealthIntegration, ObservableObject {
    let id = MetricSource.shotsy.id
    let displayName = "Shotsy"
    let iconSystemName = "syringe.fill"
    let capabilities = IntegrationCapabilities(
        metrics: [.bodyMass, .bodyFatPercentage, .leanBodyMass, .exerciseMinutes],
        requiresBackend: false)

    /// When a Shotsy file was last read successfully, and what it contained.
    private static let lastImportKey = "integration.shotsy.lastImport"
    private static let lastSummaryKey = "integration.shotsy.lastSummary"

    static var lastImportDate: Date? {
        get {
            let stamp = UserDefaults.standard.double(forKey: lastImportKey)
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastImportKey)
        }
    }

    /// The sentence from the last successful import, so the detail screen can
    /// show what actually came across rather than only that something did.
    static var lastImportSummary: String? {
        get { UserDefaults.standard.string(forKey: lastSummaryKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSummaryKey) }
    }

    static func recordImport(summary: String, at date: Date = Date()) {
        lastImportDate = date
        lastImportSummary = summary
    }

    /// Connected once a file has ever arrived; before that there is nothing to
    /// be connected *to*. `lastSync` is the last file, which is what the shared
    /// row already knows how to render.
    var status: IntegrationStatus {
        guard let last = Self.lastImportDate else {
            return .notConnected
        }
        return .connected(lastSync: last)
    }

    /// There is nothing to pull, so there is nothing that can stop pulling.
    /// A gap between exports is the reader's own pace, not a fault to notify
    /// them about — see `HealthIntegration.syncsOnItsOwn`.
    var syncsOnItsOwn: Bool { false }

    /// Nothing to authorise. The reader "connects" this integration by sharing
    /// a file, so a Connect button would be a control that does nothing —
    /// `ShotsyIntegrationView` explains the real gesture instead.
    func connect() async throws {}

    /// Forget that a file ever arrived. Deliberately does **not** delete the
    /// imported readings: they are the reader's own history, and a disconnect
    /// is a statement about the source rather than a request to lose data.
    func disconnect() async {
        Self.lastImportDate = nil
        Self.lastImportSummary = nil
    }

    /// There is no pull. Shotsy has no API — that is the entire reason this is
    /// file-based — so a sync can only ever return what it already has, which
    /// is nothing new.
    func sync() async throws -> SyncedData { SyncedData() }
}
