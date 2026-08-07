import Foundation

/// **The occasion, drawn.** `SubstanceEpisodes` decides what an occasion *is*;
/// this decides what there is to say about each one, and — deliberately — how
/// little.
///
/// ## Why this exists and why it does not score
///
/// The reader's brief for the substance card was "score everything that is
/// charted but not scored" (backlog `P16`). Independent statistical review of
/// their own record then refuted the premise, and the refutation is not a
/// quibble about a p-value:
///
/// - `heartRate`'s apparent stimulant response fell from **0.91 SD to 0.03**
///   once same-day step count entered the model. The effect was their own
///   movement.
/// - Three of the four "confirmed" effects were in the *welcome* direction, and
///   two of the four were the same measurement twice (r = 0.912).
/// - The permutation null was ~2× anti-conservative, and Benjamini-Hochberg is
///   invalid under the measured negative dependence (r = −0.795) — it needs
///   Benjamini-Yekutieli or Westfall-Young.
/// - The whole finding set flipped on the choice of day boundary: three
///   confirmations at UTC+8, one at UTC, **zero** at UTC−5.
///
/// The reader's ruling on being shown that, verbatim and standing:
/// **"Honest version, always!"** So this type reports **per-episode deltas with
/// the named alternative explanation beside each one, and no score at all**.
/// There is no number here for a dial to consume, on purpose: a score is a
/// claim about what a substance does to this person, and four exposure episodes
/// cannot support one.
///
/// `ordinaryRun` is the sentence that goes with it, and it is the reader's
/// wording rather than a hedge invented here.
public enum SubstanceEpisodeReport {

    /// **The sentence.** Standing copy, held here rather than in the app target
    /// so it is testable and so it cannot be softened by whichever view happens
    /// to render it next.
    public static let ordinaryRun =
        "Nothing has happened the same way often enough to tell it from an ordinary run."

    /// How far after an episode ends this will look for a return to baseline
    /// before giving up and saying so.
    ///
    /// A week, because the gap rule already says a fortnight is a separate
    /// occasion and looking further than the next occasion would attribute one
    /// exposure's tail to another. It is a horizon, not a claim: an episode
    /// whose readings have not come back inside it reports "not back within the
    /// week", never a bigger number.
    public static let recoveryHorizonHours: Double = 7 * 24

    /// A departure smaller than this is not something to time the recovery of.
    ///
    /// One baseline standard deviation. Below it the "return" is indistinguishable
    /// from the reading it started at, and a recovery time measured off it would
    /// be timing noise.
    public static let departureThresholdSDs = 1.0

    // MARK: - The shape of an occasion

    /// What kind of occasion this was — the reader's own three cases: one, a
    /// few close together, or a long stretch.
    ///
    /// It is a description of the *log*, not of a dose: the app deliberately
    /// does not model amount (`SubstanceEvent.units` is optional and free), so
    /// "a big weekend" here means *logged across more than one day*, and the
    /// copy says exactly that rather than implying the app knows how much.
    public enum Shape: String, Sendable, Equatable, CaseIterable {
        /// One logged event.
        case single
        /// Several logged events inside a single day.
        case severalClose
        /// Logged events spanning more than one day — a weekend.
        case extended

        public var displayName: String {
            switch self {
            case .single: return "One occasion"
            case .severalClose: return "Several close together"
            case .extended: return "A longer stretch"
            }
        }

        /// What the reader is actually looking at. Says *logged*, every time —
        /// the app is counting entries, not measuring intake.
        public var explanation: String {
            switch self {
            case .single:
                return "One entry, so this is the simplest case: what your readings did after a single logged event."
            case .severalClose:
                return "Several entries inside a day. The app counts them as one occasion, because a response cannot tell them apart — it does not know how much, only how many entries."
            case .extended:
                return "Entries across more than one day. Anything measured here covers the whole stretch, so it cannot separate the first day from the last."
            }
        }
    }

    /// Longer than this, end to end, and the occasion is a stretch rather than
    /// an evening.
    ///
    /// **Measured in elapsed hours, not in calendar days**, and the first
    /// version of this got it wrong in the most predictable way available: two
    /// drinks at 11pm and 1am are two calendar days and one evening, so a
    /// day-boundary test called the reader's most ordinary occasion "a longer
    /// stretch". The day boundary is also precisely what the statistical
    /// refutation of this card turned on — the finding set flipped from three
    /// confirmations to zero across three time zones — so nothing here may
    /// depend on where midnight falls.
    public static let extendedThresholdHours: Double = 24

    static func shape(of episode: SubstanceEpisodes.Episode) -> Shape {
        guard episode.eventCount > 1 else { return .single }
        let hours = episode.end.timeIntervalSince(episode.start) / 3600
        return hours >= extendedThresholdHours ? .extended : .severalClose
    }

    // MARK: - One metric, one occasion

    /// What one signal did around one occasion — **a difference, never a
    /// finding**.
    ///
    /// `alternative` is the whole honesty mechanism and is not a disclaimer:
    /// it is the named, well-measured thing that would produce the same
    /// difference without the substance doing anything. The app does not yet
    /// adjust for it, so naming it lets the reader discount it themselves.
    public struct MetricDelta: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        /// Mean of the readings inside the occasion's response window.
        public let duringMean: Double
        /// Mean of this reader's readings over the same 90 days that fall
        /// outside *every* occasion's window.
        public let cleanMean: Double
        public let cleanSD: Double
        public let duringReadings: Int
        public let cleanReadings: Int
        /// The named alternative explanation, where there is a well-measured
        /// one. `nil` means no candidate is known — not that none exists.
        public let alternative: String?

        public var id: MetricType { metric }
        public var delta: Double { duringMean - cleanMean }

        /// The departure in this reader's own baseline spreads, **signed as the
        /// metric is measured**. `nil` where the baseline had no spread to
        /// divide by: a difference against a flat baseline is unjudgeable, not
        /// infinitely large.
        public var z: Double? { cleanSD > 0 ? delta / cleanSD : nil }

        /// Whether this departure is big enough to be worth timing a return
        /// from. See `departureThresholdSDs`.
        public var departed: Bool { (z.map { abs($0) } ?? 0) >= departureThresholdSDs }

        public init(metric: MetricType, duringMean: Double, cleanMean: Double,
                    cleanSD: Double, duringReadings: Int, cleanReadings: Int,
                    alternative: String?) {
            self.metric = metric
            self.duringMean = duringMean
            self.cleanMean = cleanMean
            self.cleanSD = cleanSD
            self.duringReadings = duringReadings
            self.cleanReadings = cleanReadings
            self.alternative = alternative
        }
    }

    /// **How long until it looked like an ordinary day again.**
    ///
    /// The reader's question — "how long does it take me to recover" — answered
    /// only where it can be: a departure of at least one baseline SD, a daily
    /// mean afterwards that comes back inside that band, and no later occasion
    /// interrupting. Where any of those fails, `hoursToBaseline` is `nil` and
    /// `observedHours` says how far it was possible to look, which is a
    /// different statement from "it took a long time".
    public struct Recovery: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        /// Hours from the end of the occasion until the first day whose mean is
        /// back inside one baseline SD. `nil` = it did not come back inside
        /// what could be observed.
        public let hoursToBaseline: Double?
        /// How much interruption-free time there was to look at.
        public let observedHours: Double
        /// The departure being recovered from, in baseline SDs, signed.
        public let departureZ: Double

        public var id: MetricType { metric }

        public init(metric: MetricType, hoursToBaseline: Double?,
                    observedHours: Double, departureZ: Double) {
            self.metric = metric
            self.hoursToBaseline = hoursToBaseline
            self.observedHours = observedHours
            self.departureZ = departureZ
        }
    }

    /// One occasion, everything there is to say about it.
    public struct Episode: Sendable, Equatable, Identifiable {
        public let episode: SubstanceEpisodes.Episode
        public let shape: Shape
        /// Every signal with enough readings on both sides, largest departure
        /// first. **Unranked by welcome-ness** — see `SubstanceReport`, which is
        /// where the good/bad split lives.
        public let deltas: [MetricDelta]
        /// Only for signals that actually departed. Usually empty, and that is
        /// the honest common case.
        public let recoveries: [Recovery]

        public var id: Date { episode.start }

        public init(episode: SubstanceEpisodes.Episode, shape: Shape,
                    deltas: [MetricDelta], recoveries: [Recovery]) {
            self.episode = episode
            self.shape = shape
            self.deltas = deltas
            self.recoveries = recoveries
        }

        /// The slowest thing to come back, where anything did. The section's one
        /// figure.
        public var slowestRecovery: Recovery? {
            recoveries.filter { $0.hoursToBaseline != nil }
                .max { ($0.hoursToBaseline ?? 0) < ($1.hoursToBaseline ?? 0) }
        }
    }

    // MARK: - One substance

    /// **Good versus bad, per substance — and mostly, "not enough to say".**
    ///
    /// The split is by direction only: which signals moved the way the reader
    /// would want, and which the other way. It is explicitly *not* a verdict on
    /// the substance, because with fewer than
    /// `SubstanceEpisodes.minimumEpisodesToDescribe` occasions there is nothing
    /// to tell a direction from an ordinary run — which is what
    /// `isAttributable` gates and what `ordinaryRun` says out loud.
    ///
    /// ⚠️ On this reader's real record there are **15 stimulant events and one
    /// cannabis event in ~25 days**, which is four occasions in total. Cannabis
    /// at n = 1 is unattributable by construction and gets the honest empty
    /// state rather than a row; the stimulant panel will near-duplicate the
    /// pooled card, and its copy has to say so rather than pretend to be a
    /// second, independent look.
    public struct SubstanceReport: Sendable, Equatable, Identifiable {
        public let substance: SubstanceClass
        public let episodes: [Episode]
        /// Signals that moved the way the reader would want, on the most recent
        /// occasion that measured them. Direction only.
        public let welcome: [MetricDelta]
        /// Signals that moved the other way. Direction only.
        public let unwelcome: [MetricDelta]
        /// Signals whose direction has no "better" end — a temperature, a
        /// glucose — so neither list may claim them. Kept rather than dropped:
        /// a measured signal that vanishes is indistinguishable from one the
        /// app forgot.
        public let noBetterEnd: [MetricDelta]

        public var id: String { substance.rawValue }
        public var occasions: Int { episodes.count }

        /// Whether this substance has repeated often enough for the card to
        /// describe a pattern at all. **Never enough to call one proven** — see
        /// `SubstanceEpisodes.minimumEpisodesToDescribe`.
        public var isAttributable: Bool {
            occasions >= SubstanceEpisodes.minimumEpisodesToDescribe
        }

        /// What the panel says instead of a verdict.
        public var verdict: String {
            guard isAttributable else {
                let n = occasions
                return "\(n) \(n == 1 ? "occasion" : "occasions") logged. "
                    + "\(ordinaryRun) The differences below are real measurements of "
                    + "your own readings; any one of them can be an ordinary week."
            }
            return "\(occasions) occasions logged, which is enough to describe what "
                + "repeats — not enough to call it proven. Every row names something "
                + "else that would produce the same difference."
        }

        public init(substance: SubstanceClass, episodes: [Episode],
                    welcome: [MetricDelta], unwelcome: [MetricDelta],
                    noBetterEnd: [MetricDelta]) {
            self.substance = substance
            self.episodes = episodes
            self.welcome = welcome
            self.unwelcome = unwelcome
            self.noBetterEnd = noBetterEnd
        }
    }

    /// The whole log, reported.
    public struct Report: Sendable, Equatable {
        public let substances: [SubstanceReport]
        public var totalOccasions: Int { substances.reduce(0) { $0 + $1.occasions } }
        /// True while *nothing* in the log has repeated enough to describe.
        /// The card leads with `ordinaryRun` when it is.
        public var isEmptyOfEvidence: Bool { !substances.contains(where: \.isAttributable) }

        public init(substances: [SubstanceReport]) { self.substances = substances }
    }

    // MARK: - Building it

    /// Everything the episode sections draw, in one pass.
    ///
    /// `metrics` defaults to the pooled card's own watched list, so the two can
    /// never disagree about which signals are being looked at.
    public static func report(events: [SubstanceEvent],
                              samples: [HealthMetricSample],
                              metrics: [MetricType] = SubstanceResponseAnalyzer.comparedMetrics,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> Report {
        let visible = events.filter { $0.timestamp <= now }
        let all = SubstanceEpisodes.episodes(events: visible, calendar: calendar)
        guard !all.isEmpty else { return Report(substances: []) }

        // Every occasion's response window, for *any* substance. A reading
        // inside one of these is not clean, whichever substance put it there —
        // pooling a stimulant night into alcohol's baseline would make the
        // baseline the thing that moved.
        let windows = all.map { $0.responseWindow(SubstanceResponseAnalyzer.afterWindow) }
        let cutoff = now.addingTimeInterval(-SubstanceResponseAnalyzer.comparisonWindowDays * 86_400)

        var byMetric: [MetricType: (clean: [Double], series: [HealthMetricSample])] = [:]
        for metric in metrics {
            let series = samples.samples(of: metric)
                .filter { $0.start >= cutoff && $0.start <= now }
            guard series.count >= 5 else { continue }
            let clean = series.filter { sample in
                !windows.contains { $0.contains(sample.start) }
            }
            byMetric[metric] = (clean.map(\.value), series)
        }

        var reports: [SubstanceReport] = []
        for substance in Set(all.map(\.substance)).sorted(by: { $0.rawValue < $1.rawValue }) {
            let mine = all.filter { $0.substance == substance }
            var episodes: [Episode] = []
            for episode in mine {
                let window = episode.responseWindow(SubstanceResponseAnalyzer.afterWindow)
                var deltas: [MetricDelta] = []
                for (metric, pools) in byMetric {
                    let during = pools.series.filter { window.contains($0.start) }.map(\.value)
                    // Two readings inside the window and three clean ones is the
                    // same floor the pooled card uses. Below it there is nothing
                    // to compare, and a one-reading difference drawn as a bar is
                    // the exact defect this whole file is a response to.
                    guard during.count >= 2, pools.clean.count >= 3,
                          let a = Baseline.mean(during), let b = Baseline.mean(pools.clean),
                          b != 0 else { continue }
                    deltas.append(MetricDelta(
                        metric: metric, duringMean: a, cleanMean: b,
                        cleanSD: Baseline.standardDeviation(pools.clean) ?? 0,
                        duringReadings: during.count, cleanReadings: pools.clean.count,
                        alternative: SubstanceEpisodes.alternativeExplanation(for: metric)))
                }
                // Largest departure first, alphabetical on a tie — the
                // dictionary above has no order of its own, and a section whose
                // rows reshuffle between launches reads as new information.
                deltas.sort {
                    abs($0.z ?? 0) == abs($1.z ?? 0)
                        ? $0.metric.rawValue < $1.metric.rawValue
                        : abs($0.z ?? 0) > abs($1.z ?? 0)
                }

                let horizonEnd = nextInterruption(after: episode, in: all, now: now)
                let recoveries = deltas.filter(\.departed).compactMap { delta -> Recovery? in
                    guard let z = delta.z, let pools = byMetric[delta.metric] else { return nil }
                    return recovery(for: delta, series: pools.series, from: episode.end,
                                    until: horizonEnd, departureZ: z, calendar: calendar)
                }
                episodes.append(Episode(episode: episode, shape: shape(of: episode),
                                        deltas: deltas, recoveries: recoveries))
            }

            // The good/bad split reads the most recent occasion that measured
            // each signal — not a mean across occasions. Averaging four
            // occasions' deltas would manufacture exactly the false precision
            // the refutation is about.
            var latest: [MetricType: MetricDelta] = [:]
            for episode in episodes {
                for delta in episode.deltas { latest[delta.metric] = delta }
            }
            var welcome: [MetricDelta] = []
            var unwelcome: [MetricDelta] = []
            var neither: [MetricDelta] = []
            let ordered = latest.values.sorted {
                abs($0.z ?? 0) == abs($1.z ?? 0)
                    ? $0.metric.rawValue < $1.metric.rawValue
                    : abs($0.z ?? 0) > abs($1.z ?? 0)
            }
            for delta in ordered {
                switch SubstanceResponseAnalyzer.higherIsBetter(delta.metric) {
                case .some(let up):
                    let good = up ? delta.delta > 0 : delta.delta < 0
                    if good { welcome.append(delta) } else { unwelcome.append(delta) }
                case .none:
                    neither.append(delta)
                }
            }
            reports.append(SubstanceReport(substance: substance, episodes: episodes,
                                           welcome: welcome, unwelcome: unwelcome,
                                           noBetterEnd: neither))
        }
        // Most-logged first: the substance with something to look at leads, and
        // ties break alphabetically so the order is stable between launches.
        return Report(substances: reports.sorted {
            $0.occasions == $1.occasions
                ? $0.substance.rawValue < $1.substance.rawValue
                : $0.occasions > $1.occasions
        })
    }

    /// When the recovery clock has to stop: the next occasion of anything, the
    /// horizon, or now — whichever comes first.
    static func nextInterruption(after episode: SubstanceEpisodes.Episode,
                                 in all: [SubstanceEpisodes.Episode],
                                 now: Date) -> Date {
        let horizon = episode.end.addingTimeInterval(recoveryHorizonHours * 3600)
        let next = all.map(\.start).filter { $0 > episode.end }.min()
        return [horizon, now, next].compactMap { $0 }.min() ?? horizon
    }

    /// Hours until the metric's daily mean is back inside one baseline SD.
    ///
    /// Daily means rather than raw readings: a single reading dipping back into
    /// the band is not a recovery, and heart rate alone would supply hundreds of
    /// chances for one to.
    static func recovery(for delta: MetricDelta, series: [HealthMetricSample],
                         from end: Date, until horizon: Date,
                         departureZ: Double, calendar: Calendar) -> Recovery {
        let observed = max(0, horizon.timeIntervalSince(end)) / 3600
        guard delta.cleanSD > 0 else {
            return Recovery(metric: delta.metric, hoursToBaseline: nil,
                            observedHours: observed, departureZ: departureZ)
        }
        let band = delta.cleanSD * departureThresholdSDs
        let after = series.filter { $0.start > end && $0.start <= horizon }
        let byDay = Dictionary(grouping: after) { calendar.startOfDay(for: $0.start) }
        for day in byDay.keys.sorted() {
            guard let mean = Baseline.mean(byDay[day]?.map(\.value) ?? []) else { continue }
            if abs(mean - delta.cleanMean) <= band {
                // Timed to the end of that day's readings, not to midnight: the
                // reader asked how long it took, and the last reading that day
                // is the latest moment the app can honestly point at.
                let last = byDay[day]?.map(\.start).max() ?? day
                return Recovery(metric: delta.metric,
                                hoursToBaseline: max(0, last.timeIntervalSince(end)) / 3600,
                                observedHours: observed, departureZ: departureZ)
            }
        }
        return Recovery(metric: delta.metric, hoursToBaseline: nil,
                        observedHours: observed, departureZ: departureZ)
    }
}

public extension SubstanceResponseAnalyzer {

    /// Which direction the card calls better, for the app target.
    ///
    /// `higherIsBetter` is internal and the episode sections live in the app,
    /// which has no `@testable` reach. Re-exported rather than duplicated: two
    /// tables of directions is how a chart's legend ends up disagreeing with the
    /// row above it.
    static func betterDirection(_ metric: MetricType) -> Bool? { higherIsBetter(metric) }

    /// One delta, worded the way this card words that metric. Same reason.
    ///
    /// `baseline` is required rather than defaulted: the two HRV rows are
    /// formatted as a **percentage** of it, and a version of this that took the
    /// difference alone would have printed "HRV +0%" for every one of them.
    static func format(delta: Double, baseline: Double, of metric: MetricType) -> String {
        deltaLabel(MetricEffect(metric: metric, baseline: baseline,
                                afterUse: baseline + delta,
                                deltaAbsolute: delta,
                                deltaPercent: baseline != 0 ? delta / abs(baseline) * 100 : 0,
                                affectedNights: 0, baselineNights: 0,
                                isAdverse: false, baselineSD: 0))
    }
}
