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

    /// What became of the most recent arrival once the sanitiser had seen it.
    ///
    /// ⚠️ **The ledger observes before the sanitiser runs, and that order is
    /// deliberate** (backlog D43, ruled 2026-08-07). A reading outside its
    /// metric's `plausibleRange` is a real arrival that produced no data, and
    /// the two halves of that sentence are separately worth knowing: observing
    /// *after* sanitising would make a metric arriving persistently out of range
    /// look identical to nothing arriving at all, which is exactly the state a
    /// reader needs to see when a device starts sending garbage.
    ///
    /// So the sighting stands and this says what happened to it.
    public enum ArrivalOutcome: String, Codable, Sendable, Equatable {
        /// At least one reading survived and became data.
        case usable
        /// Everything that arrived sat outside the metric's plausible range.
        case outsidePlausibleRange
        /// Everything that arrived was zero or negative for a metric that
        /// cannot legitimately be either — a provider placeholder.
        case notPositive

        /// How the Data tab says this beside the type's name. `nil` for a
        /// sighting that became data, which needs no qualifier.
        public var rowNote: String? {
            switch self {
            case .usable: return nil
            case .outsidePlausibleRange: return "arrived, but outside the plausible range"
            case .notPositive: return "arrived, but every reading was zero or below"
            }
        }
    }

    public struct Sighting: Codable, Sendable, Equatable {
        /// Wall-clock instant the app first ingested this identifier.
        public var firstImported: Date
        /// …and most recently.
        public var lastImported: Date
        /// True when this row was written by the migration rather than by an
        /// actual first sighting, so its `firstImported` is "when the ledger
        /// began" rather than "when this arrived".
        public var seededFromHistory: Bool
        /// What the sanitiser did with the most recent arrival, where anything
        /// judged it. `nil` for a raw field (nothing sanitises those) and for
        /// any sighting written before D43 shipped — a missing key decodes to
        /// nil, which is why this is optional rather than defaulted to
        /// `.usable`. "Not judged" and "judged fine" are different answers and
        /// the row must not print the second when it has the first.
        public var outcome: ArrivalOutcome?

        public init(firstImported: Date, lastImported: Date, seededFromHistory: Bool,
                    outcome: ArrivalOutcome? = nil) {
            self.firstImported = firstImported
            self.lastImported = lastImported
            self.seededFromHistory = seededFromHistory
            self.outcome = outcome
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

    /// Record what the sanitiser did with an identifier's most recent arrival.
    ///
    /// A no-op for an identifier the ledger has never seen: an outcome without
    /// a sighting is a verdict on something that never arrived.
    public mutating func record(_ outcome: ArrivalOutcome, for identifier: String) {
        guard var existing = sightings[identifier] else { return }
        existing.outcome = outcome
        sightings[identifier] = existing
    }

    /// Why the most recent arrival of `identifier` produced no data — `nil`
    /// when it did, and `nil` when nothing has judged it.
    public func discardedOutcome(for identifier: String) -> ArrivalOutcome? {
        guard let outcome = sightings[identifier]?.outcome, outcome != .usable else { return nil }
        return outcome
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

// MARK: - What the sanitiser did with an arrival (D43)

public extension TypeSightingLedger {

    /// Fold one sync's sanitiser verdict into the ledger.
    ///
    /// ⚠️ **`kept` and `dropped` must be the partition of what arrived in *this
    /// sync*, not of the merged store.** The merged partition includes the
    /// retained cache and the reader's manual entries, and a cached sample
    /// rejected on this run was not an arrival — blaming its type would put
    /// "arrived, but outside the plausible range" on a row that is delivering
    /// perfectly well today.
    ///
    /// A type is only marked as discarded when **nothing** it delivered this
    /// sync survived. One good reading among bad ones means the type produced
    /// data, and that is what the row should say.
    ///
    /// Marking the survivors `.usable` is not redundant: it is what clears a
    /// note from a metric that has recovered, so the qualifier describes the
    /// last arrival rather than the worst one ever seen.
    mutating func recordSanitisation(kept: [HealthMetricSample],
                                     dropped: [HealthMetricSample]) {
        let survived = Set(kept.map(\.type))
        for type in survived { record(.usable, for: type.rawValue) }

        let lost = Dictionary(grouping: dropped.filter { !survived.contains($0.type) },
                              by: \.type)
        for (type, samples) in lost {
            record(Self.outcome(forDropped: samples, of: type), for: type.rawValue)
        }
    }

    /// Which of the sanitiser's two refusals to name.
    ///
    /// `.notPositive` only when *every* rejected reading was a placeholder zero,
    /// because that is the claim the row makes. A single genuinely out-of-range
    /// value among them is the more informative fault and the more honest note:
    /// a provider sending 1e9 is not sending nothing.
    static func outcome(forDropped samples: [HealthMetricSample],
                        of type: MetricType) -> ArrivalOutcome {
        let allPlaceholders = samples.allSatisfy { type.requiresPositiveValue && $0.value <= 0 }
        return allPlaceholders ? .notPositive : .outsidePlausibleRange
    }
}
