import Foundation

/// **The sound you took on this week, against the allowance the WHO publishes
/// for it** — backlog §B3 #22, and the second half of §B5 #33.
///
/// ## Why this card can exist when a "total sound exposure" card cannot
///
/// The original refusal is still right and is the reason this card is shaped
/// the way it is. Measured on the reader's own export (2026-08-06): environmental
/// audio lands on **14 of the last 90 days**, headphone audio on **56**, across
/// 13,768 headphone rows over 467 days. Adding the two would assert that every
/// hour the watch was in a drawer was silent, which is inventing the quiet
/// hours — so they are never summed, here or anywhere.
///
/// ⚠️ **But the two absences mean opposite things, and that asymmetry is what
/// makes a headphone budget honest.** A day with no environmental sample is a
/// day nothing was listening; a day with no *headphone* sample is a day nothing
/// was **playing**, because the exposure is written by the device doing the
/// playing. So a missing environmental day is unmeasured and a missing headphone
/// day is genuinely quiet — which is exactly the condition a cumulative total
/// needs, and exactly what environmental sound cannot satisfy. Headphone dose is
/// the number; environmental sits beside it with its coverage stated and carries
/// no share of it.
///
/// The one thing that asymmetry does not cover is audio played through something
/// else — a laptop, a car, a second phone, headphones that report nothing. The
/// card says so rather than counting that as silence.
///
/// ## The arithmetic, and why it needs the duration
///
/// A dose is a level **times a time**. 85 dB(A) for ten minutes and 85 dB(A) for
/// ten hours are the same LEQ and sixty times the exposure, so the day's LEQ
/// alone cannot be weighed against any published limit — which is why
/// `SoundDoseModel` carries the measured seconds in each derived sample's span
/// (`SoundDoseModel.measuredSeconds(of:)`).
///
/// **The budget is WHO/ITU H.870's**: for adults, a recreational sound allowance
/// of **80 dB(A) for 40 hours a week**. It is stated as a weekly *energy*
/// allowance, which is the same shape as WHO's physical-activity guideline that
/// `ActivityDoseModel` and `EffortIntensityModel` already score — a week's worth
/// of something, accumulated, against a published figure. That is what makes
/// this the one domain on the backlog with real data and a published dose in the
/// same form as the exercise one.
///
/// Each day contributes
///
///     hours × 10^((LEQ − 80) / 10)
///
/// allowance-hours, and the week's total is judged against 40. Because the
/// exponent is base ten over ten, three decibels doubles the rate: an hour at
/// 83 dB(A) costs what two hours at 80 do, and an hour at 100 dB(A) costs a
/// hundred of them. That is the whole point of a dose and the reason a
/// listening-level average is not one.
///
/// **NIOSH's REL is reported per day rather than scored**: 85 dB(A) for eight
/// hours with a 3 dB exchange rate, so the permitted time is
/// `8 h / 2^((L − 85) / 3)`. It is an occupational limit for a working lifetime
/// of eight-hour days, not a recreational weekly allowance, so scoring both
/// would be scoring one week's energy twice. It earns its place as the sentence
/// that turns a percentage into an instruction: *at that level you have about
/// forty minutes*.
///
/// ## What it refuses to claim
///
/// ⚠️ **This is not a hearing test and nothing here is a diagnosis.** The
/// allowance is a population-level exposure limit; staying under it is not a
/// promise, and one week over it is not a loss. Noise-induced hearing loss is
/// cumulative over years, and this card can see 467 days at most.
///
/// ⚠️ **The level is what the device reports**, which is the output it drove,
/// modelled through a headphone profile it may or may not know. Apple's own
/// figure is an estimate for exactly the same reason.
public enum SoundExposureModel {

    // MARK: - The published figures

    /// WHO/ITU H.870's recreational allowance for adults: 80 dB(A) for 40 hours
    /// a week. (The standard's sensitive-listener figure is 75 dB(A) for the
    /// same 40 hours; it is not used here, because nothing in this app knows
    /// whether the reader is one and guessing would silently halve their
    /// allowance.)
    public static let allowanceLevel = 80.0
    public static let allowanceHours = 40.0

    /// NIOSH's Recommended Exposure Limit: 85 dB(A) over 8 hours, 3 dB exchange
    /// rate. Reported, never scored — see the type comment.
    public static let nioshLevel = 85.0
    public static let nioshHours = 8.0
    public static let nioshExchangeDB = 3.0

    /// The window the allowance is stated over. Seven days, because the
    /// allowance is, and not because a week is a convenient number.
    public static let windowDays = 7

    /// How far back coverage is reported over. Ninety days matches every other
    /// coverage figure in the app and is long enough that a fortnight's holiday
    /// does not read as a sensor failing.
    public static let coverageDays = 90

    // MARK: - The pieces

    /// One day, on one of the two sensors.
    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        /// The day's equal-energy level in dB(A), over the hours below.
        public let level: Double
        /// The hours the sensor could hear. **The denominator of the LEQ and
        /// the multiplier of the dose** — never assumed, always measured.
        public let hours: Double

        public var id: Date { date }

        /// Allowance-hours this day used: an hour at the allowance level costs
        /// one, and every 3 dB above it doubles the rate.
        public var allowanceHoursUsed: Double {
            hours * pow(10, (level - SoundExposureModel.allowanceLevel) / 10)
        }

        /// Hours NIOSH permits at this day's level, for the sentence that turns
        /// a percentage into an instruction.
        public var nioshPermittedHours: Double {
            SoundExposureModel.nioshHours
                / pow(2, (level - SoundExposureModel.nioshLevel)
                        / SoundExposureModel.nioshExchangeDB)
        }

    }

    /// What the watch heard, and how little of the time it was listening.
    ///
    /// A separate type from `Day` on purpose: environmental exposure is reported
    /// and never accumulated, and giving it the same shape as the thing that
    /// *is* accumulated is how the two would eventually be added together.
    public struct Environment: Sendable, Equatable {
        /// The most recent day the watch heard anything, and its level.
        public let latest: Day
        /// Days in the last `coverageDays` carrying any environmental figure.
        public let daysMeasured: Int
        /// Mean hours a measured day was actually listened to. The second half
        /// of the coverage statement: 14 days of 20 minutes each is not 14 days.
        public let meanHoursPerMeasuredDay: Double

        /// Share of the last ninety days the watch heard anything at all.
        public var coverage: Double {
            Double(daysMeasured) / Double(SoundExposureModel.coverageDays)
        }
    }

    public struct Output: Sendable, Equatable {
        /// The week's headphone days, oldest first. Days with nothing playing
        /// are absent rather than zero — see `Day`.
        public let days: [Day]
        /// Allowance-hours used across the window, against `allowanceHours`.
        public let allowanceHoursUsed: Double
        /// The steady level that would have delivered the same energy across
        /// the full 40 hours — so a percentage can be said in decibels, which is
        /// the unit the limit is published in.
        public let equivalentLevelOver40Hours: Double
        /// Hours audio actually played, across the window.
        public let listeningHours: Double
        /// Days of the window carrying any headphone audio.
        public let recordedDays: Int
        /// Days of history this reader has on headphones at all. **This is what
        /// separates a quiet week from a reader whose phone never wrote one** —
        /// see `evaluate`.
        public let historyDays: Int
        /// What the watch heard, where it heard anything. Never added to the
        /// figures above.
        public let environment: Environment?
        public let score: Double

        /// Fraction of the weekly allowance used. 1.0 is exactly the published
        /// allowance.
        public var allowanceUsed: Double {
            allowanceHoursUsed / SoundExposureModel.allowanceHours
        }

        /// The loudest day of the window, which is usually the one worth naming.
        public var loudestDay: Day? {
            days.max { $0.allowanceHoursUsed < $1.allowanceHoursUsed }
        }
    }

    // MARK: - Reading the two series

    /// The window's days for one dose metric, oldest first.
    ///
    /// Internal rather than private so the tests can drive it without building
    /// an insight around it.
    static func days(_ metric: MetricType, samples: [HealthMetricSample],
                     from start: Date, to end: Date) -> [Day] {
        samples.samples(of: metric)
            .filter { $0.start >= start && $0.start <= end }
            .compactMap { sample in
                let seconds = SoundDoseModel.measuredSeconds(of: sample)
                // A dose sample with no span predates the span being carried
                // (or came back from a store that dropped it). It still holds a
                // real level, but no honest dose can be built from it, and
                // assuming a duration is precisely the invention this whole
                // domain exists to refuse.
                guard seconds > 0, sample.value.isFinite else { return nil }
                return Day(date: sample.start, level: sample.value,
                           hours: seconds / 3600)
            }
            .sorted { $0.date < $1.date }
    }

    /// `nil` when this reader has no headphone exposure on record at all.
    ///
    /// ⚠️ **A quiet week is not the same as no data, and this is the one place
    /// that distinction is drawn.** Because headphone exposure is written by
    /// the device doing the playing, a week with no samples is a week nothing
    /// played — a real and reportable zero — *provided* the reader has any
    /// history showing their phone writes these at all. With none, the card has
    /// nothing to say and asks instead.
    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let headphones = samples.samples(of: .headphoneSoundDose)
        guard !headphones.isEmpty else { return nil }

        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let week = days(.headphoneSoundDose, samples: samples, from: windowStart, to: now)

        let used = week.reduce(0) { $0 + $1.allowanceHoursUsed }
        let listening = week.reduce(0) { $0 + $1.hours }
        // The percentage said in decibels. Flat at the allowance level for a
        // silent week rather than diverging to −∞, because "your week was
        // equivalent to minus infinity decibels" is not a sentence.
        let equivalent = used > 0
            ? allowanceLevel + 10 * log10(used / allowanceHours)
            : allowanceLevel + 10 * log10(1 / (allowanceHours * 3600))

        let historyDays = Set(headphones.map { calendar.startOfDay(for: $0.start) }).count

        return Output(days: week,
                      allowanceHoursUsed: used,
                      equivalentLevelOver40Hours: equivalent,
                      listeningHours: listening,
                      recordedDays: week.count,
                      historyDays: historyDays,
                      environment: environment(samples: samples, now: now,
                                               calendar: calendar),
                      score: score(allowanceUsed: used / allowanceHours))
    }

    /// What the watch heard over the coverage window, or nothing.
    static func environment(samples: [HealthMetricSample], now: Date,
                            calendar: Calendar = .current) -> Environment? {
        let start = calendar.date(byAdding: .day, value: -coverageDays, to: now) ?? now
        let measured = days(.environmentalSoundDose, samples: samples, from: start, to: now)
        guard let latest = measured.last else { return nil }
        let hours = measured.reduce(0) { $0 + $1.hours } / Double(measured.count)
        return Environment(latest: latest,
                           daysMeasured: Set(measured.map { calendar.startOfDay(for: $0.date) }).count,
                           meanHoursPerMeasuredDay: hours)
    }

    // MARK: - Scoring

    /// Fraction of the weekly allowance used → 0–100, higher is better.
    ///
    /// **Scored in decibels, because that is the axis the quantity lives on.**
    /// The allowance is used up multiplicatively — 200% and 400% are one 3 dB
    /// step apart, exactly as 25% and 50% are — so anchoring on the percentage
    /// would put nine tenths of the curve's resolution in the first tenth of the
    /// range and then run out of score in the region that matters. `10·log10` of
    /// the fraction is decibels relative to the allowance: 0 is exactly the
    /// published limit, +3 is twice it, −10 is a tenth of it.
    ///
    /// The anchors: the allowance is a *ceiling* rather than a target, so
    /// sitting exactly on it is `fair` and not `good` — there is no headroom
    /// left in the week — while comfortably under it is unremarkable and scores
    /// like it. `ScoreCurve.through` is flat outside its ends, so a silent week
    /// scores 100 and a catastrophic one bottoms out rather than going negative.
    public static func score(allowanceUsed fraction: Double) -> Double {
        guard fraction > 0, fraction.isFinite else { return 100 }
        let dB = 10 * log10(fraction)
        return ScoreCurve.through([
            (-20, 100),   //   1% of the allowance
            (-10, 96),    //  10%
            (-3, 86),     //  50%
            // ⚠️ Two points **under** `ScoreBand.goodFloor`, deliberately.
            // Sitting exactly on the published allowance means the week has no
            // headroom left in it, and a card drawing that green would be
            // congratulating somebody at the limit. `testSittingExactlyOn-
            // TheAllowanceIsNotGood` pins it.
            (0, 68),      // exactly the WHO allowance — just inside `fair`
            (3, 45),      // twice it — the top of `poor`
            (6, 25),      // four times
            (10, 8),      // ten times
            (15, 0),      // thirty times
        ], at: dB)
    }

    /// The word for a score, shared so a headline and a chart cannot disagree.
    public static func band(_ score: Double) -> String {
        switch ScoreBand(score: score) {
        case .good: return "Comfortably under"
        case .fair: return "Near your weekly allowance"
        case .poor: return "Over your weekly allowance"
        }
    }

    /// How long NIOSH permits at a level, in plain words — the sentence that
    /// turns a percentage into something a reader can act on.
    public static func permittedTimePhrase(atLevel level: Double) -> String {
        let hours = nioshHours / pow(2, (level - nioshLevel) / nioshExchangeDB)
        if hours >= 24 { return "all day" }
        if hours >= 2 { return String(format: "about %.0f hours", hours) }
        if hours >= 1 { return String(format: "about %.0f minutes", hours * 60) }
        if hours * 60 >= 1 { return String(format: "under %.0f minutes", (hours * 60).rounded(.up)) }
        return "seconds"
    }

    /// The coverage sentence for the environmental half. **Never optional** —
    /// the whole reason environmental sound is on this card at all is that it
    /// says how little of the time anything was listening, and a version of this
    /// section without the sentence would be the refused card.
    public static func coveragePhrase(_ environment: Environment) -> String {
        String(format: "Your watch heard %d of the last %d days, for about %@ on a day it heard anything. That is why this sits beside the headphone figure rather than adding to it: the days it missed are unmeasured, not quiet, and totalling them would invent the silence.",
               environment.daysMeasured, coverageDays,
               environment.meanHoursPerMeasuredDay >= 1
                   ? String(format: "%.1f hours", environment.meanHoursPerMeasuredDay)
                   : String(format: "%.0f minutes", environment.meanHoursPerMeasuredDay * 60))
    }
}

/// The card.
///
/// `.trend` by the default in `InsightID.cadence`, and correctly so: the subject
/// is a week's accumulated energy, which is not a statement about this morning.
public struct SoundExposureInsight: InsightModel {
    public let id: InsightID = .soundExposure
    public let title = "Sound you took on"

    public init() {}

    /// Both dose series. Environmental is declared and read even though it
    /// carries no share — `CandidateReachabilityTests` requires a declared
    /// metric with data to reach `contributors`, and this one does: it is
    /// charted and narrated, and its row states why its weight is zero.
    public var candidateMetrics: [MetricType] {
        [.headphoneSoundDose, .environmentalSoundDose]
    }

    /// None. Every input is sensed, and there is no fact a reader could type
    /// that would make a headphone's own output estimate more accurate.
    public var requirements: [GroundingRequirement] { [] }

    public func evaluate(samples: [HealthMetricSample],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        guard let out = SoundExposureModel.evaluate(samples: samples, now: now) else {
            return invitingInput(
                id, title,
                action: "Listen through your iPhone",
                message: "Your iPhone records the level it drives your headphones at, and your Apple Watch records what it can hear around you. This weighs the first against the World Health Organization's published allowance — 80 dB(A) for 40 hours a week — and shows the second beside it. Nothing here has been recorded yet, so there is nothing to weigh.")
        }

        var drivers: [InsightDriver] = []
        var contributions: [MetricContribution] = []

        let percent = out.allowanceUsed * 100
        let headline = String(format: "%.0f%% of your weekly allowance", percent)

        // The lead line is the dose in the unit the limit is published in, not
        // the percentage — a percentage of a thing nobody has heard of explains
        // nothing on its own.
        drivers.append(InsightDriver(
            text: String(format: "%@ of headphone audio over the last %d days, which carried the same energy as %.0f hours at %.0f dB(A) — %.0f%% of the World Health Organization's weekly allowance of %.0f hours at %.0f dB(A).",
                         out.listeningHours >= 1
                             ? String(format: "%.1f hours", out.listeningHours)
                             : String(format: "%.0f minutes", out.listeningHours * 60),
                         SoundExposureModel.windowDays,
                         SoundExposureModel.allowanceHours,
                         out.equivalentLevelOver40Hours,
                         percent,
                         SoundExposureModel.allowanceHours,
                         SoundExposureModel.allowanceLevel),
            isNotable: out.allowanceUsed >= 1))

        if let loudest = out.loudestDay, out.recordedDays > 0 {
            drivers.append(InsightDriver(
                text: String(format: "Your loudest day averaged %.0f dB(A) across %@ of listening, which is %.0f%% of the week's allowance in one day. At that level the NIOSH occupational limit allows %@.",
                             loudest.level,
                             loudest.hours >= 1
                                 ? String(format: "%.1f hours", loudest.hours)
                                 : String(format: "%.0f minutes", loudest.hours * 60),
                             loudest.allowanceHoursUsed / SoundExposureModel.allowanceHours * 100,
                             SoundExposureModel.permittedTimePhrase(atLevel: loudest.level)),
                isNotable: loudest.allowanceHoursUsed >= SoundExposureModel.allowanceHours / 2))
        }

        // The quiet week, said as a fact rather than left as an absence. A
        // reader whose phone has written these for months and whose week holds
        // none has genuinely not listened, and that is worth a line.
        if out.recordedDays == 0 {
            drivers.append(InsightDriver(
                text: "Nothing played through your headphones in the last \(SoundExposureModel.windowDays) days. Your iPhone has recorded \(out.historyDays) days of headphone audio in total, so this is a quiet week rather than a gap.",
                isNotable: false))
        }

        contributions.append(MetricContribution(
            metric: .headphoneSoundDose, higherIsBetter: false,
            weight: 1.0,
            detail: String(format: "%.0f%% of the weekly allowance, from %d day%@ of listening",
                           percent, out.recordedDays,
                           out.recordedDays == 1 ? "" : "s"),
            componentScore: out.score,
            value: out.equivalentLevelOver40Hours))

        if let environment = out.environment {
            drivers.append(InsightDriver(
                text: String(format: "Around you, your watch last measured %.0f dB(A) over %@. %@",
                             environment.latest.level,
                             environment.latest.hours >= 1
                                 ? String(format: "%.1f hours", environment.latest.hours)
                                 : String(format: "%.0f minutes", environment.latest.hours * 60),
                             SoundExposureModel.coveragePhrase(environment)),
                isNotable: false))
            contributions.append(MetricContribution(
                metric: .environmentalSoundDose, higherIsBetter: false,
                // ⚠️ **Zero, and the reason is coverage rather than modesty.**
                // The number above is a *cumulative* total, and a series
                // present on 14 days in 90 cannot enter one: every unmeasured
                // day would have to be counted as silent to make the sum, which
                // is the exact invention the original refusal named.
                weight: 0,
                detail: String(format: "%.0f dB(A) on the last day your watch heard anything — charted, never added: it covers %d of the last %d days, so a running total would have to treat every day it missed as silent",
                               environment.latest.level,
                               environment.daysMeasured,
                               SoundExposureModel.coverageDays),
                value: environment.latest.level))
        }

        // **The caveat is the card**, in the same sense it is on Gait: without
        // it a low percentage reads as a clean bill of hearing.
        drivers.append(InsightDriver(
            text: "This is what your iPhone drove your headphones at — audio through a laptop, a car or a speaker is not in it, and arrives here as silence. The allowance is a population exposure limit rather than a personal safety line: staying under it is not a promise, one week over it is not a loss, and none of this is a hearing test.",
            isNotable: false))

        return InsightResult(
            id: id, title: title,
            primaryValue: percent,
            headline: SoundExposureModel.band(out.score),
            subheadline: headline,
            score: out.score,
            // Never better than moderate. The level is the device's own model of
            // what it drove, not a measurement at the eardrum, and the standard
            // behind the allowance says as much about its own tolerance.
            confidence: out.recordedDays >= 3 ? .moderate : .low,
            explanation: "Your last \(SoundExposureModel.windowDays) days of headphone audio, accumulated as energy rather than averaged as loudness, against the World Health Organization's published allowance of \(Int(SoundExposureModel.allowanceHours)) hours a week at \(Int(SoundExposureModel.allowanceLevel)) dB(A). Every 3 dB doubles how fast the allowance is spent, so an hour of something loud costs more than an afternoon of something quiet. What your watch hears around you is shown beside this and never added to it.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: contributions,
            weighting: .singleMeasure("the World Health Organization's weekly recreational sound allowance"),
            otherFactors: Self.producedFigures(out),
            derivedOutputs: Self.derivedOutputs(out))
    }

    // MARK: - What this card works out (add-insight §5a)
    //
    // **(b) Produced figures, both of them.**
    //
    // `allowanceUsed` is a function of *two* things the series holds — the level
    // and the span — accumulated across a window. It is not monotone in the
    // day's LEQ: a loud ten minutes and a quiet afternoon can trade places
    // between weeks without either series moving the way the total does. Series.
    //
    // `listeningHours` is the denominator itself, and it is the one quantity in
    // this domain that nothing else in the app holds at all: the dose metric is
    // a *level*, and how long audio played is a separate fact carried in the
    // sample's span. A reader who wants to know whether their week was loud or
    // merely long can only get that from this row. Series.
    //
    // **The environmental figure gets none** — it is one metric's latest value
    // at face value, which is the reader's own pass-through rule (c). Its
    // departure is harvested from `MetricContribution` for free.
    //
    // Neither carries a weight: both are functions of the single contributor
    // above, and giving either a share would divide this card's number twice.

    static let allowanceKey = "weeklyAllowanceUsed"
    static let listeningKey = "weeklyListeningHours"

    static func derivedOutputs(_ out: SoundExposureModel.Output) -> [DerivedOutput] {
        [
            .init(key: allowanceKey,
                  displayName: "Weekly sound allowance used",
                  unit: "%", value: out.allowanceUsed * 100,
                  higherIsBetter: false, precision: 0),
            .init(key: listeningKey,
                  displayName: "Headphone listening, weekly",
                  unit: "h", value: out.listeningHours,
                  // Neither end is the good one: a long quiet week and a short
                  // loud one are different weeks, not a better and a worse one,
                  // and the allowance row above is where that judgement lives.
                  higherIsBetter: nil, precision: 1),
        ]
    }

    /// ⚠️ Weight 0 throughout — see `ScoreFactor.producedFigure`.
    static func producedFigures(_ out: SoundExposureModel.Output) -> [ScoreFactor] {
        [
            .producedFigure(
                DerivedSeriesID(.soundExposure, allowanceKey),
                name: "Weekly sound allowance used",
                detail: String(format: "%.0f%% of %.0f hours at %.0f dB(A) — this *is* the card's number rather than an input to it, so it carries no share of itself.",
                               out.allowanceUsed * 100,
                               SoundExposureModel.allowanceHours,
                               SoundExposureModel.allowanceLevel)),
            .producedFigure(
                DerivedSeriesID(.soundExposure, listeningKey),
                name: "Headphone listening, weekly",
                detail: String(format: "%.1f hours across %d day%@ — the multiplier the level is weighed by, not a judgement in itself, so it carries no share: an hour of something loud and an afternoon of something quiet can be the same dose.",
                               out.listeningHours, out.recordedDays,
                               out.recordedDays == 1 ? "" : "s")),
        ]
    }
}
