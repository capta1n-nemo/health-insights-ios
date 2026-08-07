import Foundation

/// **Screen time on a day, against the night that followed it.**
///
/// Backlog B18-2, the reader's ask: screen time deserves its own section rather
/// than a driver row inside the sleep-onset deep-dive. `SleepOnsetModel` already
/// reads screen time as one of five factors moving *latency*; this asks the
/// wider question — what did the evening's screen use go with, across the whole
/// night: how long it lasted, how long it took to start, and how much of the
/// time in bed was actually slept.
///
/// ## The honest problem, stated first
///
/// **There are twenty-six days of it.** Apple sandboxes Screen Time so no app
/// can read it (see `MetricType.screenTimeMinutes`); every one of those days was
/// typed in or read off a screenshot the reader supplied. That is a real number
/// of days and it is a small one, so this type does two things about it rather
/// than one:
///
/// - It carries a `CoverageGate` so the section can say *how many more* — the
///   number that makes somebody carry on, and the thing this app was failing to
///   say everywhere a figure was withheld.
/// - It **refuses the contrast** below the floor rather than reporting a weak
///   one. A median split over six pairs is arithmetic, not evidence, and a
///   sentence built from it would read exactly like a sentence built from sixty.
///
/// ## Why a median split and not a correlation
///
/// The same reason `SleepOnsetModel` and `SubstanceResponseAnalyzer` use one: a
/// Pearson r assumes the relationship is a straight line, and this one plainly
/// is not — the difference between two hours and four is not the difference
/// between eight and ten. Splitting the reader's own days at their own middle
/// and contrasting the two halves makes no shape assumption at all, and the
/// figure it produces ("about forty minutes less sleep on your heavier half") is
/// one a person can actually picture.
///
/// **It is an association and never a cause**, and the sentence says so. A
/// heavy-screen evening is also a late evening, a stressful one and often a
/// drinking one; nothing here can separate those and nothing here pretends to.
public struct ScreenTimeSleepLink: Sendable, Equatable {

    /// The fewest day/night pairs that can carry a contrast.
    ///
    /// Fourteen: a full fortnight, and enough that each half of the split is a
    /// week rather than a handful. Deliberately above `SleepOnsetModel`'s ten,
    /// because that model contrasts one factor against a latency it has hundreds
    /// of nights of, and this one has only the days the reader typed.
    public static let minimumPairs = 14

    /// One day's screen time and the night that followed it.
    public struct Pair: Sendable, Equatable, Identifiable {
        /// The wake day the night is keyed to — `SleepOnset.night(of:)`'s key,
        /// so this is the morning *after* the screen time was clocked up.
        public let night: Date
        /// The day the screen time was recorded on, i.e. the evening before.
        public let day: Date
        public let screenMinutes: Double
        public let sleepHours: Double?
        public let latencyMinutes: Double?
        public let efficiency: Double?

        public var id: Date { night }

        public init(night: Date, day: Date, screenMinutes: Double,
                    sleepHours: Double?, latencyMinutes: Double?, efficiency: Double?) {
            self.night = night
            self.day = day
            self.screenMinutes = screenMinutes
            self.sleepHours = sleepHours
            self.latencyMinutes = latencyMinutes
            self.efficiency = efficiency
        }
    }

    /// What the night measured, for the split.
    public enum Outcome: String, Sendable, CaseIterable, Identifiable {
        case sleepHours, latencyMinutes, efficiency
        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .sleepHours: return "How long you slept"
            case .latencyMinutes: return "How long you took to fall asleep"
            case .efficiency: return "How much of the time in bed you slept"
            }
        }

        /// Written so a difference can be read straight into a sentence.
        var unit: String {
            switch self {
            case .sleepHours: return "h"
            case .latencyMinutes: return "min"
            case .efficiency: return "%"
            }
        }

        /// Whether more of this is the better night. Used only for wording — the
        /// figure is reported whichever way it points.
        var higherIsBetter: Bool {
            switch self {
            case .sleepHours, .efficiency: return true
            case .latencyMinutes: return false
            }
        }

        func value(of pair: Pair) -> Double? {
            switch self {
            case .sleepHours: return pair.sleepHours
            case .latencyMinutes: return pair.latencyMinutes
            case .efficiency: return pair.efficiency
            }
        }
    }

    /// One outcome, contrasted across the reader's own median split.
    public struct Contrast: Sendable, Equatable, Identifiable {
        public let outcome: Outcome
        /// Mean of the outcome on the heavier-screen half.
        public let heavier: Double
        /// Mean on the lighter half.
        public let lighter: Double
        /// Screen minutes the split fell at.
        public let splitMinutes: Double
        public let heavierNights: Int
        public let lighterNights: Int

        public var id: String { outcome.rawValue }
        public var difference: Double { heavier - lighter }

        public init(outcome: Outcome, heavier: Double, lighter: Double,
                    splitMinutes: Double, heavierNights: Int, lighterNights: Int) {
            self.outcome = outcome
            self.heavier = heavier
            self.lighter = lighter
            self.splitMinutes = splitMinutes
            self.heavierNights = heavierNights
            self.lighterNights = lighterNights
        }

        /// The sentence, which never says "because".
        public var sentence: String {
            let magnitude = abs(difference)
            guard magnitude >= outcome.threshold else {
                return "\(outcome.displayName.lowercased()) came out about the same "
                    + "on both halves — nothing to see here, which is the ordinary "
                    + "answer."
            }
            let worse = outcome.higherIsBetter ? difference < 0 : difference > 0
            return String(format: "On your heavier half — above %.0f min of screen "
                          + "time — %@ ran %@%@ %@. That is what went with it, not "
                          + "what caused it.",
                          splitMinutes, outcome.displayName.lowercased(),
                          Self.formatted(magnitude, outcome), outcome.unit,
                          worse ? "worse" : "better")
        }

        static func formatted(_ value: Double, _ outcome: Outcome) -> String {
            switch outcome {
            case .sleepHours: return String(format: "%.1f ", value)
            default: return String(format: "%.0f ", value)
            }
        }
    }

    public let pairs: [Pair]
    public let contrasts: [Contrast]
    /// How far the reader is from a contrast at all, and `nil` once they are
    /// past it.
    public let coverage: CoverageGate?

    public init(pairs: [Pair], contrasts: [Contrast], coverage: CoverageGate?) {
        self.pairs = pairs
        self.contrasts = contrasts
        self.coverage = coverage
    }

    /// How many days of screen time have been supplied at all — including the
    /// ones with no night beside them, because that is the number the reader
    /// recognises as "days I've entered".
    public var daysSupplied: Int { Set(pairs.map(\.day)).count }

    // MARK: - Building

    /// Pair every day of screen time with the night that followed it.
    ///
    /// The keying is the whole correctness question here, and it is the one thing
    /// a reader could never check: screen time is stamped on the **day it was
    /// clocked up**, and the night that follows is keyed to the **next morning**
    /// (`SleepOnset.night(of:)`). Pairing day D with night D would hold an
    /// evening's phone use against the sleep that happened *before* it.
    public static func build(samples: [HealthMetricSample],
                             calendar: Calendar = .current) -> ScreenTimeSleepLink {
        let screen = samples.samples(of: .screenTimeMinutes)
        // One value per day. `ScreenTimePrecedence` decides which source wins
        // upstream; here the last reading of a day is taken, which is the later
        // correction on a day the reader entered twice.
        var byDay: [Date: Double] = [:]
        for sample in screen {
            byDay[calendar.startOfDay(for: sample.start)] = sample.value
        }

        func nightly(_ type: MetricType) -> [Date: Double] {
            var out: [Date: Double] = [:]
            for sample in samples.samples(of: type) {
                out[calendar.startOfDay(for: sample.start)] = sample.value
            }
            return out
        }
        let duration = nightly(.sleepDurationHours)
        let latency = nightly(.sleepLatencyMinutes)
        let efficiency = nightly(.sleepEfficiency)

        var pairs: [Pair] = []
        for (day, minutes) in byDay {
            guard let night = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let hours = duration[night]
            let onset = latency[night]
            let efficient = efficiency[night]
            // A day with screen time and no night at all is not a pair; it is a
            // day the ring was on charge. Dropping it here rather than carrying
            // an all-nil row keeps `pairs.count` meaning "days I can compare".
            guard hours != nil || onset != nil || efficient != nil else { continue }
            pairs.append(Pair(night: night, day: day, screenMinutes: minutes,
                              sleepHours: hours, latencyMinutes: onset,
                              efficiency: efficient))
        }
        pairs.sort { $0.night < $1.night }

        let coverage = CoverageGate.ifShort(
            need: minimumPairs, have: pairs.count,
            unit: "day of screen time with a night beside it",
            unlocks: "this can contrast your heavier evenings against your lighter ones")

        return ScreenTimeSleepLink(pairs: pairs,
                                   contrasts: coverage == nil ? split(pairs) : [],
                                   coverage: coverage)
    }

    /// The median split, per outcome.
    ///
    /// An outcome is skipped where either half is thinner than a third of the
    /// pairs — a "contrast" resting on two nights on one side is a pair of nights
    /// with a mean drawn over them.
    static func split(_ pairs: [Pair]) -> [Contrast] {
        guard let middle = Baseline.median(pairs.map(\.screenMinutes)) else { return [] }
        var out: [Contrast] = []
        for outcome in Outcome.allCases {
            let usable = pairs.filter { outcome.value(of: $0) != nil }
            guard usable.count >= minimumPairs else { continue }
            let heavier = usable.filter { $0.screenMinutes > middle }.compactMap(outcome.value)
            let lighter = usable.filter { $0.screenMinutes <= middle }.compactMap(outcome.value)
            let floor = Swift.max(3, usable.count / 3)
            guard heavier.count >= floor, lighter.count >= floor,
                  let heavyMean = Baseline.mean(heavier),
                  let lightMean = Baseline.mean(lighter) else { continue }
            out.append(Contrast(outcome: outcome, heavier: heavyMean, lighter: lightMean,
                                splitMinutes: middle,
                                heavierNights: heavier.count, lighterNights: lighter.count))
        }
        return out
    }
}

extension ScreenTimeSleepLink.Outcome {
    /// The smallest difference worth calling a difference.
    ///
    /// Not a significance test — a mean over a fortnight cannot support one —
    /// but a floor below which the two halves are the same to anybody living
    /// them. A tenth of an hour of sleep is four minutes.
    var threshold: Double {
        switch self {
        case .sleepHours: return 0.25
        case .latencyMinutes: return 4
        case .efficiency: return 2
        }
    }
}
