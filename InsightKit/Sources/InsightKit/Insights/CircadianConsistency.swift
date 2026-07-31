import Foundation

/// How steady the clock you sleep by is — and how far the weekend pulls it.
///
/// The roadmap carried this as **blocked on a missing signal** for a long time,
/// on the reading that no provider gives us a bedtime. That was true of what the
/// app ingested and false of what the providers serve; see `SleepOnset`, which
/// is where the unblocking actually happened. What follows is what to do with it.
///
/// ## Why regularity and not timing
///
/// The obvious card is "you go to bed too late", and it is the one thing this
/// must not say. Chronotype is largely constitutional and shift work is a job:
/// telling a night nurse that 09:00 is the wrong time to sleep is both useless
/// and untrue. What the evidence is actually about is *regularity* — the Sleep
/// Regularity Index literature finds irregular timing tracks with cardiometabolic
/// risk after adjusting for how much sleep people get, which is to say
/// independently of everything `SleepDebt` already measures. So this scores the
/// spread and never the hour.
///
/// ## Social jetlag, reported separately
///
/// The weekday-to-weekend shift is a *different* quantity from night-to-night
/// scatter and is folded out of it here rather than averaged in. Somebody who
/// sleeps at 23:00 every weeknight and 02:00 every weekend is perfectly regular
/// within each block and carries a three-hour recurring shift; somebody whose
/// bedtime wanders randomly by ninety minutes has no shift at all and is less
/// regular. One number cannot say both, and blending them describes neither.
public enum CircadianConsistencyModel {

    /// Nights considered. Two weeks, so both weekend blocks are represented —
    /// one weekend cannot decide the social-jetlag figure on its own.
    public static let windowNights = 14
    /// Nights needed before a spread means anything.
    public static let minimumNights = 5
    /// Nights needed *in each block* before a weekday/weekend shift is reported.
    public static let minimumNightsPerBlock = 2

    /// The spread at which the score reaches zero, in hours.
    ///
    /// A two-hour standard deviation in onset means the middle two-thirds of
    /// nights span four hours. There is no clinical cut-point to borrow here —
    /// the regularity literature reports continuous associations, not
    /// thresholds — so this is a scale choice, stated rather than dressed up:
    /// it is the point past which "what time do you go to bed" has no answer.
    public static let zeroScoreSpreadHours = 2.0

    public struct Output: Sendable, Equatable {
        /// Standard deviation of sleep onset, in hours, with any recurring
        /// weekday/weekend shift removed.
        public let spreadHours: Double
        /// The typical onset, in signed hours from midnight.
        public let typicalOnset: Double
        public let nightsCounted: Int
        /// Weekend onset minus weekday onset, in hours. Positive is the usual
        /// direction — later at the weekend. `nil` when either block is too thin.
        public let socialJetlagHours: Double?
        /// The single most out-of-step night in the window, if there is one
        /// worth naming.
        public let mostIrregular: (date: Date, onset: Double)?

        public var band: String {
            switch spreadHours {
            case ..<0.5: return "Very regular"
            case 0.5..<1.0: return "Regular"
            case 1.0..<1.5: return "Variable"
            default: return "Irregular"
            }
        }

        public static func == (a: Output, b: Output) -> Bool {
            a.spreadHours == b.spreadHours && a.typicalOnset == b.typicalOnset
                && a.nightsCounted == b.nightsCounted
                && a.socialJetlagHours == b.socialJetlagHours
                && a.mostIrregular?.date == b.mostIrregular?.date
                && a.mostIrregular?.onset == b.mostIrregular?.onset
        }
    }

    public static func evaluate(samples: [HealthMetricSample], now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let nights = VitalReader.dailySeries(.sleepOnset, from: samples,
                                             days: windowNights, now: now,
                                             calendar: calendar)
        guard nights.count >= minimumNights,
              let typical = Baseline.mean(nights.map(\.value)) else { return nil }

        // Blocks split by the night's *key*, which `SleepOnset` stamps as the
        // morning the night ends on — so "Saturday" here is the night from
        // Friday into Saturday, which is the one people mean by a Friday night.
        let weekend = nights.filter { calendar.isDateInWeekend($0.date) }
        let weekday = nights.filter { !calendar.isDateInWeekend($0.date) }

        var jetlag: Double?
        if weekend.count >= minimumNightsPerBlock, weekday.count >= minimumNightsPerBlock,
           let weekendMean = Baseline.mean(weekend.map(\.value)),
           let weekdayMean = Baseline.mean(weekday.map(\.value)) {
            jetlag = weekendMean - weekdayMean
        }

        // Each night against *its own block's* centre, so a recurring shift is
        // not counted as scatter. With no measurable shift both centres are the
        // overall mean and this reduces to a plain standard deviation.
        let weekdayCentre = Baseline.mean(weekday.map(\.value)) ?? typical
        let weekendCentre = Baseline.mean(weekend.map(\.value)) ?? typical
        func centre(for date: Date) -> Double {
            guard jetlag != nil else { return typical }
            return calendar.isDateInWeekend(date) ? weekendCentre : weekdayCentre
        }
        let residuals = nights.map { $0.value - centre(for: $0.date) }
        // Population form, not the sample form: these residuals are already
        // measured about fitted centres, and `Baseline.standardDeviation` would
        // divide by n − 1 having not been told how many were estimated.
        let spread = (residuals.map { $0 * $0 }.reduce(0, +) / Double(residuals.count))
            .squareRoot()

        let worst = nights.max { abs($0.value - centre(for: $0.date))
                                    < abs($1.value - centre(for: $1.date)) }
        let worstDeparture = worst.map { abs($0.value - centre(for: $0.date)) } ?? 0

        return Output(spreadHours: spread, typicalOnset: typical,
                      nightsCounted: nights.count, socialJetlagHours: jetlag,
                      // Only worth naming when it is a real outlier rather than
                      // simply the largest of a tight set.
                      mostIrregular: worstDeparture >= 1 && spread > 0
                          ? worst.map { ($0.date, $0.value) } : nil)
    }

    /// 0–100, higher is better. Continuous, because a regularity score has no
    /// published cut-points to step at and every step function this app has
    /// shipped has had to be replaced by a curve later.
    public static func score(spreadHours: Double) -> Double {
        Swift.max(0, Swift.min(100, 100 * (1 - spreadHours / zeroScoreSpreadHours)))
    }
}

/// The Insights-tab card.
public struct CircadianConsistencyInsight: InsightModel {
    public let id: InsightID = .circadianConsistency
    public let title = "Sleep Regularity"
    public init() {}

    public var requirements: [GroundingRequirement] { [] }
    public var candidateMetrics: [MetricType] { [.sleepOnset, .sleepDurationHours] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let output = CircadianConsistencyModel.evaluate(samples: samples, now: now) else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "Needs a few nights",
                score: nil, confidence: .low,
                explanation: "This measures how steady the clock you sleep by is, which the research treats as separate from how much you sleep. It needs \(CircadianConsistencyModel.minimumNights) nights with a recorded sleep time — Apple Health or a ring supplies those. Sleep that starts outside 18:00–06:00 is read as a nap rather than a bedtime and isn't counted, so a night-shift pattern will show nothing here.",
                drivers: [], unmetRequirements: [])
        }

        let score = CircadianConsistencyModel.score(spreadHours: output.spreadHours)
        let clock = MetricValueFormatter.string(output.typicalOnset, .sleepOnset)

        var drivers: [InsightDriver] = [
            .component(String(format: "Sleep starts around %@, give or take %d minutes",
                              clock, Int((output.spreadHours * 60).rounded())),
                       score: score)
        ]
        if let jetlag = output.socialJetlagHours, abs(jetlag) >= 0.5 {
            drivers.append(InsightDriver(
                text: String(format: "Weekends run %.1f h %@ than weeknights",
                             abs(jetlag), jetlag > 0 ? "later" : "earlier"),
                // A recurring shift is a finding in its own right, and it has
                // been kept out of the spread above rather than double-counted.
                isNotable: abs(jetlag) >= 1))
        }
        if let worst = output.mostIrregular {
            drivers.append(.routine(String(
                format: "Furthest out: %@, %@",
                worst.date.formatted(.dateTime.weekday(.wide)),
                MetricValueFormatter.string(worst.onset, .sleepOnset))))
        }
        drivers.append(.routine("\(output.nightsCounted) nights with a recorded sleep time"))

        var explanation: String
        switch output.spreadHours {
        case ..<0.5:
            explanation = "Your sleep starts at close to the same time every night. Regularity of timing tracks with cardiovascular and metabolic measures independently of how long you sleep, which is why it gets its own card rather than being folded into Sleep Debt."
        case 0.5..<1.5:
            explanation = "Your sleep time moves around by about \(Int((output.spreadHours * 60).rounded())) minutes night to night. This is a description of the pattern, not a target — the card scores the spread and deliberately never the hour, because what time is right for you is not something your data can say."
        default:
            explanation = "Your sleep time varies by more than an hour and a half night to night, which is wide enough that \"what time do you go to bed\" has no single answer. Reported because regularity is measured separately from duration in the research, and Sleep Debt would not show it."
        }
        if output.socialJetlagHours.map({ abs($0) >= 1 }) == true {
            explanation += " The weekday-to-weekend shift is reported on its own line and has been taken out of the spread, so a consistent weekend lie-in doesn't read as randomness."
        }

        return InsightResult(
            id: id, title: title, primaryValue: output.spreadHours,
            headline: "\(output.band) · \(clock)",
            score: score,
            // The window is short by construction and one recorded night can
            // move it, so this never claims high.
            confidence: output.nightsCounted >= 10 ? .moderate : .low,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: [
                // Weight 1 and 0: the score is a function of onset alone.
                // Duration is a candidate because the card talks about the
                // distinction, and carrying it at zero puts it on the detail
                // chart beside onset without claiming it moved the number.
                .init(metric: .sleepOnset, higherIsBetter: nil, weight: 1,
                      detail: clock),
                .init(metric: .sleepDurationHours, higherIsBetter: true, weight: 0,
                      detail: "for contrast")
            ])
    }
}
