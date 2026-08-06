import Foundation

/// **How long the reader has been running hot.**
///
/// The reader asked for a stress card on 2026-08-03. The roadmap note written
/// then named the trap, and it is the whole design constraint:
///
/// > *"The risk is overlap — Readiness absorbed the vitals scan and the early
/// > warning for exactly this reason — so the honest version needs to answer a
/// > question Readiness does not, most likely **sustained** load rather than
/// > today."*
///
/// So three cards read the same four signals and none of them competes:
///
/// | Card | Window | Question |
/// | --- | --- | --- |
/// | Readiness | today vs 28 days | how am I *this morning* |
/// | Symptom radar | 3 days vs 21 | is something acute converging *now* |
/// | **This** | **28 days vs 90** | **has this been going on for weeks** |
///
/// Only the third can see a drift that never trips an acute threshold: a
/// fortnight where HRV sits four points low every single night is invisible to
/// a detector asking "is today unusual", because by the second week it is not.
///
/// ## What it deliberately does not claim
///
/// **It is not a stressometer.** Nothing here measures stress; it measures four
/// autonomic signals that stress moves — along with illness, alcohol, heat,
/// training load, a new baby and a hard fortnight at work. The card names that
/// rather than implying a cause it cannot see, which is also why it is called
/// sustained *load* and not stress: load is what was measured, stress is one
/// interpretation of it.
public enum SustainedLoadModel {

    /// The stretch being judged. Four weeks: long enough that a bad weekend
    /// cannot carry it, short enough to still be about now.
    public static let recentDays = 28
    /// What it is judged against. A season, so a genuine multi-week shift has
    /// somewhere to stand out from.
    public static let referenceDays = 90
    /// Days each window needs before this says anything.
    public static let minimumDays = 10

    /// The signals, the direction load pushes them, and their share.
    ///
    /// Weights are not equal because the signals are not equally specific to
    /// autonomic load. HRV is the most direct read on parasympathetic tone;
    /// sleep duration is the least specific, because a short fortnight is as
    /// likely to be a choice as a symptom — it earns a place because sustained
    /// short sleep *causes* the other three to drift, so leaving it out would
    /// report the consequence and hide the cause.
    static let watched: [(metric: MetricType, risingIsLoad: Bool, weight: Double)] = [
        (.heartRateVariabilityRMSSD, false, 1.0),
        (.restingHeartRate, true, 0.9),
        (.respiratoryRate, true, 0.6),
        (.sleepDurationHours, false, 0.5),
    ]

    public static var watchedMetrics: [MetricType] { watched.map { $0.metric } }

    public struct Channel: Sendable, Equatable {
        public let metric: MetricType
        public let recent: Double
        public let reference: Double
        /// Standard deviations from the reference, signed so positive is always
        /// *toward* load whichever way the raw metric moved.
        public let loadZ: Double
        public let weight: Double
    }

    public struct Output: Sendable, Equatable {
        public let channels: [Channel]
        /// 0–100, higher is better — the same direction as every other dial.
        public let score: Double
        /// The weighted mean one-sided departure, in SDs. The quantity the
        /// score is a rendering of.
        public let load: Double
    }

    /// `nil` when neither window has enough days to compare.
    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        var channels: [Channel] = []
        for entry in watched {
            let daily = VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                                calendar: calendar)
            let recentStart = now.addingTimeInterval(-Double(recentDays) * 86_400)
            let referenceStart = recentStart.addingTimeInterval(-Double(referenceDays) * 86_400)

            let recentValues = daily.filter { $0.date >= recentStart && $0.date < now }.map(\.value)
            let referenceValues = daily
                .filter { $0.date >= referenceStart && $0.date < recentStart }.map(\.value)

            guard recentValues.count >= minimumDays, referenceValues.count >= minimumDays,
                  let recent = Baseline.median(recentValues),
                  let reference = Baseline.median(referenceValues),
                  // Robust, for the reason the whole app now uses it: a
                  // standard deviation has a breakdown point of zero, and a
                  // season containing one bad fortnight would widen enough to
                  // hide the next one.
                  let spread = Baseline.robustScale(referenceValues), spread > 0
            else { continue }

            let raw = (recent - reference) / spread
            // Signed toward load, so every channel adds in the same direction
            // and a channel moving the *welcome* way subtracts nothing rather
            // than cancelling another out.
            let loadZ = entry.risingIsLoad ? raw : -raw
            channels.append(Channel(metric: entry.metric, recent: recent,
                                    reference: reference, loadZ: loadZ,
                                    weight: entry.weight))
        }

        // Two channels minimum: one signal drifting is a signal drifting, and
        // this card exists to say that several did.
        guard channels.count >= 2 else { return nil }

        // **One joint statistic, coverage-normalised** — never a count of
        // channels past a threshold. Six signals each at 95% specificity, OR'd,
        // give a 26.5% false-alarm rate; the same mistake made the symptom
        // radar fire on a quarter of this reader's days.
        //
        // Clamped at zero per channel: this scores the load direction only. A
        // fortnight of unusually *good* HRV is a fine thing and is not evidence
        // against a raised resting heart rate.
        let weightTotal = channels.reduce(0) { $0 + $1.weight }
        let load = channels.reduce(0) { $0 + $1.weight * Swift.max(0, $1.loadZ) } / weightTotal
        return Output(channels: channels, score: score(load: load), load: load)
    }

    /// Load in SDs → 0–100, higher is better.
    ///
    /// A curve rather than a band table, because `verify.sh` rejects the
    /// staircase form and the reason is a shipped defect: a `switch` on a
    /// measurement puts twenty points between two readings a hair apart.
    /// Anchored where the meaning changes rather than on round numbers — half
    /// an SD sustained for a month is already worth saying, and two is a lot.
    public static func score(load: Double) -> Double {
        ScoreCurve.through([(0, 100), (0.5, 80), (1.0, 55), (2.0, 25), (3.0, 10)], at: load)
    }

    /// The word for a load, shared so the headline and any chart band cannot
    /// disagree about where "settled" ends.
    public static func band(_ score: Double) -> String {
        switch ScoreBand(score: score) {
        case .good: return "Settled"
        case .fair: return "Running warm"
        case .poor: return "Running hot"
        }
    }
}

/// The card.
public struct SustainedLoadInsight: InsightModel {
    public let id: InsightID = .sustainedLoad
    /// ⚠️ **"Stress" is in the name, and an earlier version's omission of it was
    /// a real failure.** The reader asked for a stress card on 2026-08-03. It
    /// shipped as "Sustained load" because the model genuinely cannot tell
    /// stress from illness, alcohol, heat or hard training — sound reasoning
    /// about the *measurement*, and a poor decision about the *product*: they
    /// then asked three separate times where their stress card was, while it sat
    /// twelfth on the Insights tab under a word they would never scroll for.
    ///
    /// The honesty lives where it belongs — in the caveat driver every rendering
    /// carries, which says in as many words that this cannot tell stress from
    /// the other four things. A name has one job, which is to be findable by the
    /// person who asked for it.
    public let title = "Stress load"

    public init() {}

    public var candidateMetrics: [MetricType] { SustainedLoadModel.watchedMetrics }

    /// None. Built entirely from sensed data — there is no fact a reader could
    /// type in that would make this more accurate.
    public var requirements: [GroundingRequirement] { [] }

    public func evaluate(samples: [HealthMetricSample],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        guard let out = SustainedLoadModel.evaluate(samples: samples, now: now) else {
            return invitingInput(
                id, title,
                action: "Wear your device for a few weeks",
                message: "This compares your last four weeks with the three months before them, so it needs both — about \(SustainedLoadModel.minimumDays) days in each on at least two signals. It is the one view that can see a drift too slow to set anything off day to day.")
        }

        var drivers: [InsightDriver] = []
        var contributions: [MetricContribution] = []
        let total = out.channels.reduce(0) { $0 + $1.weight }

        for channel in out.channels.sorted(by: { $0.loadZ > $1.loadZ }) {
            let name = channel.metric.displayName
            let direction = channel.loadZ > 0 ? "toward load" : "the welcome way"
            let text = String(format: "%@ has sat %.1f SD %@ this month against your last season",
                              name, abs(channel.loadZ), direction)
            drivers.append(InsightDriver(text: text, isNotable: channel.loadZ >= 0.5))
            let risingIsLoad = SustainedLoadModel.watched
                .first { $0.metric == channel.metric }!.risingIsLoad
            contributions.append(MetricContribution(
                metric: channel.metric,
                // Whether *up* is good for this metric, which is the opposite
                // of `risingIsLoad` — the chart asks about the reading, not
                // about the load direction the model signs it toward.
                higherIsBetter: !risingIsLoad,
                weight: channel.weight / total,
                detail: text,
                // **No componentScore, deliberately.** The score is a curve
                // over the *pooled* load, and a curve is not linear — a
                // per-channel 0–100 would hand the decomposition a
                // counterfactual arithmetic this model cannot support.
                // What each channel genuinely has is its month, its season,
                // and the departure between them.
                value: channel.recent, baseline: channel.reference,
                // `loadZ` is signed toward load; the field's contract is
                // "signed as the metric is measured", so un-flip the channels
                // where *falling* is the load direction (HRV, sleep).
                z: risingIsLoad ? channel.loadZ : -channel.loadZ))
        }

        // **The caveat is not decoration.** Four autonomic signals move for
        // stress, illness, alcohol, heat, altitude, hard training and a bad
        // fortnight at work, and this card cannot tell those apart. Saying so is
        // the difference between a measurement and a diagnosis.
        drivers.append(InsightDriver(
            text: "This measures four signals that load moves — it cannot tell stress from illness, alcohol, heat or hard training. What it can say is that the shift has lasted weeks rather than days.",
            isNotable: false))

        return InsightResult(
            id: id, title: title,
            primaryValue: out.score,
            headline: SustainedLoadModel.band(out.score),
            score: out.score,
            confidence: out.channels.count >= 3 ? .moderate : .low,
            explanation: "Your last \(SustainedLoadModel.recentDays) days against the \(SustainedLoadModel.referenceDays) before them, across \(out.channels.count) signals. Readiness answers how you are this morning and the symptom radar watches for something acute; this is the only one that can see a drift too slow to trip either.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: contributions,
            weighting: .weightedAverage)
    }
}
