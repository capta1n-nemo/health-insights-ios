import Foundation
import InsightKit

/// **Where the reader's handful of anchors lives, and nothing else.**
///
/// `UserDefaults` rather than SwiftData, for the reason `AppModel` already
/// stores the type-sighting ledger and the tag mappings there: it is a small
/// bounded value read on launch, not a growing table anything queries. The bound
/// is the point — `PlaceAnchorSet` caps itself at twelve, so this file cannot
/// grow into a location history however long the app is used.
///
/// ⚠️ **Standard `UserDefaults`, not the App Group suite.** The app has an App
/// Group entitlement and the widget/extension side can read that suite. Anchors
/// are the most sensitive thing this feature holds, nothing outside the app
/// needs them, and the narrowest container that works is the right one. If a
/// future extension genuinely needs a familiarity, it should be handed the
/// *answer* (`PlaceFamiliarity`, one of four words) rather than the anchors.
struct PlaceAnchorStore {

    static let standard = PlaceAnchorStore()

    private let defaults: UserDefaults
    private let key = "location.placeAnchors.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PlaceAnchorSet {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(PlaceAnchorSet.self, from: data)
        else { return PlaceAnchorSet() }
        return decoded
    }

    func save(_ set: PlaceAnchorSet) {
        // An empty set clears the key rather than writing `[]`. "The reader
        // pressed forget" should leave nothing behind, not a tidy empty record
        // that says they once had places.
        guard !set.anchors.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(set) else { return }
        defaults.set(data, forKey: key)
    }
}

/// **The reader's answers to flagged events, and the events still waiting.**
///
/// Two collections, and the split is the whole design:
///
/// - **`judgements` are kept.** They are what the reader said, they are the
///   labelled set the accuracy figure is computed from, and nothing recomputes
///   them. Losing one loses a correction the app cannot get back.
/// - **`events` are a cache.** The detector rebuilds them from samples on every
///   refresh. They are stored only so a *place* — which cannot be recomputed,
///   because it was observed once and then thrown away — survives a launch, and
///   they are swept by `FlaggedEventRetention` every time they are loaded.
///
/// ⚠️ **The sweep is on the read path deliberately.** A retention rule that runs
/// only when somebody remembers to call it is not a retention rule; putting it
/// here means a coordinate cannot outlive its fortnight even if every other code
/// path is forgotten.
struct EventFeedStore {

    static let standard = EventFeedStore()

    private let defaults: UserDefaults
    private let judgementsKey = "flaggedEvents.judgements.v1"
    private let eventsKey = "flaggedEvents.pendingEvents.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadJudgements() -> [FlaggedEventJudgement] {
        guard let data = defaults.data(forKey: judgementsKey),
              let decoded = try? JSONDecoder().decode([FlaggedEventJudgement].self, from: data)
        else { return [] }
        return decoded
    }

    func save(judgements: [FlaggedEventJudgement]) {
        guard let data = try? JSONEncoder().encode(judgements) else { return }
        defaults.set(data, forKey: judgementsKey)
    }

    /// Stored events, **already swept**. See the type comment: a caller cannot
    /// read a coordinate that should have expired, because there is no route to
    /// one that skips this.
    func loadEvents(answeredIDs: Set<String>, now: Date = Date()) -> [FlaggedEvent] {
        guard let data = defaults.data(forKey: eventsKey),
              let decoded = try? JSONDecoder().decode([FlaggedEvent].self, from: data)
        else { return [] }
        let swept = FlaggedEventRetention.sweep(events: decoded,
                                                answeredIDs: answeredIDs, now: now)
        // Written back, so the expiry is a deletion rather than a filter applied
        // on the way out. A coordinate that is merely hidden is still held.
        if swept != decoded { save(events: swept) }
        return swept
    }

    func save(events: [FlaggedEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: eventsKey)
    }

    /// Drop everything this feature holds — answers included. Offered beside
    /// "forget my places" for the same reason.
    func forgetEverything() {
        defaults.removeObject(forKey: judgementsKey)
        defaults.removeObject(forKey: eventsKey)
    }
}
