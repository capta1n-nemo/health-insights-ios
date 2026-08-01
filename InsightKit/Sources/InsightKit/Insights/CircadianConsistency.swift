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

        /// One night, with the centre it was actually judged against.
        ///
        /// Carried out of the model rather than recomputed by whatever draws it.
        /// The weekday/weekend split below is not a presentation detail — it is
        /// the thing that separates a recurring shift from scatter, and a chart
        /// that re-derived it would be a second implementation free to disagree
        /// with the score. Same reasoning as `InsightResult.contributors`: the
        /// series a picture draws are emitted by the code that did the scoring.
        public struct Night: Sendable, Equatable, Identifiable {
            /// The night's key — the morning it ends on, as `SleepOnset` stamps it.
            public let date: Date
            /// Signed hours from midnight, the `.sleepOnset` encoding.
            public let onset: Double
            /// The centre this night was measured against: its own block's, or
            /// the overall mean when no weekday/weekend shift was measurable.
            public let centre: Double
            public let isWeekend: Bool

            /// Signed distance from that centre. The residual the spread is
            /// built from, so a chart drawing these is drawing the score.
            public var departure: Double { onset - centre }

            public var id: Date { date }

            public init(date: Date, onset: Double, centre: Double, isWeekend: Bool) {
                self.date = date
                self.onset = onset
                self.centre = centre
                self.isWeekend = isWeekend
            }
        }

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
        /// Every night counted, oldest first, each with its own centre.
        public let nights: [Night]

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
                && a.nights == b.nights
        }
    }

    /// The raw nights, before anything is fitted to them.
    ///
    /// Split out from `evaluate` so a chart can re-fit over whatever stretch is
    /// on screen without re-reading the sample set each time the reader drags a
    /// finger. Reading the nights is the expensive half — a filter and a daily
    /// bucket over the whole history — and fitting a centre to a handful of
    /// them is arithmetic.
    public static func nights(from samples: [HealthMetricSample],
                              days: Int = windowNights,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> [VitalReader.DailyValue] {
        VitalReader.dailySeries(.sleepOnset, from: samples, days: days, now: now,
                                calendar: calendar)
    }

    public static func evaluate(samples: [HealthMetricSample], now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        evaluate(nights: nights(from: samples, now: now, calendar: calendar),
                 calendar: calendar)
    }

    /// Fit a centre, a spread and a weekend shift to exactly these nights.
    ///
    /// **Every number in the result describes the nights it was given** — the
    /// centre, the band, the jetlag and the spread are all measured over them
    /// and over nothing else. That is what lets the bedtime strip pan: scroll to
    /// last spring and the middle it draws is last spring's middle, not this
    /// fortnight's imposed on it. A chart that reused a fit from a different
    /// window would be drawing nights against a centre they were never judged
    /// against, which is the one thing the `Night.centre` field exists to
    /// prevent.
    public static func evaluate(nights: [VitalReader.DailyValue],
                                calendar: Calendar = .current) -> Output? {
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
                          ? worst.map { ($0.date, $0.value) } : nil,
                      // Built from the same `centre(for:)` the residuals above
                      // used, so a chart of these nights and the score computed
                      // from them cannot disagree about where the middle is.
                      nights: nights.map {
                          Output.Night(date: $0.date, onset: $0.value,
                                       centre: centre(for: $0.date),
                                       isWeekend: calendar.isDateInWeekend($0.date))
                      })
    }

    /// 0–100, higher is better. Continuous, because a regularity score has no
    /// published cut-points to step at and every step function this app has
    /// shipped has had to be replaced by a curve later.
    public static func score(spreadHours: Double) -> Double {
        Swift.max(0, Swift.min(100, 100 * (1 - spreadHours / zeroScoreSpreadHours)))
    }
}

/// The Insights-tab card.

