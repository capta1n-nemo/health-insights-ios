import Foundation

/// The week's activity dose, scored against the WHO 2020 guideline band.
///
/// This is the first term on the Fitness card about what the reader actually
/// *does*: VO₂max level and trajectory both move over months, and every other
/// activity signal on the card is supporting-only because no published curve
/// exists for it. This one is different — WHO 2020 (Bull et al., Br J Sports
/// Med 2020) states 150–300 minutes of moderate activity per week with an
/// explicit dose–response, and Apple's "exercise minute" accrues at
/// brisk-walk intensity and above, which *is* the guideline's
/// moderate-intensity definition. A dose against a published band is a 0–100
/// by construction — the same reason the audio-exposure item ranks where it
/// does in `docs/data-opportunities.md`, where this term is item #1.
///
/// **Weekly, never daily.** The guideline is a weekly figure and deliberately
/// says nothing about how it is spread — the whole dose on two weekend days
/// counts in the trials it rests on. Scoring days would mark down exactly the
/// pattern the evidence says is fine (and it is why `.exerciseMinutes` has no
/// daily `referenceRange`).
///
/// **A missing day counts as zero, and the floor below guards that choice.**
/// HealthKit writes exercise-time samples only when minutes accrue, so "no
/// sample" is ambiguous between an unworn watch and a sedentary day. Treating
/// missing as zero is the honest reading of a mostly-worn week — the
/// alternative, scaling up from recorded days, credits a week of rest days for
/// the one day that had a workout. The `minimumRecordedDays` floor stops the
/// worst case of the zero reading: a watch worn twice in a week returns `nil`
/// (cannot judge) rather than a damning number.
public enum ActivityDoseModel {

    /// WHO 2020: the band's floor and the top of its stated range.
    public static let weeklyFloorMinutes = 150.0
    public static let weeklyTargetMinutes = 300.0

    /// Days in the trailing week that must have recorded *any* exercise time
    /// before a weekly total is offered at all.
    public static let minimumRecordedDays = 3

    public struct Output: Sendable, Equatable {
        /// Minutes of at-least-moderate activity over the trailing 7 days,
        /// missing days counted as zero.
        public let weeklyMinutes: Double
        /// Days of the seven with any recorded exercise time.
        public let recordedDays: Int
        public let score: Double
    }

    /// `nil` when the metric has no data, or too few recorded days to make
    /// missing-as-zero an honest reading.
    public static func evaluate(samples: [HealthMetricSample], now: Date,
                                calendar: Calendar = .current) -> Output? {
        let daily = VitalReader.dailyValues(.exerciseMinutes, from: samples,
                                            days: 7, now: now, calendar: calendar)
        guard daily.count >= minimumRecordedDays else { return nil }
        let weekly = daily.reduce(0, +)
        return Output(weeklyMinutes: weekly, recordedDays: daily.count,
                      score: score(weeklyMinutes: weekly))
    }

    /// Piecewise linear through the guideline's own anchors, monotone by
    /// construction.
    ///
    /// A sedentary week floors at 20 rather than 0 — the same convention every
    /// other term in this app uses (sleep's duration term floors at 30, its
    /// oxygen term at 35), so one bad week cannot single-handedly crater a
    /// composite. Meeting the band's floor is a solid 75; the top of the band
    /// is 100; past it the score holds rather than climbs, because WHO states
    /// additional benefit above 300 minutes but no longer quantifies it — a
    /// slope up there would be drawn from nothing.
    public static func score(weeklyMinutes: Double) -> Double {
        let m = Swift.max(0, weeklyMinutes)
        switch m {
        case ..<weeklyFloorMinutes:
            return 20 + (m / weeklyFloorMinutes) * 55
        case ..<weeklyTargetMinutes:
            return 75 + (m - weeklyFloorMinutes)
                / (weeklyTargetMinutes - weeklyFloorMinutes) * 25
        default:
            return 100
        }
    }

    /// The sentence beside the number: where this week sits against the band.
    public static func phrase(_ output: Output) -> String {
        let minutes = Int(output.weeklyMinutes.rounded())
        switch output.weeklyMinutes {
        case ..<weeklyFloorMinutes:
            return "\(minutes) min of exercise this week — the guideline band starts at \(Int(weeklyFloorMinutes))"
        case ..<weeklyTargetMinutes:
            return "\(minutes) min of exercise this week — inside the \(Int(weeklyFloorMinutes))–\(Int(weeklyTargetMinutes)) min guideline band"
        default:
            return "\(minutes) min of exercise this week — past the top of the \(Int(weeklyFloorMinutes))–\(Int(weeklyTargetMinutes)) min guideline band"
        }
    }
}
