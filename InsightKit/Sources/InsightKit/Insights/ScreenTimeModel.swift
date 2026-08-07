import Foundation

/// **Screen time — described, and never graded.** Backlog B9-2.
///
/// The reader's ask was *"a screen time card, based on all the new screen time
/// data we are supporting"*. It was gated behind `B10-1` and `B10-2` — the OCR
/// import attributed single days to the wrong date and whole-week scans were
/// broken — because a card built on mis-dated days would have shipped a
/// confident wrong finding. Both are fixed, so this exists.
///
/// ## ⚠️ The one thing this card refuses, and it is the whole design
///
/// **It never scores how long the reader looked at a screen.** Not on a
/// published band, not against a guideline, not against their own median dressed
/// up as one. See `evidenceRefusal` for the sentence that says so on screen.
///
/// The reason is not squeamishness. There is no published dose–response for
/// adult recreational screen time and any health outcome. The figures that get
/// quoted come overwhelmingly from cross-sectional surveys of *self-reported*
/// use, and two things are true of that literature at once: self-reported use
/// correlates only moderately with logged use, so the exposure variable is
/// largely measurement error; and where the same questions have been asked of
/// large datasets with the analytic choices made explicit, the effects shrink
/// towards nothing and several headline findings have failed to replicate.
/// Importing any of that as a threshold would be this app inventing a scale and
/// then charging the reader for believing it — the same refusal
/// `SocialBatteryModel.capacityRefusal` and `BreathingDisturbanceTrend
/// .notAnApnoeaTest` already make in their own domains.
///
/// ## So what *is* the number?
///
/// The one comparison the reader's own record can support: **their heavier
/// screen days against their lighter ones, and what their body did on the nights
/// after each.** 100 means the two halves look alike. Lower means the nights
/// after the heavier half ran measurably worse *for this person*.
///
/// Two properties make that honest where a screen-time score is not:
///
/// - **The direction is not assumed.** A body that looks *better* after the
///   heavier half scores high and the card says so. Nothing here starts from
///   "more screen time is worse" and looks for confirmation.
/// - **Every claim it makes is about this person's own days.** "Shorter sleep is
///   the worse night" is established and is not a screen-time claim; "screen
///   time caused it" is a claim this card never makes, in any wording.
///
/// ## ⚠️ Coverage is the constraint and it is on screen
///
/// Apple sandboxes Screen Time — see `MetricType.screenTimeMinutes` — so no app
/// can read it and every day of it here was typed in or read off a screenshot
/// the reader supplied. On their export that is **twenty-six rows across
/// twenty-five days**, of which about twenty have a night after them the app
/// also holds. That is the governing fact about this card, so `CoverageGate`
/// carries it and the card leads with it rather than burying it in a footnote.
public enum ScreenTimeModel {

    /// Days needed on **each** side of the reader's own median before the two
    /// halves are contrasted at all.
    ///
    /// ⚠️ **Ten, which is deliberately above `ScreenTimeSleepLink.minimumPairs`
    /// of fourteen total.** That section contrasts one outcome; this pools three
    /// channels and prints a 0–100 beside them, and a number is read as more
    /// certain than a sentence. It is also the specific literature this card
    /// refuses to import that was built on small contrasts of exactly this
    /// shape, so setting the floor low here would be making the same mistake
    /// while claiming to avoid it.
    public static let minimumDaysPerHalf = 10

    /// The fewest days before "a typical day of yours" means anything.
    public static let minimumDaysToDescribe = 7

    /// The pooled departure at which the body has said something, in SDs of the
    /// reader's own night-to-night spread. The same 0.5 the work and social
    /// cards mark a channel notable at.
    public static let notableResponse = 0.5

    /// ⚠️ **The response channels are `WorkImpactModel.watched`, unchanged and
    /// on purpose.**
    ///
    /// Resting heart rate, variability and sleep duration, all read on the night
    /// *after* the day being judged. Two reasons for reusing that list rather
    /// than writing a screen-time-flavoured one:
    ///
    /// - **It is the neutral list.** Picking sleep latency and sleep efficiency
    ///   — the outcomes the popular claims are about — would be choosing the
    ///   channels most likely to produce the expected answer, which is the
    ///   analytic freedom that got that literature into trouble in the first
    ///   place. These three were chosen for a different card, for a different
    ///   question, before this one existed.
    /// - **Sleep onset and efficiency against screen time already have a home**
    ///   — `ScreenTimeSleepLink`, drawn by the Sleep card's own screen-time
    ///   section (B18-2). Answering it twice, two ways, on two cards is how two
    ///   surfaces come to disagree.
    static var watched: [(metric: MetricType, higherIsWorse: Bool)] {
        WorkImpactModel.watched
    }

    /// One day the reader supplied.
    public struct Day: Sendable, Equatable, Identifiable {
        public let day: Date
        public let minutes: Double
        public var id: Date { day }

        public init(day: Date, minutes: Double) {
            self.day = day
            self.minutes = minutes
        }
    }

    /// **What the reader's own screen time looks like** — available long before
    /// any contrast is, and shown on its own until one is.
    ///
    /// Separated from `Output` for exactly that reason: a card that can describe
    /// twelve days but cannot yet contrast them has something worth reading, and
    /// collapsing the two would have made the coverage gate hide the description
    /// as well as the number.
    public struct Description: Sendable, Equatable {
        /// Oldest first, one per calendar day.
        public let days: [Day]
        /// The reader's own median day. Their unit, and the line the split is
        /// made at — there is no external one to use.
        public let typicalMinutes: Double
        public let lightestMinutes: Double
        public let busiestMinutes: Double
        /// Median of Monday–Friday and of Saturday/Sunday, `nil` where either
        /// side has fewer than three days.
        public let weekdayMedian: Double?
        public let weekendMedian: Double?
        /// The fitted line through the recorded days, `nil` below eight of them.
        /// Read `isMeaningful` before naming a direction.
        public let trend: ScoreTrend?
        /// Days with a night after them the app also holds a reading for — the
        /// number the contrast is actually gated on, rather than the number of
        /// days entered.
        public let pairedDays: Int

        public init(days: [Day], typicalMinutes: Double, lightestMinutes: Double,
                    busiestMinutes: Double, weekdayMedian: Double?,
                    weekendMedian: Double?, trend: ScoreTrend?, pairedDays: Int) {
            self.days = days
            self.typicalMinutes = typicalMinutes
            self.lightestMinutes = lightestMinutes
            self.busiestMinutes = busiestMinutes
            self.weekdayMedian = weekdayMedian
            self.weekendMedian = weekendMedian
            self.trend = trend
            self.pairedDays = pairedDays
        }

        public var daysRecorded: Int { days.count }

        public var span: ClosedRange<Date>? {
            guard let first = days.first?.day, let last = days.last?.day,
                  first <= last else { return nil }
            return first...last
        }

        /// Calendar days between the first and last entry inclusive — so the
        /// card can say "twenty-five days out of a stretch of forty", which is a
        /// different and more useful fact than the count alone.
        public var spanDays: Int {
            guard let span else { return days.count }
            return Int((span.upperBound.timeIntervalSince(span.lowerBound) / 86_400).rounded()) + 1
        }
    }

    public struct Output: Sendable, Equatable {
        public let description: Description
        /// Sorted worst-first, as the work card sorts them.
        public let channels: [WorkImpactModel.Channel]
        public let heavyDays: Int
        public let lightDays: Int
        public let heavyMedianMinutes: Double
        public let lightMedianMinutes: Double
        /// Mean departure across the channels, signed so **positive is the
        /// unwelcome direction**.
        ///
        /// ⚠️ It treats the channels as independent and they are not — resting
        /// heart rate, variability and sleep move together — so the real spread
        /// around this figure is wider than three channels' worth. The card says
        /// so; the same warning `SocialBatteryModel.Response` carries.
        public let pooled: Double
        public let score: Double
        public let contributions: [MetricContribution]

        public init(description: Description, channels: [WorkImpactModel.Channel],
                    heavyDays: Int, lightDays: Int, heavyMedianMinutes: Double,
                    lightMedianMinutes: Double, pooled: Double, score: Double,
                    contributions: [MetricContribution]) {
            self.description = description
            self.channels = channels
            self.heavyDays = heavyDays
            self.lightDays = lightDays
            self.heavyMedianMinutes = heavyMedianMinutes
            self.lightMedianMinutes = lightMedianMinutes
            self.pooled = pooled
            self.score = score
            self.contributions = contributions
        }

        /// The gap the split rests on, in minutes a day.
        public var gapMinutes: Double { heavyMedianMinutes - lightMedianMinutes }
    }

    /// ⚠️ **Three outcomes, not two.** `describing` is the one that matters: the
    /// card has days to draw and cannot yet contrast them, which is a completely
    /// different state from having nothing — and rendering both as "no data" is
    /// the defect `CoverageGate` exists to stop.
    public enum Result: Sendable, Equatable {
        case ready(Output)
        case describing(Description, CoverageGate)
        case nothing
    }

    // MARK: - Building

    public static func analyse(samples: [HealthMetricSample], now: Date,
                               calendar: Calendar = .current) -> Result {
        // One figure per day, later reading wins — the correction the reader
        // typed after a screenshot import, which is also what
        // `ScreenTimePrecedence` decides upstream.
        var byDay: [Date: Double] = [:]
        for sample in samples.samples(of: .screenTimeMinutes) {
            byDay[calendar.startOfDay(for: sample.start)] = sample.value
        }
        let days = byDay.keys.sorted().map { Day(day: $0, minutes: byDay[$0] ?? 0) }
        guard !days.isEmpty else { return .nothing }

        // The night after each day, per channel. Built once so the paired count
        // the gate reports is the same set the channels are built from — a gate
        // counting something other than what it gates is how a card comes to say
        // "twenty of twenty" and still withhold its figure.
        let nightly: [MetricType: [Date: Double]] = Dictionary(
            uniqueKeysWithValues: watched.map { entry in
                let series = VitalReader.dailySeries(entry.metric, from: samples,
                                                     now: now, calendar: calendar)
                return (entry.metric,
                        Dictionary(series.map { ($0.date, $0.value) },
                                   uniquingKeysWith: { first, _ in first }))
            })

        func nextDay(_ day: Date) -> Date? {
            calendar.date(byAdding: .day, value: 1, to: day)
        }

        let paired = days.filter { day in
            guard let after = nextDay(day.day) else { return false }
            return nightly.values.contains { $0[after] != nil }
        }.count

        let description = describe(days: days, paired: paired, calendar: calendar)

        let contrastGate = CoverageGate.ifShort(
            need: minimumDaysPerHalf * 2, have: paired,
            unit: "day of screen time with a night recorded after it",
            unlocks: "this can hold your heavier days against your lighter ones and "
                + "say what your body did after each")
        // `ifShort` is nil once the requirement is met, so this branch is exactly
        // the short one and the met case falls through to the contrast below.
        if let contrastGate { return .describing(description, contrastGate) }

        // Split at the reader's own median. There is no external threshold for
        // "a lot of screen time" and inventing one is the thing this card exists
        // not to do, so "heavy" means heavy *for them* and the copy says so.
        let median = description.typicalMinutes
        let heavy = days.filter { $0.minutes > median }
        let light = days.filter { $0.minutes <= median }
        guard heavy.count >= minimumDaysPerHalf, light.count >= minimumDaysPerHalf else {
            return .describing(description, CoverageGate(
                need: minimumDaysPerHalf,
                have: Swift.min(heavy.count, light.count),
                unit: "day on the lighter side of your own middle",
                unlocks: "this can contrast your heavier days with your lighter ones — "
                    + "right now they are too alike to split"))
        }

        var channels: [WorkImpactModel.Channel] = []
        for entry in watched {
            guard let byNight = nightly[entry.metric] else { continue }
            func values(_ group: [Day]) -> [Double] {
                group.compactMap { nextDay($0.day).flatMap { byNight[$0] } }
            }
            let heavyValues = values(heavy)
            let lightValues = values(light)
            guard heavyValues.count >= minimumDaysPerHalf,
                  lightValues.count >= minimumDaysPerHalf,
                  let heavyMean = Baseline.mean(heavyValues),
                  let lightMean = Baseline.mean(lightValues),
                  let spread = pooledSpread(heavyValues, lightValues),
                  spread > 0 else { continue }
            let raw = (heavyMean - lightMean) / spread
            channels.append(WorkImpactModel.Channel(
                metric: entry.metric, onHeavyDays: heavyMean, onLightDays: lightMean,
                towardWorse: entry.higherIsWorse ? raw : -raw))
        }
        guard channels.count >= 2 else {
            return .describing(description, CoverageGate(
                need: 2, have: channels.count, unit: "responding signal",
                unlocks: "this can tell a real difference between your days from one "
                    + "instrument having a bad fortnight"))
        }

        let pooled = channels.reduce(0) { $0 + $1.towardWorse } / Double(channels.count)
        let heavyMedian = Baseline.median(heavy.map(\.minutes)) ?? median
        let lightMedian = Baseline.median(light.map(\.minutes)) ?? median

        // ⚠️ **`metricShare: 1` — the body carries the whole number, and the
        // zero on the other side is the card's entire argument.**
        //
        // Work impact and social battery both give their *exposure* a share:
        // hours in meetings and hours with people are things the reader carried,
        // and a heavy fortnight counts for something even when the body shrugs
        // it off. Screen time gets no such share, because there is no scale on
        // which four hours is worse than two. Handing it one would be exactly
        // the headline import this card refuses, arriving through the weighting
        // section instead of the copy.
        let terms = channels.map { channel in
            ScoreBlend.Term(
                metric: channel.metric,
                higherIsBetter: !(watched.first { $0.metric == channel.metric }?.higherIsWorse ?? true),
                score: WorkImpactModel.responseScore(towardWorse: channel.towardWorse),
                weight: 1,
                detail: sentence(channel),
                // Judged against the reader's own spread, not a published band.
                isPublishedScale: false,
                value: channel.onHeavyDays, baseline: channel.onLightDays,
                z: channel.towardWorse)
        }
        guard let blended = ScoreBlend.blend(metrics: terms, factors: [],
                                             metricShare: 1) else {
            return .describing(description, CoverageGate(
                need: 1, have: 0, unit: "weighted signal",
                unlocks: "this can put a number on how your days compare"))
        }

        return .ready(Output(
            description: description,
            channels: channels.sorted { $0.towardWorse > $1.towardWorse },
            heavyDays: heavy.count, lightDays: light.count,
            heavyMedianMinutes: heavyMedian, lightMedianMinutes: lightMedian,
            pooled: pooled, score: blended.score,
            contributions: blended.contributions + [screenTimeRow(description)]))
    }

    /// **The yardstick a difference between two groups is measured in: their
    /// own spread, pooled — not the spread of the two groups stacked together.**
    ///
    /// ⚠️ This is deliberately *not* what `WorkImpactModel` does, and the reason
    /// is a property of the median absolute deviation rather than a preference.
    /// MAD is taken about the median of whatever it is handed; hand it two
    /// well-separated lumps of roughly equal size and the median lands between
    /// them, every deviation is about half the gap, and the statistic reports
    /// the *gap* rather than the noise. The departure then comes back divided by
    /// something far too small — a fixture of two clean levels produced
    /// "67 SD worse", which is not a number any card may print.
    ///
    /// A calendar cannot easily produce that shape, which is why the work card
    /// has never met it. **Screen time can**: a reader who fills in their phone
    /// screen's weekly summary gets a heavy working pattern and a light one with
    /// very little between, and the split is 50/50 by construction because it is
    /// made at their own median.
    ///
    /// So each half is measured about its *own* middle and the two are pooled in
    /// quadrature — the robust twin of the pooled SD behind Cohen's d. On data
    /// that is not degenerate the two agree; only in the two-lump case do they
    /// differ, and there this one is right.
    static func pooledSpread(_ heavy: [Double], _ light: [Double]) -> Double? {
        guard let heavyScale = Baseline.robustScale(heavy),
              let lightScale = Baseline.robustScale(light) else { return nil }
        return ((heavyScale * heavyScale + lightScale * lightScale) / 2).squareRoot()
    }

    static func describe(days: [Day], paired: Int, calendar: Calendar) -> Description {
        let minutes = days.map(\.minutes)
        let weekday = days.filter { !calendar.isDateInWeekend($0.day) }.map(\.minutes)
        let weekend = days.filter { calendar.isDateInWeekend($0.day) }.map(\.minutes)
        var trend: ScoreTrend?
        if days.count >= 8, let first = days.first?.day {
            let x = days.map { $0.day.timeIntervalSince(first) / 86_400 }
            trend = Baseline.linearRegression(x: x, y: minutes).map {
                ScoreTrend(slopePerWeek: $0.slope * 7, residualSD: $0.residualSD,
                           start: first, intercept: $0.intercept,
                           slopePerDay: $0.slope, sampleCount: days.count)
            }
        }
        return Description(
            days: days,
            typicalMinutes: Baseline.median(minutes) ?? 0,
            lightestMinutes: minutes.min() ?? 0,
            busiestMinutes: minutes.max() ?? 0,
            weekdayMedian: weekday.count >= 3 ? Baseline.median(weekday) : nil,
            weekendMedian: weekend.count >= 3 ? Baseline.median(weekend) : nil,
            trend: trend, pairedDays: paired)
    }

    /// **Screen time's own row: charted, never scored.**
    ///
    /// ⚠️ The em-dash clause is not decoration — `ChartedWeightRuleTests` splits
    /// on it and fails a zero with no stated reason. It is also the shortest
    /// place the card's whole argument is written down, so a reader who opens
    /// only "How this is weighted" still meets it.
    static func screenTimeRow(_ description: Description) -> MetricContribution {
        MetricContribution(
            metric: .screenTimeMinutes,
            // Neither direction is the good one, because nothing published says
            // which is. `nil` is the same answer skin-temperature deviation
            // gives, for the same reason.
            higherIsBetter: nil,
            weight: 0,
            detail: String(format: "%@ on a typical day across %d days you entered "
                           + "— charted and never scored: no published work says what "
                           + "amount of screen time is good or bad for an adult, so "
                           + "this card scores what your own body did rather than how "
                           + "long you looked at a screen",
                           minutesPhrase(description.typicalMinutes),
                           description.daysRecorded),
            value: description.typicalMinutes)
    }

    // MARK: - What it is allowed to say

    /// The refusal, written once so every surface says the same thing.
    ///
    /// ⚠️ It lives in InsightKit rather than in the view for the reason
    /// `SectionCaveat`'s words do: the app target has no test target, and this
    /// is the honesty claim rather than copy.
    public static let evidenceRefusal =
        "⚠️ This card does not grade your screen time, and will not. There is no "
        + "published amount that is healthy or unhealthy for an adult — the widely "
        + "repeated links to sleep and mood come mostly from surveys that asked "
        + "people to estimate their own use, which matches measured use only "
        + "loosely, and where the same questions have been put to large datasets "
        + "with every analytic choice made explicit the effects shrink towards "
        + "nothing and several have failed to replicate. So none of it is imported "
        + "here. The only comparison this card makes is between your own heavier "
        + "and lighter days, and even that is an association: a heavy screen day "
        + "is also often a late one, a stressful one and an indoor one, and nothing "
        + "here can separate those."

    /// Why there will never be many days, and the two routes that add one.
    public static let howItArrives =
        "iOS does not let any app read your Screen Time — Apple's own extension "
        + "runs read-only and cannot pass its numbers out — so this only ever knows "
        + "the days you hand it. \"View & add\" on this card takes a day's total, "
        + "the camera import reads a Screen Time screenshot, and the Shortcuts "
        + "automation under Settings can send it without you typing anything."

    /// The headline, from the comparison rather than from the dial — and phrased
    /// as *what went with what*, never as cause.
    public static func headline(_ out: Output) -> String {
        guard abs(out.pooled) >= 0.3 else {
            return "Your heavier screen days look like your lighter ones"
        }
        return out.pooled > 0
            ? "Your heavier screen days went with rougher nights"
            : "Your heavier screen days went with better nights"
    }

    public static func subheadline(_ description: Description) -> String {
        String(format: "%@ on a typical day, from %d %@ you have entered",
               minutesPhrase(description.typicalMinutes),
               description.daysRecorded,
               description.daysRecorded == 1 ? "day" : "days")
    }

    /// How the reader's own days are shaped — the half of this card that needs
    /// no contrast and no night beside it.
    public static func shapeSentence(_ d: Description) -> String {
        String(format: "Across %d %@ you have entered, a typical day is %@, your "
               + "quietest was %@ and your busiest %@. \"Heavy\" on this card means "
               + "heavy for you: there is no outside number to measure it against.",
               d.daysRecorded, d.daysRecorded == 1 ? "day" : "days",
               minutesPhrase(d.typicalMinutes),
               minutesPhrase(d.lightestMinutes),
               minutesPhrase(d.busiestMinutes))
    }

    /// Weekday against weekend, or `nil` where either side is too thin to say.
    public static func weekPatternSentence(_ d: Description) -> String? {
        guard let weekday = d.weekdayMedian, let weekend = d.weekendMedian else { return nil }
        let gap = weekend - weekday
        guard abs(gap) >= 15 else {
            return String(format: "Your weekends look like your weekdays — %@ against "
                          + "%@ on a typical one.",
                          minutesPhrase(weekend), minutesPhrase(weekday))
        }
        return String(format: "Weekends run %@ %@ than weekdays — %@ against %@ on a "
                      + "typical one.",
                      minutesPhrase(abs(gap)), gap > 0 ? "heavier" : "lighter",
                      minutesPhrase(weekend), minutesPhrase(weekday))
    }

    /// Whether the entered days are drifting, and `nil` where there is no line.
    public static func driftSentence(_ d: Description) -> String? {
        guard let trend = d.trend else { return nil }
        guard trend.isMeaningful else {
            return String(format: "No drift up or down across those days that stands "
                          + "out from how much they differ anyway — the days scatter "
                          + "by about %@ around the line.",
                          minutesPhrase(trend.residualSD))
        }
        return String(format: "Your entered days are drifting %@ by about %@ a week, "
                      + "against a day-to-day scatter of %@.",
                      trend.slopePerWeek > 0 ? "up" : "down",
                      minutesPhrase(abs(trend.slopePerWeek)),
                      minutesPhrase(trend.residualSD))
    }

    /// The split, said out loud with both counts, so a reader can see how thin
    /// the comparison is without doing arithmetic.
    public static func splitSentence(_ out: Output) -> String {
        String(format: "Split at your own middle of %@: %d heavier %@ averaging %@ "
               + "against %d lighter %@ averaging %@.",
               minutesPhrase(out.description.typicalMinutes),
               out.heavyDays, out.heavyDays == 1 ? "day" : "days",
               minutesPhrase(out.heavyMedianMinutes),
               out.lightDays, out.lightDays == 1 ? "day" : "days",
               minutesPhrase(out.lightMedianMinutes))
    }

    /// What the pooled figure is, and what it is not.
    public static func pooledSentence(_ out: Output) -> String {
        guard abs(out.pooled) >= 0.3 else {
            return String(format: "Pooled across %d signals, the nights after your "
                          + "heavier days differ from the nights after your lighter "
                          + "ones by %.2f of your own night-to-night spread — which "
                          + "is to say, not noticeably.",
                          out.channels.count, abs(out.pooled))
        }
        return String(format: "Pooled across %d signals, the nights after your heavier "
                      + "days run %.2f of your own night-to-night spread %@ than the "
                      + "nights after your lighter ones. That is what went with them, "
                      + "not what caused them.",
                      out.channels.count, abs(out.pooled),
                      out.pooled > 0 ? "worse" : "better")
    }

    /// One channel, in the same shape the work card states its own.
    public static func sentence(_ channel: WorkImpactModel.Channel) -> String {
        String(format: "%@ %@ on the nights after your heavier days — %@ against %@ — "
               + "which is %.1f SD %@",
               channel.metric.displayName,
               abs(channel.towardWorse) < 0.3 ? "is about the same"
                   : "runs \(channel.towardWorse > 0 ? "worse" : "better")",
               MetricValueFormatter.string(channel.onHeavyDays, channel.metric),
               MetricValueFormatter.string(channel.onLightDays, channel.metric),
               abs(channel.towardWorse), channel.towardWorse > 0 ? "worse" : "better")
    }

    /// Hours and minutes, because "142 min" is not something anybody pictures.
    public static func minutesPhrase(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return "\(total) min" }
        let hours = total / 60
        let rest = total % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    // MARK: - The figures this card produces (add-insight §5a)
    //
    // Two, both **(b) produced figures**: each is a function of the rows below
    // it, so a share would count the same evidence twice.
    //
    // ⚠️ Deliberately *not* filed: the typical day, the busiest day and the
    // weekday/weekend medians. Every one of them is **(c) a pass-through** — a
    // quantile of `MetricType.screenTimeMinutes` and nothing else — and filing
    // one would put the same number in the Data tab twice under a second name.

    public static let contrastKey = "heavyLightGap"
    public static let responseKey = "pooledResponse"

    public static func derivedOutputs(_ out: Output) -> [DerivedOutput] {
        [
            DerivedOutput(key: contrastKey,
                          displayName: "Screen time gap, heavier days vs lighter",
                          unit: "min", value: out.gapMinutes,
                          // Neither more nor less of a gap is the better one: it
                          // is the width of the comparison, not a health figure.
                          higherIsBetter: nil, precision: 0),
            DerivedOutput(key: responseKey,
                          displayName: "How differently your body read those days",
                          unit: "SD", value: out.pooled,
                          higherIsBetter: false, precision: 2)
        ]
    }

    public static func producedFigures(_ out: Output) -> [ScoreFactor] {
        [
            .producedFigure(DerivedSeriesID(.screenTime, contrastKey),
                            name: "The gap your days are split at",
                            detail: String(format: "%@ a day between your heavier and "
                                           + "lighter halves — it carries no share "
                                           + "because it decides *which* days the rows "
                                           + "above compare rather than feeding the "
                                           + "number, and scoring it would mean scoring "
                                           + "how long you use your phone",
                                           minutesPhrase(out.gapMinutes))),
            .producedFigure(DerivedSeriesID(.screenTime, responseKey),
                            name: "Pooled difference in your body",
                            detail: String(format: "%.2f SD %@ after your heavier days "
                                           + "— it carries no share because it is the "
                                           + "average of the rows above, and giving it "
                                           + "one would count the same evidence twice",
                                           abs(out.pooled),
                                           out.pooled > 0 ? "worse" : "better"))
        ]
    }
}

/// **The card.** `ScreenTimeModel` holds the arithmetic and the wording; this
/// says what reaches the reader, in what order, and what it refuses to say.
public struct ScreenTimeInsight: InsightModel {
    public let id: InsightID = .screenTime
    public let title = "Screen time"

    public init() {}

    /// Screen time itself, plus the three channels the nights after it are read
    /// on. Declared rather than implied — and every one of them is reported,
    /// which `ContributorsTests` holds in both directions.
    public var candidateMetrics: [MetricType] {
        [.screenTimeMinutes] + ScreenTimeModel.watched.map(\.metric)
    }

    public var requirements: [GroundingRequirement] { [] }

    /// The reader hands this card its subject, so the route is the point rather
    /// than an afterthought — `ContributionRoute.screenTime` is the same one the
    /// Sleep card's screen-time section points at.
    public var contributions: [ContributionRoute] { [.screenTime] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        let context = "This reads the days of screen time you have entered, and what "
            + "your body did on the nights after them."
        switch ScreenTimeModel.analyse(samples: samples, now: now) {
        case .nothing:
            return invitingInput(
                id, title,
                action: "Add a day of screen time",
                message: "\(context) iOS does not let any app read your Screen Time, "
                    + "so it only ever knows the days you hand it — type one in, "
                    + "photograph the Screen Time screen, or set up the Shortcuts "
                    + "automation under Settings. \(ScreenTimeModel.evidenceRefusal)")

        case .describing(let description, let gate):
            // ⚠️ **Not `waitingOn`.** That helper is right for a card with
            // nothing to show but a count, and this one has the reader's own days
            // to describe — the shape of them, the weekday pattern, the drift.
            // Rendering all of that as "Learning" with no lines under it would
            // be the same defect `CoverageGate` was written to stop, one layer
            // up: an app that has something to say and says "not yet".
            return InsightResult(
                id: id, title: title, primaryValue: nil,
                headline: "Your days so far",
                subheadline: ScreenTimeModel.subheadline(description),
                score: nil, confidence: .low,
                explanation: "\(context) \(gate.sentence ?? "")",
                driverLines: describingDrivers(description, gate: gate),
                unmetRequirements: [],
                contributors: [ScreenTimeModel.screenTimeRow(description)],
                weighting: .unstated,
                invitesInput: false, isLearning: true)

        case .ready(let out):
            return InsightResult(
                id: id, title: title, primaryValue: out.score,
                headline: ScreenTimeModel.headline(out),
                subheadline: ScreenTimeModel.subheadline(out.description),
                score: out.score,
                confidence: confidence(out),
                explanation: "The number is not a judgement of your screen time — "
                    + "nothing here grades that. It is how differently your body read "
                    + "the nights after your heavier days compared with the nights "
                    + "after your lighter ones, over the days you have entered. 100 "
                    + "means the two halves look alike; lower means the nights after "
                    + "your heavier days ran measurably worse for you. If they ran "
                    + "*better*, this says so — the direction is read off your own "
                    + "nights rather than assumed. \(ScreenTimeModel.evidenceRefusal)",
                driverLines: readyDrivers(out),
                unmetRequirements: [],
                contributors: out.contributions,
                weighting: .weightedAverage,
                otherFactors: ScreenTimeModel.producedFigures(out),
                derivedOutputs: ScreenTimeModel.derivedOutputs(out))
        }
    }

    /// ⚠️ **Never `.high`, on any amount of data this card can realistically
    /// hold.** Its subject is hand-entered, so the sample is small by
    /// construction and self-selected by whichever days the reader remembered —
    /// which is a bias no count fixes.
    private func confidence(_ out: ScreenTimeModel.Output) -> InsightConfidence {
        guard out.channels.count >= 3, out.description.pairedDays >= 40 else { return .low }
        return .moderate
    }

    private func describingDrivers(_ d: ScreenTimeModel.Description,
                                   gate: CoverageGate) -> [InsightDriver] {
        var lines: [InsightDriver] = []
        if let sentence = gate.sentence { lines.append(.notable(sentence)) }
        lines.append(.routine(ScreenTimeModel.shapeSentence(d)))
        if let week = ScreenTimeModel.weekPatternSentence(d) { lines.append(.routine(week)) }
        if let drift = ScreenTimeModel.driftSentence(d) { lines.append(.routine(drift)) }
        lines.append(.routine(ScreenTimeModel.evidenceRefusal))
        lines.append(.routine(ScreenTimeModel.howItArrives))
        return lines
    }

    private func readyDrivers(_ out: ScreenTimeModel.Output) -> [InsightDriver] {
        var lines: [InsightDriver] = [
            InsightDriver(text: ScreenTimeModel.pooledSentence(out),
                          isNotable: abs(out.pooled) >= ScreenTimeModel.notableResponse)
        ]
        for channel in out.channels {
            lines.append(InsightDriver(
                text: ScreenTimeModel.sentence(channel),
                isNotable: channel.towardWorse >= ScreenTimeModel.notableResponse))
        }
        lines.append(.routine(ScreenTimeModel.splitSentence(out)))
        lines.append(.routine(ScreenTimeModel.shapeSentence(out.description)))
        if let week = ScreenTimeModel.weekPatternSentence(out.description) {
            lines.append(.routine(week))
        }
        if let drift = ScreenTimeModel.driftSentence(out.description) {
            lines.append(.routine(drift))
        }
        lines.append(.routine(String(
            format: "How thin this is, stated rather than implied: %d %@ of screen "
                + "time, %d of them with a night after them the app also holds. A "
                + "comparison this size can miss a real difference and can invent one; "
                + "read it as a first look at your own record, not as a finding.",
            out.description.daysRecorded,
            out.description.daysRecorded == 1 ? "day" : "days",
            out.description.pairedDays)))
        lines.append(.routine("⚠️ The spread around every figure here is worked out as "
                              + "if resting heart rate, variability and sleep move "
                              + "independently, and they do not — so the true range is "
                              + "wider than the one printed. Where this card is close "
                              + "to saying nothing, treat it as closer."))
        lines.append(.routine(ScreenTimeModel.evidenceRefusal))
        lines.append(.routine(ScreenTimeModel.howItArrives))
        return lines.filter { $0.isNotable == true } + lines.filter { $0.isNotable != true }
    }
}
