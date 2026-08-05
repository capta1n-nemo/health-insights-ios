import Foundation

/// **How you walk, against how you used to walk.**
///
/// Measured against the reader's own export on 2026-08-05, the three gait
/// signals are the densest unused data in the app by a wide margin — 1,093 days
/// each, 91 of the last 90, 366 of the last 365 — and nothing else is close.
/// They come from the iPhone in a pocket, so unlike every other card here this
/// one keeps working through a week the ring spent on charge.
///
/// ## The thing it can say that a number cannot
///
/// Walking speed is step length times cadence, exactly:
///
///     speed (m/s) = step length (m) × steps per second
///
/// So when speed moves, this card can name **which half moved**. Taking the
/// same steps less often and taking shorter steps at the same rhythm are
/// different findings — the first tracks drive and fatigue, the second tracks
/// caution, stiffness and pain — and no product in the competitive scan draws
/// that line, because none of them is holding step length.
///
/// Cadence is derived rather than read: nothing publishes it, but it falls out
/// of two numbers the phone already writes.
///
/// ## What it refuses to claim
///
/// ⚠️ **This is walking the phone saw, not all walking.** A day carrying it in
/// a bag, an hour on a treadmill holding the rails, a session in the gym — each
/// arrives as *less* walking rather than *different* walking. Every rendering
/// says so, because "your walking speed is falling" is heard as a sentence
/// about ageing.
///
/// ⚠️ **The famous thresholds do not apply.** 0.8 m/s is the EWGSOP2 slow-gait
/// cut and 1.0 m/s is the line most of the mortality literature uses; both were
/// measured on a marked course, under supervision, in older adults. Rendering
/// them over a pocket sensor's average would turn a change in how the phone was
/// carried into a clinical finding. The reference here is the reader's own
/// previous year, and the card says which reference it used.
public enum GaitModel {

    /// The stretch being judged. Four weeks: gait moves slowly, and a week is
    /// mostly a report on the weather.
    public static let recentDays = 28
    /// What it is judged against — the reader's own previous year, which is the
    /// only defensible reference for a measurement whose population norms were
    /// collected a different way.
    public static let referenceDays = 365
    /// Days each window needs on a signal before it contributes.
    public static let minimumDays = 10

    /// The signals, which direction is the welcome one, and their share.
    ///
    /// Speed carries the most because it is the one with three decades of
    /// literature behind it. Steadiness and asymmetry carry least: both are
    /// published on a rolling window rather than per bout, so they move late,
    /// and both were already in the app being read by nothing but the generic
    /// vitals sweep.
    static let watched: [(metric: MetricType, higherIsBetter: Bool, weight: Double)] = [
        (.walkingSpeed, true, 1.0),
        (.walkingStepLength, true, 0.7),
        (.walkingDoubleSupport, false, 0.7),
        (.walkingSteadiness, true, 0.5),
        (.walkingAsymmetry, false, 0.5),
    ]

    public static var watchedMetrics: [MetricType] { watched.map { $0.metric } }

    public struct Channel: Sendable, Equatable {
        public let metric: MetricType
        public let recent: Double
        public let reference: Double
        /// Robust SDs from the reader's own reference, signed so **positive is
        /// always the unwelcome direction** whichever way the raw number moved.
        public let adverseZ: Double
        public let weight: Double
        /// Percent change against the reference, for the sentence a reader
        /// actually understands.
        public var percentChange: Double {
            reference == 0 ? 0 : (recent - reference) / reference * 100
        }
    }

    /// Which half of a speed change is which.
    ///
    /// From `speed = length × cadence`, taking logs makes the change additive:
    /// `ln Δspeed = ln Δlength + ln Δcadence`. So the two shares sum to the
    /// whole and can be reported as fractions of it without any fitting.
    public struct SpeedSplit: Sendable, Equatable {
        /// Fractional change in speed, e.g. −0.04 for four percent slower.
        public let speedChange: Double
        public let stepLengthChange: Double
        public let cadenceChange: Double
        /// Share of the speed change attributable to step length, 0–1. `nil`
        /// when the speed change is too small to apportion — dividing a rounding
        /// error into halves produces two confident-looking numbers about
        /// nothing.
        public let stepLengthShare: Double?

        /// Below this, the split is not reported. Half a percent over four weeks
        /// is inside the noise of what the phone happened to witness.
        public static let reportableChange = 0.005
    }

    public struct Output: Sendable, Equatable {
        public let channels: [Channel]
        public let split: SpeedSplit?
        /// 0–100, higher is better — the same direction as every other dial.
        public let score: Double
        /// Weighted mean adverse departure in robust SDs. What the score renders.
        public let drift: Double
    }

    /// `nil` when no signal has both windows.
    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let recentStart = now.addingTimeInterval(-Double(recentDays) * 86_400)
        let referenceStart = recentStart.addingTimeInterval(-Double(referenceDays) * 86_400)

        var channels: [Channel] = []
        var medians: [MetricType: (recent: Double, reference: Double)] = [:]

        for entry in watched {
            let daily = VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                                calendar: calendar)
            let recentValues = daily.filter { $0.date >= recentStart && $0.date < now }.map(\.value)
            let referenceValues = daily
                .filter { $0.date >= referenceStart && $0.date < recentStart }.map(\.value)

            guard recentValues.count >= minimumDays, referenceValues.count >= minimumDays,
                  let recent = Baseline.median(recentValues),
                  let reference = Baseline.median(referenceValues),
                  // Robust scale, for the reason the whole app now uses it: a
                  // standard deviation has a breakdown point of zero, so a year
                  // containing one injured month would widen enough to hide the
                  // next one.
                  let spread = Baseline.robustScale(referenceValues), spread > 0
            else { continue }

            medians[entry.metric] = (recent, reference)
            let raw = (recent - reference) / spread
            channels.append(Channel(metric: entry.metric, recent: recent,
                                    reference: reference,
                                    adverseZ: entry.higherIsBetter ? -raw : raw,
                                    weight: entry.weight))
        }

        guard !channels.isEmpty else { return nil }

        // One joint statistic, clamped at zero per channel — never a count of
        // channels past a threshold. Five signals each at 95% specificity, OR'd,
        // would fire on nearly a quarter of all windows.
        //
        // Clamped because walking *better* than your own year is a fine thing
        // and is not evidence against a gait that has stiffened. It shows up in
        // the driver lines, where it belongs, rather than cancelling a real
        // departure out of the score.
        let weightTotal = channels.reduce(0) { $0 + $1.weight }
        let drift = channels.reduce(0) { $0 + $1.weight * Swift.max(0, $1.adverseZ) } / weightTotal

        return Output(channels: channels,
                      split: split(medians: medians),
                      score: score(drift: drift),
                      drift: drift)
    }

    /// Apportion a speed change between step length and cadence.
    ///
    /// Internal so the test can drive it from medians directly rather than
    /// building a year of samples to reach it.
    static func split(medians: [MetricType: (recent: Double, reference: Double)]) -> SpeedSplit? {
        guard let speed = medians[.walkingSpeed],
              let length = medians[.walkingStepLength],
              speed.recent > 0, speed.reference > 0,
              length.recent > 0, length.reference > 0
        else { return nil }

        // Centimetres to metres, so the cadence below is steps per second and
        // not a hundredth of one.
        let cadenceRecent = speed.recent / (length.recent / 100)
        let cadenceReference = speed.reference / (length.reference / 100)

        let speedChange = speed.recent / speed.reference - 1
        let lengthChange = length.recent / length.reference - 1
        let cadenceChange = cadenceRecent / cadenceReference - 1

        // The logs are what make the two shares sum to one; the fractional
        // changes above are what the reader is shown, because "3% shorter" is a
        // sentence and "ln −0.0305" is not.
        var share: Double?
        if abs(speedChange) >= SpeedSplit.reportableChange {
            let lnSpeed = Foundation.log(speed.recent / speed.reference)
            let lnLength = Foundation.log(length.recent / length.reference)
            if lnSpeed != 0 { share = Swift.max(0, Swift.min(1, lnLength / lnSpeed)) }
        }

        return SpeedSplit(speedChange: speedChange, stepLengthChange: lengthChange,
                          cadenceChange: cadenceChange, stepLengthShare: share)
    }

    /// Adverse drift in robust SDs → 0–100, higher is better.
    ///
    /// A curve rather than a band table: `verify.sh` rejects the staircase form,
    /// and the reason is a shipped defect where twenty points sat between two
    /// readings a hair apart. Anchored where the meaning changes — gait is a
    /// stable measurement, so half an SD sustained across a month is already
    /// worth a sentence.
    public static func score(drift: Double) -> Double {
        ScoreCurve.through([(0, 100), (0.5, 82), (1.0, 60), (2.0, 30), (3.0, 12)], at: drift)
    }

    /// The word for a drift, shared so a headline and a chart band cannot
    /// disagree about where "steady" ends.
    public static func band(_ score: Double) -> String {
        switch ScoreBand(score: score) {
        case .good: return "Walking as usual"
        case .fair: return "Slightly changed"
        case .poor: return "Noticeably changed"
        }
    }
}

/// The card.
///
/// `.trend` rather than `.daily`, deliberately. Gait moves over months, and a
/// Today card reporting "1.31 m/s" every morning would be a number nobody could
/// act on — the finding here is always a comparison across weeks, which is the
/// definition of a trend card at the top of `Insight.swift`.
public struct GaitInsight: InsightModel {
    public let id: InsightID = .gait
    public let title = "How you walked"

    public init() {}

    public var candidateMetrics: [MetricType] { GaitModel.watchedMetrics }

    /// None. Every input is sensed, and there is no fact a reader could type in
    /// that would make a pocket sensor's average more accurate.
    public var requirements: [GroundingRequirement] { [] }

    public func evaluate(samples: [HealthMetricSample],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        guard let out = GaitModel.evaluate(samples: samples, now: now) else {
            return invitingInput(
                id, title,
                action: "Carry your phone when you walk",
                message: "Your iPhone measures how fast you walk and how long your steps are, whenever it is in a pocket or a bag on you. This compares your last four weeks with your previous year, so it needs about \(GaitModel.minimumDays) days in each. No watch or ring required.")
        }

        var drivers: [InsightDriver] = []
        var contributions: [MetricContribution] = []
        let total = out.channels.reduce(0) { $0 + $1.weight }

        // The decomposition leads, because it is the only line here a reader
        // cannot get from any other product.
        if let split = out.split, let share = split.stepLengthShare {
            let slower = split.speedChange < 0
            let verb = slower ? "slower" : "faster"
            let lead = share >= 0.6
                ? "mostly your step length"
                : (share <= 0.4 ? "mostly your rhythm" : "step length and rhythm about equally")
            drivers.append(InsightDriver(
                text: String(format: "You walked %.0f%% %@ than your previous year, and it was %@ — steps %.0f%% %@, taken %.0f%% %@ often",
                             abs(split.speedChange) * 100, verb, lead,
                             abs(split.stepLengthChange) * 100,
                             split.stepLengthChange < 0 ? "shorter" : "longer",
                             abs(split.cadenceChange) * 100,
                             split.cadenceChange < 0 ? "less" : "more"),
                isNotable: true))
        } else if out.split != nil {
            drivers.append(InsightDriver(
                text: "Your walking speed is within half a percent of your previous year, which is too small a difference to say anything about where it came from",
                isNotable: false))
        }

        for channel in out.channels.sorted(by: { $0.adverseZ > $1.adverseZ }) {
            let name = channel.metric.displayName
            let text = String(format: "%@ is %@ over the last four weeks: %@ against %@ across your previous year",
                              name,
                              abs(channel.percentChange) < 1
                                  ? "unchanged"
                                  : String(format: "%.0f%% %@", abs(channel.percentChange),
                                           channel.percentChange > 0 ? "higher" : "lower"),
                              MetricValueFormatter.string(channel.recent, channel.metric),
                              MetricValueFormatter.string(channel.reference, channel.metric))
            drivers.append(InsightDriver(text: text, isNotable: channel.adverseZ >= 0.5))
            contributions.append(MetricContribution(
                metric: channel.metric,
                higherIsBetter: GaitModel.watched
                    .first { $0.metric == channel.metric }!.higherIsBetter,
                weight: channel.weight / total,
                detail: text))
        }

        // **The caveat is the card.** Without it this reads as a statement about
        // the body, when half of what moves it is how the phone was carried.
        drivers.append(InsightDriver(
            text: "This is the walking your phone was in your pocket for — a month of carrying it in a bag, or of treadmill work holding the rails, arrives here as less walking rather than different walking. It is measured against your own previous year, not against anybody else's normal.",
            isNotable: false))

        return InsightResult(
            id: id, title: title,
            primaryValue: out.channels.first { $0.metric == .walkingSpeed }?.recent ?? out.score,
            headline: GaitModel.band(out.score),
            score: out.score,
            confidence: out.channels.count >= 3 ? .moderate : .low,
            explanation: "Your last \(GaitModel.recentDays) days of walking against your previous year, across \(out.channels.count) measures your iPhone records on its own. Walking speed is one of the most studied numbers in health and it moves before strength or endurance do — but the published thresholds come from supervised walking tests, so this compares you with you.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: contributions,
            weighting: .weightedAverage)
    }
}
