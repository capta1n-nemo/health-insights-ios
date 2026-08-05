import Foundation

/// **How the last fortnight has been going, from behaviour rather than mood.**
///
/// Backlog #27, refused after nine adversarial attacks and reversed by the
/// reader on 2026-08-06: *"I want a mental health card. Figure it out, creative
/// licence + data science."*
///
/// ## The refusal was right about the failure mode and wrong about the feature
///
/// Its three designs all read HealthKit's mood surfaces — `MindfulSession`,
/// `StateOfMind`, `MoodChanges` — and all three had **zero rows**, so each was a
/// permanent null. The reader's answer to "there is no data" is the right one
/// for this app: *use the data people already have*. Behaviour is data, it is
/// dense, and the actigraphy literature on low mood is about behaviour before it
/// is about anything else — **reduced activity, later and more scattered sleep
/// timing, and lower heart-rate variability** are its most replicated
/// correlates, and this app holds all three at daily resolution.
///
/// ## The one attack that still stands, and what it changes
///
/// *"'You seem fine' arriving by arithmetic to someone having a bad month is the
/// worst available failure."* That is true and it is not a reason to refuse — it
/// is a design constraint, and it shapes every sentence here:
///
/// - **This card never reassures.** With nothing moved it says so *about the
///   measurements*, never about the person: "your step count and your sleep
///   timing have held steady — that is a statement about those two numbers, not
///   about how you feel."
/// - **It has no diagnostic vocabulary.** It does not contain the word
///   depression, it does not screen, and it does not have a "low mood" band.
/// - **Every channel names its alternative explanation on its own row.** A week
///   of illness, a deadline, a holiday and a flat ring all move these signals,
///   and a card that omits that is inviting a wrong conclusion.
/// - **The reader outranks it, explicitly, in the copy.**
///
/// ## What it measures, and why these four
///
/// Not levels — *departures from this reader's own usual*, over a fortnight
/// against a season. Levels are what Sleep, Energy and Readiness already report,
/// and a fifth rendering of last night's sleep score would be a card pretending
/// to be a domain.
///
/// | Channel | Why it is here |
/// | --- | --- |
/// | **Doing less** | The most replicated behavioural correlate there is, and the one a phone measures best |
/// | **Sleep timing scatter** | *When* sleep happens, not how much — circadian irregularity tracks mood independently of duration |
/// | **Withdrawal from the day** | Exercise minutes: intentional activity, which falls before incidental activity does |
/// | **Autonomic tone** | HRV against the reader's own season — the physiological channel, and the one most confounded |
///
/// ## What it is not
///
/// Not a screen, not a diagnosis, and not a substitute for anybody. It is a
/// mirror held up to four numbers, with the caveats attached.
public enum MentalHealthModel {

    /// The stretch being described. Two weeks: long enough that one bad night
    /// does not decide it, short enough to still be about now.
    public static let recentDays = 14
    /// What it is judged against — the reader's own previous season.
    public static let referenceDays = 120
    /// Days each window needs on a signal before that channel may speak.
    public static let minimumDays = 7

    /// A channel, its direction, its share, and the alternative explanation that
    /// must travel with it.
    ///
    /// **The alternative is a stored property, not a comment.** Every one of
    /// these signals has an ordinary explanation that has nothing to do with
    /// mood, and a card that reports the signal without it is inviting the
    /// reader to conclude something the data cannot support.
    public struct Channel: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let label: String
        /// Which direction is the one associated with low mood.
        public let lowMoodDirection: Direction
        public let weight: Double
        public let alternative: String

        public enum Direction: Sendable, Equatable { case falls, rises }
        public var id: String { metric.rawValue }
    }

    /// Four channels. Deliberately few: each extra one is another chance to
    /// find a pattern in noise, and three of these four are already known to
    /// move together.
    public static let channels: [Channel] = [
        Channel(metric: .stepCount, label: "Moving around",
                lowMoodDirection: .falls, weight: 1.0,
                alternative: "A week indoors, an injury, or a phone left on a desk all look the same here."),
        Channel(metric: .sleepOnset, label: "When you went to bed",
                lowMoodDirection: .rises, weight: 0.9,
                alternative: "Shift work, travel across time zones and a good series all shift bedtimes too."),
        Channel(metric: .exerciseMinutes, label: "Deliberate exercise",
                lowMoodDirection: .falls, weight: 0.8,
                alternative: "A rest block, a busy fortnight or a change of sport reads the same way."),
        Channel(metric: .heartRateVariabilityRMSSD, label: "Heart-rate variability",
                lowMoodDirection: .falls, weight: 0.6,
                alternative: "This falls for illness, alcohol, heat and hard training — it is the least specific signal here."),
    ]

    public struct Reading: Sendable, Equatable, Identifiable {
        public let channel: Channel
        public let recent: Double
        public let reference: Double
        /// Standard deviations from the reader's own season, **signed so that
        /// positive always means the low-mood direction**. That normalisation is
        /// what lets four signals in four units be added up at all.
        public let towardLowMood: Double
        public let recentDays: Int
        public var id: String { channel.metric.rawValue }

        /// Whether this channel has moved enough to be worth a sentence.
        public var hasMoved: Bool { abs(towardLowMood) >= 0.8 }
    }

    public struct Output: Sendable, Equatable {
        public let readings: [Reading]
        /// 0–100, where **low means more has moved in the low-mood direction**.
        public let score: Double
        /// Weighted mean of `towardLowMood`, the statistic behind the score.
        public let pooled: Double
        public let contributions: [MetricContribution]

        /// Channels that moved, worst first.
        public var moved: [Reading] {
            readings.filter(\.hasMoved).sorted { $0.towardLowMood > $1.towardLowMood }
        }
    }

    /// The score curve.
    ///
    /// ⚠️ **Asymmetric on purpose.** Moving *away* from the low-mood direction
    /// is capped well below 100: this card is not able to certify a good
    /// fortnight, and a dial pinned at 100 would be doing exactly that. The top
    /// of its range means "none of these four has moved", which is a much
    /// smaller claim and is the only one the measurements support.
    public static func score(pooled: Double) -> Double {
        ScoreCurve.through([(-1.5, 82), (-0.5, 80), (0, 78),
                            (0.5, 68), (1.0, 55), (1.75, 38), (3.0, 20)],
                           at: pooled)
    }

    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let recentStart = now.addingTimeInterval(-Double(recentDays) * 86_400)
        let referenceStart = recentStart.addingTimeInterval(-Double(referenceDays) * 86_400)

        var readings: [Reading] = []
        for channel in channels {
            let daily = VitalReader.dailySeries(channel.metric, from: samples, now: now,
                                                calendar: calendar)
            let recentValues = daily.filter { $0.date >= recentStart && $0.date < now }.map(\.value)
            let referenceValues = daily
                .filter { $0.date >= referenceStart && $0.date < recentStart }.map(\.value)

            guard recentValues.count >= minimumDays, referenceValues.count >= minimumDays,
                  let recent = Baseline.median(recentValues),
                  let reference = Baseline.median(referenceValues),
                  // Robust scale for the reason the whole app uses it: a season
                  // containing one illness would otherwise widen enough to hide
                  // the next thing.
                  let spread = Baseline.robustScale(referenceValues), spread > 0
            else { continue }

            let raw = (recent - reference) / spread
            readings.append(Reading(
                channel: channel, recent: recent, reference: reference,
                towardLowMood: channel.lowMoodDirection == .falls ? -raw : raw,
                recentDays: recentValues.count))
        }

        // ⚠️ **Two channels minimum, and the reason is the whole design.** One
        // channel moving is a fact about a step count. The claim this card is
        // allowed to make — that several unrelated parts of a life moved the
        // same way at once — needs several.
        guard readings.count >= 2 else { return nil }

        let totalWeight = readings.reduce(0) { $0 + $1.channel.weight }
        let pooled = readings.reduce(0.0) { $0 + $1.towardLowMood * $1.channel.weight }
            / totalWeight

        let contributions = readings.map { reading in
            MetricContribution(
                metric: reading.channel.metric,
                higherIsBetter: reading.channel.lowMoodDirection == .falls,
                weight: reading.channel.weight / totalWeight,
                detail: sentence(reading))
        }

        return Output(readings: readings, score: score(pooled: pooled),
                      pooled: pooled, contributions: contributions)
    }

    /// One channel, in plain words, with its alternative explanation attached.
    public static func sentence(_ reading: Reading) -> String {
        let direction = reading.towardLowMood > 0 ? "toward" : "away from"
        let movement = abs(reading.towardLowMood) < 0.8
            ? "has held about where it usually sits"
            : String(format: "has moved %.1f SD %@ the pattern low mood usually shows",
                     abs(reading.towardLowMood), direction)
        return "\(reading.channel.label) \(movement) — "
            + "\(MetricValueFormatter.string(reading.recent, reading.channel.metric)) over the last "
            + "\(MentalHealthModel.recentDays) days against \(MetricValueFormatter.string(reading.reference, reading.channel.metric)) across your previous season. "
            + reading.channel.alternative
    }

    /// The headline.
    ///
    /// ⚠️ **Read every one of these against the rule that this card never
    /// reassures.** The top band is a statement about four measurements and says
    /// so; it is not "you are well".
    public static func headline(_ out: Output) -> String {
        switch out.moved.count {
        case 0: return "Nothing much has shifted"
        case 1: return "One thing has shifted"
        default:
            return out.pooled > 0
                ? "\(out.moved.count) things have shifted together"
                : "\(out.moved.count) things have shifted"
        }
    }
}

/// The card.
public struct MentalHealthInsight: InsightModel {
    public let id: InsightID = .mentalHealth
    /// **Named the thing the reader asked for.** The Stress-load lesson from
    /// 2026-08-06 is part of this card's brief: a card shipped under a name the
    /// reader could not find is a card that does not exist, and they asked three
    /// times before finding the last one.
    public let title = "Mental health"

    public init() {}

    public var candidateMetrics: [MetricType] { MentalHealthModel.channels.map(\.metric) }

    /// None. Everything here is behaviour the phone already records, and there
    /// is no fact a reader could type that would make a fortnight of step counts
    /// more informative.
    public var requirements: [GroundingRequirement] { [] }

    public func evaluate(samples: [HealthMetricSample],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        guard let out = MentalHealthModel.evaluate(samples: samples, now: now) else {
            return invitingInput(
                id, title,
                action: "Wear something, or carry your phone",
                message: "This one watches four ordinary things — how much you move, when you go to bed, whether you exercise on purpose, and your heart-rate variability — and tells you when several of them drift together, which is a pattern worth noticing. It needs about \(MentalHealthModel.minimumDays) days in the last fortnight on at least two of them.")
        }

        var drivers: [InsightDriver] = []

        // ⚠️ **The lead sentence carries the card's whole honesty burden**, and
        // the empty case is the dangerous one. "Nothing has moved" must never be
        // allowed to become "you are fine" in the reader's head — so it is
        // stated about the measurements, out loud, in the same sentence.
        if out.moved.isEmpty {
            drivers.append(InsightDriver(
                text: "None of the four has moved much this fortnight. That is a statement about your step count, your bedtimes, your exercise minutes and your heart-rate variability — not about how you have been feeling. If this fortnight has been hard, this card has simply not seen it, and you are right and it is wrong.",
                isNotable: false))
        } else {
            let names = out.moved.map(\.channel.label).joined(separator: ", ")
            drivers.append(InsightDriver(
                text: out.pooled > 0
                    ? "\(names) — \(out.moved.count == 1 ? "this has" : "these have") moved the way they tend to when someone is having a harder time. That is a pattern, not a finding, and each of them has an ordinary explanation listed below."
                    : "\(names) shifted this fortnight, but away from the low-mood pattern rather than toward it.",
                isNotable: out.pooled > 0.5))
        }

        var contributions = out.contributions
        for reading in out.readings.sorted(by: { $0.towardLowMood > $1.towardLowMood }) {
            drivers.append(InsightDriver(text: MentalHealthModel.sentence(reading),
                                         isNotable: reading.hasMoved && reading.towardLowMood > 0))
        }

        // Channels with no data are named rather than omitted — the same rule
        // biological age learnt the hard way. A card that quietly drops a
        // declared input contradicts itself across two sections.
        let present = Set(out.readings.map(\.channel.metric))
        for channel in MentalHealthModel.channels where !present.contains(channel.metric) {
            let text = "\(channel.label): not enough of it in the last fortnight to compare with your season — not counted."
            drivers.append(.routine(text))
            contributions.append(MetricContribution(metric: channel.metric,
                                                    higherIsBetter: nil, weight: 0,
                                                    detail: text))
        }

        drivers.append(.routine("This card has no idea how you feel, and it is not trying to guess. It watches four behaviours against your own previous \(MentalHealthModel.referenceDays) days and tells you when they move together — which is sometimes worth a second thought, and is sometimes a busy fortnight."))
        drivers.append(.routine("It does not diagnose anything and it cannot. If you want to talk to someone, do that — nothing here is a reason to wait, and nothing here is a reason not to."))

        return InsightResult(
            id: id, title: title,
            primaryValue: out.score,
            headline: MentalHealthModel.headline(out),
            score: out.score,
            confidence: out.readings.count >= 3 ? .moderate : .low,
            explanation: "Four everyday behaviours — how much you move, when you go to bed, whether you exercise on purpose, and your heart-rate variability — each measured against your own previous \(MentalHealthModel.referenceDays) days. It reports when several drift the same way at once. It is not a screen, it does not diagnose, and it never says you are fine: the top of its range means these four numbers have not moved, which is a much smaller thing.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: contributions,
            weighting: .weightedAverage)
    }
}
