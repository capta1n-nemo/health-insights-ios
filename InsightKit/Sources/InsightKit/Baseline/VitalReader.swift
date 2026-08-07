import Foundation

/// One metric reduced to what an insight should actually reason about: a day's
/// representative value, judged against a windowed personal baseline.
///
/// Every insight used to do this by hand as `series.last` plus
/// `Array(series.dropLast())`, which has four defects and had them everywhere:
///
/// 1. **The newest raw sample isn't the day's value.** For a continuously
///    sampled vital that's one minute of one afternoon — a reading taken during
///    a run reported as the day's heart rate.
/// 2. **The baseline was every reading ever taken**, so it adapts to a real
///    change far too slowly, and for high-frequency metrics it was actually the
///    last few *hours* — a baseline that moves with the thing it should be
///    detecting.
/// 3. **Duplicates counted twice.** The same ring arriving directly and through
///    Apple Health both survived, so inter-device disagreement rather than
///    physiology set the standard deviation, and departures never cleared it.
/// 4. **No reading was ever too old to use.** A months-old value was reported as
///    today's.
///
/// Vitals Check was fixed first; this is that fix made shared, so the rest of the
/// app stops repeating the mistake.
public struct VitalReading: Sendable, Equatable {
    public let metric: MetricType
    /// The day's representative value, using the metric's own bucketing rule
    /// (median for weight, sum for step-like totals, mean otherwise).
    public let value: Double
    /// Start of the day this value represents.
    public let date: Date
    /// Rolling baseline the value is judged against.
    public let baseline: Double?
    public let zScore: Double?
    /// Daily values behind the baseline, oldest first, excluding today.
    public let history: [Double]
    /// Which device's series this came from.
    public let sourceName: String
    /// Whether the reading is recent enough to describe now.
    public let isFresh: Bool

    /// Whether there was enough history to judge the value at all. A single
    /// reading is not a clean bill of health, and shouldn't read as one.
    public var isJudged: Bool { zScore != nil }
}

/// Whether the days immediately before today may help set the bar today is
/// judged against.
///
/// ## Why this is a type and not an `Int` with a default
///
/// `reading()` took `gapDays: Int = 0` from the day the gap was added, so
/// exactly one caller — `VitalSignsCheck` — ever stated an answer and the other
/// twenty-odd got theirs by omission. That is not "no gap decided": it is *the
/// no-gap answer, chosen by nobody*, on every card that says a number is away
/// from your normal. The reader caught the consequence twice on 2026-08-05
/// ("still the same value.. but no longer in danger?") — an excursion ages two
/// days into its own baseline and stops being an excursion without the body
/// changing at all.
///
/// The fix is **not** a better default. There is no right global answer here:
/// a card asking *"is today unusual?"* must hold the recent days out, and a
/// card asking *"what is my level lately?"* must not, because holding them out
/// deletes its newest and most relevant data. So the parameter is required and
/// named, every call site says which question it is asking, and a new caller
/// cannot get an answer without choosing one.
public enum ReferenceGap: Sendable, Equatable {
    /// The baseline runs right up to yesterday.
    ///
    /// For a caller whose question is *"where am I now"* rather than *"is this
    /// unusual"* — a level, a trend, a score's input, a chart's own mean. Those
    /// callers want the newest days most of all, and a gap would silently cost
    /// them the ones that matter.
    case none

    /// Hold the last `n` days out of the baseline before judging today.
    case days(Int)

    /// Days this gap actually withholds.
    public var count: Int {
        switch self {
        case .none: return 0
        case .days(let n): return max(0, n)
        }
    }
}

public enum VitalReader {

    /// The house answer for a caller whose sentence is *"today is away from
    /// your normal"*.
    ///
    /// **Two, because two is the one that has already shipped through this
    /// function** — `VitalSignsCheck.referenceGapDays` has passed it since
    /// 2026-08-05 and is the only measured evidence available for a gap on this
    /// path. The illness radar's `HealthWatchModel.referenceGapDays` is 4 and
    /// stays 4: it is watching a signal that builds over several days, so it has
    /// to hold out more of them, and it does its own windowing rather than
    /// coming through here.
    ///
    /// ⚠️ Widening this moves the baseline of every judging caller at once,
    /// which moves their z-scores. Anything calibrated against a z — and the
    /// score bands are — has to be re-checked in the same change.
    public static let judgementGap = ReferenceGap.days(2)

    // MARK: - The rule the call sites were decided by
    //
    // Every `reading()` caller in this target now states a gap, and they were
    // not all given the same one. The line drawn, on 2026-08-07:
    //
    // - **`judgementGap` where the reading's whole job is to say *"this is
    //   away from your normal"***  — the clinical scan (`VitalSignsCheck`), the
    //   departure panel every card renders (`VitalDeparture`), and the two
    //   sentences in `SleepInsight` that print a departure from baseline. These
    //   are the surfaces the defect was actually reported on.
    // - **`.none` where the reading is a *level*** — `value` and `isFresh` only
    //   (`PeerStanding`, `CardiovascularRiskInsight`, `HeartAgeAnalyser`,
    //   `HeartResponseModel`, most of `SleepInsight`), or `baseline` used as
    //   "your usual figure" rather than as a bar (`HeartHealthScore`). A gap
    //   would cost these their newest days and buy them nothing.
    // - **`.none`, deliberately and provisionally, on the scoring path** —
    //   `ReadinessScore`, `Energy`, `FitnessInsight`, `BodyCompositionInsight`
    //   and `HeartHealthScore`'s supporting terms feed z-scores into bands that
    //   were calibrated against the ungapped baseline. Moving the denominator
    //   moves every one of those bands, and this repo already has the lesson
    //   recorded: the robust-spread change was made opt-in precisely because
    //   applied to scoring it made `ReadinessScore` fall across a month of
    //   *improving* HRV. Whether the gap helps a score is an empirical question
    //   that needs the reader's export to answer, and it has not been answered.
    //   ⚠️ **This is a decision, not an oversight** — do not "tidy" it to match
    //   the judging callers without measuring first.
    //
    // The distinction that actually matters, when a new caller has to choose:
    // a **judgement** asks whether today is unusual, so the last few days are
    // contamination; a **level** asks where you are, so they are the answer.

    // MARK: -

    /// Days of history a baseline is built from.
    public static let defaultWindowDays = 28
    /// Daily values needed before any z-score is offered.
    public static let defaultMinimumDays = 4
    /// How recent a reading must be to describe now.
    public static let defaultFreshness: TimeInterval = 36 * 3600

    /// The day's reading for one metric, or nil when the metric has no data.
    ///
    /// Returns the reading even when stale or unjudged — the caller decides what
    /// to do about that, because "we have a number but can't judge it" and "we
    /// have nothing" deserve different words.
    ///
    /// `gap` has **no default on purpose** — see `ReferenceGap`. A caller
    /// reading only `value`, `date` or `isFresh` is unaffected by it either way
    /// and should say `.none`; the moment it touches `baseline`, `zScore` or
    /// `history` the answer is load-bearing.
    public static func reading(_ metric: MetricType,
                               from samples: [HealthMetricSample],
                               now: Date = Date(),
                               windowDays: Int = defaultWindowDays,
                               minimumDays: Int = defaultMinimumDays,
                               freshWithin: TimeInterval = defaultFreshness,
                               gap: ReferenceGap,
                               calendar: Calendar = .current) -> VitalReading? {
        // One series per physical device, de-duplicated: the same ring arriving
        // twice is one instrument.
        let breakdown = MultiSource.breakdown(metric, from: samples)
        guard !breakdown.sources.isEmpty else { return nil }
        let buckets = dailyBuckets(metric, breakdown: breakdown, from: samples, calendar: calendar)

        var best: (reading: VitalReading, historyCount: Int)?
        for (series, daily) in zip(breakdown.sources, buckets) {
            guard let today = daily.last else { continue }

            // **A gap, so the last few days cannot set the bar they are judged
            // against.** `dropLast()` alone removes only *today*, which is what
            // let a departure age into its own baseline — the reader caught it
            // twice on 2026-08-05 ("still the same value.. but no longer in
            // danger?"). Robust spread removed the dominant term; this removes
            // the rest of it, and it is the same device `HealthWatchModel` has
            // always had (`referenceGapDays`).
            //
            // `.none` is a real answer and not an absence of one: a caller that
            // wants "how does today compare with the recent past" — a trend, a
            // chart's own mean, a score's input — is asking a different question
            // and must not lose its newest days. Which is why `gap` is required
            // and typed rather than an `Int` that defaults to zero.
            let earlier = daily.dropLast()
            func window(gap: Int) -> [Double] {
                let gapEnd = today.date.addingTimeInterval(-Double(gap) * 86_400)
                let cutoff = gapEnd.addingTimeInterval(-Double(windowDays) * 86_400)
                return earlier.filter { $0.date >= cutoff && $0.date < gapEnd }.map(\.value)
            }
            // **The gap is affordable, not mandatory.** It costs `gap.count` of
            // history, and a reader who has just started has none to spare —
            // holding the line strictly would leave them with no judgement at
            // all for their first week and a half, which is worse than the
            // weakness the gap exists to remove. So: take the gap when the
            // window can still clear its own minimum without those days, and
            // fall back to the ungapped window when it cannot.
            let gapped = window(gap: gap.count)
            let history = gapped.count >= minimumDays ? gapped : window(gap: 0)
            let deviation = history.count >= minimumDays
                ? Baseline.deviation(latest: today.value, history: history)
                : nil

            let reading = VitalReading(
                metric: metric, value: today.value, date: today.date,
                baseline: deviation?.baseline, zScore: deviation?.zScore,
                history: history, sourceName: series.displayName,
                isFresh: now.timeIntervalSince(today.date) <= freshWithin)

            // Freshness decides first, and then the tie-break depends on which
            // side of it we're on.
            //
            // History alone used to be the whole rule, and it had this backwards
            // at the top: a device that stopped reporting a week ago has the
            // *most* established baseline and the *weakest* claim on describing
            // today. A user with a quiet ring and an active watch got the ring's
            // stale value, correctly labelled `isFresh: false` — and callers that
            // drop a stale component, as Readiness does, lost the signal
            // altogether rather than reading it off the watch. `VitalSignsCheck`
            // had always dropped stale sources *before* choosing; this is that
            // rule, made shared.
            //
            // Among fresh sources, the best-established spread wins: its z is the
            // one worth trusting, and that half of the old rule was right.
            // Among stale ones, the most recent wins instead — the caller's
            // honest sentence is "last measured N days ago", and N has to be the
            // true minimum, not whichever quiet device happens to have the
            // longest memory.
            //
            // The winner is always one series, never a blend: pooling them is
            // what let the gap between two miscalibrated instruments become the
            // variance, so nothing ever cleared a threshold.
            let wins: Bool = {
                guard let best else { return true }
                if reading.isFresh != best.reading.isFresh { return reading.isFresh }
                if reading.isFresh {
                    if history.count != best.historyCount { return history.count > best.historyCount }
                    return reading.date > best.reading.date
                }
                if reading.date != best.reading.date { return reading.date > best.reading.date }
                return history.count > best.historyCount
            }()
            if wins { best = (reading, history.count) }
        }
        return best?.reading
    }

    /// One day's representative value, with the day it represents.
    public struct DailyValue: Sendable, Equatable {
        public let date: Date
        public let value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Daily values with their dates, oldest first, **from one instrument**.
    ///
    /// `dailyValues` is this with the dates thrown away. Anything fitting a line
    /// needs them: a series with a twenty-week silence in the middle is not
    /// evenly spaced, and regressing it against `0, 1, 2, …` does not produce a
    /// slightly wrong slope — it produces a different quantity. Measured on a
    /// real VO₂max series with such a gap: 160 mL/kg·min per year against a true
    /// 10.1. Nothing at the type level catches that, which is why this exists.
    ///
    /// ## It used to say "merged across devices", and that was the defect
    ///
    /// `reading()` above has said for months that *"the winner is always one
    /// series, never a blend: pooling them is what let the gap between two
    /// miscalibrated instruments become the variance."* The rule was applied to
    /// one of the two entry points. This one meant each day's per-source buckets
    /// together, so a day reported by one device and a day reported by two were
    /// different quantities returned as one series — and the series' **level**
    /// tracked which instruments happened to report rather than the body.
    ///
    /// **Measured on the reader's own export**, replaying the exact pipeline:
    ///
    /// - Resting heart rate: **36.5% of 211 days carry more than one source**,
    ///   and the pooled value sits a median of 6.0 bpm (p90 14) from the
    ///   best-covered single series. Watch reads ~14 bpm above ring.
    /// - Respiratory rate: the 21-day reference window's standard deviation —
    ///   **the denominator of every symptom-radar and sustained-load z** — is
    ///   **1.77× wider pooled** than single-series. Day-to-day steps across a
    ///   change in which devices reported are 1.98× the steps on days where the
    ///   composition held. The sawtooth was the devices, not the person.
    /// - Replaying `HealthWatchModel` day by day over 200 days, `isLeaning`
    ///   **disagrees on 50 of 687 (day, metric) pairs — 7.3%**, and on a third
    ///   of comparable resting-heart-rate days. That is the illness radar
    ///   flipping on device composition.
    ///
    /// ## Why it does not simply reuse `reading()`'s winner
    ///
    /// ⚠️ **Because that is measurably worse.** `reading()` ranks fresh sources
    /// by *total* history, and this reader's Apple Watch holds the most
    /// resting-heart-rate days overall (116) but only 8 in the last 60 — a dead
    /// device with a long memory. Selecting it globally cuts the radar's usable
    /// signal-days from 138 to 30 for resting heart rate: the card goes blind on
    /// exactly the channel that flips most.
    ///
    /// So the winner is the source best covering **the window actually being
    /// read**, which keeps 894 of 902 signal-days (99.1%) and still never
    /// blends. Ties break on the more recent last reading, so a stalled device
    /// cannot hold the series by having reported the same number of days.
    ///
    /// ## And why not calibrate one device onto the other
    ///
    /// The tempting third option, and it is not supportable on this data: the
    /// watch-versus-ring resting-heart-rate difference has a median of 14.0 bpm
    /// but an IQR of 16.25, and it drifts by 10.5 between the first and second
    /// half of the co-reported days. The instruments are not one quantity with a
    /// constant offset, so there is no offset to remove.
    public static func dailySeries(_ metric: MetricType,
                                   from samples: [HealthMetricSample],
                                   days: Int? = nil,
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [DailyValue] {
        let breakdown = MultiSource.breakdown(metric, from: samples)
        let cutoff = days.map { now.addingTimeInterval(-Double($0) * 86_400) } ?? .distantPast
        let windows = dailyBuckets(metric, breakdown: breakdown, from: samples,
                                   calendar: calendar)
            .map { $0.filter { $0.date >= cutoff } }
            .filter { !$0.isEmpty }

        // Coverage of the window being read, then recency, then the source's own
        // name. Never a blend.
        //
        // The last of the three is not decoration: with two instruments tied on
        // both coverage and recency — one day each, the same day — `max(by:)`
        // would otherwise return whichever the sort happened to reach last, so
        // the same input could produce different numbers on different runs. A
        // chart that is unstable across launches is worse than one that picks
        // the "wrong" instrument consistently.
        let ranked = zip(windows, breakdown.sources.map(\.displayName))
        guard let winner = ranked.max(by: { left, right in
            if left.0.count != right.0.count { return left.0.count < right.0.count }
            let leftLast = left.0.map(\.date).max() ?? .distantPast
            let rightLast = right.0.map(\.date).max() ?? .distantPast
            if leftLast != rightLast { return leftLast < rightLast }
            return left.1 > right.1
        })?.0 else { return [] }

        // One source can still report a day twice — `bucketed(by:)` already
        // reduces within a source, so this is a defensive collapse rather than
        // the cross-device mean that was here before.
        var byDay: [Date: [Double]] = [:]
        for point in winner { byDay[point.date, default: []].append(point.value) }
        return byDay.keys.sorted().compactMap { day in
            byDay[day].flatMap { Baseline.mean($0) }.map { DailyValue(date: day, value: $0) }
        }
    }

    /// The day-bucketed series for each source of a metric, in `breakdown.sources`
    /// order. Both `reading` and `dailySeries` are built on exactly this.
    ///
    /// Memoised for the length of an evaluation pass, because bucketing walks
    /// every reading and asks the calendar for a day boundary — and seven of the
    /// seventeen insight models ask for resting heart rate, each of which used to
    /// redo the whole thing. Falls through to computing it when there is no memo
    /// (a chart, a one-off read) or when `samples` isn't the array the memo was
    /// opened for.
    static func dailyBuckets(_ metric: MetricType,
                             breakdown: MultiSourceBreakdown,
                             from samples: [HealthMetricSample],
                             calendar: Calendar) -> [[AggregatedPoint]] {
        let compute = {
            breakdown.sources.map { $0.bucketed(by: .day, for: metric, calendar: calendar) }
        }
        guard let memo = MultiSource.memo, memo.covers(samples) else { return compute() }
        return memo.daily(.init(metric: metric, calendar: calendar), compute: compute)
    }

    /// Daily values for a metric over a window, oldest first, de-duplicated.
    ///
    /// For the things that need the series rather than a single day — sleep
    /// consistency being the night-to-night spread, for instance.
    public static func dailyValues(_ metric: MetricType,
                                   from samples: [HealthMetricSample],
                                   days: Int,
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [Double] {
        dailySeries(metric, from: samples, days: days, now: now, calendar: calendar)
            .map(\.value)
    }
}
