import Foundation

/// **The Sleep Regularity Index** — how likely you are to be in the same state,
/// asleep or awake, at the same clock time on two consecutive days.
///
/// ## Why it replaces two estimators rather than joining them
///
/// Sleep carried two separate figures for "how steady is this":
///
/// - `consistencyScore`, the standard deviation of **how long** the nights were;
/// - `CircadianConsistencyModel.score`, the standard deviation of **when** they
///   started.
///
/// Both are crude in the same way. A standard deviation of bedtimes says nothing
/// about wake times, so somebody who goes to bed at 23:00 every night and gets
/// up anywhere between 05:00 and 10:00 scores perfectly regular. A standard
/// deviation of durations says nothing about *placement*, so eight hours from
/// 23:00 and eight hours from 04:00 are identical to it. Neither can see the
/// thing they are both proxies for, which is whether the body's clock is being
/// asked the same question each day.
///
/// SRI asks it directly: **for every minute of the day, were you in the same
/// state at that minute yesterday?** Timing and duration both fall out of it,
/// which is why it can take both terms' weight and not a point more —
/// `SleepInsight.Weight.regularity` is the sum of the two coefficients it
/// replaced, not a new share.
///
/// ## The evidence for preferring it
///
/// SRI beat sleep **duration** head-to-head as a predictor of all-cause
/// mortality in UK Biobank accelerometry (n = 88,975; Windred et al., 2024).
/// That is a strong result for a quantity this app can compute from what it
/// already ingests, and it is the whole argument for the swap: the two
/// estimators were the app's own inventions, and this one has been tested
/// against an outcome.
///
/// ⚠️ **What is measured here is not the same instrument as the published one.**
/// The cohort figure comes from continuous wrist accelerometry, which sees naps,
/// long wakes and the exact minute of every state change. This is computed from
/// one sleep *interval* per night — bedtime plus duration — so it treats the
/// whole daytime as awake and the whole night as asleep. That reconstruction is
/// what a sleep-diary SRI is, and it is stated on the card rather than glossed:
/// the *number* is comparable in shape, not in calibration, to the published
/// distribution.
public enum SleepRegularityIndex {

    /// One night as a stretch of wall-clock time.
    ///
    /// Deliberately not `SleepSegment`: this is the reconstructed *episode*, one
    /// per night, and it may come from any source that reports a bedtime and a
    /// duration. Feeding real per-stage segments in would also work and would be
    /// strictly better data — the arithmetic below does not care which it got,
    /// only that the intervals are non-overlapping and in order.
    public struct Interval: Sendable, Equatable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// Resolution of the comparison grid, in minutes.
    ///
    /// Five, which is Oura's own phase resolution (`NightSleepDetail.phaseStep`)
    /// and is far finer than the reconstruction's real precision. A finer grid
    /// costs memory and buys nothing when the input is a rectangle; a coarser
    /// one would start rounding away genuine half-hour shifts.
    public static let epochMinutes = 5

    /// Epochs in one day. 288 at five minutes.
    public static let epochsPerDay = 24 * 60 / epochMinutes

    /// Consecutive-day **pairs** needed before an index is reported.
    ///
    /// Seven, so the answer spans a whole week and cannot be decided by a run of
    /// weekdays alone. Below it the model returns `nil` and the card holds its
    /// term neutral — the same handling every other absent term on that card
    /// gets, rather than a confident number from four days.
    public static let minimumPairs = 7

    public struct Output: Sendable, Equatable {
        /// −100 to +100. 100 is perfect repetition; 0 is a coin flip; negative
        /// means you were systematically awake when you had been asleep the day
        /// before, which in practice only happens on a shift rotation.
        public let index: Double
        /// Consecutive-day pairs the index was measured over.
        public let pairs: Int
        /// The span the pairs came from, so the card can say how far back it
        /// looked without the caller re-deriving it.
        public let firstDay: Date
        public let lastDay: Date
        /// Consecutive-day pairs inside that span that had to be skipped because
        /// a night filling one of the two days was never recorded.
        ///
        /// **Reported, not hidden**: an index built over a fortnight with nine
        /// holes in it is a weaker claim than one built over a solid fortnight,
        /// and only this number says which it is.
        public let pairsSkipped: Int

        /// The published cohort's own descriptive bands, named plainly.
        ///
        /// The wording is about *this reader against that distribution*, not a
        /// diagnosis: the cohort was middle-aged and British and wore an
        /// accelerometer, and none of those is a fact about the person reading
        /// this.
        public var band: String {
            switch index {
            case 85...: return "Very regular"
            case 75..<85: return "Regular"
            case 65..<75: return "Middling"
            case 50..<65: return "Irregular"
            default: return "Very irregular"
            }
        }
    }

    // MARK: - Building the intervals

    /// Reconstruct one sleep episode per night from the canonical series.
    ///
    /// `.sleepOnset` is signed hours from midnight **stamped at the night's key**
    /// (the morning it ends on) and `.sleepDurationHours` is stamped the same
    /// way, so the two join on the key with no date arithmetic beyond undoing
    /// the encoding. That shared stamping is `SleepNights`' whole point, and it
    /// is what makes this join safe rather than approximate.
    ///
    /// A night with only one of the two contributes nothing: half an episode is
    /// not a shorter episode, it is an unknown one, and inventing either end
    /// would put a fabricated state on the grid.
    public static func intervals(from samples: [HealthMetricSample],
                                 days: Int? = nil,
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> [Interval] {
        let onsets = VitalReader.dailySeries(.sleepOnset, from: samples, days: days,
                                             now: now, calendar: calendar)
        let durations = VitalReader.dailySeries(.sleepDurationHours, from: samples,
                                                days: days, now: now, calendar: calendar)
        var durationByNight: [Date: Double] = [:]
        for point in durations { durationByNight[point.date] = point.value }

        return onsets.compactMap { onset -> Interval? in
            guard let hours = durationByNight[onset.date], hours > 0 else { return nil }
            // The key is the morning the night ended on, and the onset is signed
            // hours from *that* midnight — so a −1.5 bedtime is 22:30 the
            // evening before, which is exactly what subtracting from the key
            // gives.
            let start = onset.date.addingTimeInterval(onset.value * 3600)
            return Interval(start: start, end: start.addingTimeInterval(hours * 3600))
        }.sorted { $0.start < $1.start }
    }

    // MARK: - The index

    public static func evaluate(samples: [HealthMetricSample],
                                days: Int? = 90,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        evaluate(intervals: intervals(from: samples, days: days, now: now,
                                      calendar: calendar),
                 calendar: calendar)
    }

    /// SRI over exactly these episodes.
    ///
    /// ## The formula
    ///
    /// Windred et al.'s definition, unchanged:
    ///
    /// ```
    /// SRI = −100 + (200 / (M(N−1))) · Σ Σ δ(s[i][j], s[i+1][j])
    /// ```
    ///
    /// — `M` epochs per day, `N` days, `s` the binary sleep state, `δ` 1 when
    /// the two states agree. Written below as "agreements over comparisons,
    /// mapped from [0, 1] onto [−100, 100]", which is the same thing and reads
    /// as what it is.
    ///
    /// ## The one judgement that is not in the formula
    ///
    /// **Which days may be compared.** A day with no recorded night is not a day
    /// of wakefulness — it is a day the app knows nothing about — and letting it
    /// on the grid as 24 hours awake would score a holiday from the ring as
    /// catastrophic irregularity.
    ///
    /// The admission rule is written in **night keys**, not in "an episode
    /// started that day", and the difference is not pedantry. `SleepOnset.night`
    /// puts every night's key on the morning it ends, so a calendar day D is
    /// filled by exactly two of them: key D, which holds everything from 18:00
    /// the evening before, and key D+1, which holds everything from 18:00 that
    /// evening. Asking instead whether an episode *began* inside D would silently
    /// reject every day whose following night started after midnight — which is
    /// to say, it would drop the late nights of precisely the irregular sleeper
    /// this index exists to describe, and bias the answer upward.
    ///
    /// Pairs are then formed only between two admitted, genuinely consecutive
    /// days, and everything skipped is counted and reported.
    public static func evaluate(intervals: [Interval],
                                calendar: Calendar = .current) -> Output? {
        guard !intervals.isEmpty else { return nil }

        let sorted = intervals.sorted { $0.start < $1.start }
        let recorded = Set(sorted.map { SleepOnset.night(of: $0.start, calendar: calendar) })
        // A day is describable when both of the night keys that fill it were
        // recorded.
        let admitted = recorded.filter {
            recorded.contains(calendar.startOfDay(for: $0.addingTimeInterval(86_400 + 3600)))
        }
        guard let first = admitted.min(), let last = admitted.max() else { return nil }

        // The grid, one bool per epoch, over the whole span. Days outside
        // `admitted` are still allocated so indexing stays trivial; they are
        // simply never compared.
        let dayCount = Int(((last.timeIntervalSince(first)) / 86_400).rounded()) + 1
        guard dayCount >= 2 else { return nil }
        var asleep = [Bool](repeating: false, count: dayCount * epochsPerDay)
        let epochSeconds = Double(epochMinutes) * 60
        for interval in sorted {
            let fromEpoch = Int(((interval.start.timeIntervalSince(first)) / epochSeconds)
                .rounded(.down))
            let toEpoch = Int(((interval.end.timeIntervalSince(first)) / epochSeconds)
                .rounded(.up))
            // Clamped to the grid at **both** ends before the range is formed.
            // An episode may legitimately start before the first admitted day or
            // run past the last — the night after the final admitted day is one
            // — and building `a..<b` from unclamped bounds traps at runtime
            // rather than drawing nothing, which is how this first went down.
            let lower = Swift.max(0, Swift.min(asleep.count, fromEpoch))
            let upper = Swift.max(0, Swift.min(asleep.count, toEpoch))
            guard upper > lower else { continue }
            for epoch in lower..<upper { asleep[epoch] = true }
        }

        var agreements = 0
        var comparisons = 0
        var pairs = 0
        var skipped = 0
        for day in 0..<(dayCount - 1) {
            let today = first.addingTimeInterval(Double(day) * 86_400)
            let tomorrow = first.addingTimeInterval(Double(day + 1) * 86_400)
            // `startOfDay` rather than the raw offset, so a daylight-saving
            // boundary lands on the day it belongs to rather than an hour into
            // its neighbour.
            guard admitted.contains(calendar.startOfDay(for: today)),
                  admitted.contains(calendar.startOfDay(for: tomorrow)) else {
                skipped += 1
                continue
            }
            pairs += 1
            let base = day * epochsPerDay
            for epoch in 0..<epochsPerDay {
                comparisons += 1
                if asleep[base + epoch] == asleep[base + epochsPerDay + epoch] {
                    agreements += 1
                }
            }
        }

        guard pairs >= minimumPairs, comparisons > 0 else { return nil }
        let concordance = Double(agreements) / Double(comparisons)
        return Output(index: -100 + 200 * concordance,
                      pairs: pairs, firstDay: first, lastDay: last,
                      pairsSkipped: skipped)
    }

    /// 0–100, higher is better.
    ///
    /// ⚠️ **These anchors are a scale choice, stated rather than dressed as
    /// cut-points.** The regularity literature reports continuous associations
    /// and publishes no threshold, exactly as `CircadianConsistencyModel` already
    /// said of its own scale. What the anchors follow is the *shape* the cohort
    /// reported: the distribution sits in the seventies, the risk gradient is
    /// steep across the bottom of it, and it flattens towards the top — so the
    /// curve is steepest between 55 and 75 and nearly flat above 85, and a
    /// reader at the cohort's middle scores a middling number rather than a
    /// flattering one.
    ///
    /// Continuous, for the reason every scoring curve in this app is: every step
    /// function shipped here has had to be replaced by a curve later.
    public static func score(index: Double) -> Double {
        ScoreCurve.through([
            (30, 5), (45, 20), (55, 35), (65, 50), (72, 62),
            (78, 76), (85, 92), (92, 100)
        ], at: index)
    }
}
