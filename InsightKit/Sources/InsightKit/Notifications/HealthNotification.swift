import Foundation

/// What the app is allowed to interrupt somebody for.
///
/// ⚠️ **This app does not nag.** `SuggestionEngine` ranks *"a feature you
/// haven't tried"* below every grounding gap for that reason, and a
/// notification is a far louder surface than a row on Today — so the list here
/// is deliberately shorter than the suggestion list, and two whole categories
/// that *are* on Today are absent from it on purpose:
///
/// - **Nothing that says a card is fine.** ⚠️ *A detector is never the good
///   news.* The symptom radar reading 100 means nothing was **detected**, which
///   is not the same claim as "you are well" — so `.symptomsDetected` fires
///   only on a step *towards* signs and never on the way back to quiet.
///   `.radarEpisodeClosed` is the one kind that reports an improvement, and it
///   reports it as an **observation about the signals** rather than as
///   congratulation; `NotificationCopyTests` holds that line.
/// - **Nothing the reader has simply never used.** A first body scan, an
///   unconnected wearable and an untried input are all invitations, and an
///   invitation is a Today row. `.bodyScanDue` therefore fires only for
///   somebody who has scanned before and whose *trend now has a hole in it*.
///
/// Every case is either something the reader named — **symptoms**, and **a card
/// changing majorly** — or one of the four added under the creative authority
/// they granted alongside those two.
public enum HealthNotificationKind: String, Codable, Sendable, CaseIterable {
    /// Today's radar verdict stepped up: quiet → some signs, or some signs →
    /// strong signs. The reader's own word for this is **symptoms**.
    case symptomsDetected
    /// A flagged stretch has begun — the slower, multi-day statement that a
    /// single morning cannot make.
    case radarEpisodeOpened
    /// A flagged stretch we announced the start of has ended.
    case radarEpisodeClosed
    /// A source that is still connected has stopped bringing anything back.
    /// Silent data loss is the failure this app is least able to see for
    /// itself, and every card downstream degrades without saying why.
    case connectorStalled
    /// A fact a card cannot sense has lapsed — the cuff reading the blood
    /// pressure estimate needs, and its like.
    case groundingFactStale
    /// A card's score has moved a full band. The reader's second named ask.
    case cardChangedMajorly
    /// The body-scan interval has passed for somebody who scans.
    case bodyScanDue

    /// Delivery order when the daily cap bites, lowest first.
    ///
    /// The ranking is the same judgement `SuggestionEngine` makes: **something
    /// happening to the body outranks something wrong with the plumbing, which
    /// outranks a number moving, which outranks a reminder.** A stalled
    /// connector sits second rather than last because a card starved of data
    /// still prints a number, and a wrong number is worse than a missing one.
    public var rank: Int {
        switch self {
        case .symptomsDetected: return 0
        case .radarEpisodeOpened: return 1
        case .connectorStalled: return 2
        case .groundingFactStale: return 3
        case .cardChangedMajorly: return 4
        case .radarEpisodeClosed: return 5
        case .bodyScanDue: return 6
        }
    }

    /// What the settings screen calls it.
    public var displayName: String {
        switch self {
        case .symptomsDetected: return "Symptoms"
        case .radarEpisodeOpened: return "A flagged stretch starting"
        case .radarEpisodeClosed: return "A flagged stretch ending"
        case .connectorStalled: return "A source that has stopped syncing"
        case .groundingFactStale: return "A fact that has gone out of date"
        case .cardChangedMajorly: return "A card changing a lot"
        case .bodyScanDue: return "Your next body scan"
        }
    }

    /// What the reader is agreeing to, said plainly, in the settings row.
    public var explanation: String {
        switch self {
        case .symptomsDetected:
            return "When several of your vitals lean the way an immune response pushes them on the same day. An observation about your own numbers, never a diagnosis."
        case .radarEpisodeOpened:
            return "When those signals have stayed away from your normal long enough to count as a stretch rather than a morning."
        case .radarEpisodeClosed:
            return "When a stretch you were told about has ended. Only ever sent for one you were told the start of."
        case .connectorStalled:
            return "When a connected source is still connected but has brought nothing back for two days. Cards keep printing numbers from stale data otherwise."
        case .groundingFactStale:
            return "When something a card needs from you — a cuff reading, a blood test — has passed its freshness window and stopped counting as current."
        case .cardChangedMajorly:
            return "When a card's score moves a whole band. Small day-to-day movement never sends anything."
        case .bodyScanDue:
            return "When it has been longer than your scan interval and the measurements trend has a gap in it. Never sent if you have never scanned."
        }
    }

    /// How long after one of these before another of the same kind may be sent.
    ///
    /// A floor under the fingerprint check rather than a replacement for it:
    /// deduplication stops the *same* finding being sent twice, and this stops
    /// a run of *different* findings of one kind becoming a stream. The values
    /// are the shortest interval at which each kind could still say something
    /// new — the radar re-evaluates daily, a body scan is monthly.
    public var minimumInterval: TimeInterval {
        switch self {
        case .symptomsDetected: return 20 * 3600      // at most one a day
        case .radarEpisodeOpened: return 3 * 86_400
        case .radarEpisodeClosed: return 3 * 86_400
        case .connectorStalled: return 3 * 86_400
        case .groundingFactStale: return 7 * 86_400
        case .cardChangedMajorly: return 3 * 86_400
        case .bodyScanDue: return 7 * 86_400
        }
    }

    /// Whether it is on before the reader has said anything.
    ///
    /// The two the reader named are on. So is a stalled connector, because it
    /// is the only kind here that reports the app being **wrong** rather than
    /// the body being interesting. The rest are opt-in: they were added under
    /// creative authority, and something nobody asked for should not arrive
    /// unasked.
    public var isOnByDefault: Bool {
        switch self {
        case .symptomsDetected, .cardChangedMajorly, .connectorStalled: return true
        case .radarEpisodeOpened, .radarEpisodeClosed, .groundingFactStale, .bodyScanDue: return false
        }
    }

    /// Grouping key for the system's notification list, so three findings about
    /// the radar stack together rather than reading as three separate alarms.
    public var threadIdentifier: String {
        switch self {
        case .symptomsDetected, .radarEpisodeOpened, .radarEpisodeClosed: return "radar"
        case .connectorStalled: return "sources"
        case .groundingFactStale, .bodyScanDue: return "grounding"
        case .cardChangedMajorly: return "cards"
        }
    }
}

/// One finding, ready to be delivered.
///
/// `fingerprint` identifies the **finding**, not the delivery — "the stretch
/// that started on 3 August", not "the alert sent at 09:12". That is what lets
/// the same evaluation run every two hours in the background without the reader
/// hearing about one thing seven times: `NotificationLedger` remembers the
/// fingerprint, and a candidate whose fingerprint is already in it is dropped
/// before the cap or the quiet hours are even consulted.
public struct HealthNotification: Sendable, Equatable, Identifiable {
    public let kind: HealthNotificationKind
    public let fingerprint: String
    public let title: String
    public let body: String
    /// Where tapping it should land, as an in-app route. `nil` opens Today.
    public let insight: InsightID?

    /// Stable across evaluations, and the key the ledger stores.
    public var id: String { "\(kind.rawValue)|\(fingerprint)" }

    public init(kind: HealthNotificationKind, fingerprint: String,
                title: String, body: String, insight: InsightID? = nil) {
        self.kind = kind
        self.fingerprint = fingerprint
        self.title = title
        self.body = body
        self.insight = insight
    }
}
