import Foundation

/// Everything the app has worked out, kept per day and per series.
///
/// Deliberately a plain value type with no persistence of its own: the app
/// target decides where it lives, the same way it does for the sample cache.
/// What lives here is the part worth testing — merging, ordering, the
/// one-value-per-day rule, and the trend read.
public struct DerivedSeriesStore: Sendable, Equatable {

    /// Specs, keyed by id. A series that has never been produced is absent
    /// rather than empty, so "the app has never computed this" and "the app
    /// computed it and got nothing" stay distinguishable.
    public private(set) var specs: [DerivedSeriesID: DerivedSeriesSpec] = [:]
    private var points: [DerivedSeriesID: [Date: Double]] = [:]

    public init() {}

    // MARK: Writing

    /// Record one day's value. **Last write wins for a given day**, which is
    /// what makes a re-run idempotent: replaying the same history twice must
    /// leave the store exactly as one run did, or every launch would double the
    /// series.
    public mutating func record(_ spec: DerivedSeriesSpec, value: Double, on day: Date,
                                calendar: Calendar = .current) {
        guard value.isFinite else { return }
        specs[spec.id] = spec
        points[spec.id, default: [:]][calendar.startOfDay(for: day)] = value
    }

    /// Record everything a finished evaluation implies.
    public mutating func record(_ result: InsightResult, on day: Date,
                                calendar: Calendar = .current) {
        for (spec, value) in DerivedHarvest.series(from: result) {
            record(spec, value: value, on: day, calendar: calendar)
        }
    }

    // MARK: Reading

    public var seriesIDs: [DerivedSeriesID] { specs.keys.sorted() }

    public func spec(_ id: DerivedSeriesID) -> DerivedSeriesSpec? { specs[id] }

    /// Oldest first. The form every chart and trend wants.
    public func series(_ id: DerivedSeriesID) -> [DerivedPoint] {
        (points[id] ?? [:])
            .map { DerivedPoint(series: id, day: $0.key, value: $0.value) }
            .sorted { $0.day < $1.day }
    }

    public func latest(_ id: DerivedSeriesID) -> DerivedPoint? { series(id).last }

    /// The value on a specific day, if the app computed one.
    ///
    /// ⚠️ **This is the read a score input must use, never `latest`.** A card
    /// reading another card's derived figure has to read *the day it is scoring*
    /// — reaching for the most recent value would let a stale figure from last
    /// week silently stand in for today's.
    public func value(_ id: DerivedSeriesID, on day: Date,
                      calendar: Calendar = .current) -> Double? {
        points[id]?[calendar.startOfDay(for: day)]
    }

    /// Every series a given card produced, in a stable order.
    public func series(producedBy insight: InsightID) -> [DerivedSeriesSpec] {
        specs.values.filter { $0.producedBy == insight }
            .sorted { ($0.kind.rawValue, $0.displayName) < ($1.kind.rawValue, $1.displayName) }
    }

    public func series(ofKind kind: DerivedSeriesKind) -> [DerivedSeriesSpec] {
        specs.values.filter { $0.kind == kind }
            .sorted { $0.displayName < $1.displayName }
    }

    public var pointCount: Int { points.values.reduce(0) { $0 + $1.count } }

    /// Fold another store in. Used by the backfill, which builds one store per
    /// model so the replay can run them independently.
    public mutating func merge(_ other: DerivedSeriesStore) {
        for (id, spec) in other.specs { specs[id] = spec }
        for (id, days) in other.points {
            for (day, value) in days { points[id, default: [:]][day] = value }
        }
    }

    // MARK: The two snapshots that make reading safe — see `DerivedDependencies`

    /// Everything strictly before `day` — **the snapshot a consumer reads.**
    ///
    /// This is safeguard 1, done structurally: a model scoring a given day is
    /// handed a store that cannot contain that day, so every read is lagged at
    /// least one day and a same-day self-read is impossible to write. Loops
    /// become defined difference equations instead of evaluation-order puzzles.
    public func upTo(day: Date, calendar: Calendar = .current) -> DerivedSeriesStore {
        let cutoff = calendar.startOfDay(for: day)
        var out = DerivedSeriesStore()
        out.specs = specs
        out.points = points.mapValues { $0.filter { $0.key < cutoff } }
        // A spec whose every point was cut is dropped with them, so "absent"
        // keeps meaning "never computed as of that day".
        for (id, days) in out.points where days.isEmpty {
            out.points[id] = nil
            out.specs[id] = nil
        }
        return out
    }

    /// Only the declared series — **the snapshot enforcement of safeguard 2.**
    /// An undeclared read comes back empty rather than quietly working, which
    /// is what keeps `DerivedDependencies.edges` a complete picture instead of
    /// a well-meant convention.
    public func filtered(to declared: [DerivedSeriesID]) -> DerivedSeriesStore {
        let keep = Set(declared)
        var out = DerivedSeriesStore()
        out.specs = specs.filter { keep.contains($0.key) }
        out.points = points.filter { keep.contains($0.key) }
        return out
    }
}

/// Fills a derived store from history, by replaying the models.
///
/// **The reader chose backfill over collect-from-today, and the reason holds
/// up:** a derived series that starts empty cannot be trended and cannot be a
/// score input for months, which would make the whole mechanism inert exactly
/// when it is new. Insights are pure functions of `(samples, profile, now)` —
/// that is what `ScoreHistory` already relies on — so the past can be
/// recomputed rather than invented.
///
/// ⚠️ **A replayed point is a reconstruction, not a record of what the reader
/// was shown.** It is what today's model says about the data as it stood on
/// that day, so a model change rewrites its own history. `SectionCaveat
/// .replayedHistory` already says this for the score charts and the same
/// sentence has to carry here.
public enum DerivedBackfill {

    public static func fill(models: [any InsightModel],
                            samples: [HealthMetricSample],
                            events: [VitalEvent] = [],
                            profile: UserHealthProfile,
                            days: Int = 90,
                            calendar: Calendar = .current,
                            now: Date = Date()) -> DerivedSeriesStore {
        var store = DerivedSeriesStore()
        for model in models {
            // The replay is the same walk `ScoreHistory` already does — one
            // pass over the samples, growing the visible prefix — so this costs
            // what the score charts already cost rather than a second sweep.
            _ = ScoreHistory.replay(
                model: model, samples: samples, events: events, profile: profile,
                days: days, calendar: calendar, now: now,
                observing: { day, result in
                    store.record(result, on: day, calendar: calendar)
                })
        }
        return store
    }
}
