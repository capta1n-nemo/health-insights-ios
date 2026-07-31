import Foundation

/// One segment of sleep as a provider recorded it, stripped of any platform type.
///
/// HealthKit is the only source that hands us *segments* rather than a nightly
/// total, and `HKCategorySample` cannot cross into InsightKit. This is the
/// shape the aggregation actually needs, so the rule that decides which night a
/// segment belongs to can be tested on Linux.
public struct SleepSegment: Sendable, Equatable {

    /// The stages this app distinguishes.
    ///
    /// `awake` is carried rather than discarded because it is the difference
    /// between "no data" and "measured, and you were awake" — the in-bed
    /// denominator needs one and not the other.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case core, deep, rem, unspecified, inBed, awake

        /// Whether this stage counts toward time *asleep*.
        var isAsleep: Bool {
            switch self {
            case .core, .deep, .rem, .unspecified: return true
            case .inBed, .awake: return false
            }
        }
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    public init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// Never negative — a provider writing `end` before `start` should
    /// contribute nothing rather than subtract from the night.
    var seconds: Double { max(0, end.timeIntervalSince(start)) }
}

/// Turning a pile of sleep segments into one set of figures per **night**.
///
/// ## The defect this exists to fix
///
/// `HealthKitService.fetchSleep` keyed every nightly figure on
/// `Calendar.startOfDay(for: segment.startDate)` — the calendar day the segment
/// itself began. `SleepOnset.night(of:)`, in the same function and over the same
/// segments, already said in as many words that this is wrong:
///
/// > Grouping by calendar day is what the duration series already does and it is
/// > wrong for a *timestamp*: 23:30 on Monday and 01:00 on Tuesday are one night
/// > and two days.
///
/// It is wrong for a *duration* for exactly the same reason. A night from 23:00
/// to 07:00 is written by Apple Health as many stage segments; the ones before
/// midnight were filed under Monday and the ones after under Tuesday. So one
/// night became two, the smaller of which was a sliver — which is where the data
/// export's **0.01 h minimum sleep duration** came from, and, because efficiency
/// split its numerator and denominator independently, its **2% efficiency** too.
///
/// It also put Apple Health a day out from Oura, which stamps a night at the day
/// it *ends*. `MetricType.sleepDurationHours` aggregates by `.mean`, so a real
/// night from one source was being averaged with a sliver of a different night
/// from the other — the same "7.5 h night reported as 4 h" symptom the Oura nap
/// fix chased, from a second cause that outlived it.
///
/// ## The rule
///
/// One rule, `SleepOnset.night(of:)`, for every nightly figure — the same one
/// the onset series already uses, so the two can never disagree again.
public enum SleepNights {

    /// Local hour after which a sleep segment can no longer belong to the night
    /// that is closing, and before which it cannot belong to the one opening.
    ///
    /// This is `SleepOnset`'s own branch cut, not a new constant. A night is
    /// keyed into an 18:00→18:00 window; noon to 18:00 is the tail of that
    /// window, and sleep starting there is an afternoon nap rather than any part
    /// of the night before it. Excluding it is what stops a 3 pm nap adding its
    /// minutes to last night's total.
    static let afternoonCutoffHour = 12

    /// Nightly samples for every night these segments describe.
    ///
    /// Emits `.sleepDurationHours`, `.sleepDeepMinutes`, `.sleepRemMinutes`,
    /// `.sleepEfficiency` and `.sleepOnset`, each stamped at the night's key —
    /// the morning it ends on, matching every other overnight figure here.
    ///
    /// ### Two limitations, both deliberate, both inherited
    ///
    /// **An 8 pm nap is indistinguishable from an early bedtime.** HealthKit —
    /// unlike Oura — publishes no segment *type*. Oura's parser drops naps on
    /// `type`; there is nothing here to drop them on, and a duration-or-gap
    /// heuristic would be a guess dressed as a rule. So a lone evening nap can
    /// still register as a short night. It needs the user to nap in the evening
    /// *and* not sleep that night, which is why it is tolerable.
    ///
    /// **Sleep that starts outside ±6 h of midnight produces no night at all** —
    /// a night-shift worker sleeping at 09:00 gets nothing rather than something
    /// wrong. That is not a new judgement: it is `SleepOnset.plausibleHours`,
    /// which already made this exact trade for the bedtime series and recorded
    /// it as "the honest failure". Applying it here too is what keeps the two
    /// series agreeing about how many nights there have been; the alternative —
    /// duration counting a night that onset refuses to — is the disagreement
    /// this type exists to end. If it is ever revisited, revisit both together.
    public static func samples(from segments: [SleepSegment],
                               source: MetricSource,
                               calendar: Calendar = .current) -> [HealthMetricSample] {
        // Afternoon sleep belongs to no night. Dropped before grouping so it can
        // neither open a night nor add its minutes to one.
        let nightly = segments.filter { segment in
            let hour = calendar.component(.hour, from: segment.start)
            return hour < afternoonCutoffHour || hour >= Int(24 - SleepOnset.plausibleHours)
        }

        var byNight: [Date: [SleepSegment]] = [:]
        for segment in nightly {
            byNight[SleepOnset.night(of: segment.start, calendar: calendar), default: []]
                .append(segment)
        }

        var samples: [HealthMetricSample] = []
        for (night, group) in byNight {
            let asleep = group.filter { $0.kind.isAsleep }
            // A cluster with no plausible onset is a nap that happened to fall
            // inside the window, not a night. Same admission test the onset
            // series uses, so the two agree on what a night is by construction.
            guard let earliest = asleep.map(\.start).min(),
                  SleepOnset.hoursFromMidnight(earliest, calendar: calendar) != nil
            else { continue }

            func add(_ type: MetricType, _ value: Double) {
                samples.append(HealthMetricSample(type: type, value: value,
                                                  start: night, end: night, source: source))
            }

            let asleepSeconds = asleep.reduce(0) { $0 + $1.seconds }
            guard asleepSeconds > 0 else { continue }
            add(.sleepDurationHours, asleepSeconds / 3600)

            func minutes(_ kind: SleepSegment.Kind) -> Double? {
                let total = group.filter { $0.kind == kind }.reduce(0) { $0 + $1.seconds }
                return total > 0 ? total / 60 : nil
            }
            if let deep = minutes(.deep) { add(.sleepDeepMinutes, deep) }
            if let rem = minutes(.rem) { add(.sleepRemMinutes, rem) }

            // Efficiency needs a denominator and `inBed` is the only honest one.
            // Sources that never write an in-bed segment — most rings, which
            // infer sleep rather than bedtime — get no efficiency rather than a
            // fabricated 100%.
            //
            // Numerator and denominator now come from the *same* night, which is
            // what the old `min(100,)` clamp was really hiding: a sliver of
            // asleep over a whole night in bed reads as 2%, and the reverse
            // overflowed. The clamp stays as a guard against a provider writing
            // overlapping segments, which is a different fault and a real one.
            let inBedSeconds = group.filter { $0.kind == .inBed }.reduce(0) { $0 + $1.seconds }
            if inBedSeconds > 0 {
                add(.sleepEfficiency, Swift.min(100, asleepSeconds / inBedSeconds * 100))
            }
        }

        // The onset series, from the same segments and the same night rule.
        let onsets = SleepOnset.samples(fromSegmentStarts: nightly.filter(\.kind.isAsleep).map(\.start),
                                        source: source, calendar: calendar)
        return (samples + onsets).sorted { $0.start < $1.start }
    }
}
