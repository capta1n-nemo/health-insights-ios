import Foundation

/// When the **app** first saw a data type, as distinct from when the data was
/// measured.
///
/// The reader wants the Data tab to point out what has newly started arriving
/// and what has quietly stopped. Roadmap #31 parked that as "not derivable
/// today", and the reason it gave is exactly right: **every connector
/// backfills.** Connect Oura this morning and it hands over two years of
/// history, so the earliest sample of a brand-new field is dated 2024.
/// `FieldCatalogue.firstSeen` is stamped with the *sample's* date, so it cannot
/// answer "is this new to me" for 157 of the reader's 158 identifiers.
///
/// The fix is smaller than that note assumed: keep **two clocks** rather than
/// replace one.
///
/// | Clock | Answers |
/// | --- | --- |
/// | `FieldCatalogue.firstSeen` / `lastSeen` | "How far back does this data go?" |
/// | `firstImported` / `lastImported` here | "When did *I* first see this?" |
///
/// ⚠️ **Seeding is not optional.** On the first launch after this ships, every
/// identifier a reader already has would otherwise look brand new — 158 "new
/// data type" announcements for data they have had for years, which is the
/// feature's worst possible debut. Anything present at migration is recorded
/// with `seededFromHistory` and can never be called new.
public struct TypeSightingLedger: Codable, Sendable, Equatable {

    public struct Sighting: Codable, Sendable, Equatable {
        /// Wall-clock instant the app first ingested this identifier.
        public var firstImported: Date
        /// …and most recently.
        public var lastImported: Date
        /// True when this row was written by the migration rather than by an
        /// actual first sighting, so its `firstImported` is "when the ledger
        /// began" rather than "when this arrived".
        public var seededFromHistory: Bool

        public init(firstImported: Date, lastImported: Date, seededFromHistory: Bool) {
            self.firstImported = firstImported
            self.lastImported = lastImported
            self.seededFromHistory = seededFromHistory
        }
    }

    public private(set) var sightings: [String: Sighting] = [:]

    public init() {}

    /// How recently a type must have first arrived to count as new.
    public static let newWithin: TimeInterval = 14 * 86_400

    /// How long a type must have been absent before it is worth mentioning.
    ///
    /// Sixty days, and deliberately generous. A field going quiet is far more
    /// often the reader changing device or leaving a ring on charge than a
    /// provider withdrawing something, so this errs heavily toward silence.
    public static let staleAfter: TimeInterval = 60 * 86_400

    /// Record that `identifier` arrived now.
    public mutating func observe(_ identifier: String, at now: Date) {
        if var existing = sightings[identifier] {
            existing.lastImported = Swift.max(existing.lastImported, now)
            sightings[identifier] = existing
        } else {
            sightings[identifier] = Sighting(firstImported: now, lastImported: now,
                                             seededFromHistory: false)
        }
    }

    /// Write every identifier the app already holds as pre-existing.
    ///
    /// Call once, on the first launch that has this ledger. Idempotent: an
    /// identifier already recorded is left alone, so running it twice cannot
    /// rewrite a genuine first sighting into a seeded one.
    public mutating func seed(_ identifiers: some Sequence<String>, at now: Date) {
        for identifier in identifiers where sightings[identifier] == nil {
            sightings[identifier] = Sighting(firstImported: now, lastImported: now,
                                             seededFromHistory: true)
        }
    }

    /// Types that genuinely started arriving recently.
    ///
    /// Never includes a seeded row — that is the whole point of the flag.
    public func newlyArrived(asOf now: Date) -> [String] {
        sightings.filter { _, sighting in
            !sighting.seededFromHistory
                && now.timeIntervalSince(sighting.firstImported) <= Self.newWithin
        }.keys.sorted()
    }

    /// Types that have stopped arriving **while their source is still alive**.
    ///
    /// ⚠️ **The qualifier is the whole feature.** Without it this reports "your
    /// ring data is deprecated" the week the reader leaves the ring on charge,
    /// which is both wrong and alarming. `activeSourcePrefixes` is the set of
    /// sources that *have* delivered something recently; a type is only called
    /// stale when its own source is among them. A source that went quiet
    /// entirely says nothing here — that is a connection problem, and the
    /// connection screen is where it belongs.
    public func stoppedArriving(asOf now: Date,
                                activeSourcePrefixes: Set<String>) -> [String] {
        sightings.filter { identifier, sighting in
            guard now.timeIntervalSince(sighting.lastImported) >= Self.staleAfter else { return false }
            return activeSourcePrefixes.contains { identifier.hasPrefix($0) }
        }.keys.sorted()
    }

    /// The prefixes that are still delivering, worked out from the ledger itself.
    ///
    /// The caller for `stoppedArriving` needs a set of live sources, and the
    /// ledger is the only thing that knows when each identifier last arrived —
    /// so deriving it here keeps the two halves from disagreeing about what
    /// "recently" means.
    ///
    /// A prefix is the identifier up to its first `.` for a provider path
    /// (`oura.`, `withings.`), and the whole HealthKit type-class prefix
    /// otherwise, because `HKQuantityTypeIdentifier…` has no dots and one
    /// silent HealthKit type does not mean HealthKit went away.
    public func activePrefixes(asOf now: Date,
                               within: TimeInterval = staleAfter) -> Set<String> {
        var live = Set<String>()
        for (identifier, sighting) in sightings
        where now.timeIntervalSince(sighting.lastImported) < within {
            live.insert(Self.prefix(of: identifier))
        }
        return live
    }

    static func prefix(of identifier: String) -> String {
        if let dot = identifier.firstIndex(of: ".") {
            return String(identifier[...dot])
        }
        for known in ["HKQuantityTypeIdentifier", "HKCategoryTypeIdentifier",
                      "HKCorrelationTypeIdentifier", "HKWorkoutTypeIdentifier"]
        where identifier.hasPrefix(known) {
            return known
        }
        return identifier
    }
}
