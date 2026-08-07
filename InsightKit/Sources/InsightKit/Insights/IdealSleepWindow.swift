import Foundation

/// **What time you went to bed, against how the next day went.**
///
/// The reader, 2026-08-07: *"I also want an ideal sleep timeframe section, which
/// will compare over a very long period the days you feel best vs the times you
/// went to sleep."*
///
/// This is the one sleep question that is personal by construction. Every app
/// can restate a published bedtime; only one holding your own record can ask
/// which bedtime *preceded your own good days*.
///
/// ## Three decisions, all of which change the answer
///
/// ### 1. "Days you feel best" has no measurement, so the proxy is the design
///
/// There is no sensor for feeling well. The app can offer several stand-ins and
/// they answer different questions — next-day Readiness is a physiological
/// reading, the Energy level is a modelled state, the feedback ledger is the
/// reader's own word, a symptom-free flag is an absence. **This model does not
/// choose.** It takes the outcome series and its name from the caller and prints
/// the name wherever the finding is shown, because a card that says "your best
/// days start at 22:45" without saying what "best" meant is not a finding, it is
/// a horoscope.
///
/// ### 2. The day boundary, fixed in advance
///
/// A bedtime is stamped at the night's key — the morning it ends on
/// (`SleepOnset.night`). The outcome it is held against is **that same key's
/// day**: you go to bed on Tuesday evening, and the day this asks about is
/// Wednesday. Fixed here, once, rather than searched over: the substance-card
/// review found a whole finding set that flipped on the day boundary, and a
/// boundary chosen after seeing the answer is not a boundary, it is a
/// hyperparameter fitted to noise.
///
/// ### 3. The weekend is a confound, not a nuisance
///
/// Later bedtimes cluster before days with no alarm, and days with no alarm feel
/// different for reasons that have nothing to do with the bedtime. A naive "late
/// nights precede good days" is that artefact, drawn.
///
/// So **the outcome is de-meaned within its day type before anything is compared**
/// — weekend days against the weekend mean, weekdays against the weekday mean —
/// using the same weekend split `CircadianConsistencyModel` already fits for
/// social jetlag, so the two cannot disagree about which nights are which. What
/// each bin then reports is *how much better than a typical day of its own kind*
/// the days after that bedtime were.
///
/// ## What it refuses to say
///
/// A bedtime bin with too few nights is reported with its count and never
/// promoted to a finding; and where nothing separates the bins, the verdict is
/// that nothing separates the bins. **"Your bedtime does not appear to move
/// this" is the honest, common and useful answer**, and it is the one this
/// returns unless a bin clears both a two-standard-error gap and a real
/// difference in the outcome's own units.
public enum IdealSleepWindow {

    /// Bedtime bin width, in hours. Half an hour: fine enough that "before
    /// eleven" and "after midnight" are different bins, coarse enough that a
    /// year of nights still fills several of them.
    public static let binHours = 0.5

    /// Nights needed before the question is asked at all.
    public static let minimumNights = 30
    /// Nights needed in a bin before it is reported.
    public static let minimumPerBin = 5
    /// Standard errors between the best bin and the rest before a window is
    /// named. Two, which is the conventional line and is stated rather than
    /// tuned — moving it after seeing the answer is the fitting this model's
    /// whole design refuses.
    public static let requiredSeparation = 2.0

    /// One night joined to the day that followed it.
    public struct Night: Sendable, Equatable, Identifiable {
        /// The night's key — the morning it ended on, which is also the day the
        /// outcome is read from.
        public let date: Date
        /// Signed hours from midnight, the `.sleepOnset` encoding.
        public let onset: Double
        public let outcome: Double
        public let isWeekend: Bool
        /// The outcome with its own day type's mean removed. The quantity every
        /// comparison below is actually made on.
        public let adjustedOutcome: Double

        public var id: Date { date }
    }

    /// One half-hour of bedtime, and how the days after it went.
    public struct Bin: Sendable, Equatable, Identifiable {
        /// Signed hours from midnight at the bin's lower edge.
        public let lowerBound: Double
        public let nights: Int
        /// Mean adjusted outcome — zero means "an ordinary day of its kind".
        public let mean: Double
        /// Standard error of that mean. `nil` for a single night, where there is
        /// no spread to estimate one from.
        public let standardError: Double?

        public var upperBound: Double { lowerBound + binHours }
        public var centre: Double { lowerBound + binHours / 2 }
        public var id: Double { lowerBound }
    }

    public enum Verdict: Sendable, Equatable {
        /// A bedtime window that preceded better days than the rest, by more
        /// than `requiredSeparation` standard errors.
        case window(from: Double, to: Double, betterBy: Double)
        /// Enough nights, and nothing separated them.
        case nothingSeparates
        /// Not enough nights to ask.
        case notEnoughNights(have: Int, need: Int)
    }

    public struct Output: Sendable, Equatable {
        /// What "feeling best" was taken to mean. Printed wherever this is.
        public let outcomeName: String
        /// Whether higher is the good direction for that outcome.
        public let higherIsBetter: Bool
        public let nights: [Night]
        /// Reported bins, earliest bedtime first. Bins under `minimumPerBin`
        /// are dropped from here and counted in `thinBins`.
        public let bins: [Bin]
        public let thinBins: Int
        public let verdict: Verdict
        /// The reader's own middle bedtime, so the finding can be placed against
        /// their habit rather than against a clock.
        public let typicalOnset: Double
        /// Weekend minus weekday bedtime, in hours — the confound this model
        /// folded out, reported so the section can say it did.
        public let socialJetlagHours: Double?

        public var span: ClosedRange<Date>? {
            guard let first = nights.map(\.date).min(),
                  let last = nights.map(\.date).max(), first <= last else { return nil }
            return first...last
        }
    }

    /// Join bedtimes to an outcome and ask the question.
    ///
    /// - Parameters:
    ///   - onsets: `.sleepOnset` daily values, stamped at the night key.
    ///   - outcome: one value per day, stamped at the *same* key — see the day
    ///     boundary note above. Anything not matching a night is ignored.
    ///   - outcomeName: what the caller is calling "feeling best". Carried into
    ///     the output so no surface can show the finding without it.
    ///   - higherIsBetter: which direction of `outcome` is the good one.
    public static func evaluate(onsets: [VitalReader.DailyValue],
                                outcome: [VitalReader.DailyValue],
                                outcomeName: String,
                                higherIsBetter: Bool = true,
                                calendar: Calendar = .current) -> Output {
        var outcomeByDay: [Date: Double] = [:]
        for point in outcome {
            outcomeByDay[calendar.startOfDay(for: point.date)] = point.value
        }
        /// A joined pair, as a named type rather than a tuple — key paths do not
        /// work on tuple elements and `verify.sh` fails on `\.2`.
        struct Joined {
            let day: Date
            let onset: Double
            let outcome: Double
            let isWeekend: Bool
        }
        let joined = onsets.compactMap { onset -> Joined? in
            let day = calendar.startOfDay(for: onset.date)
            guard let value = outcomeByDay[day] else { return nil }
            return Joined(day: day, onset: onset.value, outcome: value,
                          isWeekend: calendar.isDateInWeekend(day))
        }.sorted { $0.day < $1.day }

        let weekendOutcomes = joined.filter(\.isWeekend).map(\.outcome)
        let weekdayOutcomes = joined.filter { !$0.isWeekend }.map(\.outcome)
        let overall = Baseline.mean(joined.map(\.outcome)) ?? 0
        // Each day type against its own middle. With one block empty both
        // centres are the overall mean and this reduces to plain de-meaning,
        // which is the right degenerate case rather than a special one.
        let weekendCentre = Baseline.mean(weekendOutcomes) ?? overall
        let weekdayCentre = Baseline.mean(weekdayOutcomes) ?? overall

        let nights = joined.map { pair in
            Night(date: pair.day, onset: pair.onset, outcome: pair.outcome,
                  isWeekend: pair.isWeekend,
                  adjustedOutcome: pair.outcome
                      - (pair.isWeekend ? weekendCentre : weekdayCentre))
        }

        let typical = Baseline.median(nights.map(\.onset)) ?? 0
        var jetlag: Double?
        let weekendOnsets = nights.filter(\.isWeekend).map(\.onset)
        let weekdayOnsets = nights.filter { !$0.isWeekend }.map(\.onset)
        if weekendOnsets.count >= CircadianConsistencyModel.minimumNightsPerBlock,
           weekdayOnsets.count >= CircadianConsistencyModel.minimumNightsPerBlock,
           let a = Baseline.mean(weekendOnsets), let b = Baseline.mean(weekdayOnsets) {
            jetlag = a - b
        }

        guard nights.count >= minimumNights else {
            return Output(outcomeName: outcomeName, higherIsBetter: higherIsBetter,
                          nights: nights, bins: [], thinBins: 0,
                          verdict: .notEnoughNights(have: nights.count,
                                                    need: minimumNights),
                          typicalOnset: typical, socialJetlagHours: jetlag)
        }

        // MARK: Bins

        var byBin: [Double: [Double]] = [:]
        for night in nights {
            let lower = (night.onset / binHours).rounded(.down) * binHours
            byBin[lower, default: []].append(night.adjustedOutcome)
        }
        var reported: [Bin] = []
        var thin = 0
        for (lower, values) in byBin.sorted(by: { $0.key < $1.key }) {
            guard values.count >= minimumPerBin else { thin += 1; continue }
            let mean = Baseline.mean(values) ?? 0
            let sd = Baseline.standardDeviation(values)
            reported.append(Bin(lowerBound: lower, nights: values.count, mean: mean,
                                standardError: sd.map { $0 / Double(values.count).squareRoot() }))
        }

        // MARK: The verdict
        //
        // The best bin has to beat **every other reported bin** by two standard
        // errors of the difference, not merely beat the pooled average — a bin
        // can sit above the average purely because the average includes it.
        // Two bins that are indistinguishable from each other are reported as
        // one window rather than as a winner and a runner-up.
        let ordered = higherIsBetter
            ? reported.sorted { $0.mean > $1.mean }
            : reported.sorted { $0.mean < $1.mean }
        var verdict: Verdict = .nothingSeparates
        if let best = ordered.first, reported.count >= 2 {
            // Bins statistically tied with the best one, which together form the
            // window. Ordered by clock time so the window is a stretch of
            // evening rather than a ranking.
            let tied = reported.filter { bin in
                guard let separation = separation(best, bin) else { return true }
                return separation < requiredSeparation
            }.sorted { $0.lowerBound < $1.lowerBound }
            let rest = reported.filter { candidate in
                !tied.contains { $0.lowerBound == candidate.lowerBound }
            }
            // A window has to leave something outside it — a "window" containing
            // every bin is the finding that nothing separates them, written to
            // look like a finding.
            if !rest.isEmpty,
               rest.allSatisfy({ (separation(best, $0) ?? 0) >= requiredSeparation }),
               let furthest = rest.map({ abs(best.mean - $0.mean) }).max(),
               let lower = tied.first?.lowerBound, let upper = tied.last?.upperBound {
                verdict = .window(from: lower, to: upper, betterBy: furthest)
            }
        }

        return Output(outcomeName: outcomeName, higherIsBetter: higherIsBetter,
                      nights: nights, bins: reported, thinBins: thin,
                      verdict: verdict, typicalOnset: typical,
                      socialJetlagHours: jetlag)
    }

    /// Standard errors between two bins' means. `nil` when either bin has no
    /// spread estimate, which is treated as "cannot be told apart" by callers
    /// rather than as a separation of zero.
    static func separation(_ a: Bin, _ b: Bin) -> Double? {
        guard let sea = a.standardError, let seb = b.standardError else { return nil }
        let combined = (sea * sea + seb * seb).squareRoot()
        guard combined > 0 else { return nil }
        return abs(a.mean - b.mean) / combined
    }
}
