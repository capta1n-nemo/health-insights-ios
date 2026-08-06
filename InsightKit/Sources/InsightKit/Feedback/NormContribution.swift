import Foundation

/// **The shape a norm gets built from** — one reader, one cohort, one week,
/// summarised.
///
/// ## Why this is a second type and not a wider `TelemetryEvent`
///
/// `TelemetryEvent` is *accuracy* telemetry: it answers "is model v2 better than
/// v1 for 40-49 year old men?" with a DP-noised **error percentage**, and it
/// carries no values by construction. Building a norm needs the opposite — the
/// **distribution of the values themselves** — so widening that type would give
/// one struct two jobs and it would end up doing neither honestly.
/// `docs/norms-and-telemetry.md` holds the full reasoning and the reader's own
/// tenet behind it:
///
/// > *"we are building this app so we can collect this telemetry, and start
/// > building these norms."*
///
/// ## ⚠️ Nothing is sent. This build has no network path for any of it.
///
/// These types and `NormContributionBuilder` are the *shape*, deliberately
/// built before any transport exists. Settings ▸ Data & model improvement is
/// off by default and states that nothing leaves the phone in this build, and
/// that promise holds: there is no client, no endpoint and no upload anywhere
/// in this file or reachable from it.
///
/// ## The three rules this type enforces structurally
///
/// 1. **Summaries, never dated series.** A per-day timeline is re-identifying
///    even with no name on it; a pooled distribution is not. There is no field
///    here that can hold a date, a timestamp or a per-day value — the coarsest
///    time this type can express is `weekBucket`.
/// 2. **No free text, anywhere, by construction rather than by care.** Every
///    `String` reachable from a `NormContribution` is either one of `Cohort`'s
///    four enum-backed buckets or an identifier declared in this app's own
///    source — `MetricType.rawValue`, `DerivedSeriesID.rawValue`,
///    `InsightID.rawValue`, `DerivedSeriesKind.rawValue`. **There is no field
///    for a name, a label, a title, a note or a display string.** A calendar
///    event's title cannot appear here because nothing in this file has
///    anywhere to put one, and `NormContributionBuilder` cannot even be handed
///    a `CalendarEvent`: its inputs are samples, derived series and the
///    profile. The calendar contributes its *quantities* — meeting hours,
///    formality, presence, and every component score they feed — while its text
///    stays on the phone.
/// 3. **A quantity below `NormContributionBuilder.minimumSampleCount`
///    contributes nothing at all.** See that constant for the number and why.
public struct NormContribution: Codable, Sendable, Equatable {

    /// Bumped when a field is added or renamed. A pool has to be able to read
    /// an old contribution against the shape it was written with, exactly as
    /// `HealthDataExport.schemaVersion` does for the personal file.
    public static let currentSchemaVersion = 1

    /// One quantity's distribution over the period.
    ///
    /// ⚠️ **Quantiles, and deliberately no min or max.** An extreme is the most
    /// re-identifying single number a distribution carries — the tallest person
    /// in a cohort is findable, their 90th percentile is not — and a norm needs
    /// the body of the distribution, not its tails. `p10`/`p90` are as far out
    /// as this goes.
    public struct QuantitySummary: Codable, Sendable, Equatable {
        /// How many readings this summary is over. Carried rather than implied,
        /// because a norm assembled from summaries has to weight them, and
        /// because `AgeComparison`'s rule applies to a returned norm too: the
        /// figure that says how much to trust it belongs on the row.
        public let n: Int
        public let p10: Double
        public let p25: Double
        public let median: Double
        public let p75: Double
        public let p90: Double

        public init(n: Int, p10: Double, p25: Double, median: Double,
                    p75: Double, p90: Double) {
            self.n = n
            self.p10 = p10
            self.p25 = p25
            self.median = median
            self.p75 = p75
            self.p90 = p90
        }
    }

    /// One measured series' week.
    public struct MetricSummary: Codable, Sendable, Equatable {
        /// A `MetricType`, not a string — the vocabulary is closed, so a pool
        /// cannot be fed a quantity this app has never defined.
        public let metric: MetricType
        public let summary: QuantitySummary

        public init(metric: MetricType, summary: QuantitySummary) {
            self.metric = metric
            self.summary = summary
        }
    }

    /// One derived series' week — **the half with no published norm**, and
    /// therefore the half this whole mechanism exists for.
    public struct DerivedSummary: Codable, Sendable, Equatable {
        public let series: DerivedSeriesID
        /// The card that produced it. Non-optional here on purpose: the builder
        /// drops any series whose id does not resolve to a known `InsightID`,
        /// so a stored id from an older build cannot smuggle an unrecognised
        /// string into the pool.
        public let producedBy: InsightID
        public let kind: DerivedSeriesKind
        public let summary: QuantitySummary

        public init(series: DerivedSeriesID, producedBy: InsightID,
                    kind: DerivedSeriesKind, summary: QuantitySummary) {
            self.series = series
            self.producedBy = producedBy
            self.kind = kind
            self.summary = summary
        }
    }

    public let schemaVersion: Int
    /// Strata for the norm itself, not for comparison — which is the difference
    /// between this and `TelemetryEvent`'s use of the same type.
    public let cohort: Cohort
    /// Whole weeks since 1970, from `Telemetry.weekBucket`. The coarsest time
    /// this type can express, and the only one it has.
    public let weekBucket: Int
    /// Sorted by metric raw value, so two contributions for the same week
    /// encode identically and a diff of the payload means something.
    public let metrics: [MetricSummary]
    /// Sorted by series id, for the same reason.
    public let derived: [DerivedSummary]

    public init(cohort: Cohort, weekBucket: Int,
                metrics: [MetricSummary], derived: [DerivedSummary],
                schemaVersion: Int = NormContribution.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.cohort = cohort
        self.weekBucket = weekBucket
        self.metrics = metrics
        self.derived = derived
    }

    /// True when every quantity fell below the floor and there is nothing worth
    /// pooling. A caller should send nothing rather than an empty envelope: an
    /// envelope is still a record that this cohort existed that week.
    public var isEmpty: Bool { metrics.isEmpty && derived.isEmpty }
}

/// Turns what the phone holds into the summaries a pool could be built from.
///
/// ⚠️ **Building is not sending.** Nothing in this enum opens a connection.
public enum NormContributionBuilder {

    /// **A quantity with fewer than this many readings in the week contributes
    /// nothing.**
    ///
    /// Five, and the reason is not arbitrary:
    ///
    /// - Below five, `p10` and `p90` sit within one order statistic of the
    ///   smallest and largest reading, so the "summary" is the raw values
    ///   wearing a statistical name. That is exactly the re-identification the
    ///   summarise-don't-serialise rule exists to prevent, and it would be
    ///   worse for being disguised.
    /// - Five is also the smallest count at which a *weekly* median is a claim
    ///   most of the week contributed to. A median of two days called "this
    ///   reader's week" is a number with no basis — which is the failure this
    ///   app exists to avoid, stated at it rather than by it.
    ///
    /// ⚠️ **This is not the cohort-size floor.** That is a different number
    /// answering a different question — *how many people* before a norm is
    /// published back — and it is still open in
    /// `docs/norms-and-telemetry.md`. Conflating the two would let a norm from
    /// four people through because each of them had a full week.
    public static let minimumSampleCount = 5

    /// Every week the data covers, oldest first. Weeks in which nothing cleared
    /// the floor are omitted rather than emitted empty.
    public static func buildAll(samples: [HealthMetricSample],
                                derived: DerivedSeriesStore,
                                profile: UserHealthProfile,
                                now: Date = Date()) -> [NormContribution] {
        var weeks = Set(samples.map { Telemetry.weekBucket($0.start) })
        for id in derived.seriesIDs {
            for point in derived.series(id) { weeks.insert(Telemetry.weekBucket(point.day)) }
        }
        return weeks.sorted().compactMap { week in
            let contribution = build(samples: samples, derived: derived,
                                     profile: profile, weekBucket: week, now: now)
            return contribution.isEmpty ? nil : contribution
        }
    }

    /// One week's contribution.
    ///
    /// `now` is only used to age the profile into a cohort band, which is why it
    /// is separate from the week being summarised.
    public static func build(samples: [HealthMetricSample],
                             derived: DerivedSeriesStore,
                             profile: UserHealthProfile,
                             weekBucket week: Int,
                             now: Date = Date()) -> NormContribution {
        var byMetric: [MetricType: [Double]] = [:]
        for sample in samples where Telemetry.weekBucket(sample.start) == week {
            guard sample.value.isFinite else { continue }
            byMetric[sample.type, default: []].append(sample.value)
        }

        let metrics = byMetric
            .compactMap { metric, values -> NormContribution.MetricSummary? in
                summarise(values).map { .init(metric: metric, summary: $0) }
            }
            .sorted { $0.metric.rawValue < $1.metric.rawValue }

        let derivedSummaries = derived.seriesIDs
            .compactMap { id -> NormContribution.DerivedSummary? in
                // A spec whose id does not resolve to a card is dropped rather
                // than passed through: `producedBy` is the guarantee that every
                // string in the payload came from this app's own namespacing.
                guard let spec = derived.spec(id), let card = id.producedBy,
                      card == spec.producedBy else { return nil }
                let values = derived.series(id)
                    .filter { Telemetry.weekBucket($0.day) == week && $0.value.isFinite }
                    .map(\.value)
                guard let summary = summarise(values) else { return nil }
                return .init(series: id, producedBy: card, kind: spec.kind, summary: summary)
            }
            .sorted { $0.series < $1.series }

        return NormContribution(cohort: .from(profile: profile, now: now),
                                weekBucket: week,
                                metrics: metrics, derived: derivedSummaries)
    }

    /// `nil` below the floor — the floor is applied here, once, so no caller can
    /// forget it.
    public static func summarise(_ values: [Double]) -> NormContribution.QuantitySummary? {
        let sorted = values.filter(\.isFinite).sorted()
        guard sorted.count >= minimumSampleCount else { return nil }
        return .init(n: sorted.count,
                     p10: quantile(sorted, 0.10), p25: quantile(sorted, 0.25),
                     median: quantile(sorted, 0.50),
                     p75: quantile(sorted, 0.75), p90: quantile(sorted, 0.90))
    }

    /// Linear interpolation between order statistics — the definition R calls
    /// type 7 and NumPy uses by default.
    ///
    /// Named rather than left implicit because there are nine of these and they
    /// disagree at small `n`, which is the only `n` this app has: a pool that
    /// mixed two definitions would have a spread it could not explain.
    /// `sorted` must be sorted and non-empty.
    public static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard let first = sorted.first else { return .nan }
        guard sorted.count > 1 else { return first }
        let position = min(max(q, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
}
