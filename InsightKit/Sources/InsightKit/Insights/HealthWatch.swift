import Foundation

/// Whether several signals are moving together in the way a body does a day or
/// two before you notice anything.
///
/// This is the feature people screenshot. "My ring told me I was getting sick
/// before I felt it" is the single most repeated story in wearable communities,
/// and it is repeated because it is the only moment these devices tell you
/// something you could not have worked out yourself.
///
/// ## Why this is not Vitals Check again
///
/// Vitals Check asks "is any one signal unusual today". This asks the different
/// and harder question: **are several signals leaning the same way at once**. The
/// distinction matters because that is the actual shape of an immune response —
/// resting heart rate up, HRV down, skin temperature up, breathing faster, oxygen
/// saturation down — each one individually within the noise, and all five
/// together not remotely a coincidence.
///
/// ## The baseline excludes the window it is judging
///
/// This is the part that makes it work, and it came out of a real defect. The
/// golden-dataset fixture showed that a *sustained* departure hides in its own
/// rolling baseline: by the fourth day of a fever, three of those nights are
/// inside the 28-day window the fourth is compared against, so the mean lifts,
/// the spread inflates, and the z-score sinks back under the threshold exactly
/// when the person is most unwell.
///
/// So the reference period here stops well before the recent window starts. The
/// last few days are judged against a fortnight that ended before they began, and
/// a run that has been going for a week is *more* visible rather than less.
public enum HealthWatchModel {

    /// How many recent days are treated as "now".
    public static let recentDays = 3
    /// The gap between the recent window and the reference period. Without it,
    /// yesterday would help set the baseline that judges today.
    public static let referenceGapDays = 4
    /// How long the reference period runs.
    public static let referenceDays = 21
    /// Daily values a signal needs in the reference period before it can vote.
    public static let minimumReferenceDays = 7
    /// How far a signal must move before the card **points at it**.
    ///
    /// ⚠️ **This is a presentation threshold and no longer a scoring gate.** It
    /// used to be both, and that was the defect measured on 2026-08-05: four
    /// signals *all* leaning the illness way at z = 0.95 scored exactly 100,
    /// "Nothing stirring", because `score` opened with `guard signal.isLeaning`
    /// and threw the other side of the bar away. The reader reported it from the
    /// other end — *"my heart rate is still elevated, my HRV is still down …
    /// why am I now back at 99%"*. The score is continuous now; this only
    /// decides which rows are worth naming on the card.
    public static let leaningZ = 1.0
    /// And how far before the card calls it a hard lean.
    public static let strongZ = 2.0

    /// How far one channel's departure can count, in SDs.
    ///
    /// The second half of the same defect: with no cap, one signal at z = 3.0
    /// scored **55** while four signals at z = 1.2 scored **64** — the exact
    /// opposite of what this file's own doc comment claimed it did. Past two and
    /// a half SDs a single channel carries almost no additional information
    /// about *illness* and quite a lot about a hot bedroom, a hard session or a
    /// sensor slipping, so it stops accumulating.
    public static let channelCap = 2.5

    /// `E[max(0, Z)] = 1/√(2π)` for a standard normal.
    ///
    /// **The number that makes this calibrated rather than merely continuous.**
    /// A perfectly well body scores about 0.4 on the one-sided statistic below,
    /// every single day, purely from noise — so a curve that read 0.4 as
    /// evidence would grade health itself as a symptom. The score is a function
    /// of how far past this the day sits, in units of the statistic's own null
    /// spread, which is why it can be stated as a false-alarm budget at all.
    static let nullMean = 1 / (2 * Double.pi).squareRoot()
    /// `Var[max(0, Z)] = ½ − 1/(2π)`.
    static let nullVariance = 0.5 - 1 / (2 * Double.pi)

    /// How much the surviving channels still move together, after the same-basis
    /// collapse has taken out the pairs that are one measurement twice.
    ///
    /// A stated assumption, not a measurement — an equicorrelation of 0.3 for
    /// signals that share a sympathetic drive without sharing an instrument. The
    /// simulation in `SymptomRadarTests` runs the alarm rate at 0, 0.3 and 0.5
    /// so the cost of being wrong is written down rather than hoped about: at
    /// 0.5 the strong band fires about three times as often as designed, which
    /// is a degradation and not a collapse.
    static let assumedDependence = 0.3

    /// One signal's verdict.
    public struct Signal: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let recent: Double
        public let reference: Double
        public let zScore: Double
        /// True when the movement is in the direction illness pushes it.
        public let isConcerning: Bool
        public var id: MetricType { metric }

        public var isLeaning: Bool {
            isConcerning && abs(zScore) >= HealthWatchModel.leaningZ
        }
    }

    public struct Output: Sendable, Equatable {
        public let signals: [Signal]
        /// 0–100, higher is better — nothing stirring.
        public let score: Double
        /// The collapse losers: signals that were evaluated and then folded into
        /// a same-basis twin's vote (`collapsingDuplicates`). Carried so the
        /// radar web can draw an open dot on the HRV or thermal twin that leaned
        /// but did not vote — "counted once" must not render as "not looked at".
        /// Readiness reads only `signals` / `leaning` / `score` and is untouched.
        public let discounted: [Signal]
        public var leaning: [Signal] { signals.filter(\.isLeaning) }

        init(signals: [Signal], score: Double, discounted: [Signal] = []) {
            self.signals = signals
            self.score = score
            self.discounted = discounted
        }
    }

    /// The direction illness pushes each signal, and how much weight its vote
    /// carries.
    ///
    /// Weights are not equal because the signals are not equally specific.
    /// Skin temperature rising is close to a thermometer; a slightly lower
    /// oxygen saturation happens for a dozen ordinary reasons.
    /// ⚠️ **A metric listed here is a candidate, not a vote.** Everything in
    /// one `MetricFamily` collapses to a single signal before scoring
    /// (`collapsingDuplicates`), so the four thermal entries below are one
    /// thermal channel between them and never four.
    static let watched: [(metric: MetricType, risingIsConcerning: Bool, weight: Double)] = [
        (.skinTemperatureDeviation, true, 1.0),
        (.skinTemperature, true, 1.0),
        // **The reader's own morning thermometer, added 2026-08-07 (backlog
        // R33) — and the reason it is worth having is the nights it covers,
        // not the nights it duplicates.**
        //
        // The three thermal entries above all come off a wearable, so a night
        // the ring spent on charge is a night this card has no temperature at
        // all — and a card that loses its most specific channel exactly when
        // somebody is too unwell to remember their ring is a card that goes
        // quiet when it matters. The reader has been writing a waking
        // temperature to Health through a Shortcut for months (136 records
        // over 124 days, 80 of the last 90, read by nothing until now), and it
        // does not care whether anything was worn.
        //
        // ⚠️ **It does not add a channel — it rescues one.** `.thermal`, so
        // `collapsingDuplicates` folds it in with the wearable temperatures
        // and keeps whichever leans harder. Letting it vote separately would
        // count one morning's warmth twice in a statistic whose entire claim
        // is *agreement between independent things*, and the null spread
        // assumes an equicorrelation of 0.3 between surviving channels, which
        // two thermometers on one body would badly violate.
        //
        // **The cost, stated rather than hidden:** on a morning when both the
        // ring and the thermometer reported, the thermal channel is now a
        // maximum over two z-scores instead of one, and selecting a maximum
        // inflates the statistic. That is the same effect the decision
        // interval was already moved from 5.0 to 6.0 for, and it is measured
        // through the real path in `SymptomRadarTests
        // .testTheAccumulationsRunLengthIsWhatItClaims` and
        // `.testTheFalseAlarmBudgetIsWhatTheBandsClaim`, both of which now
        // simulate this channel.
        //
        // Weight 1.0, the same as the other temperatures: weight here is
        // *specificity for illness*, and a thermometer under the tongue at a
        // fixed hour is at least as specific as a ring's nightly deviation.
        // Its extra noise — a variable wake time, a variable technique — is
        // already handled where noise belongs, in the denominator of its own
        // z-score, which is computed against this series' own spread.
        (.basalBodyTemperature, true, 1.0),
        (.restingHeartRate, true, 0.9),
        (.heartRateVariabilityRMSSD, false, 0.9),
        (.heartRateVariabilitySDNN, false, 0.8),
        (.respiratoryRate, true, 0.8),
        (.oxygenSaturation, false, 0.5)
    ]

    /// The watched metrics alone, for `candidateMetrics` declarations.
    /// `{ $0.metric }` rather than `\.metric`: `watched` is an array of tuples,
    /// and a key path into a tuple element is a compile error (the trap is
    /// already documented at `ReadinessInsight.candidateMetrics`).
    public static var watchedMetrics: [MetricType] { watched.map { $0.metric } }

    /// The vote weight a metric carries, 0 for anything unwatched.
    static func weight(for metric: MetricType) -> Double {
        watched.first { $0.metric == metric }?.weight ?? 0
    }

    /// The direction illness pushes a watched metric, `nil` for anything else.
    static func risingIsConcerning(for metric: MetricType) -> Bool? {
        watched.first { $0.metric == metric }?.risingIsConcerning
    }

    public static func evaluate(samples: [HealthMetricSample], now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        var signals: [Signal] = []
        for entry in watched {
            if let signal = signal(for: entry, samples: samples, now: now, calendar: calendar) {
                signals.append(signal)
            }
        }
        return output(fromEvaluated: signals)
    }

    /// Collapse, gate and score one day's evaluated signals — shared by the live
    /// `evaluate` and the radar's `SymptomRadarModel.timeline`, so a replayed
    /// day can never be composed by different rules than a live one.
    static func output(fromEvaluated signals: [Signal]) -> Output? {
        // Signals sharing a measurement basis — the two HRV metrics, the thermal
        // pair, and anything else derived from one stream — are each one signal
        // reported several ways; letting each vote would double-weight them.
        let collapsed = collapsingDuplicates(signals)
        guard collapsed.count >= 2 else { return nil }
        let surviving = Set(collapsed.map(\.metric))
        return Output(signals: collapsed, score: score(collapsed),
                      discounted: signals.filter { !surviving.contains($0.metric) })
    }

    static func signal(for entry: (metric: MetricType, risingIsConcerning: Bool, weight: Double),
                       samples: [HealthMetricSample], now: Date,
                       calendar: Calendar) -> Signal? {
        signal(for: entry,
               daily: VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                              calendar: calendar),
               now: now)
    }

    /// The pure window half of `signal(for:samples:now:calendar:)`, split out so
    /// the radar's timeline can fetch each metric's daily series once and slide
    /// the windows over it — never 90 × a full fetch, which multiplies score
    /// replay's cost by the span.
    static func signal(for entry: (metric: MetricType, risingIsConcerning: Bool, weight: Double),
                       daily: [VitalReader.DailyValue], now: Date) -> Signal? {
        guard !daily.isEmpty else { return nil }

        let recentStart = now.addingTimeInterval(-Double(recentDays) * 86_400)
        let referenceEnd = now.addingTimeInterval(-Double(referenceGapDays) * 86_400)
        let referenceStart = referenceEnd.addingTimeInterval(-Double(referenceDays) * 86_400)

        // `date < now` as well as the lower bound: when a *past* day is being
        // scored (the radar's timeline, score replay) the series still holds
        // every later day, and a recent window that read the future would let
        // tomorrow's fever flag yesterday. A no-op for a live evaluation, whose
        // samples all precede `now` by construction.
        let recentValues = daily
            .filter { $0.date >= recentStart && $0.date < now }
            .map(\.value)
        let referenceValues = daily
            .filter { $0.date >= referenceStart && $0.date < referenceEnd }
            .map(\.value)

        guard !recentValues.isEmpty,
              referenceValues.count >= minimumReferenceDays,
              let recent = Baseline.mean(recentValues),
              let reference = Baseline.mean(referenceValues),
              let spread = Baseline.standardDeviation(referenceValues), spread > 0
        else { return nil }

        let z = (recent - reference) / spread
        let concerning = entry.risingIsConcerning ? z > 0 : z < 0
        return Signal(metric: entry.metric, recent: recent, reference: reference,
                      zScore: z, isConcerning: concerning)
    }

    /// Metrics that are a **standby** for their family rather than a rival to
    /// it: they hold the channel open on a day nothing else in it reported, and
    /// they never take the channel off something that did.
    ///
    /// ⚠️ **This exists because "keep whichever leans hardest" is a maximum,
    /// and a maximum is not the statistic the null assumes.** The measurement,
    /// on 400,000 simulated well days through the real path, 2026-08-07: adding
    /// the basal temperature to the thermal family as an ordinary member —
    /// free to win the collapse — moved the 99.45th percentile of the joint
    /// statistic from 3.35 to 3.74, took the strong band from about two false
    /// alarms a year to **4.8**, and cut the accumulation's in-control run
    /// length from over 300 days to **116**. Every one of `someSignsExcess`,
    /// `strongSignsExcess` and `Memory.decisionInterval` would have had to move,
    /// and the card would have ended up *less* sensitive than it is today in
    /// exchange for a channel it only actually needs on the nights the ring was
    /// off.
    ///
    /// **And max-selection buys almost nothing in return.** Under a real fever
    /// both thermometers rise and the winner is at `channelCap` either way, so
    /// the maximum is paying a null-distribution price for an alternative it
    /// cannot exploit. A standby pays neither.
    ///
    /// The cost of the rule, stated rather than buried: on a morning when the
    /// ring reported an ordinary temperature and the thermometer read half a
    /// degree high, the ring's reading is the one that votes. The thermometer's
    /// is not thrown away — it lands in `Output.discounted`, which is what the
    /// radar web draws as an open dot, so "counted once" never renders as "not
    /// looked at".
    static let standbyMetrics: Set<MetricType> = [.basalBodyTemperature]

    /// One signal, one vote. Where a person has both HRV metrics or several
    /// thermal ones, keep whichever is leaning hardest — **except** that a
    /// standby never displaces a first-choice instrument. See `standbyMetrics`.
    static func collapsingDuplicates(_ signals: [Signal]) -> [Signal] {
        var out: [Signal] = []
        for signal in signals {
            if let index = out.firstIndex(where: {
                $0.metric.sharesMeasurementBasis(with: signal.metric)
            }) {
                if prefers(signal, over: out[index]) { out[index] = signal }
            } else {
                out.append(signal)
            }
        }
        return out
    }

    /// Which of two same-basis signals holds the channel.
    ///
    /// Standby status first, `|z|` second. Ordering it the other way round
    /// would make the rule cosmetic — the standby would still win whenever it
    /// happened to be the louder of the two, which is precisely the maximum the
    /// rule exists to avoid.
    static func prefers(_ candidate: Signal, over incumbent: Signal) -> Bool {
        let candidateIsStandby = standbyMetrics.contains(candidate.metric)
        let incumbentIsStandby = standbyMetrics.contains(incumbent.metric)
        if candidateIsStandby != incumbentIsStandby { return incumbentIsStandby }
        return abs(candidate.zScore) > abs(incumbent.zScore)
    }

    /// The weighted mean one-sided departure, in SDs.
    ///
    /// **One joint statistic, never a count of channels past a threshold.** Six
    /// signals each at 95% specificity, OR'd together, give a 26.5% false-alarm
    /// rate — roughly a hundred alarming mornings a year on a body that is
    /// perfectly well. That arithmetic is why this is a mean and not a tally.
    ///
    /// One-sided per channel: a signal moving the *welcome* way is good news and
    /// contributes nothing, rather than cancelling out one that moved the wrong
    /// way. A gloriously high HRV does not disprove a raised resting heart rate.
    static func concern(_ signals: [Signal]) -> Double {
        var weighted = 0.0
        var total = 0.0
        for signal in signals {
            guard let weight = watched.first(where: { $0.metric == signal.metric })?.weight
            else { continue }
            total += weight
            guard signal.isConcerning else { continue }
            weighted += weight * Swift.min(channelCap, abs(signal.zScore))
        }
        guard total > 0 else { return 0 }
        return weighted / total
    }

    /// How far past an ordinary day this one sits, in the statistic's own null
    /// standard deviations. Zero is a perfectly well body; three is a finding.
    ///
    /// The null spread is computed from the weights that actually voted rather
    /// than fixed, because it genuinely changes with them: `Var[Σwᵢxᵢ/Σwᵢ] =
    /// Var[x]·Σwᵢ²/(Σwᵢ)²`. A morning where the ring was off and only two
    /// channels reported is a noisier morning, and this says so instead of
    /// grading it on a four-channel scale.
    ///
    /// ⚠️ **The channels are not independent, and assuming they were fired on
    /// 5.3% of well days — nineteen mornings a year.** That number is measured,
    /// not feared: the first version of this used `Var·Σwᵢ²/(Σwᵢ)²`, and the
    /// simulation in `SymptomRadarTests` caught it immediately.
    ///
    /// `collapsingDuplicates` removes the worst of the dependence — the two HRV
    /// metrics, the thermal pair, the whole cardiac/autonomic group where
    /// resting heart rate and rMSSD come off one interbeat stream and correlate
    /// −0.93, and respiratory rate against oxygen saturation. What survives
    /// still shares a sympathetic drive, so the spread carries an equicorrelated
    /// term at `assumedDependence`:
    ///
    ///     Var[Σwᵢxᵢ/Σwᵢ] = Var[x]·(Σwᵢ²(1−ρ) + ρ(Σwᵢ)²) / (Σwᵢ)²
    ///
    /// **The property that buys**, measured over 400,000 simulated null days:
    /// the excess at a given quantile becomes almost identical whether four
    /// channels reported or two (99.45th percentile: 3.26 against 3.35). A
    /// morning when the ring was off is then graded on the same scale as a
    /// morning when everything reported, rather than on a quietly stricter one.
    static func excess(_ signals: [Signal]) -> Double {
        let weights = signals.compactMap { signal in
            watched.first { $0.metric == signal.metric }?.weight
        }
        let total = weights.reduce(0, +)
        let sumOfSquares = weights.reduce(0) { $0 + $1 * $1 }
        guard total > 0, sumOfSquares > 0 else { return 0 }
        return Swift.max(0, standardised(signals))
    }

    /// The same quantity **unclamped**, so a quieter-than-usual day reads
    /// negative.
    ///
    /// `excess` clamps because a score cannot be better than 100 and a body
    /// cannot be less than well. Sequential accumulation needs the sign: a CUSUM
    /// only returns to zero because ordinary days push it *down*, and clamping
    /// them at zero would leave it ratcheting up forever.
    static func standardised(_ signals: [Signal]) -> Double {
        let weights = signals.compactMap { signal in
            watched.first { $0.metric == signal.metric }?.weight
        }
        let total = weights.reduce(0, +)
        let sumOfSquares = weights.reduce(0) { $0 + $1 * $1 }
        guard total > 0, sumOfSquares > 0 else { return 0 }
        let variance = nullVariance
            * (sumOfSquares * (1 - assumedDependence) + assumedDependence * total * total)
            / (total * total)
        return (concern(signals) - nullMean) / variance.squareRoot()
    }

    /// Where the card stops giving an all-clear, in null SDs. The 95th
    /// percentile of the null.
    public static let someSignsExcess = 1.9
    /// Where it says something is clearly going on. The 99.45th percentile —
    /// about two alarming mornings a year on a well body.
    public static let strongSignsExcess = 3.3

    /// 0–100, higher is better.
    ///
    /// Deliberately *not* worst-offender-dominant, which is the rule everywhere
    /// else in this app. One signal off is an ordinary Tuesday — the whole point
    /// here is agreement, so the departures accumulate and a single outlier
    /// cannot dominate. Four signals at z = 1.2 worry this card considerably
    /// more than one at z = 3, which is what its doc comment always said and
    /// what, until 2026-08-05, it did the exact reverse of.
    ///
    /// **The anchors are measured null quantiles, not chosen numbers.** From
    /// 400,000 simulated well days at `assumedDependence`:
    ///
    /// | Excess | Percentile | Well days a year above it | Score |
    /// | --- | --- | --- | --- |
    /// | 1.9 | 95th | ~18 | 85 — the card starts pointing at rows |
    /// | 3.3 | 99.45th | ~2 | 50 — the card says something is going on |
    ///
    /// So the band edges are a **stated false-alarm budget**: about two alarming
    /// mornings a year on a body that is perfectly well. The comparison worth
    /// keeping in mind is six signals each at 95% specificity simply OR'd
    /// together, which gives ninety-seven.
    ///
    /// The band *values* — 85 and 50 — did not move when this was rebuilt. Only
    /// the statistic under them, and what they now mean.
    static func score(_ signals: [Signal]) -> Double { score(excess: excess(signals)) }

    /// The curve alone, so the accumulated statistic can be rendered on exactly
    /// the same scale as today's rather than on a parallel one that could drift
    /// away from it.
    public static func score(excess: Double) -> Double {
        ScoreCurve.through([(0, 100), (1.0, 94), (someSignsExcess, 85), (2.5, 72),
                            (strongSignsExcess, 50), (4.0, 35), (5.0, 18),
                            (6.0, 8), (8.0, 2)],
                           at: excess)
    }
}

// MARK: - The Today card

/// The three states, on Oura's precedent (nothing stirring / some signs /
/// strong signs), derived from the existing weighted vote rather than a new
/// one (docs/planned-modules.md ▸ module 7).
public enum SymptomRadarStatus: String, Sendable, Equatable {
    case quiet, someSigns, strongSigns
}

public extension HealthWatchModel.Output {
    /// Labels over the already-continuous score — bands, like Readiness's, not
    /// a scoring curve, so there is nothing to enrol in `ScoreContinuityTests`.
    ///
    /// The thresholds are statements about how far past an ordinary day this
    /// one sits, in the joint statistic's own null standard deviations:
    /// - **85 is one null SD.** Below it the day is inside the range a well body
    ///   produces on its own, and the card says nothing is stirring.
    /// - **50 is two and a half.** Under the null that is roughly a 1-in-160
    ///   morning, or about **two false alarms a year** — a stated budget rather
    ///   than a threshold somebody liked the look of. Six signals each at 95%
    ///   specificity, OR'd, would give ninety-seven.
    ///
    /// ⚠️ **`strongSigns` additionally requires two signals leaning**, and that
    /// is a rule rather than an emergent property. It used to be emergent —
    /// weight 1.0 fully leaning landed exactly on 50 — and that guarantee was
    /// lost when the score became a properly calibrated mean, because on a
    /// morning when only two channels reported, one extreme channel can reach
    /// any excess at all. The claim is the card's whole thesis and is worth
    /// stating outright: **agreement is the finding, and one dramatic number is
    /// never the finding.** The score itself stays continuous; only the label is
    /// gated, and the card still shows the number underneath it.
    /// ⚠️ **And `quiet` additionally requires that nothing is leaning hard**, for
    /// the mirror-image reason. The joint statistic is a measure of *agreement*,
    /// and it is right that one channel cannot move it far — but the reader's
    /// resting heart rate sitting 23 bpm above their own normal is something
    /// stirring, whatever the other signals are doing, and a card that answers
    /// "nothing stirring" to that has told them something false. The two gates
    /// are symmetric: **agreement decides how strong a finding is, and a single
    /// hard lean is enough to stop the card giving an all-clear.**
    var status: SymptomRadarStatus {
        let anythingHard = signals.contains {
            $0.isConcerning && abs($0.zScore) >= HealthWatchModel.strongZ
        }
        if score >= 85 && !anythingHard { return .quiet }
        if score >= 50 || leaning.count < 2 { return .someSigns }
        return .strongSigns
    }

    /// How far past an ordinary day this one sits, in null SDs — the quantity
    /// the score renders. Exposed so the card can say *how unusual*, and so a
    /// test can measure the false-alarm rate the bands claim.
    var excess: Double { HealthWatchModel.excess(signals) }
}

/// The pure machinery behind the symptom-radar card: the day-by-day timeline,
/// the episodes cut from it, and the self-grading ledger.
///
/// All static and value-in/value-out, like `HealthWatchModel` itself — nothing
/// here holds state, so replayed history and the live card cannot disagree
/// with a stored copy. There deliberately is no stored copy.
public enum SymptomRadarModel {

    /// One calendar day's watch verdict. `output` is nil on a day the watch
    /// could not evaluate (fewer than two votable signals).
    public struct DaySnapshot: Sendable, Equatable {
        public let day: Date            // startOfDay, in the given calendar
        public let output: HealthWatchModel.Output?

        public init(day: Date, output: HealthWatchModel.Output?) {
            self.day = day
            self.output = output
        }
    }

    /// The ledger's span. 90 days of timeline is what the card grades itself
    /// over — long enough for a hit rate to mean something, short enough that
    /// last winter's model is not marking this spring's homework.
    public static let ledgerDays = 90

    // MARK: - Memory

    /// What the reader asked for, in their own words:
    ///
    /// > *"Today my heart rate is still elevated, my HRV is still down, and
    /// > yesterday it flagged I had symptoms which was absolutely correct. Why
    /// > am I now back at 99% just 1 day later? Shouldn't it take into
    /// > consideration the day before? Like I am not fully recovered obviously."*
    ///
    /// A single-day detector cannot answer that, however well calibrated, and
    /// the calibration work made it worse rather than better: the fix that
    /// stopped four mild signals scoring 100 also means the second day of a real
    /// illness — by which time the trailing baseline has begun absorbing the
    /// first — is judged as though it were the first time anything had happened.
    ///
    /// **A CUSUM is the standard answer and it is the right one here.** It
    /// accumulates each day's departure, subtracts an allowance so ordinary days
    /// pull it back down, and floors at zero:
    ///
    ///     Sₜ = max(0, Sₜ₋₁ + xₜ − k)
    ///
    /// The property the reader is asking for falls straight out: while the body
    /// stays away from its own normal, `S` **holds**, whatever the rolling
    /// baseline underneath is doing. It only returns to zero once the signals do.
    ///
    /// ⚠️ **It does not replace the daily statistic — it runs beside it.** A
    /// CUSUM trades speed for false alarms and takes about six days to catch a
    /// one-SD shift, which is far too slow to be an early warning on its own.
    /// The card reports whichever of the two is saying more: today's number
    /// catches an acute onset in a morning, and the accumulation is what refuses
    /// to let go of it afterwards.
    public enum Memory {
        /// The daily allowance, in null SDs. The textbook choice for detecting a
        /// shift of size δ is δ/2, and δ = 1 is the shift worth catching here.
        public static let allowance = 0.5
        /// Where the accumulation itself becomes a finding.
        ///
        /// **Chosen by simulation against a stated in-control run length**, the
        /// same way the daily bands were chosen against a stated false-alarm
        /// budget. Over simulated well days at `HealthWatchModel
        /// .assumedDependence`, with the allowance above:
        ///
        /// | h | Days between false alarms | Days to catch a 1 SD shift |
        /// | --- | --- | --- |
        /// | 3 | 72 | — |
        /// | 4 | 167 | — |
        /// | **5** | **389** | **5.6** |
        /// | 6 | 922 | — |
        ///
        /// A real sustained shift is found inside a week. Raising `k` and
        /// lowering `h` buys the same run length with slower detection (k = 1,
        /// h = 3 gives 290 days and 10.1), which is the wrong trade for a card
        /// whose whole promise is noticing early.
        ///
        /// ⚠️ **6, not the 5 that simulation suggested.** The table above assumes
        /// three fixed channels; the real card runs `collapsingDuplicates` first,
        /// which keeps *whichever* of a same-basis pair leans harder. Selecting a
        /// maximum inflates the statistic, and the run length measured in Swift
        /// through the real path came out at 195 days rather than 389 — an alarm
        /// every six months rather than every year. The Swift measurement is the
        /// one that counts, and it is now a test.
        public static let decisionInterval = 6.0

        /// ⚠️ **The accumulation is bounded at the decision interval**, and it
        /// has to be.
        ///
        /// An unbounded CUSUM keeps climbing for as long as the departure lasts,
        /// so a bad week leaves a number so large that ordinary days cannot work
        /// it back down: measured on a seven-day fixture it stood at 13.5 a
        /// *fortnight* after every signal had returned to normal, and the card
        /// was still announcing an illness that was over. Under a true null the
        /// statistic only falls by the allowance each day, so recovery time
        /// scales with how bad the episode was — which is precisely backwards.
        ///
        /// Bounded, the card drops out of `strongSigns` the first well day and
        /// settles over the following few. The cost, stated plainly: memory
        /// alone can carry the score down to the strong-signs edge and no
        /// further. Anything below that has to come from the day itself — which
        /// is right, because "this has been going on a while" is a different
        /// claim from "today is bad", and only the second one gets to be loud.
        public static var accumulationCap: Double { decisionInterval }
    }

    /// The accumulated state on the last day of a timeline.
    public struct Accumulation: Sendable, Equatable {
        /// `S` — how much unexplained departure has piled up.
        public let statistic: Double
        /// Consecutive days `S` has been above zero. What the card counts when
        /// it says "day 3".
        public let daysRunning: Int
        /// What this accumulation is worth on the daily statistic's own scale,
        /// so the two can be compared and rendered by one curve.
        ///
        /// Linear in `S`, anchored so that reaching the decision interval is
        /// worth exactly as much as a day at the strong-signs edge. That is a
        /// presentational choice and is stated as one: `S` and a daily excess
        /// are different quantities, and the only claim being made is that
        /// *arriving at each one's threshold means the same amount of concern*.
        public var excess: Double {
            statistic / Memory.decisionInterval * HealthWatchModel.strongSignsExcess
        }

        public static let none = Accumulation(statistic: 0, daysRunning: 0)
    }

    /// Run the CUSUM forward over a timeline, oldest day first.
    ///
    /// A day the watch could not evaluate contributes nothing and does **not**
    /// reset the accumulation — a night the ring spent on charge is missing
    /// evidence, not evidence of recovery. Treating it as a zero would quietly
    /// pull `S` down by the allowance for every day the reader forgot to wear
    /// something, which is a way of forgetting an illness because somebody
    /// stopped measuring it.
    public static func accumulation(over timeline: [DaySnapshot]) -> Accumulation {
        history(over: timeline).last?.accumulation ?? .none
    }

    // MARK: - S4: flagged days over time, and how they build

    /// **One day of the radar's history, as the reader would see it** — backlog
    /// `S4`, the reader's own idea: *"when sickness was flagged and how it
    /// builds"*.
    ///
    /// Both halves in one row, because the whole point of the chart is that they
    /// are different quantities: `score` is what the card said *that morning* on
    /// its own, and `accumulation` is what had piled up behind it. A day where
    /// the second is high and the first is not is the reader's own reported
    /// complaint — *"why am I now back at 99% just 1 day later?"* — made visible
    /// rather than argued about.
    public struct DayHistory: Sendable, Equatable, Identifiable {
        public let day: Date
        /// The output for that day, or nil where the watch could not judge it.
        /// **Kept nil rather than filled**, so a chart can leave a real gap: a
        /// night nothing was worn is missing evidence, and an interpolated
        /// point there would invent a reading.
        public let output: HealthWatchModel.Output?
        /// The accumulation as it stood at the end of that day. Carried
        /// unchanged across a day with no output, exactly as `accumulation`
        /// does — a night on charge is not evidence of recovery.
        public let accumulation: Accumulation
        /// What the card would have reported that morning, memory included.
        /// Nil on an unjudgeable day.
        public let status: SymptomRadarStatus?

        public var id: Date { day }
        /// The day's own score, before memory. Nil where nothing was judgeable.
        public var dailyScore: Double? { output?.score }
        /// True where the card was not quiet — the definition `dayCounters` and
        /// `episodes` already use, restated nowhere else.
        public var isFlagged: Bool { status != nil && status != .quiet }
    }

    /// The whole history in **one forward pass** over a timeline that was itself
    /// built in one pass.
    ///
    /// ⚠️ **Never `days × evaluate`.** `timeline(samples:days:endingAt:calendar:)`
    /// fetches each watched metric's daily series once and slides the windows;
    /// this walks the result once more to run the CUSUM. Rebuilding either per
    /// day would multiply score replay's cost by the span, which is exactly what
    /// a longer chart window would make expensive.
    ///
    /// The recurrence is the same three lines `accumulation` used to hold, and
    /// that method now reads its last row — so the chart and the card cannot
    /// disagree about what had accumulated by a given morning.
    public static func history(over timeline: [DaySnapshot]) -> [DayHistory] {
        var statistic = 0.0
        var daysRunning = 0
        var out: [DayHistory] = []
        out.reserveCapacity(timeline.count)
        for snapshot in timeline {
            if let output = snapshot.output {
                let daily = HealthWatchModel.standardised(output.signals)
                statistic = Swift.min(Memory.accumulationCap,
                                      Swift.max(0, statistic + daily - Memory.allowance))
                daysRunning = statistic > 0 ? daysRunning + 1 : 0
            }
            let memory = Accumulation(statistic: statistic, daysRunning: daysRunning)
            // The status the card would have shown, which is the *verdict's* —
            // today's number and the accumulation, whichever says more. Reusing
            // `verdict` rather than re-deriving the bands is the point: the
            // chart cannot drift from the card by construction.
            let status = snapshot.output.map { output -> SymptomRadarStatus in
                verdict(today: output, accumulation: memory).status
            }
            out.append(DayHistory(day: snapshot.day, output: snapshot.output,
                                  accumulation: memory, status: status))
        }
        return out
    }

    /// The history split into **runs of consecutive judgeable days**.
    ///
    /// A chart draws one line per run and never joins two, which is this repo's
    /// standing rule about gaps: a line crossing a fortnight the ring spent in a
    /// drawer asserts a trend nobody measured. The split lives here rather than
    /// in the view because it is a rule about what may look continuous, and this
    /// app has already learnt that such rules verified only by eye are not
    /// verified (`docs/… add-chart` §5).
    ///
    /// A single-day run is kept: one judged day between two blank stretches is a
    /// real point, and dropping it would quietly shorten the record.
    public static func runs(of history: [DayHistory],
                            calendar: Calendar = .current) -> [[DayHistory]] {
        var out: [[DayHistory]] = []
        for row in history where row.output != nil {
            if let last = out.last?.last,
               daysBetween(last.day, row.day, calendar: calendar) == 1 {
                out[out.count - 1].append(row)
            } else {
                out.append([row])
            }
        }
        return out
    }

    /// How far back the history chart looks.
    ///
    /// Twice `ledgerDays`, and the reason is the subject: the ledger grades the
    /// card over a window short enough that last winter is not marking this
    /// spring's homework, while a chart of *when the reader was ill* wants a
    /// season either side of one. Six months is also roughly two of an adult's
    /// two-to-four annual respiratory infections
    /// (`docs/illness-detection-evidence-2026-08-07.md`), so a chart this long
    /// should show a small number of stretches rather than a wall — and if it
    /// shows a wall, that is the false-alarm rate being visible, which is the
    /// honest outcome.
    public static let historyDays = 180

    /// Today's verdict, with memory — what the card actually reports.
    public struct Verdict: Sendable, Equatable {
        public let today: HealthWatchModel.Output
        public let accumulation: Accumulation
        public let score: Double
        public let status: SymptomRadarStatus
        /// True when the accumulation is saying more than today is — the case
        /// the reader reported, where the signals are still away from normal but
        /// a single-day comparison has stopped noticing.
        public let isCarriedForward: Bool
    }

    public static func verdict(today: HealthWatchModel.Output,
                               timeline: [DaySnapshot]) -> Verdict {
        verdict(today: today, accumulation: accumulation(over: timeline))
    }

    /// The same verdict against an accumulation already in hand.
    ///
    /// Split out for `history(over:)`, which walks the CUSUM forward once and
    /// has each day's memory at the moment it needs the day's status. The
    /// alternative — calling the timeline overload per day — would re-run the
    /// accumulation from the start on every row, turning one pass into `n²`.
    /// Splitting rather than copying is what stops the chart's bands drifting
    /// from the card's.
    public static func verdict(today: HealthWatchModel.Output,
                               accumulation memory: Accumulation) -> Verdict {
        let carried = memory.excess > today.excess
        let excess = Swift.max(today.excess, memory.excess)
        let score = HealthWatchModel.score(excess: excess)

        // The gates from `Output.status`, plus one for the accumulated path.
        let anythingHard = today.signals.contains {
            $0.isConcerning && abs($0.zScore) >= HealthWatchModel.strongZ
        }
        let status: SymptomRadarStatus
        if score >= 85 && !anythingHard {
            status = .quiet
        } else if score >= 50 {
            status = .someSigns
        } else if today.leaning.count >= 2
                    || memory.statistic >= Memory.decisionInterval {
            // Today's path needs two signals leaning, because agreement across
            // channels is the finding. The accumulated clause substitutes
            // agreement across *time* for it: sustained departure is evidence
            // of a different kind, and a lone channel pinned at its cap needs
            // some ten consecutive days to reach the decision interval.
            //
            // ⚠️ **What this clause does NOT do, and an earlier comment here
            // claimed it did: memory cannot reach `strongSigns` on its own.**
            // The arithmetic, because it is not obvious and a review had to
            // derive it: `Accumulation.excess` is `statistic / decisionInterval
            // * strongSignsExcess` and `accumulationCap == decisionInterval`, so
            // memory's excess maxes out at **exactly** `strongSignsExcess`;
            // `ScoreCurve.through` returns an anchor's score exactly at its
            // input; that anchor is (3.3, 50); so a memory-only day scores
            // exactly 50 and the `score >= 50` branch above always takes it
            // first.
            //
            // That is the intended design — "this has been going on for weeks"
            // is a quieter claim than "today is bad", and only the second gets
            // to be loud. The clause still earns its place for the case where
            // *today* is bad enough to score under 50 without two channels
            // leaning, and a maxed accumulation vouches for it. `SymptomRadarTests`
            // pins both halves so nobody has to derive this again.
            status = .strongSigns
        } else {
            status = .someSigns
        }
        return Verdict(today: today, accumulation: memory, score: score,
                       status: status, isCarriedForward: carried)
    }

    // MARK: - S3: how many nights it takes

    /// **How long a departure of a given size takes to reach the accumulation's
    /// decision interval** — backlog `S3`, the "nights to flag" figure.
    ///
    /// The arithmetic is the CUSUM's own and there is nothing else in it. While
    /// the body sits `excess` null SDs past ordinary, each night adds
    /// `excess − allowance` to `S`; the accumulation is a finding at
    /// `decisionInterval`; so the wait is
    ///
    ///     ⌈ decisionInterval / (excess − allowance) ⌉
    ///
    /// and a departure at or under the allowance never gets there at all, which
    /// is what `nil` means. **That is the honest answer and not a defect**: the
    /// allowance exists precisely so ordinary noise cannot accumulate, and a
    /// detector that eventually flags everything is a detector that has stopped
    /// saying anything.
    ///
    /// ⚠️ **A ceiling on a noiseless line, deliberately.** Real nights vary, and
    /// simulating the same recurrence with `N(excess, 1)` noise gives a mean
    /// wait very close to this and a median a night under it (measured at
    /// `excess` 1.0: deterministic 12, simulated mean 12.4, median 11). The
    /// deterministic figure is inside that spread, is reproducible without an
    /// RNG in shipped code, and is pinned by `SymptomRadarTests`. The sheet says
    /// "about", because none of these is a promise.
    ///
    /// ⚠️ **And it is a latency, never a sensitivity.** How long the card takes
    /// to notice a departure is a different question from how often a departure
    /// means illness, and the second one this app cannot answer:
    /// `docs/illness-detection-evidence-2026-08-07.md` puts prospective positive
    /// predictive value at 4–12%. The sheet that renders this must not let the
    /// first figure be read as the second.
    public static func nightsToFlag(atDailyExcess excess: Double) -> Int? {
        let perNight = excess - Memory.allowance
        guard perNight > 0 else { return nil }
        return Int((Memory.decisionInterval / perNight).rounded(.up))
    }

    /// The departures the "nights to flag" sheet lists, in null SDs.
    ///
    /// Four rows because four is what a reader can hold: one SD is the shift the
    /// allowance was chosen against (`k = δ/2`), three is a body that is
    /// unmistakably somewhere else, and the two between are where real illness
    /// actually sits.
    public static let flagLatencyExcesses: [Double] = [1.0, 1.5, 2.0, 3.0]

    /// A dose taken on day D covers days D through D+2 — the GI-effect window
    /// used everywhere in this feature.
    public static let doseWindowDays = 3
    /// A tag the day before an episode's first flag still confirms it…
    public static let tagLeadDays = 1
    /// …and up to three days after its last: symptoms routinely trail vitals.
    public static let tagTrailDays = 3

    /// One `Output` per calendar day, oldest first, `days` back from `now`.
    ///
    /// Fetches each watched metric's daily series **once** and slides the
    /// windows — never `days × evaluate`, which would multiply score replay's
    /// cost by the span. Per day D the anchor is `min(now, endOfDay(D))`, so a
    /// past day is judged exactly as `evaluate(samples:now:calendar:)` at the
    /// end of that day would have judged it — the shared window function
    /// range-filters both ends, so nothing after the anchor can leak in.
    public static func timeline(samples: [HealthMetricSample], days: Int,
                                endingAt now: Date, calendar: Calendar) -> [DaySnapshot] {
        guard days > 0 else { return [] }
        let series: [((metric: MetricType, risingIsConcerning: Bool, weight: Double),
                      [VitalReader.DailyValue])] = HealthWatchModel.watched.map { entry in
            (entry, VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                            calendar: calendar))
        }
        let today = calendar.startOfDay(for: now)
        var out: [DaySnapshot] = []
        out.reserveCapacity(days)
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)
            else { continue }
            let nowForDay = min(now, dayEnd)
            var signals: [HealthWatchModel.Signal] = []
            for (entry, daily) in series {
                if let signal = HealthWatchModel.signal(for: entry, daily: daily,
                                                        now: nowForDay) {
                    signals.append(signal)
                }
            }
            out.append(DaySnapshot(day: day,
                                   output: HealthWatchModel.output(fromEvaluated: signals)))
        }
        return out
    }

    /// A stretch of flagged days: start, peak, and each signal's return to
    /// baseline. This exists because the standing criticism of Whoop's Health
    /// Monitor is that it flags onset and then goes quiet — an episode has a
    /// start, a peak and a recovery per signal, and the card says all three.
    public struct SymptomRadarEpisode: Sendable, Equatable {
        public let start: Date
        public let end: Date
        /// The flag day with the lowest score; the earliest wins a tie.
        public let peakDay: Date
        public let peakScore: Double
        public let peakLeaningCount: Int
        /// Every metric that leaned on any flag day, in watched order — the
        /// canonical order, because which twin won the collapse can differ from
        /// day to day and a first-seen order would make equality flap.
        public let leaningMetrics: [MetricType]
        /// Per leaning metric, the first day strictly after the peak on which
        /// its signal was back inside the reader's range (|z| under the leaning
        /// threshold, or moving the healthy way).
        public let recoveries: [MetricType: Date]
    }

    /// Cut episodes from a timeline. A *flag day* is one whose output exists
    /// and is not quiet; two flag days join one episode when at most two
    /// non-flag days lie between them (a gap of three or more splits — one
    /// quiet morning mid-illness must not end the story).
    public static func episodes(in timeline: [DaySnapshot],
                                calendar: Calendar) -> [SymptomRadarEpisode] {
        let flagged = timeline.filter { snapshot in
            guard let output = snapshot.output else { return false }
            return output.status != .quiet
        }
        guard let first = flagged.first else { return [] }

        var groups: [[DaySnapshot]] = []
        var current: [DaySnapshot] = [first]
        for snapshot in flagged.dropFirst() {
            if let previous = current.last,
               daysBetween(previous.day, snapshot.day, calendar: calendar) <= 3 {
                current.append(snapshot)
            } else {
                groups.append(current)
                current = [snapshot]
            }
        }
        groups.append(current)

        return groups.compactMap { group in
            guard let start = group.first, let end = group.last,
                  let peak = group.min(by: { a, b in
                      let (sa, sb) = (a.output?.score ?? 100, b.output?.score ?? 100)
                      return sa == sb ? a.day < b.day : sa < sb
                  })
            else { return nil }

            var leaningSet = Set<MetricType>()
            for snapshot in group {
                for signal in snapshot.output?.leaning ?? [] { leaningSet.insert(signal.metric) }
            }
            let leaningMetrics = HealthWatchModel.watchedMetrics.filter { leaningSet.contains($0) }

            // Recovery is about the metric's own z, not its vote — so a signal
            // that lost the collapse on a given day (`discounted`) still counts
            // as observed that day.
            var recoveries: [MetricType: Date] = [:]
            let afterPeak = timeline.filter { $0.day > peak.day }
            for metric in leaningMetrics {
                for snapshot in afterPeak {
                    guard let output = snapshot.output,
                          let signal = (output.signals + output.discounted)
                              .first(where: { $0.metric == metric })
                    else { continue }
                    if abs(signal.zScore) < HealthWatchModel.leaningZ || !signal.isConcerning {
                        recoveries[metric] = snapshot.day
                        break
                    }
                }
            }

            return SymptomRadarEpisode(
                start: start.day, end: end.day, peakDay: peak.day,
                peakScore: peak.output?.score ?? 0,
                peakLeaningCount: peak.output?.leaning.count ?? 0,
                leaningMetrics: leaningMetrics, recoveries: recoveries)
        }
    }

    /// The card's own report card, recomputed pure on every evaluation — it
    /// lives nowhere persistent, so replayed history and the live card can
    /// never disagree with a stored copy.
    ///
    /// `flags` counts every flagged stretch; the card's sentence reports only
    /// `hits + unconfirmed`, because a `pending` episode's confirmation window
    /// is still open and an ongoing stretch must not be accused of silence.
    public struct SymptomRadarLedger: Sendable, Equatable {
        /// Days in the window the watch could actually evaluate.
        public let gradedDays: Int
        /// Episodes with a present, non-dose-explained tag in their window —
        /// excluding tag types this reader logs on most days, which confirm
        /// nothing (see `chronicTypes` in `ledger`).
        public let hits: Int
        /// Episodes whose window elapsed with no such tag — stated openly.
        public let unconfirmed: Int
        /// Episodes whose window is still open.
        public let pending: Int
        /// Infection-like tag clusters the radar had data for and never flagged.
        public let misses: Int
        public var flags: Int { hits + unconfirmed + pending }

        // MARK: The day counters — backlog #36, added 2026-08-06
        //
        // ⚠️ **All three were already computed inside `ledger` and thrown
        // away.** `flags` counts *episodes*, which is why no flag **rate** was
        // printable: a reader asking "how often does this card cry wolf" is
        // asking about days, and the app had the day set in hand and discarded
        // it every single evaluation.
        //
        // The reason it matters more than three counters usually would: the
        // radar's whole thesis is early detection, and its own research figure
        // is 43% sensitivity at 95% specificity — so "no signs" is not
        // reassurance and the card is supposed to say so *with numbers*. It had
        // none of its own to say it with.

        /// Days in the window on which the card was not quiet.
        public let flaggedDays: Int
        /// Days it reached its strongest band, whatever that band is called.
        public let strongDays: Int
        /// Days in the window at all, graded or not — the denominator for
        /// coverage, which is a different question from the flag rate.
        public let windowDays: Int

        /// How often this card spoke, over the days it could actually judge.
        ///
        /// Nil rather than zero when nothing was gradeable: "it never flagged"
        /// and "it never had anything to look at" are opposite statements and a
        /// 0% would say the first while meaning the second.
        public var flagRate: Double? {
            gradedDays > 0 ? Double(flaggedDays) / Double(gradedDays) : nil
        }

        /// What fraction of the window the card could judge at all. **The
        /// number that makes a quiet radar readable**: a green card over 30%
        /// coverage means something very different from one over 95%.
        public var coverage: Double? {
            windowDays > 0 ? Double(gradedDays) / Double(windowDays) : nil
        }

        public init(gradedDays: Int, hits: Int, unconfirmed: Int, pending: Int,
                    misses: Int, flaggedDays: Int = 0, strongDays: Int = 0,
                    windowDays: Int = 0) {
            self.gradedDays = gradedDays
            self.hits = hits
            self.unconfirmed = unconfirmed
            self.pending = pending
            self.misses = misses
            self.flaggedDays = flaggedDays
            self.strongDays = strongDays
            self.windowDays = windowDays
        }
    }

    /// **How often this card spoke, and how much it could see** — the four day
    /// counters, with no symptom log and no medication schedule in scope.
    ///
    /// Split out of `ledger` deliberately rather than letting a caller pass
    /// empty inputs to get the same numbers. The counters genuinely do not
    /// depend on tags or doses — only `hits`, `unconfirmed`, `pending` and
    /// `misses` do — and a call site that fakes two arguments to reach a third
    /// result is one refactor away from a caller who fakes them and *does* read
    /// the grades. Backlog #36.
    public static func dayCounters(samples: [HealthMetricSample], now: Date = Date(),
                                   calendar: Calendar = .current) -> SymptomRadarLedger {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(ledgerDays - 1), to: today)
            ?? today
        let timeline = SymptomRadarModel.timeline(samples: samples, days: ledgerDays,
                                                  endingAt: now, calendar: calendar)
        let graded = timeline.filter { $0.day >= windowStart && $0.day <= today }
        return SymptomRadarLedger(
            gradedDays: graded.filter { $0.output != nil }.count,
            hits: 0, unconfirmed: 0, pending: 0, misses: 0,
            flaggedDays: graded.filter { ($0.output?.status ?? .quiet) != .quiet }.count,
            strongDays: graded.filter { $0.output?.status == .strongSigns }.count,
            windowDays: daysBetween(windowStart, today, calendar: calendar) + 1)
    }

    public static func ledger(timeline: [DaySnapshot], symptoms: [SymptomEvent],
                              medication: MedicationSchedule?, now: Date,
                              calendar: Calendar) -> SymptomRadarLedger {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(ledgerDays - 1), to: today)
            ?? today
        let graded = timeline.filter { $0.day >= windowStart && $0.day <= today }
        let gradedDays = graded.filter { $0.output != nil }.count

        // Everything the grade reads is clipped to `now` — the model itself is
        // what keeps score replay honest, not its caller.
        var presentByDay: [Date: [SymptomEvent]] = [:]
        for event in symptoms where event.date <= now && event.severity.isPresent {
            presentByDay[calendar.startOfDay(for: event.date), default: []].append(event)
        }
        let qualifyingDoseDays: [Date] = (medication?.doses ?? [])
            .filter { !$0.isInferred && $0.takenAt <= now }
            .map { calendar.startOfDay(for: $0.takenAt) }

        func doseCovers(_ day: Date) -> Bool {
            qualifyingDoseDays.contains { doseDay in
                let gap = daysBetween(doseDay, day, calendar: calendar)
                return gap >= 0 && gap < doseWindowDays
            }
        }
        // A day is dose-explained only when *every* present tag on it is a
        // recognised GLP-1 effect and a qualifying dose's window covers it. An
        // infection-like tag can never be dose-explained — the two clusters are
        // disjoint by construction (`SymptomTests.testTheTwoClustersDoNotOverlap`).
        func isDoseExplained(day: Date, tags: [SymptomEvent]) -> Bool {
            guard !tags.isEmpty else { return false }
            return tags.allSatisfy { $0.type.isCommonGLP1Effect } && doseCovers(day)
        }

        // A tag type this reader logs most days cannot confirm an episode —
        // the same reasoning that keeps fatigue out of `isInfectionLike`, one
        // level up: a menopausal reader tagging hot flushes every evening
        // would otherwise "confirm" every stretch the radar ever flags, and a
        // 100% hit rate built that way carries zero information (2026-08-04).
        // The denominator is the whole 90-day window, not graded days, so a
        // fortnight of dense tagging in a young account is not called chronic.
        let windowDayCount = daysBetween(windowStart, today, calendar: calendar) + 1
        var presentDaysByType: [SymptomType: Set<Date>] = [:]
        for (day, tags) in presentByDay where day >= windowStart && day <= today {
            for event in tags { presentDaysByType[event.type, default: []].insert(day) }
        }
        let chronicTypes = Set(presentDaysByType
            .filter { Double($0.value.count) > 0.4 * Double(windowDayCount) }
            .keys)

        var hits = 0, unconfirmed = 0, pending = 0
        for episode in episodes(in: graded, calendar: calendar) {
            guard let confirmStart = calendar.date(byAdding: .day, value: -tagLeadDays,
                                                   to: episode.start),
                  let confirmEnd = calendar.date(byAdding: .day, value: tagTrailDays,
                                                 to: episode.end)
            else { continue }
            let confirmed = presentByDay.contains { day, tags in
                guard day >= confirmStart && day <= confirmEnd else { return false }
                // `gradesTheRadar`, so the confirm side and the miss side draw
                // from one population. Without it a mood tag could raise the hit
                // rate and never the miss rate — see `SymptomType.gradesTheRadar`.
                let signal = tags.filter {
                    !chronicTypes.contains($0.type) && $0.type.gradesTheRadar
                }
                return !signal.isEmpty && !isDoseExplained(day: day, tags: signal)
            }
            if confirmed {
                hits += 1
            } else if confirmEnd > today {
                pending += 1
            } else {
                unconfirmed += 1
            }
        }

        // Misses: cluster the infection-like tag days (≤ 3 days apart joins),
        // grade a cluster only where the radar had output to flag with, and
        // call it a miss when no flag day falls in [clusterStart − 3, clusterEnd].
        // `isInfectionLike`, deliberately narrower than the confirm side above:
        // a tag that fires on every bad night would make a miss of every bad
        // night. The asymmetry is documented on that property.
        let infectionDays = presentByDay
            .filter { _, tags in tags.contains { $0.type.isInfectionLike } }
            .keys.sorted()
        var clusters: [[Date]] = []
        for day in infectionDays {
            if let last = clusters.last?.last,
               daysBetween(last, day, calendar: calendar) <= 3 {
                clusters[clusters.count - 1].append(day)
            } else {
                clusters.append([day])
            }
        }
        let outputDays = graded.compactMap { $0.output != nil ? $0.day : nil }
        let flagDays = graded.compactMap { snapshot -> Date? in
            guard let output = snapshot.output, output.status != .quiet else { return nil }
            return snapshot.day
        }
        var misses = 0
        for cluster in clusters {
            guard let clusterStart = cluster.first, let clusterEnd = cluster.last,
                  let rangeStart = calendar.date(byAdding: .day, value: -tagTrailDays,
                                                 to: clusterStart)
            else { continue }
            let gradeable = outputDays.contains { $0 >= rangeStart && $0 <= clusterEnd }
            let flaggedInRange = flagDays.contains { $0 >= rangeStart && $0 <= clusterEnd }
            if gradeable && !flaggedInRange { misses += 1 }
        }

        let strongDays = graded.filter { $0.output?.status == .strongSigns }.count

        return SymptomRadarLedger(gradedDays: gradedDays, hits: hits,
                                  unconfirmed: unconfirmed, pending: pending,
                                  misses: misses,
                                  // `flagDays` is built above for the miss
                                  // calculation and was discarded with it.
                                  flaggedDays: flagDays.count,
                                  strongDays: strongDays,
                                  windowDays: windowDayCount)
    }

    /// Whole calendar days from `a` to `b` — signed, so callers can ask both
    /// "how long ago" and "how far ahead".
    static func daysBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a),
                                to: calendar.startOfDay(for: b)).day ?? 0
    }
}

/// The card: `HealthWatchModel` rendered directly, graded against the reader's
/// own symptom tags (roadmap #31) — *which signals moved* is more actionable
/// than a score, and the early warning got its own card back for exactly that.
///
/// The shaping constraint is the best published prospective validation of this
/// approach — sleep resting HR, respiratory rate and HRV over 470 health-care
/// workers (JMIR Formative Research, 2024): **43% sensitivity at 95%
/// specificity**. A model of this kind misses more than half of real
/// illnesses, so the quiet state says so where every competitor puts a green
/// tick, and the card keeps a hit/miss ledger against the reader's own tags
/// rather than asking to be believed.
public struct SymptomRadarInsight: InsightModel {
    public let id: InsightID = .symptomRadar
    public let title = "Symptom radar"
    /// Construction state, rebound by `InsightEngine.withSymptoms(_:medication:)`
    /// on every recompute — the SubstanceImpact pattern, chosen over a third
    /// `evaluate` overload on the add-insight skill's explicit guidance.
    /// Everything read from either is clipped to `date <= now` inside
    /// `evaluate`, which is what keeps score replay honest.
    public let symptoms: [SymptomEvent]
    public let medication: MedicationSchedule?
    /// `.current` in production (the engine rebinds with the default); injected
    /// as `TestClock.utc` by tests, because day-precise assertions made against
    /// a machine-local calendar fail abroad — the exact class the Oura parser's
    /// calendar injection closed on 2026-08-04.
    let calendar: Calendar

    public init(symptoms: [SymptomEvent] = [], medication: MedicationSchedule? = nil,
                calendar: Calendar = .current) {
        self.symptoms = symptoms
        self.medication = medication
        self.calendar = calendar
    }

    /// Built entirely from sensed signals against the reader's own history —
    /// nothing to ask the profile for.
    public var requirements: [GroundingRequirement] { [] }
    /// The log is construction state, not `samples`.
    public var readsOnlySamples: Bool { false }
    public var candidateMetrics: [MetricType] { HealthWatchModel.watchedMetrics }
    /// The tags arrive from Apple Health rather than an in-app sheet, so the
    /// route views and guides instead of opening one — see `.symptomLog`.
    public var contributions: [ContributionRoute] { [.symptomLog] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let watch = HealthWatchModel.evaluate(samples: samples, now: now,
                                                    calendar: calendar) else {
            return unscoredResult(samples: samples, now: now)
        }

        let timeline = SymptomRadarModel.timeline(samples: samples,
                                                  days: SymptomRadarModel.ledgerDays,
                                                  endingAt: now, calendar: calendar)
        let episodes = SymptomRadarModel.episodes(in: timeline, calendar: calendar)
        let tags = symptoms.filter { $0.date <= now }
        let schedule = medication.map { bound in
            MedicationSchedule(compound: bound.compound,
                               doses: bound.doses.filter { $0.takenAt <= now })
        }
        let ledger = SymptomRadarModel.ledger(timeline: timeline, symptoms: tags,
                                              medication: schedule, now: now,
                                              calendar: calendar)
        let today = calendar.startOfDay(for: now)
        // The verdict, not the day: `watch.status` alone is what put the reader
        // back at 99% the morning after a correct flag.
        let verdict = SymptomRadarModel.verdict(today: watch, timeline: timeline)
        let status = verdict.status

        // The episode the reader is in, or just out of. Ongoing while the last
        // flag day is at most two days old; a closed episode is still worth a
        // recap for a day after that.
        let last = episodes.last
        let sinceEnd = last.map {
            SymptomRadarModel.daysBetween($0.end, today, calendar: calendar)
        }
        let ongoing = (sinceEnd ?? .max) <= 2 ? last : nil
        let recentlyClosed = ongoing == nil && (sinceEnd ?? .max) <= 3 ? last : nil
        let dayN = ongoing.map {
            SymptomRadarModel.daysBetween($0.start, today, calendar: calendar) + 1
        } ?? 1

        let headline: String
        switch status {
        case .quiet: headline = "Nothing stirring"
        case .someSigns: headline = "Some signs — day \(dayN)"
        case .strongSigns: headline = "Strong signs — day \(dayN)"
        }

        // #32: the 43% sentence lives in the quiet state, where every
        // competitor puts a green tick. It is the most important sentence on
        // the card and `SymptomRadarTests` pins it to `drivers.first`.
        let explanation: String
        if status == .quiet {
            // The first clause must agree with the radar web drawn beneath it.
            // Quiet is score >= 85 — concern <= 0.3 — which admits a genuinely
            // leaning signal (a lone SpO2 at z ≈ −1.5 scores 87.5), and the web
            // draws that dot past the inner ring under a caption saying "dots
            // past the inner ring are leaning". "None is leaning" printed above
            // it would be a falsehood visible on the same page (2026-08-04) —
            // and quiet copy overstating quietness is exactly the direction
            // this card promises not to err in.
            let quietLead: String
            if watch.leaning.isEmpty {
                quietLead = "None of your watched signals is leaning the way "
                    + "illness pushes them, judged against your own three-week "
                    + "baseline."
            } else if watch.leaning.count == 1, let only = watch.leaning.first {
                quietLead = "Only one signal — \(only.metric.displayName) — is a "
                    + "touch outside your usual range, on its own inside the "
                    + "noise; nothing else is leaning with it, judged against "
                    + "your own three-week baseline."
            } else {
                quietLead = "\(watch.leaning.count) signals are a touch outside "
                    + "your usual range — each barely past leaning, together "
                    + "still inside the noise, judged against your own "
                    + "three-week baseline."
            }
            explanation = quietLead + " Read "
                + "the quiet carefully: in the best published test of this approach "
                + "— sleep heart rate, breathing rate and HRV across 470 "
                + "health-care workers — it caught 43% of confirmed illnesses at "
                + "95% specificity. Quiet here misses more than half of them. If "
                + "you feel unwell, that is the better information."
        } else {
            let suffix = status == .someSigns
                ? " Signs, not certainty — this pattern also follows a poor night, alcohol, or hard training."
                : " Several signals agree, and agreement is the finding."
            explanation = "\(watch.leaning.count) of \(watch.signals.count) watched "
                + "signals are leaning the way illness pushes them, judged against "
                + "your own three-week baseline — which ends four days ago, so a "
                + "run cannot hide in its own average. Votes accumulate here: "
                + "several small agreeing moves outrank one dramatic number."
                + suffix
        }

        var lines: [InsightDriver] = []
        // **The reader's question, answered on the card.** When the accumulation
        // is carrying the verdict, the single-day numbers below it will look
        // milder than the headline — and an unexplained mismatch between a
        // headline and the rows under it is exactly the "the app does not show
        // its work" complaint that runs through this whole category.
        if verdict.isCarriedForward && status != .quiet {
            lines.append(.notable(
                "Still counting: your signals have been away from your usual for "
                + "\(verdict.accumulation.daysRunning) days running. Today on its own looks "
                + "milder than that, partly because your recent baseline has "
                + "started to absorb the stretch it is being compared with — so "
                + "this keeps the run in view rather than starting again each "
                + "morning."))
        }
        if status == .quiet {
            lines.append(.notable(
                "Quiet is not an all-clear: this kind of watch catches fewer than "
                + "half of real illnesses (43% in its best published test). How "
                + "you feel outranks it."))
            if let episode = recentlyClosed {
                let length = SymptomRadarModel.daysBetween(episode.start, episode.end,
                                                           calendar: calendar) + 1
                let recovered = episode.leaningMetrics
                    .filter { episode.recoveries[$0] != nil }.count
                let tail = !episode.leaningMetrics.isEmpty
                    && recovered == episode.leaningMetrics.count
                    ? "every signal is back inside your usual range"
                    : "\(recovered) of \(episode.leaningMetrics.count) signals back inside your usual range"
                lines.append(.routine(
                    "Settled: a \(length)-day stretch ended "
                    + "\(weekdayName(episode.end)); \(tail)."))
            }
            lines.append(ledgerDriver(ledger))
        } else {
            // #33 and #34 as behaviour: name the confounder from data the app
            // already holds, and never let a dose explain an infection-like
            // tag. The clusters are disjoint by construction
            // (SymptomTests.testTheTwoClustersDoNotOverlap), so the two
            // explanations can always be told apart.
            let windowTags = tags.filter { event in
                guard event.severity.isPresent else { return false }
                let gap = SymptomRadarModel.daysBetween(event.date, today,
                                                        calendar: calendar)
                return gap >= 0 && gap <= 2
            }
            let giTags = windowTags.filter { $0.type.isCommonGLP1Effect }
            let infTags = windowTags.filter { $0.type.isInfectionLike }
            // Only doses the reader entered or confirmed count (`isInferred`
            // false — a confirmed extrapolation arrives cleared, see
            // `DoseLogRecord.administered`): the app may guess out loud, and
            // may not act on its own guess as though the reader had said it.
            let qualifying = (schedule?.doses ?? []).filter { !$0.isInferred }
            let nearDose = qualifying.last { dose in
                let gap = SymptomRadarModel.daysBetween(dose.takenAt, today,
                                                        calendar: calendar)
                return gap >= 0 && gap < SymptomRadarModel.doseWindowDays
            }
            let stepUpFrom: Double? = nearDose.flatMap { dose in
                qualifying.last { $0.takenAt < dose.takenAt }
                    .flatMap { $0.milligrams < dose.milligrams ? $0.milligrams : nil }
            }

            var leadIsNeutral = false
            var confounders: [InsightDriver] = []
            if let dose = nearDose, let schedule {
                // Only GI tags dated on or after the dose day can be the
                // dose's effects — the same `gap >= 0` rule `doseCovers`
                // applies in the ledger. Without this, nausea tagged two days
                // *before* this morning's dose (early gastroenteritis) would
                // suppress the illness lead and the copy would say "tagged …
                // since", a temporally impossible attribution — the mirror
                // image of the defect this table exists to prevent
                // (2026-08-04). Pre-dose GI tags fall through to the
                // dose-present-no-GI row: illness lead retained, overlap note
                // still naming the dose.
                let sinceDose = giTags.filter { event in
                    SymptomRadarModel.daysBetween(dose.takenAt, event.date,
                                                  calendar: calendar) >= 0
                }
                let compound = schedule.compound.displayName.lowercased()
                let doseDay = weekdayName(dose.takenAt)
                let step = stepUpFrom.map {
                    ", stepping up from \(Self.milligrams($0)) mg"
                } ?? ""
                let overlap = InsightDriver.routine(
                    "This overlaps the days after your \(doseDay) \(compound) "
                    + "dose\(step). Dose days can move these same signals, so "
                    + "keep that in the picture.")
                if !sinceDose.isEmpty && infTags.isEmpty {
                    // The one case that downgrades the illness phrasing: the
                    // dose is named as the likelier explanation *alongside* the
                    // finding — the signals, the score and the radar all still
                    // render. Never instead of.
                    leadIsNeutral = true
                    confounders.append(.notable(
                        "You took \(compound) \(Self.milligrams(dose.milligrams)) mg "
                        + "on \(doseDay)\(step) and tagged \(namedList(sinceDose)) "
                        + "since. Those are the drug's most common effects, and "
                        + "the likelier explanation for what these signals show — "
                        + "though a stomach bug can look identical, so if this "
                        + "worsens or lingers, believe your body over this card."))
                } else if !sinceDose.isEmpty {
                    confounders.append(.notable(
                        "You tagged \(namedList(infTags)) — not a known "
                        + "\(compound) effect — alongside \(namedList(sinceDose)), "
                        + "which is. The dose may explain the stomach's part of "
                        + "this; it does not explain \(firstName(infTags))."))
                } else if !infTags.isEmpty {
                    // Not a row in the design table, which covers (dose, GI,
                    // infection-like) as (yes, yes, *) and (yes, no, no). A dose
                    // with *only* infection-like tags gets the acknowledgement a
                    // doseless one would — an infection-like tag is never
                    // dose-explained — plus the overlap note, because hiding
                    // either half would be the dishonest option.
                    confounders.append(.notable(
                        "You tagged \(namedList(infTags)) yourself — taken with "
                        + "these signals, your body is telling the same story "
                        + "from two directions."))
                    confounders.append(overlap)
                } else {
                    confounders.append(overlap)
                }
            } else if !infTags.isEmpty {
                confounders.append(.notable(
                    "You tagged \(namedList(infTags)) yourself — taken with these "
                    + "signals, your body is telling the same story from two "
                    + "directions."))
            } else if !giTags.isEmpty {
                confounders.append(.routine(
                    "You tagged \(namedList(giTags)), with no dose in the last "
                    + "three days to explain them, so nothing here writes them "
                    + "off."))
            }

            let leaning = watch.leaning
            lines.append(.notable(lead(count: leaning.count,
                                       single: leaning.first?.metric,
                                       neutral: leadIsNeutral)))
            for signal in leaning {
                let hard = abs(signal.zScore) >= HealthWatchModel.strongZ
                lines.append(.notable(
                    "\(signal.metric.displayName): "
                    + "\(MetricValueFormatter.string(signal.recent, signal.metric)) "
                    + "against "
                    + "\(MetricValueFormatter.string(signal.reference, signal.metric)) "
                    + "usual — leaning\(hard ? " hard" : "")."))
            }
            lines.append(contentsOf: confounders)
            // #35: the episode, not just the onset — day count, the hardest day
            // so far, and each signal's return to baseline.
            if let episode = ongoing, dayN >= 2 {
                lines.append(.routine(
                    "Day \(dayN) of this stretch — hardest so far "
                    + "\(weekdayName(episode.peakDay)), \(episode.peakLeaningCount) "
                    + "signals leaning."))
                for metric in episode.leaningMetrics {
                    guard let day = episode.recoveries[metric] else { continue }
                    lines.append(.routine(
                        "\(metric.displayName) back inside your usual range since "
                        + "\(weekdayName(day))."))
                }
            }
            // The unseen confounder, named on-card until cycle tracking exists:
            // a luteal phase moves resting HR, breathing and HRV in exactly the
            // pattern this card reads as illness (docs/planned-modules.md ▸
            // "the cycle warning"). The card must not silently compete with it.
            if profile.sex == .female {
                lines.append(.routine(
                    "One thing this cannot see yet: cycle phase. Late-cycle days "
                    + "push resting heart rate, breathing and HRV in exactly this "
                    + "direction, and this card cannot tell that pattern from an "
                    + "early illness."))
            }
            lines.append(ledgerDriver(ledger))
        }

        return InsightResult(
            id: id, title: title, primaryValue: verdict.score, headline: headline,
            score: verdict.score,
            // Never `.high`: a validated approach applied bluntly — the same
            // restraint as Energy's `testItNeverClaimsToBeAMeasurement`.
            confidence: .moderate,
            explanation: explanation,
            // Notable-first, the same partition Readiness applies: the Today
            // preview shows `drivers.first`, so a routine line arriving after a
            // notable one must not be able to reach the front.
            driverLines: lines.filter { $0.isNotable == true }
                + lines.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: contributors(for: watch),
            weighting: .accumulative,
            otherFactors: Self.producedFigures(verdict),
            derivedOutputs: Self.derivedOutputs(verdict))
    }

    // MARK: - What this card works out (2026-08-06)
    //
    // **The accumulated statistic is the reason this card exists**, and until
    // now nothing kept it. `S` is a CUSUM run forward over the whole timeline —
    // a quantity with *memory*, which is precisely what no daily reading has and
    // what no per-metric departure can be recovered into. The reader's own
    // complaint about it was that a correct flag was followed by a 99% the next
    // morning; the fix was to carry `S` forward, and the figure that fix turns
    // on had no history of its own.
    //
    // ## Refused
    //
    // - **Each signal's `zScore`** — one metric against its own three-week
    //   baseline. The reader's stated exception, and already harvested from
    //   `MetricContribution.z` for free.
    // - **`leaning.count`** — a threshold count over those same z-scores.
    //   Deliberately *not* kept, and the reason is this card's founding
    //   argument: counting signals past a threshold is the OR-of-six mistake
    //   (a 26.5% false-alarm rate) that the accumulated statistic replaced. A
    //   series of it would be trending the discarded method.

    static let statisticKey = "accumulatedStatistic"
    static let daysRunningKey = "daysRunning"

    static func derivedOutputs(_ verdict: SymptomRadarModel.Verdict) -> [DerivedOutput] {
        [
            .init(key: statisticKey, displayName: "Accumulated departure",
                  unit: "", value: verdict.accumulation.statistic,
                  higherIsBetter: false, precision: 2),
            .init(key: daysRunningKey, displayName: "Days running above your usual",
                  unit: "days", value: Double(verdict.accumulation.daysRunning),
                  higherIsBetter: false, precision: 0),
        ]
    }

    /// ⚠️ Weight 0 — see `ScoreFactor.producedFigure`. This card's basis is
    /// `.accumulative`: each signal's vote carries its weight, and the
    /// accumulation is what those votes pile into. Giving the pile a vote of its
    /// own would count every one of them a second time.
    static func producedFigures(_ verdict: SymptomRadarModel.Verdict) -> [ScoreFactor] {
        [
            .producedFigure(
                DerivedSeriesID(.symptomRadar, statisticKey),
                name: "Accumulated departure",
                detail: String(format: "%.2f, built up over %d day%@ running — this is where the votes below accumulate, so it carries no vote itself%@.",
                               verdict.accumulation.statistic,
                               verdict.accumulation.daysRunning,
                               verdict.accumulation.daysRunning == 1 ? "" : "s",
                               verdict.isCarriedForward
                                   ? " — and today it is saying more than today's readings are"
                                   : ""))
        ]
    }

    // MARK: - The two empty states

    /// Mirrors Readiness's split (ReadinessScore.swift): an established
    /// baseline waiting on today's sync is the opposite morning from a fresh
    /// install, and they need opposite sentences.
    private func unscoredResult(samples: [HealthMetricSample], now: Date) -> InsightResult {
        let recorded = HealthWatchModel.watchedMetrics
            .flatMap { samples.samples(of: $0) }
            .map(\.start)
        let recordedDays = Set(recorded.map { calendar.startOfDay(for: $0) })
        if let latest = recorded.max(),
           recordedDays.count >= HealthWatchModel.minimumReferenceDays {
            let days = max(1, Int(now.timeIntervalSince(latest) / 86_400))
            if days <= 3 {
                let age = days == 1 ? "yesterday" : "\(days) days ago"
                return InsightResult(
                    id: id, title: title, primaryValue: nil,
                    headline: "Waiting for today's sync",
                    score: nil, confidence: .low,
                    explanation: "The radar scores your last three days against "
                        + "your own three-week baseline, and today's data hasn't "
                        + "arrived — your latest readings are from \(age). This "
                        + "fills in on its own once your wearable syncs; pull to "
                        + "refresh to ask again.",
                    drivers: [], unmetRequirements: [],
                    isAwaitingTodaysData: true)
            }
        }
        // The imperative headline is the CardVisibilityTests contract: a card
        // that invites input must lead with the ask, not with "No data yet".
        return invitingInput(
            id, title,
            action: "Wear your watch to sleep",
            message: "The radar watches seven overnight signals — skin "
                + "temperature (absolute and deviation), resting heart rate, HRV "
                + "(two measures), breathing rate and blood oxygen — for several "
                + "leaning the illness way at once. It needs about three weeks "
                + "of nights to learn your normal before it can say anything. "
                + "One honesty note up front: even at its best, this approach "
                + "catches fewer than half of real illnesses (43% at 95% "
                + "specificity in its best published test), so it will never "
                + "replace how you feel.")
    }

    // MARK: - Pieces

    /// One `MetricContribution` per evaluated signal. Voting signals carry
    /// their vote's share (watched weight over the sum of surviving weights —
    /// always positive, sums to 1); collapse losers ride at weight 0 with the
    /// reason on their own row, because "counted once with its twin" and "not
    /// looked at" are opposite statements and a missing row says the second.
    /// The zero rows are also what keeps every declared candidate reachable
    /// (`CandidateReachabilityTests`) — the collapse spans whole measurement
    /// bases, wider than `interchangeableGroups`.
    private func contributors(for watch: HealthWatchModel.Output) -> [MetricContribution] {
        let votingTotal = watch.signals.reduce(0.0) {
            $0 + HealthWatchModel.weight(for: $1.metric)
        }
        func direction(_ metric: MetricType) -> Bool? {
            HealthWatchModel.risingIsConcerning(for: metric).map { !$0 }
        }
        func reading(_ signal: HealthWatchModel.Signal) -> String {
            "\(MetricValueFormatter.string(signal.recent, signal.metric)) vs "
                + "\(MetricValueFormatter.string(signal.reference, signal.metric)) usual"
        }
        // **The decomposition fields, and why one of the four stays nil.**
        //
        // Backlog D25: a weighted row that reports no sub-score is a card whose
        // deep dive cannot show its own working. Every one of these rows carried
        // a share and nothing else — so the radar was the widest of the four
        // weighted gaps, at seven signals.
        //
        // `componentScore` is **deliberately still nil**, and that is not the
        // gap. The radar scores a *pooled* excess through a single curve
        // (`HealthWatchModel.score(excess:)`), so no individual signal owns a
        // 0–100; the card declares `.accumulative` for exactly that reason and
        // `ScoreDecomposition` therefore refuses a counterfactual on it. Minting
        // a per-signal 0–100 here would license arithmetic the curve cannot
        // honour — the same refusal Sustained Load, Gait and Mental Health make
        // (ScoreDecompositionTests ▸
        // `testTheBaselineWindowModelsShowTheirWorkingAndDeclineASubScore`).
        //
        // What each signal *does* genuinely hold is now on the row: the recent
        // window, the reference it was judged against, and the departure between
        // them. `Signal` has carried all three since it was written — they were
        // being formatted into `detail` and then thrown away, which also cost
        // the Data tab a `componentDeparture` series per signal for free
        // (`DerivedHarvest.series(from:)`).
        func decomposed(_ signal: HealthWatchModel.Signal,
                        weight: Double, detail: String) -> MetricContribution {
            MetricContribution(
                metric: signal.metric,
                higherIsBetter: direction(signal.metric),
                weight: weight,
                detail: detail,
                value: signal.recent,
                baseline: signal.reference,
                // Signed as the metric is measured — `(recent − reference) / SD`
                // — never as "good" or "bad", so a reader of the series can
                // render direction themselves. `isConcerning` is the model's
                // reading of that sign and is already on the row's wording.
                z: signal.zScore)
        }

        var out: [MetricContribution] = watch.signals.map { signal in
            decomposed(signal,
                       weight: votingTotal > 0
                           ? HealthWatchModel.weight(for: signal.metric) / votingTotal
                           : 0,
                       detail: reading(signal))
        }
        for signal in watch.discounted {
            let winner = watch.signals.first {
                $0.metric.sharesMeasurementBasis(with: signal.metric)
            }?.metric
            // A collapse loser was evaluated in full and then folded into its
            // twin's vote, so it has the same three numbers to show. Weight 0
            // says it carries none of the score; nil there would say it was
            // never looked at, which is the opposite statement this whole block
            // exists to avoid.
            out.append(decomposed(signal, weight: 0,
                                  detail: reading(signal) + " — counted once with "
                                      + (winner?.displayName ?? "its twin")))
        }
        return out
    }

    /// The lead line. The plural illness form is the shipped Readiness driver,
    /// copied verbatim (ReadinessScore.swift:273) so the two surfaces say the
    /// same sentence — modifying `ReadinessInsight` is out of bounds, so a
    /// test pins the shared phrase instead of a shared symbol. The neutral
    /// form replaces only the middle clause; the disclaimer always travels
    /// with the finding, not just the card.
    private func lead(count: Int, single: MetricType?, neutral: Bool) -> String {
        let disclaimer = "An observation about your own numbers, not a diagnosis "
            + "— if you feel unwell, treat that as the better information."
        guard count >= 2 else {
            // The plural sentences don't survive count == 1 ("1 signals are…"),
            // and one signal alone has not earned the illness framing — the
            // score already agrees, since a single vote cannot pass someSigns.
            let name = single?.displayName ?? "one of your vitals"
            return "One signal is leaning the way illness pushes it — \(name), "
                + "still inside the noise on its own. \(disclaimer)"
        }
        let middle = neutral
            ? "together a pattern worth watching"
            : "together the pattern a body tends to show before an illness announces itself"
        return "\(count) signals are leaning the same way at once — individually "
            + "inside the noise, \(middle). \(disclaimer)"
    }

    /// #36: the card grades itself out loud — hits, silences and misses — on
    /// the pattern the blood-pressure estimator already ships. Pending episodes
    /// are excluded from the sentence: a window still open is not a silence.
    private func ledgerDriver(_ ledger: SymptomRadarModel.SymptomRadarLedger) -> InsightDriver {
        let reportable = ledger.hits + ledger.unconfirmed
        guard reportable > 0 || ledger.misses > 0 else {
            return .routine(
                "No track record with you yet: when you feel unwell, tag "
                + "symptoms in Apple Health (Browse ▸ Symptoms) and this card "
                + "will keep score against them — misses included.")
        }
        let weeks = max(1, Int((Double(ledger.gradedDays) / 7).rounded()))
        let missClause = ledger.misses == 0 && ledger.gradedDays > 0 && reportable > 0
            ? "and has missed none you tagged"
            : "and it missed \(ledger.misses) you tagged without a flag"
        return .routine(
            "Its record with you: over the last \(weeks) weeks it flagged "
            + "\(reportable) stretch\(reportable == 1 ? "" : "es") — "
            + "\(ledger.hits) matched symptoms you tagged, \(ledger.unconfirmed) "
            + "heard nothing back — \(missClause).")
    }

    /// Distinct symptom names in first-tagged order, lowercased for
    /// mid-sentence use: "nausea, fatigue".
    private func namedList(_ events: [SymptomEvent]) -> String {
        var seen = Set<SymptomType>()
        var names: [String] = []
        for event in events where !seen.contains(event.type) {
            seen.insert(event.type)
            names.append(event.type.title.lowercased())
        }
        return names.joined(separator: ", ")
    }

    private func firstName(_ events: [SymptomEvent]) -> String {
        events.first.map { $0.type.title.lowercased() } ?? "it"
    }

    private func weekdayName(_ date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.standaloneWeekdaySymbols
        guard symbols.indices.contains(index) else { return "that day" }
        return symbols[index]
    }

    /// "7.5" and "5", never "5.0" — a dose is quoted back in the reader's own
    /// terms.
    private static func milligrams(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

