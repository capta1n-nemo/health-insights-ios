import Foundation

/// **How hard you were working, not how long** — the week's activity read
/// through Apple's `physicalEffort` rather than its exercise minute.
///
/// Backlog §B5 #34, and the reader's own reversal of a refusal. The refusal was
/// right about the data and wrong about the conclusion: 81,252 rows *is* a trap,
/// because they are ten-second samples and land on only 14 of the last 90 days.
/// What follows from that is a coverage gate, not a permanent no.
///
/// ## Why this is one term with `ActivityDoseModel`, not a second one
///
/// Both answer "did you meet the guideline this week", so scoring both would
/// count one afternoon's walking twice. They differ in what they can see:
/// Apple's exercise minute is a *count* of minutes at brisk-walk intensity and
/// above, and physical effort is those same minutes **with the intensity
/// attached**. WHO 2020 states an explicit substitution — one vigorous minute
/// for two moderate ones — and only the intensity-carrying input can apply it.
///
/// So this supersedes the exercise-minute dose whenever the week has enough
/// effort data, and falls back to it when it does not. **The score curve is
/// literally `ActivityDoseModel.score`**, not a copy of it, so the two routes
/// cannot drift apart about what 200 minutes is worth.
///
/// ## What the bands are
///
/// The Compendium of Physical Activities (Ainsworth et al., 2011) fixes them:
/// under 3 METs is light, 3–6 is moderate, 6 and above is vigorous. These are
/// the same edges WHO's guideline is written in terms of, which is what lets a
/// MET reading be scored against it at all. `MetricType.physicalEffort` is in
/// kcal/hr·kg, which *is* the MET — no conversion happens anywhere.
///
/// ## Measured on the reader's own record before any of this was written
///
/// 2026-08-06, against their export: samples are a median **10 seconds** long,
/// a worn day records a median **899 minutes** (p10 301, p90 1,362), and the
/// last twelve weeks hold 7, 4, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0 recorded days.
/// Two decisions come straight out of that:
///
/// 1. ⚠️ **Vigorous minutes alone would have been a wrong answer.** Their best
///    week is 26 vigorous minutes against WHO's 75-minute floor — a poor score
///    — while the same week holds 392 moderate minutes, which is *past the top*
///    of the moderate band. A reader who exceeds the guideline by walking would
///    have been told they were unfit. The substitution rule is what stops that.
/// 2. **A partly-worn day is not scaled up.** A day recording 301 minutes and
///    one recording 1,362 both count as one recorded day, and the total is
///    whatever was measured. Scaling would credit activity nobody observed,
///    which is the trap `ActivityDoseModel` already names for missing days.
///    `wornMinutes` is reported instead, so the reader can see it.
public enum EffortIntensityModel {

    // MARK: Band edges — Compendium of Physical Activities

    public static let moderateFloorMETs = 3.0
    public static let vigorousFloorMETs = 6.0

    /// WHO 2020's own substitution rate: 75–150 min of vigorous activity is
    /// stated as equivalent to 150–300 min of moderate.
    public static let vigorousEquivalence = 2.0

    /// Days of the trailing seven that must carry effort data before a weekly
    /// total is offered. Shared with `ActivityDoseModel` deliberately: it is
    /// the same judgement about the same window, and two different floors would
    /// mean the card silently changed its mind about what "enough" is depending
    /// on which input it happened to use.
    public static var minimumRecordedDays: Int { ActivityDoseModel.minimumRecordedDays }

    public struct Output: Sendable, Equatable {
        /// Minutes under 3 METs — desk work, standing, pottering.
        public let lightMinutes: Double
        /// Minutes at 3–6 METs.
        public let moderateMinutes: Double
        /// Minutes at 6 METs and above.
        public let vigorousMinutes: Double
        /// `moderate + 2 × vigorous`, the form WHO's band is stated in.
        public let moderateEquivalentMinutes: Double
        /// MET-minutes of moderate-to-vigorous activity — the currency the
        /// epidemiology is usually reported in. Charted, never scored: WHO
        /// states its band in minutes, and converting the band would invent a
        /// precision the guideline does not have.
        public let metMinutes: Double
        /// The hardest single sample of the week.
        public let peakMETs: Double
        /// Days of the seven carrying any effort sample at all.
        public let recordedDays: Int
        /// Minutes of the week the watch actually recorded. The honest
        /// denominator behind every figure above.
        public let wornMinutes: Double
        public let score: Double

        /// Share of measured active time spent at vigorous intensity. `nil`
        /// when there was no active time to take a share of — which is a
        /// different statement from 0%, and the card says so.
        public var vigorousShare: Double? {
            let active = moderateMinutes + vigorousMinutes
            guard active > 0 else { return nil }
            return vigorousMinutes / active
        }
    }

    /// `nil` when the week has fewer than `minimumRecordedDays` of effort data.
    ///
    /// Returning nothing is the point of this function. The alternative — a
    /// weekly figure built from one worn day — reads as "you did almost
    /// nothing this week" when what happened is that the watch was in a drawer,
    /// and on this reader's record that would be the answer for eight weeks in
    /// twelve.
    public static func evaluate(samples: [HealthMetricSample], now: Date,
                                calendar: Calendar = .current) -> Output? {
        let window = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let effort = samples.samples(of: .physicalEffort)
            .filter { $0.start >= window && $0.start <= now }
        guard !effort.isEmpty else { return nil }

        let days = Set(effort.map { calendar.startOfDay(for: $0.start) })
        guard days.count >= minimumRecordedDays else { return nil }

        var light = 0.0, moderate = 0.0, vigorous = 0.0, metMinutes = 0.0
        var peak = 0.0
        for sample in effort {
            // A sample written with no interval is a point reading, not a
            // duration. Apple does write these; counting one as a minute of
            // anything would be inventing time.
            let minutes = sample.end.timeIntervalSince(sample.start) / 60
            peak = Swift.max(peak, sample.value)
            guard minutes > 0 else { continue }
            switch sample.value {
            case ..<moderateFloorMETs:
                light += minutes
            case ..<vigorousFloorMETs:
                moderate += minutes
                metMinutes += sample.value * minutes
            default:
                vigorous += minutes
                metMinutes += sample.value * minutes
            }
        }

        let equivalent = moderate + vigorousEquivalence * vigorous
        return Output(
            lightMinutes: light, moderateMinutes: moderate,
            vigorousMinutes: vigorous, moderateEquivalentMinutes: equivalent,
            metMinutes: metMinutes, peakMETs: peak,
            recordedDays: days.count, wornMinutes: light + moderate + vigorous,
            score: ActivityDoseModel.score(weeklyMinutes: equivalent))
    }

    /// The sentence beside the number.
    ///
    /// It names the *intensity* split rather than restating the total, because
    /// the total is what the dose line already says and the split is the only
    /// thing this input can tell the reader that the exercise minute cannot.
    public static func phrase(_ output: Output) -> String {
        let moderate = Int(output.moderateMinutes.rounded())
        let vigorous = Int(output.vigorousMinutes.rounded())
        let band = ActivityDoseModel.weeklyFloorMinutes
        let equivalent = Int(output.moderateEquivalentMinutes.rounded())
        let verdict: String
        switch output.moderateEquivalentMinutes {
        case ..<band:
            verdict = "the guideline band starts at \(Int(band))"
        case ..<ActivityDoseModel.weeklyTargetMinutes:
            verdict = "inside the \(Int(band))–\(Int(ActivityDoseModel.weeklyTargetMinutes)) min guideline band"
        default:
            verdict = "past the top of the \(Int(band))–\(Int(ActivityDoseModel.weeklyTargetMinutes)) min guideline band"
        }
        if vigorous == 0 {
            return "\(moderate) min of moderate effort this week and none vigorous — \(verdict)"
        }
        return "\(moderate) min moderate and \(vigorous) min vigorous this week — \(equivalent) moderate-equivalent minutes, \(verdict)"
    }

    /// What the week's coverage was, said plainly. Always shown beside the
    /// figure: on this reader's record the honest caveat is bigger news than
    /// the number, and a weekly total from four worn days is not the same claim
    /// as one from seven.
    public static func coveragePhrase(_ output: Output) -> String {
        let hours = Int((output.wornMinutes / 60).rounded())
        return "From \(output.recordedDays) of the last 7 days — about \(hours) \(SectionCaveat.plural(hours, "hour")) of recorded wear. Days the watch was off count as nothing rather than being scaled up."
    }

    /// Which band a MET reading falls in, for the chart and the rows.
    public enum Band: String, Sendable, CaseIterable {
        case light = "Light"
        case moderate = "Moderate"
        case vigorous = "Vigorous"

        public static func of(_ mets: Double) -> Band {
            switch mets {
            case ..<moderateFloorMETs: return .light
            case ..<vigorousFloorMETs: return .moderate
            default: return .vigorous
            }
        }

        /// What the band means in things a reader has done, rather than in
        /// METs. The numbers are the Compendium's own examples.
        public var example: String {
            switch self {
            case .light: return "under 3 METs — sitting, standing, pottering"
            case .moderate: return "3–6 METs — walking briskly, stairs, housework"
            case .vigorous: return "6 METs and up — running, hills, hard cycling"
            }
        }
    }

    /// One day's split, for the section's chart.
    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        public let lightMinutes: Double
        public let moderateMinutes: Double
        public let vigorousMinutes: Double
        public var id: Date { date }

        public func minutes(in band: Band) -> Double {
            switch band {
            case .light: return lightMinutes
            case .moderate: return moderateMinutes
            case .vigorous: return vigorousMinutes
            }
        }
    }

    /// **Backlog §B5 #35 — steps, distance and flights, as one week's figures.**
    ///
    /// A separate type would have been a card, which is exactly what the reader
    /// said these are not. They live here because they answer the other half of
    /// the same question: this model says how *hard*, and these three say how
    /// *much*. `total` is the honest figure for a cumulative metric and
    /// `recordedDays` is what qualifies it — 40 km over seven days and 40 km
    /// over two are different weeks.
    public struct MovementTotal: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let total: Double
        public let recordedDays: Int
        public var id: MetricType { metric }

        /// Per recorded day, not per calendar day. Dividing by seven when the
        /// phone was off for three of them reports an average nobody lived.
        public var perRecordedDay: Double? {
            recordedDays > 0 ? total / Double(recordedDays) : nil
        }
    }

    /// The three cumulative movement figures for the trailing week, in the
    /// order the reader thinks about them. A metric with nothing recorded is
    /// **absent** rather than zero, on the whole file's rule: a zero and an
    /// unworn device are different claims.
    public static let movementMetrics: [MetricType] =
        [.stepCount, .distanceWalkingRunning, .flightsClimbed]

    public static func movement(samples: [HealthMetricSample], days: Int = 7,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> [MovementTotal] {
        movementMetrics.compactMap { metric in
            let daily = VitalReader.dailyValues(metric, from: samples, days: days,
                                                now: now, calendar: calendar)
            guard !daily.isEmpty else { return nil }
            return MovementTotal(metric: metric, total: daily.reduce(0, +),
                                 recordedDays: daily.count)
        }
    }

    /// The last `days` days, one entry per day that recorded anything.
    ///
    /// Days with no data are **absent rather than zero**, for the reason the
    /// whole model is gated: a zero bar and an unworn watch look identical on a
    /// chart, and only one of them is a rest day.
    public static func dailySplit(samples: [HealthMetricSample], days: Int,
                                  now: Date, calendar: Calendar = .current) -> [Day] {
        let window = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        let effort = samples.samples(of: .physicalEffort)
            .filter { $0.start >= window && $0.start <= now }
        var byDay: [Date: (Double, Double, Double)] = [:]
        for sample in effort {
            let minutes = sample.end.timeIntervalSince(sample.start) / 60
            guard minutes > 0 else { continue }
            let day = calendar.startOfDay(for: sample.start)
            var entry = byDay[day] ?? (0, 0, 0)
            switch Band.of(sample.value) {
            case .light: entry.0 += minutes
            case .moderate: entry.1 += minutes
            case .vigorous: entry.2 += minutes
            }
            byDay[day] = entry
        }
        return byDay
            .map { Day(date: $0.key, lightMinutes: $0.value.0,
                       moderateMinutes: $0.value.1, vigorousMinutes: $0.value.2) }
            .sorted { $0.date < $1.date }
    }
}
