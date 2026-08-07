import Foundation
import UserNotifications
import InsightKit

/// Everything the notification pass needs to remember between runs, plus the
/// one call that runs it.
///
/// ## Why this is not on `AppModel`
///
/// It holds four pieces of state — the reader's policy, the delivery ledger,
/// the radar status last seen and the cards as they last stood — and all four
/// are only ever read by this pass. `AppModel` is 160 KB and a dozen agents
/// deep; a self-contained coordinator keeps the whole feature to two new files
/// and one line in `performRefresh`.
///
/// ## The order of operations, which is the point of the row
///
/// The reader's sequencing was **background delivery first, then notifications
/// on top**, and this is where that lands: `evaluate(_:)` is called from the
/// end of every refresh, and a refresh now happens on a `BGAppRefreshTask`
/// (`BackgroundRefresh`) as well as when somebody opens the app. Everything
/// here is therefore written for a caller that may run at 03:00 with the phone
/// in a pocket — which is why the trigger pass is stateless and the ledger is
/// not, and why quiet hours *hold* rather than drop.
@MainActor
@Observable
final class NotificationCoordinator {

    static let shared = NotificationCoordinator()

    // MARK: - Persisted state

    /// What the reader has switched on. `UserDefaults`-backed and mirrored in a
    /// stored property for the same reason `AppModel.bodyScanPolicy` is: the
    /// defaults are invisible to SwiftUI observation, and a settings toggle
    /// that does not move when tapped is that defect one layer over.
    private(set) var policy: NotificationPolicy = NotificationCoordinator.load(Keys.policy) ?? .standard

    /// What has already been said. See `NotificationLedger` — this is the piece
    /// that makes a stateless trigger pass safe to run on a background schedule.
    private(set) var ledger: NotificationLedger = NotificationCoordinator.load(Keys.ledger) ?? NotificationLedger()

    /// The radar status the last evaluation saw, so a *step* can be detected
    /// rather than a state. `nil` before the first pass, which is deliberately
    /// treated as "no step observed" — a fresh install must not open with a
    /// symptom alert.
    private(set) var lastRadarStatus: SymptomRadarStatus? = {
        UserDefaults.standard.string(forKey: Keys.radarStatus)
            .flatMap(SymptomRadarStatus.init(rawValue:))
    }()

    /// Each card as it last stood. Only score and confidence — see
    /// `CardSnapshot` for why comparing the whole `InsightResult` would report
    /// a change every single day.
    private(set) var lastCards: [String: CardSnapshot] = NotificationCoordinator.load(Keys.cards) ?? [:]

    private enum Keys {
        static let policy = "notifications.policy"
        static let ledger = "notifications.ledger"
        static let radarStatus = "notifications.lastRadarStatus"
        static let cards = "notifications.lastCards"
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Settings

    func setPolicy(_ policy: NotificationPolicy) {
        self.policy = policy
        Self.save(policy, Keys.policy)
    }

    func setKind(_ kind: HealthNotificationKind, enabled: Bool) {
        setPolicy(policy.enabling(kind, enabled))
    }

    // MARK: - The pass

    /// How much history the episode cut is taken over.
    ///
    /// The card's own grading window, so a stretch this pass calls "open" is
    /// the same stretch the Sick days section draws. A shorter window would be
    /// cheaper and would let the two disagree about where an episode started,
    /// which is the kind of divergence nobody notices until the reader does.
    static let episodeWindowDays = SymptomRadarModel.ledgerDays

    /// Look at everything, decide, post, and remember.
    ///
    /// ⚠️ **It runs even when the reader has denied permission**, against
    /// `NotificationPolicy.silent`. That is not wasted work: the pass is also
    /// what advances `lastRadarStatus` and `lastCards`, and skipping it would
    /// mean that the moment somebody switched notifications on, every
    /// accumulated difference since install would read as having just happened.
    func evaluate(_ model: AppModel, now: Date = Date()) async {
        await NotificationCentre.shared.refreshAuthorization()
        let authorised = NotificationCentre.shared.authorization == .authorized
            || NotificationCentre.shared.authorization == .provisional
        let effective = authorised ? policy : .silent

        let input = await inputs(model, now: now)
        let candidates = NotificationTriggers.candidates(input, ledger: ledger)
        let decision = NotificationScheduler.decide(
            candidates: candidates, policy: effective, ledger: ledger, now: now)

        if !decision.scheduled.isEmpty {
            await NotificationCentre.shared.post(decision.scheduled, now: now)
            var updated = ledger
            for item in decision.scheduled {
                updated.record(item.notification, at: item.deliverAt)
            }
            updated.pruned(asOf: now)
            ledger = updated
            Self.save(updated, Keys.ledger)
        }

        // Recorded whatever happened, so "why did I not get one?" has an
        // answer in the diagnostics rather than in somebody's memory.
        if !candidates.isEmpty {
            DiagnosticsLog.shared.info(
                "Notifications",
                "\(decision.scheduled.count) sent, \(decision.suppressed.count) held back",
                detail: (decision.scheduled.map { "· sent \($0.notification.kind.rawValue) — \($0.notification.title)" }
                         + decision.suppressed.map { "· held \($0.notification.kind.rawValue) — \($0.reason.rawValue)" })
                    .joined(separator: "\n"))
        }

        remember(input)
    }

    /// Snapshot what this pass saw, so the next one can spot a change.
    private func remember(_ input: NotificationInputs) {
        if let status = input.radar?.status {
            lastRadarStatus = status
            UserDefaults.standard.set(status.rawValue, forKey: Keys.radarStatus)
        }
        // ⚠️ A day the watch could not evaluate leaves the stored status alone.
        // Writing "no verdict" would turn the next real verdict into a step
        // from nothing, and a missing night is not a recovery — the same rule
        // `SymptomRadarModel.accumulation` applies to the CUSUM.

        guard !input.results.isEmpty else { return }
        var cards = lastCards
        for result in input.results {
            // Only a card with a number updates its snapshot. A card whose
            // wearable has not synced yet loses its score for a few hours every
            // morning, and storing that would compare tomorrow against the gap
            // rather than against yesterday's answer.
            guard result.score != nil else { continue }
            cards[result.id.rawValue] = CardSnapshot(result, at: input.now)
        }
        lastCards = cards
        Self.save(cards, Keys.cards)
    }

    // MARK: - Reading the app

    /// Build the pure input from the live model.
    ///
    /// The radar timeline is the expensive part — one `HealthWatchModel`
    /// evaluation per day over the window — so it runs off the main actor. That
    /// matters more here than it does on the card: this can be called from a
    /// `BGAppRefreshTask` whose whole budget is measured in tens of seconds.
    private func inputs(_ model: AppModel, now: Date) async -> NotificationInputs {
        let samples = model.samples
        let calendar = Calendar.current
        let window = Self.episodeWindowDays

        let radar = await Task.detached(priority: .utility) { () -> (SymptomRadarModel.Verdict?, [SymptomRadarModel.SymptomRadarEpisode]) in
            let timeline = SymptomRadarModel.timeline(samples: samples, days: window,
                                                      endingAt: now, calendar: calendar)
            let episodes = SymptomRadarModel.episodes(in: timeline, calendar: calendar)
            guard let today = HealthWatchModel.evaluate(samples: samples, now: now,
                                                        calendar: calendar) else {
                return (nil, episodes)
            }
            return (SymptomRadarModel.verdict(today: today, timeline: timeline), episodes)
        }.value

        var cards: [InsightID: CardSnapshot] = [:]
        for (raw, snapshot) in lastCards {
            guard let id = InsightID(rawValue: raw) else { continue }
            cards[id] = snapshot
        }

        return NotificationInputs(
            now: now,
            calendar: calendar,
            radar: radar.0,
            previousRadarStatus: lastRadarStatus,
            episodes: radar.1,
            results: model.results,
            previousCards: cards,
            renewals: model.engine.groundingRenewals(profile: model.profile),
            lastBodyScan: model.bodyScans.map(\.capturedAt).max(),
            connectors: connectors(model))
    }

    /// What each connected source has actually delivered.
    ///
    /// ⚠️ **The freshness measured is the *data's*, not the sync call's.**
    /// `IntegrationStatus.connected(lastSync:)` is set after a `sync()` that
    /// did not throw — and `HealthIntegration.syncWarning` exists precisely
    /// because a provider whose grant has lapsed returns normally with nothing
    /// in it, leaving a green tick and "synced 22 seconds ago". The newest
    /// reading actually held from a source is the only thing that cannot lie
    /// about this, and it is also the thing the reader cares about: a ring that
    /// authenticates perfectly and last measured them on Tuesday is stale
    /// whatever its status line says.
    ///
    /// Sources that cannot pull are excluded — see
    /// `HealthIntegration.syncsOnItsOwn`. Shotsy has no API and Shortcuts is an
    /// automation the reader owns; telling somebody a push-only source "has
    /// stopped syncing" would be blaming the app's plumbing for a file they
    /// simply have not exported yet.
    private func connectors(_ model: AppModel) -> [ConnectorSnapshot] {
        var newest: [String: Date] = [:]
        for sample in model.samples {
            let id = sample.source.id
            if let existing = newest[id], existing >= sample.start { continue }
            newest[id] = sample.start
        }
        for sample in model.otherSamples {
            let id = sample.source.id
            if let existing = newest[id], existing >= sample.start { continue }
            newest[id] = sample.start
        }

        return model.registry.integrations.compactMap { integration in
            guard integration.syncsOnItsOwn else { return nil }
            guard case .connected = integration.status else { return nil }
            return ConnectorSnapshot(id: integration.id,
                                     displayName: integration.displayName,
                                     isConnected: true,
                                     lastSuccessfulSync: newest[integration.id])
        }
    }
}
