import Foundation

/// A card as it last stood, small enough to persist and compare.
///
/// Not `InsightResult`: that carries driver lines, requirements and prose, all
/// of which move for reasons that are not a change worth telling anybody about.
/// Three fields is what "did this card change majorly?" actually needs, and
/// keeping it to three is what stops the answer being "yes, every single day".
public struct CardSnapshot: Codable, Sendable, Equatable {
    public let score: Double?
    public let confidence: InsightConfidence
    /// The day the snapshot was taken, so a comparison can say how long ago.
    public let at: Date

    public init(score: Double?, confidence: InsightConfidence, at: Date) {
        self.score = score
        self.confidence = confidence
        self.at = at
    }

    public init(_ result: InsightResult, at: Date) {
        self.init(score: result.score, confidence: result.confidence, at: at)
    }
}

/// How this app's connectors look to the notification layer.
///
/// Deliberately not `HealthIntegration`: that is a `@MainActor` protocol in the
/// app target and this package must stay platform-free. Five plain fields, so
/// the rule can be tested without a network, a keychain or a HealthKit store.
public struct ConnectorSnapshot: Sendable, Equatable {
    public let id: String
    public let displayName: String
    /// The reader has connected it and has not disconnected it.
    public let isConnected: Bool
    /// When it last **brought something back**, which is not the same as when it
    /// was last asked. See `HealthIntegration.syncWarning`.
    public let lastSuccessfulSync: Date?

    public init(id: String, displayName: String, isConnected: Bool,
                lastSuccessfulSync: Date?) {
        self.id = id
        self.displayName = displayName
        self.isConnected = isConnected
        self.lastSuccessfulSync = lastSuccessfulSync
    }
}

/// Everything the triggers read, in one value.
///
/// One struct rather than a dozen arguments because the app builds this on the
/// main actor from `AppModel` and then hands it to a pure pass — and a snapshot
/// with a name is a thing a test can construct, which a dozen arguments is not.
public struct NotificationInputs: Sendable {
    public var now: Date
    public var calendar: Calendar
    /// Today's radar verdict. `nil` on a day the watch could not evaluate —
    /// fewer than two votable signals — which is a *silence*, never a quiet.
    public var radar: SymptomRadarModel.Verdict?
    /// The status the last evaluation saw. `nil` before the first one, which is
    /// treated as "no step has been observed" rather than as quiet: a fresh
    /// install must not open with a symptom alert.
    public var previousRadarStatus: SymptomRadarStatus?
    /// Cut from the same timeline the card draws.
    public var episodes: [SymptomRadarModel.SymptomRadarEpisode]
    public var results: [InsightResult]
    public var previousCards: [InsightID: CardSnapshot]
    public var renewals: [GroundingRenewal]
    public var lastBodyScan: Date?
    public var connectors: [ConnectorSnapshot]

    public init(now: Date,
                calendar: Calendar = .current,
                radar: SymptomRadarModel.Verdict? = nil,
                previousRadarStatus: SymptomRadarStatus? = nil,
                episodes: [SymptomRadarModel.SymptomRadarEpisode] = [],
                results: [InsightResult] = [],
                previousCards: [InsightID: CardSnapshot] = [:],
                renewals: [GroundingRenewal] = [],
                lastBodyScan: Date? = nil,
                connectors: [ConnectorSnapshot] = []) {
        self.now = now
        self.calendar = calendar
        self.radar = radar
        self.previousRadarStatus = previousRadarStatus
        self.episodes = episodes
        self.results = results
        self.previousCards = previousCards
        self.renewals = renewals
        self.lastBodyScan = lastBodyScan
        self.connectors = connectors
    }
}

/// Every rule that can produce a notification, and nothing that decides whether
/// one is sent — that is `NotificationScheduler`'s job, and keeping the two
/// apart is what lets a trigger be written honestly without also having to
/// worry about being annoying.
public enum NotificationTriggers {

    // MARK: - Thresholds, named

    /// A connected source that has brought nothing back for this long is
    /// stalled. Two days rather than one: the reader's ring spends nights on
    /// charge and a provider's nightly job can slip, and a source that misses
    /// one day and catches up has not failed at anything.
    public static let connectorStaleAfter: TimeInterval = 2 * 86_400

    /// How far a card's score must move, on top of crossing a band boundary,
    /// before the move counts as major.
    ///
    /// The boundary alone is not enough. A card sitting on 59.6 and drifting to
    /// 60.2 has crossed from one band to the next and has not changed — and
    /// because the pass runs daily, an unlucky card could straddle a boundary
    /// for a fortnight and send a notification every day it wobbled. Eight
    /// points is wider than the day-to-day noise on every card that has one.
    public static let majorCardMoveFloor: Double = 8

    /// A stretch has to have been over for this long before its end is
    /// reported, so a single quiet morning inside an illness is not announced
    /// as a recovery. `SymptomRadarModel.episodes` already joins across gaps of
    /// up to three days, so this is the matching wait on the reporting side.
    public static let episodeSettledAfterDays = 3

    /// Fifths. Coarse on purpose — this is the resolution at which a score
    /// change is a *different answer* rather than a different number, and a
    /// finer band would make "majorly" mean "at all".
    static func band(_ score: Double) -> Int {
        Swift.min(4, Swift.max(0, Int(score / 20)))
    }

    // MARK: - The pass

    /// Everything true right now that is worth interrupting somebody for.
    ///
    /// `ledger` is read, never written: two rules need to know what has already
    /// been said in order to be *honest* rather than merely non-repetitive —
    /// an episode's end is only reported to somebody who was told its start.
    /// Deduplication itself still happens in the scheduler.
    public static func candidates(_ input: NotificationInputs,
                                  ledger: NotificationLedger) -> [HealthNotification] {
        var out: [HealthNotification] = []
        out += symptoms(input)
        out += episodeOpened(input)
        out += episodeClosed(input, ledger: ledger)
        out += stalledConnectors(input)
        out += staleGrounding(input)
        out += majorCardChange(input)
        out += bodyScanDue(input)
        return out
    }

    // MARK: - 1. Symptoms — the reader's own word for it

    /// Today's verdict stepped **towards** signs.
    ///
    /// ⚠️ **Only ever a step up.** The radar is a detector: 100 means nothing
    /// was detected, which is not a finding and is certainly not good news, so
    /// there is no branch here that fires on the way back to quiet. The one
    /// thing that reports an improvement is `episodeClosed`, and it reports it
    /// as an observation about the signals.
    ///
    /// A `nil` verdict is a day the watch could not evaluate. That is silence,
    /// and silence is not quiet — it must never end a step or start one.
    static func symptoms(_ input: NotificationInputs) -> [HealthNotification] {
        guard let verdict = input.radar else { return [] }
        guard let previous = input.previousRadarStatus else { return [] }
        guard severity(verdict.status) > severity(previous) else { return [] }

        let leaning = verdict.today.leaning.sorted { abs($0.zScore) > abs($1.zScore) }
        let named = leaning.isEmpty
            ? "Several of your signals have"
            : "\(list(leaning.map { $0.metric.inSentence }).capitalizedFirst) have"
        let carried = verdict.isCarriedForward
            ? " They have been away from your normal for more than a day, which is what the score is holding on to."
            : ""

        let strength = verdict.status == .strongSigns ? "Strong signs" : "Some signs"
        return [HealthNotification(
            kind: .symptomsDetected,
            fingerprint: "\(verdict.status.rawValue)|\(day(input.now, input.calendar))",
            title: "\(strength) today — \(leaning.count) signal\(leaning.count == 1 ? "" : "s") leaning",
            body: "\(named) moved the way an immune response pushes them.\(carried) "
                + "This is an observation about your own numbers, not a diagnosis — "
                + "if you feel unwell, that is the better information.",
            insight: .symptomRadar)]
    }

    static func severity(_ status: SymptomRadarStatus) -> Int {
        switch status {
        case .quiet: return 0
        case .someSigns: return 1
        case .strongSigns: return 2
        }
    }

    // MARK: - 2 & 3. A flagged stretch opening and closing

    /// The newest episode began today or yesterday.
    ///
    /// A stretch is the slower claim — that the signals have stayed away rather
    /// than that one morning looked odd — so it is a genuinely different thing
    /// to be told from `symptoms`, and the reader can have either without the
    /// other.
    static func episodeOpened(_ input: NotificationInputs) -> [HealthNotification] {
        guard let episode = input.episodes.max(by: { $0.start < $1.start }) else { return [] }
        let age = days(from: episode.start, to: input.now, input.calendar)
        guard (0...1).contains(age) else { return [] }

        let metrics = episode.leaningMetrics
        let named = metrics.isEmpty ? "Several signals" : list(metrics.map(\.inSentence)).capitalizedFirst
        return [HealthNotification(
            kind: .radarEpisodeOpened,
            fingerprint: "open|\(day(episode.start, input.calendar))",
            title: "A flagged stretch has started",
            body: "\(named) have been away from your own baseline together. "
                + "The radar treats that as one stretch rather than as separate mornings, "
                + "and will tell you when it ends.",
            insight: .symptomRadar)]
    }

    /// A stretch the reader was told the start of has ended.
    ///
    /// ⚠️ **Two constraints, and both are the point.**
    ///
    /// First, the ledger check: an ending is only news to somebody who heard
    /// the beginning. Announcing the end of a stretch nobody was told about
    /// would be the app congratulating itself for a detection it kept quiet.
    ///
    /// Second, the wording. This is the only kind here that reports an
    /// improvement, and it reports **what the signals did** — it does not say
    /// "you're better", because the app does not know that and the reader does.
    static func episodeClosed(_ input: NotificationInputs,
                              ledger: NotificationLedger) -> [HealthNotification] {
        guard let episode = input.episodes.max(by: { $0.end < $1.end }) else { return [] }
        let settled = days(from: episode.end, to: input.now, input.calendar)
        guard settled >= episodeSettledAfterDays else { return [] }
        // Still flagged today? Then nothing has ended, whatever the timeline's
        // last flagged row says.
        if let status = input.radar?.status, status != .quiet { return [] }

        let openID = HealthNotification(
            kind: .radarEpisodeOpened,
            fingerprint: "open|\(day(episode.start, input.calendar))",
            title: "", body: "").id
        guard ledger.hasDelivered(openID) else { return [] }

        let span = Swift.max(1, days(from: episode.start, to: episode.end, input.calendar) + 1)
        let metrics = episode.leaningMetrics
        let named = metrics.isEmpty ? "The signals that were leaning"
                                    : list(metrics.map(\.inSentence)).capitalizedFirst
        return [HealthNotification(
            kind: .radarEpisodeClosed,
            fingerprint: "close|\(day(episode.start, input.calendar))|\(day(episode.end, input.calendar))",
            title: "That flagged stretch has ended",
            body: "\(named) are back inside your own range after \(span) day\(span == 1 ? "" : "s"). "
                + "That is what the readings say; how you feel is your own to judge.",
            insight: .symptomRadar)]
    }

    // MARK: - 4. A source that has stopped syncing

    /// Connected, and nothing back for `connectorStaleAfter`.
    ///
    /// The fingerprint carries the day of the **last successful sync**, not
    /// today, so one stall produces one notification however many times the
    /// background pass notices it — and a source that stalls again next month
    /// is a new finding rather than a suppressed duplicate.
    ///
    /// A connected source that has *never* synced is excluded: that is a
    /// connection the reader made minutes ago, or one that needs a step they
    /// are already mid-way through, and neither is a failure yet.
    static func stalledConnectors(_ input: NotificationInputs) -> [HealthNotification] {
        input.connectors.compactMap { connector in
            guard connector.isConnected, let last = connector.lastSuccessfulSync else { return nil }
            guard input.now.timeIntervalSince(last) >= connectorStaleAfter else { return nil }
            let gap = Swift.max(1, days(from: last, to: input.now, input.calendar))
            return HealthNotification(
                kind: .connectorStalled,
                fingerprint: "\(connector.id)|\(day(last, input.calendar))",
                title: "\(connector.displayName) has stopped syncing",
                body: "It is still connected, but nothing has come back for \(gap) day\(gap == 1 ? "" : "s"). "
                    + "Cards that read it are working from data that old — opening \(connector.displayName) "
                    + "on this phone, or reconnecting it in Settings, is usually enough.")
        }
    }

    // MARK: - 5. A fact that has gone out of date

    /// A **mandatory** grounding fact has lapsed.
    ///
    /// Two deliberate narrowings, both of them the difference between a warning
    /// and a nag:
    ///
    /// - **`.stale` only, not `.expiringSoon`.** The honest moment is the one
    ///   where the number stopped counting as current and a card's confidence
    ///   actually fell — not the fortnight of advance warning, which the
    ///   Grounding screen already shows to anybody who looks.
    /// - **Mandatory only.** An optional fact improves an estimate; a mandatory
    ///   one is the difference between a card having an answer and not. The
    ///   optional ones are a Today row, which is where invitations belong.
    static func staleGrounding(_ input: NotificationInputs) -> [HealthNotification] {
        input.renewals.compactMap { renewal in
            guard renewal.isMandatory, renewal.state == .stale,
                  let recorded = renewal.recordedAt else { return nil }
            return HealthNotification(
                kind: .groundingFactStale,
                fingerprint: "\(renewal.kind.rawValue)|\(day(recorded, input.calendar))",
                title: "\(renewal.kind.displayName) is out of date",
                body: "\(renewal.sentence(asOf: input.now)) "
                    + "It is still being used — an old number beats a population average — "
                    + "but it has stopped buying the cards that need it any confidence.")
        }
    }

    // MARK: - 6. A card changing majorly

    /// The reader's second named ask.
    ///
    /// A band **and** `majorCardMoveFloor` points, so a card resting on a
    /// boundary cannot send one of these every day it wobbles; and the biggest
    /// single move only, so a sync that shifts four cards at once is one
    /// notification rather than four. The rest are still on Today, which is
    /// where a list of changes belongs.
    ///
    /// A card gaining or losing its number entirely is **not** treated as a
    /// major change. That happens whenever a wearable has not synced yet, it
    /// resolves itself by lunchtime, and it is exactly what `isAwaitingTodaysData`
    /// exists to render calmly on the card.
    static func majorCardChange(_ input: NotificationInputs) -> [HealthNotification] {
        struct Move {
            let result: InsightResult
            let from: Double
            let to: Double
            var size: Double { abs(to - from) }
        }
        let moves: [Move] = input.results.compactMap { result in
            guard let score = result.score,
                  let previous = input.previousCards[result.id]?.score else { return nil }
            guard abs(score - previous) >= majorCardMoveFloor,
                  band(score) != band(previous) else { return nil }
            return Move(result: result, from: previous, to: score)
        }
        guard let biggest = moves.max(by: { $0.size < $1.size }) else { return [] }

        let direction = biggest.to > biggest.from ? "up" : "down"
        let points = Int(biggest.size.rounded())
        return [HealthNotification(
            kind: .cardChangedMajorly,
            fingerprint: "\(biggest.result.id.rawValue)|\(band(biggest.from))|\(band(biggest.to))|\(day(input.now, input.calendar))",
            title: "\(biggest.result.title) has moved \(direction)",
            body: "It now reads \(biggest.result.headline), \(points) point\(points == 1 ? "" : "s") "
                + "\(direction) from where it was — a whole band, rather than the usual day-to-day movement. "
                + "The card says which readings did it.",
            insight: biggest.result.id)]
    }

    // MARK: - 7. The next body scan

    /// Overdue only, and only for somebody who scans.
    ///
    /// ⚠️ `BodyScanCadence.State.missing` — never scanned — is deliberately not
    /// here. That is an invitation to try a feature, `SuggestionEngine` ranks
    /// invitations below every grounding gap, and a notification is louder than
    /// every row in that list. `.expiringSoon` is out for the same reason a
    /// grounding fact's is: nothing has happened yet.
    static func bodyScanDue(_ input: NotificationInputs) -> [HealthNotification] {
        guard let last = input.lastBodyScan else { return [] }
        let state = BodyScanCadence.state(lastScan: last, now: input.now, calendar: input.calendar)
        guard state == .overdue,
              let prompt = BodyScanCadence.prompt(lastScan: last, now: input.now,
                                                  calendar: input.calendar)
        else { return [] }
        return [HealthNotification(
            kind: .bodyScanDue,
            fingerprint: "scan|\(day(last, input.calendar))",
            title: prompt.title,
            body: prompt.detail,
            insight: .bodyComposition)]
    }

    // MARK: - Small shared helpers

    /// `2026-08-07`, in the reader's own zone. The fingerprint alphabet — a
    /// locale-formatted date would make a finding's identity depend on the
    /// phone's language, and a ledger keyed on that would forget everything the
    /// day somebody switched region.
    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func days(from: Date, to: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day],
                                from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// "a, b and c" — the same joiner `SuggestionEngine` uses, so a finding
    /// worded twice reads the same both times.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
        }
    }
}
