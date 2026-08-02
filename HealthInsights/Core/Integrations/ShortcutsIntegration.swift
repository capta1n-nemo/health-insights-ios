import Foundation
import InsightKit

/// A Shortcuts automation the reader installs, as an integration.
///
/// **Why this is a first-class integration and not a settings toggle.** From the
/// reader's side "where does my data come from" has one answer, and it is
/// Settings ▸ Integrations. This source behaves differently from Oura — there is
/// no account, no token, and the app cannot pull — but it is still a source, and
/// filing it elsewhere because its transport is a URL would organise the screen
/// around our implementation rather than their question. Same argument
/// `ShotsyIntegration` already makes for a file.
///
/// **What it is for.** The most interesting signals on a phone are the ones iOS
/// will not hand an app: Screen Time is sandboxed outright, calendar density
/// needs full calendar access, barometric pressure needs a paid entitlement.
/// Shortcuts can reach all of them, and it can call a URL. So one automation,
/// installed once and run on a schedule, collects what the app cannot and hands
/// it over — and because `ShortcutIngest` accepts **any** `MetricType`, the same
/// automation keeps working as new signals are added, with no update to either
/// side.
///
/// Like Shotsy, the honest freshness claim is **when the shortcut last ran**,
/// because nothing here can pull.
@MainActor
final class ShortcutsIntegration: HealthIntegration, ObservableObject {
    let id = MetricSource.shortcuts.id
    let displayName = "Shortcuts"
    let iconSystemName = "square.stack.3d.up.fill"
    /// Deliberately open-ended: the transport carries whatever the reader's
    /// automation collects, so naming a fixed set here would be a claim the
    /// mechanism does not make. Screen time is the one the app ships a recipe
    /// for.
    let capabilities = IntegrationCapabilities(
        metrics: [.screenTimeMinutes],
        requiresBackend: false)

    private static let lastRunKey = "integration.shortcuts.lastRun"
    private static let lastSummaryKey = "integration.shortcuts.lastSummary"

    /// When the shortcut last delivered anything.
    static var lastRunDate: Date? {
        get {
            let stamp = UserDefaults.standard.double(forKey: lastRunKey)
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastRunKey)
        }
    }

    /// What the last run carried, so the detail screen can show that the right
    /// things are arriving rather than only that something did — and can name a
    /// key the automation got wrong.
    static var lastRunSummary: String? {
        get { UserDefaults.standard.string(forKey: lastSummaryKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSummaryKey) }
    }

    static func recordRun(summary: String, at date: Date = Date()) {
        lastRunDate = date
        lastRunSummary = summary
    }

    /// Connected once the shortcut has ever delivered. Before that there is
    /// nothing to be connected *to* — installing a shortcut is something the
    /// reader does in Shortcuts, and the app only finds out when it runs.
    var status: IntegrationStatus {
        guard let last = Self.lastRunDate else { return .notConnected }
        return .connected(lastSync: last)
    }

    /// Nothing to authorise: the reader "connects" this by installing an
    /// automation, so a Connect button would be a control that does nothing.
    /// `ShortcutsIntegrationView` walks them through the real gesture.
    func connect() async throws {}

    /// Forget that it ever ran. Does **not** delete the readings it delivered —
    /// they are the reader's own history, and disconnecting a source is not a
    /// request to lose data. The same rule Shotsy follows.
    func disconnect() async {
        Self.lastRunDate = nil
        Self.lastRunSummary = nil
    }

    /// There is no pull. The automation runs on the reader's schedule and calls
    /// us; we cannot ask it for anything.
    func sync() async throws -> SyncedData { SyncedData() }
}
