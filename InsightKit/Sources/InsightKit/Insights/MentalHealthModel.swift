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
    ///
    /// ## ⚠️ Derived-series verdict, per channel — 2026-08-06
    ///
    /// The reader asked for every derived figure to become a data source *"in
    /// mental health, something like the 'moving around' score, should now have
    /// its own data"* — and supplied the exception in the same breath:
    /// *"unless that was just directly derived from one other data point."*
    ///
    /// **All four channels are that exception, and none of them gets a
    /// `DerivedOutput`.** Every one is `(recent median − season median) ÷ season
    /// spread` on a *single* metric — a rescaling of one series and nothing
    /// more. Minting "Moving around" as a second series would put the reader's
    /// step count in the Data tab twice under two names, which is exactly the
    /// duplication the derived-series design exists to avoid.
    ///
    /// | Channel | Metric | Verdict |
    /// | --- | --- | --- |
    /// | Moving around | `stepCount` | **pass-through** — one metric, rescaled |
    /// | When you went to bed | `sleepOnset` | **pass-through** — one metric, rescaled |
    /// | Deliberate exercise | `exerciseMinutes` | **pass-through** — one metric, rescaled |
    /// | Heart-rate variability | `heartRateVariabilityRMSSD` | **pass-through** — one metric, rescaled |
    ///
    /// They are not *lost*, which is what makes the refusal cheap: each
    /// contribution below carries `z`, and `DerivedHarvest` turns every `z` into
    /// a `.componentDeparture` series for free. So the fortnight-against-season
    /// departure is already trendable per channel, under the tier that says what
    /// it is, without a second display name competing with the metric's own.
    ///
    /// What *does* earn a series here is what pools them — see
    /// `MentalHealthInsight.derivedOutputs`.
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
                detail: sentence(reading),
                // **No componentScore, deliberately** — the score is a curve
                // over the pooled departure, not a weighted mean of per-channel
                // 0–100s, so a sub-score here would license a counterfactual
                // the arithmetic cannot honour. The fortnight, the season and
                // the departure between them are what each channel truly has.
                value: reading.recent, baseline: reading.reference,
                // `towardLowMood` is signed toward the low-mood pattern; the
                // field wants the departure as the metric is measured, so
                // un-flip the channels where low mood shows as a *fall*.
                z: reading.channel.lowMoodDirection == .falls
                    ? -reading.towardLowMood : reading.towardLowMood)
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

    /// An Oxford-comma-free English list, so copy can name what it actually
    /// read instead of a count somebody typed.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return "nothing"
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
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

    /// **The reader's leave, B7 H6.** Construction state, like the calendar
    /// cards' events: `InsightEngine` carries samples and a profile, and a
    /// ledger is neither. Empty by default, which is the state in which this
    /// card scores nothing off it — see `LeaveRecency`.
    public let holidays: HolidayLedger

    public init(holidays: HolidayLedger = HolidayLedger()) {
        self.holidays = holidays
    }

    /// What time since a break carries here.
    ///
    /// ⚠️ **The smallest of the four shares, and deliberately.** This card's
    /// claim is that several *measured* behaviours moved together; a fact about
    /// a diary is a different kind of evidence and must stay the junior partner
    /// of the four the card is named for. It is also the card that most needs to
    /// not be read as a verdict, and a large share for "you have not had a
    /// holiday" would read as one.
    public static let leaveShare = 0.08

    public var candidateMetrics: [MetricType] { MentalHealthModel.channels.map(\.metric) }

    /// None. Everything here is behaviour the phone already records, and there
    /// is no fact a reader could type that would make a fortnight of step counts
    /// more informative.
    public var requirements: [GroundingRequirement] { [] }

    /// The leave log, because this card now scores time since a break —
    /// `mental-health-v2`. The rule it satisfies is the one `.holiday` was held
    /// to until today: a card offers an input only once its model reads it.
    public var contributions: [ContributionRoute] { [.holidayLog] }

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
                // ⚠️ **Counts and names are derived, never written out.** This
                // line said "none of the four" and named all four behaviours,
                // on a card that runs on as few as two — so on the reader's own
                // record it would have claimed to have looked at things it had
                // no data for. The repo's ledger has "a hard-coded count going
                // stale" at 4+ sessions; this is the same fault inside a
                // sentence rather than inside a doc.
                text: "\(out.readings.count == 1 ? "The one behaviour this could read has" : "None of the \(out.readings.count) behaviours this could read has") not moved much this fortnight. That is a statement about \(MentalHealthModel.list(out.readings.map { $0.channel.label.lowercased() })) — not about how you have been feeling. If this fortnight has been hard, this card has simply not seen it, and you are right and it is wrong.",
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

        drivers.append(.routine("This card has no idea how you feel, and it is not trying to guess. It watches \(out.readings.count) of \(MentalHealthModel.channels.count) everyday behaviours against your own previous \(MentalHealthModel.referenceDays) days and tells you when they move together — which is sometimes worth a second thought, and is sometimes a busy fortnight."))
        drivers.append(.routine("It does not diagnose anything and it cannot. If you want to talk to someone, do that — nothing here is a reason to wait, and nothing here is a reason not to."))

        // **B7 H6.** Time since a break, folded in after the card has scored
        // itself. ⚠️ It is *not* a fifth behaviour and the copy never presents it
        // as one: the four above are measured, this is read off a diary, and the
        // row says so. `mental-health-v2` marks every previously recorded score
        // as non-comparable, per the fitness-v2 precedent.
        let recency = LeaveRecency.read(holidays, asOf: now)
        let blended = LeaveBlend.fold(score: out.score,
                                      contributions: contributions,
                                      factors: Self.producedFigures(out),
                                      recency: recency, on: id,
                                      share: Self.leaveShare)
        drivers.append(InsightDriver(text: recency.driverLine(share: Self.leaveShare),
                                     isNotable: false))

        return InsightResult(
            id: id, title: title,
            primaryValue: blended.score,
            headline: MentalHealthModel.headline(out),
            score: blended.score,
            confidence: out.readings.count >= 3 ? .moderate : .low,
            explanation: "\(out.readings.count) everyday behaviours — \(MentalHealthModel.list(out.readings.map { $0.channel.label.lowercased() })) — each measured against your own previous \(MentalHealthModel.referenceDays) days. It reports when several drift the same way at once. It is not a screen, it does not diagnose, and it never says you are fine: the top of its range means those numbers have not moved, which is a much smaller thing.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: blended.contributions,
            weighting: .weightedAverage,
            otherFactors: blended.factors,
            derivedOutputs: Self.derivedOutputs(out)
                + (blended.didScore ? [recency.derivedOutput].compactMap { $0 } : []))
    }

    // MARK: - What this card works out (2026-08-06)
    //
    // The channels themselves are pass-throughs and are refused a series — the
    // table on `MentalHealthModel.channels` says why, one channel at a time.
    // These three are what the card adds to them: **a statistic no single
    // metric holds, and the agreement between metrics that is this card's whole
    // claim.**

    static let pooledKey = "pooledDeparture"
    static let movedKey = "channelsMoved"
    static let readKey = "channelsRead"

    static func derivedOutputs(_ out: MentalHealthModel.Output) -> [DerivedOutput] {
        [
            // **Pools.** A weighted mean across up to four unrelated behaviours,
            // each normalised against its own season first — the normalisation
            // is what makes minutes, steps and milliseconds addable at all, and
            // the sum is a quantity none of them has on its own.
            .init(key: pooledKey, displayName: "How far the fortnight has drifted",
                  unit: "SD", value: out.pooled,
                  // Positive is the low-mood direction, so lower is the
                  // welcome one — stated as a direction on a number, never as
                  // a verdict on the reader. This card does not have one.
                  higherIsBetter: false, precision: 2),
            // **Pools, differently and worth keeping separately.** The pooled
            // mean can sit near zero with two channels far out in opposite
            // directions; this counts how many actually moved. The headline is
            // built from this figure, not from the mean.
            .init(key: movedKey, displayName: "Behaviours that shifted this fortnight",
                  unit: "", value: Double(out.moved.count),
                  higherIsBetter: false, precision: 0),
            // Coverage, and the reason the count above is not readable alone:
            // two of two and two of four are different findings.
            .init(key: readKey, displayName: "Behaviours there was enough data to read",
                  unit: "", value: Double(out.readings.count),
                  higherIsBetter: true, precision: 0),
        ]
    }

    /// The two pooled figures as rows, so the card's own statistic is visible in
    /// "What goes into this" and "How this is weighted" rather than living only
    /// inside a headline.
    ///
    /// ⚠️ Weight 0 — see `ScoreFactor.producedFigure`. The channels below carry
    /// the whole of this card between them and the pooled departure is their
    /// weighted mean, so a share for it would be those same four numbers counted
    /// a second time.
    static func producedFigures(_ out: MentalHealthModel.Output) -> [ScoreFactor] {
        [
            .producedFigure(
                DerivedSeriesID(.mentalHealth, pooledKey),
                name: "How far the fortnight has drifted",
                detail: String(format: "%.2f SD %@ the low-mood pattern, pooled across the %d behaviour%@ below. It is their weighted mean, so it carries no share of its own — it is the share.",
                               abs(out.pooled), out.pooled > 0 ? "toward" : "away from",
                               out.readings.count, out.readings.count == 1 ? "" : "s")),
            .producedFigure(
                DerivedSeriesID(.mentalHealth, movedKey),
                name: "Behaviours that shifted",
                detail: "\(out.moved.count) of \(out.readings.count) moved far enough to be worth a sentence — counted rather than scored, because several small agreeing moves are the thing this card watches for and a mean can hide them."),
        ]
    }
}
