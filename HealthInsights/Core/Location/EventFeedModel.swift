import Foundation
import InsightKit
import Observation

/// **The event-confirmation feed's state** — backlog P32.
///
/// Detection, storage and the reader's answers, joined. The arithmetic all lives
/// in InsightKit (`FlaggedEventDetector`, `EventConfirmationFeed`,
/// `FlaggedEventAccuracy`) where it is tested on Linux; this is the part that
/// needs a phone: it reaches Core Location for a place and `UserDefaults` for
/// what the reader has already said.
///
/// ## Why it is not a stored property on `AppModel`
///
/// `AppModel` is three thousand lines and eleven agents deep, and this feature
/// needs nothing from it but two arrays. Adding a stored property there would
/// have meant editing the file every other change also edits, for no gain — the
/// precedent is `LocationCapture.shared` and `DiagnosticsLog.shared`, both of
/// which own a facility rather than a slice of the reader's record.
///
/// The couplings that remain are deliberately three lines: `recompute()` hands
/// it the samples, `usedInputs` and `standing(for:)` read its counts.
@MainActor
@Observable
final class EventFeedModel {

    static let shared = EventFeedModel()

    /// What the reader sees. Rebuilt whenever detection runs or an answer lands.
    private(set) var feed: EventConfirmationFeed

    /// How much heart-rate history the detector still wants. Nil once met — a
    /// met gate says nothing.
    private(set) var historyGate: CoverageGate?

    /// True once detection has run at least once this launch. Distinguishes
    /// *"nothing to ask about"* from *"the app has not looked yet"*, which the
    /// feed must not render the same way.
    private(set) var hasRun = false

    private let store: EventFeedStore
    private let location: LocationCapture

    /// What the last detection pass was run against. See `detect`.
    ///
    /// `@ObservationIgnored` because it is bookkeeping, not state anything
    /// draws — observing it would make every skipped pass invalidate a view.
    @ObservationIgnored private var lastSignature: Signature?

    private struct Signature: Equatable, Sendable {
        let sampleCount: Int
        let newestSample: Date?
        let substanceCount: Int
        /// So a phone left open overnight re-runs: `now` moves the reference
        /// window, and yesterday's answer to "is this within 28 days" is not
        /// today's.
        let day: Date
    }

    init(store: EventFeedStore = .standard,
         location: LocationCapture = .shared) {
        self.store = store
        self.location = location
        let judgements = store.loadJudgements()
        let answered = Set(judgements.filter(\.isReviewed).map(\.eventID))
        // Reading events runs the retention sweep — see `EventFeedStore`.
        let events = store.loadEvents(answeredIDs: answered)
        self.feed = EventConfirmationFeed.assemble(events: events,
                                                   judgements: judgements,
                                                   historyGate: nil)
    }

    /// What the app is allowed to observe. Read by the feed's own copy and by
    /// the dismissible suggestion.
    var access: LocationAccess { location.access }

    var pendingCount: Int { feed.pending.count }
    var anchors: PlaceAnchorSet { location.anchors }
    var canUpgradeToBackgroundVisits: Bool { location.canUpgradeToBackgroundVisits }

    // MARK: - Detection

    /// Re-run the detector and rejoin everything.
    ///
    /// Called from `AppModel.recompute()`, so the feed moves with the data
    /// rather than only when somebody opens it.
    ///
    /// ⚠️ **A stored event's place is never recomputed.** A place was observed
    /// once and then deliberately forgotten; re-deriving it from wherever the
    /// phone is *now* would put today's position on last Tuesday's event, which
    /// is the one way this feature could actively mislead. So a re-detected
    /// event inherits the place already stored, and only a genuinely new one
    /// asks `LocationCapture` for a fix.
    /// ⚠️ **Nothing here runs on the main actor except the parts that cannot
    /// leave it.** `recompute()` has thirty-three call sites, and until
    /// 2026-08-09 every one of them paid, *inline*, for a full-history `max` to
    /// build the signature and — whenever it changed — a whole detection pass.
    /// Measured on the reader's own 379,693 samples: **36 ms + 161 ms
    /// unoptimised**, which is what the phone runs (`deploy.yml` builds
    /// `-configuration Debug`). Both are pure functions of `samples`, so both
    /// are now computed off the actor and only the `UserDefaults` round trips,
    /// the location lookup and the two published properties come back to it.
    ///
    /// The generation guard is `AppModel`'s, for `AppModel`'s reason: a pass
    /// built from samples that have since been replaced must not overwrite one
    /// built from the samples on screen.
    func detect(samples: [HealthMetricSample],
                substanceEvents: [SubstanceEvent],
                now: Date = Date()) {
        detectGeneration &+= 1
        let generation = detectGeneration
        // Read here, passed in: the signature guard has to run *inside* the
        // detached task — a guard evaluated on the main actor would first have
        // to build the signature there, which is the `max` this is escaping.
        let previous = lastSignature
        detectTask?.cancel()
        detectTask = Task { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) { () -> Detection? in
                // The signature is deliberately cheap and deliberately
                // *conservative*: it changes whenever a sample is added,
                // removed or replaced, whenever the substance log moves, and
                // whenever the day turns. It cannot detect a same-count edit
                // that leaves the newest sample where it was — and that is
                // fine, because `AppModel` replaces the whole array on every
                // ingest rather than mutating it in place, so a silent
                // same-count edit is not a state this app reaches.
                let signature = Signature(
                    sampleCount: samples.count,
                    newestSample: samples.max(by: { $0.start < $1.start })?.start,
                    substanceCount: substanceEvents.count,
                    day: Calendar.current.startOfDay(for: now))
                guard signature != previous else { return nil }
                return Detection(
                    signature: signature,
                    events: FlaggedEventDetector.detect(samples: samples,
                                                        substanceEvents: substanceEvents,
                                                        now: now),
                    gate: FlaggedEventDetector.referenceGate(samples: samples, now: now))
            }.value
            guard let self, let computed, !Task.isCancelled,
                  self.detectGeneration == generation else { return }
            self.apply(computed, now: now)
        }
    }

    @ObservationIgnored private var detectGeneration = 0
    @ObservationIgnored private var detectTask: Task<Void, Never>?

    /// Everything the detached pass produced, in one `Sendable` parcel — the
    /// same shape, and for the same reason, as `AppModel.HydratedState`.
    private struct Detection: Sendable {
        let signature: Signature
        let events: [FlaggedEvent]
        let gate: CoverageGate?
    }

    /// The half that needs the main actor: `UserDefaults`, Core Location, and
    /// the two published properties the feed draws from.
    private func apply(_ detection: Detection, now: Date) {
        lastSignature = detection.signature

        let judgements = store.loadJudgements()
        let answered = Set(judgements.filter(\.isReviewed).map(\.eventID))
        let known = Dictionary(store.loadEvents(answeredIDs: answered, now: now)
            .map { ($0.id, $0) }) { a, _ in a }

        let placed = detection.events.map { event -> FlaggedEvent in
            if let existing = known[event.id] {
                return event.at(existing.place)
            }
            return event.at(location.place(forEventAt: event.start, now: now))
        }
        // Swept before storage as well as on the way out: an event detected
        // today for a window three weeks old must not be written with a fresh
        // coordinate attached to it.
        let swept = FlaggedEventRetention.sweep(events: placed,
                                                answeredIDs: answered, now: now)
        store.save(events: swept)

        historyGate = detection.gate
        feed = EventConfirmationFeed.assemble(events: swept, judgements: judgements,
                                              historyGate: historyGate, now: now)
        hasRun = true
    }

    /// A single fix, because the reader opened the feed. See
    /// `LocationCapture.takeForegroundFix()` for why this exists at all.
    func feedOpened() {
        location.takeForegroundFix()
    }

    // MARK: - The reader's answer

    /// Record what the reader said.
    ///
    /// ⚠️ **Two things happen here and both are load-bearing.** The answer goes
    /// into `FlaggedEventJudgement`, which keeps it apart from the guess so the
    /// accuracy figure means something — and the event's coordinate is dropped,
    /// because the job it was collected for is now finished. The second is not a
    /// tidy-up: it is the term on which `PlaceContext` was allowed to hold a
    /// position in the first place.
    ///
    /// - Parameters:
    ///   - correction: What it actually was. Nil with `confirmed: true` means
    ///     "your guess was right"; the two are different records and both are
    ///     kept.
    func answer(_ event: FlaggedEvent, correction: EventCause?,
                note: String? = nil, confirmed: Bool, now: Date = Date()) {
        var judgements = store.loadJudgements()
        let existing = judgements.first { $0.eventID == event.id }
            ?? FlaggedEventJudgement(pending: event)
        let updated = existing.reviewed(correction: correction, note: note,
                                        confirmed: confirmed, at: now)
        judgements.removeAll { $0.eventID == event.id }
        judgements.append(updated)
        store.save(judgements: judgements)

        let answered = Set(judgements.filter(\.isReviewed).map(\.eventID))
        var events = store.loadEvents(answeredIDs: answered, now: now)
        // Re-read rather than reusing the in-memory copy: `loadEvents` has just
        // applied the sweep, and this is the write that makes the deletion
        // durable rather than a filter on the way out.
        events = FlaggedEventRetention.sweep(events: events, answeredIDs: answered, now: now)
        store.save(events: events)

        feed = EventConfirmationFeed.assemble(events: events, judgements: judgements,
                                              historyGate: historyGate, now: now)
    }

    /// Ask about a question again — the answer is cleared, the guess is not.
    ///
    /// The way out of a mistap, and the only route back into `pending` once
    /// something has been answered. ⚠️ **The place does not come back**: the
    /// coordinate was deleted when they answered, and this app does not have a
    /// second copy to restore from. That is the design working, and the sheet
    /// says so rather than showing an empty map.
    func reopen(_ event: FlaggedEvent, now: Date = Date()) {
        var judgements = store.loadJudgements()
        judgements.removeAll { $0.eventID == event.id }
        store.save(judgements: judgements)
        let answered = Set(judgements.filter(\.isReviewed).map(\.eventID))
        let events = store.loadEvents(answeredIDs: answered, now: now)
        feed = EventConfirmationFeed.assemble(events: events, judgements: judgements,
                                              historyGate: historyGate, now: now)
    }

    // MARK: - Permission

    func requestWhileUsing() { location.requestWhileUsing() }
    func requestBackgroundVisits() { location.requestBackgroundVisits() }

    // MARK: - Erasing

    /// Forget every anchor. The questions and answers stay.
    func forgetAllPlaces() {
        location.forgetAllPlaces()
    }

    /// Forget the lot — anchors, questions and the reader's own answers.
    ///
    /// ⚠️ **It really does destroy the corrections**, and the control that calls
    /// it says so. A "clear" that quietly kept the labelled set would be the app
    /// deciding which of the reader's data it is allowed to hold onto, which is
    /// the opposite of what this whole feature is built to demonstrate.
    func forgetEverything() {
        store.forgetEverything()
        location.forgetAllPlaces()
        historyGate = nil
        // ⚠️ Without this the next `detect` would skip on an unchanged signature
        // and leave the feed permanently empty — the memo would have turned a
        // deletion into an outage.
        lastSignature = nil
        feed = EventConfirmationFeed.assemble(events: [], judgements: [],
                                              historyGate: nil)
    }
}
