import Foundation

/// How the heart responds — to a hard effort, and to the last few weeks.
///
/// ## Why this card needed something that is not a risk score
///
/// Everything else this app says about the heart is calibrated on middle age.
/// SCORE2 is validated 40–69 and ASCVD 40–79, so `HeartAgeModel` and the risk
/// card genuinely say **nothing** to a 25-year-old — and the honest response to
/// that is not to extrapolate an equation past its band, it is to report the
/// heart signals that mean something at every age.
///
/// Three do, and they are also the three that people who track their heart
/// actually look at:
///
/// - **Heart rate recovery.** How far the rate falls in the first minute after
///   a hard effort. Cole et al. (NEJM 1999) found a fall of **12 bpm or less**
///   marked a doubling of six-year mortality in 2 428 adults, independent of
///   coronary disease severity; a later meta-analysis of nine cohorts put the
///   general-population hazard at ~1.7× for cardiovascular events and all-cause
///   death. It is the rare cardiac marker whose threshold is a fixed number of
///   beats rather than a curve through age, which is exactly what makes it
///   sayable to a 25-year-old and a 65-year-old in the same words.
/// - **Resting heart rate** and **heart-rate variability**, together. Both are
///   read off the same beat-to-beat stream and they move in opposite directions
///   when the autonomic balance shifts, so a rising resting rate *with* falling
///   variability is a different statement from either alone — and it is the
///   pair that day-to-day training and illness move first.
///
/// ## What this deliberately does not do
///
/// It does not score. There is no validated 0–100 curve for heart rate recovery
/// and inventing one to sit beside a number the reader is asked to trust is the
/// thing this codebase refuses everywhere else (`dayStrain` is charted at weight
/// zero for the same reason). This reports three measurements, one published
/// threshold, and the direction each has moved.
public enum HeartResponseModel {

    /// A fall of this many beats or fewer in the first minute is the published
    /// abnormal cut-point. Cole et al., *NEJM* 1999;341:1351–7.
    public static let attenuatedRecovery = 12.0

    /// Roughly the population average on consumer wrist devices. Not a
    /// threshold and not published as a norm — it is the line above which a
    /// recovery is unremarkable rather than merely adequate, and it is quoted
    /// as an "around" figure everywhere it is shown.
    public static let typicalRecovery = 26.0

    /// How long a recovery reading stays worth reporting. Longer than the
    /// vitals window: this one only exists on days with a hard effort, and
    /// demanding one from the last week would blank the section for anybody who
    /// trains twice a month.
    public static let recoveryFreshness: TimeInterval = 45 * 86_400

    public enum RecoveryBand: String, Sendable, Equatable, CaseIterable {
        /// At or below the published cut-point.
        case attenuated
        /// Above the cut-point, below the typical consumer figure.
        case adequate
        /// At or above the typical figure.
        case strong

        public static func of(_ bpm: Double) -> RecoveryBand {
            if bpm <= attenuatedRecovery { return .attenuated }
            return bpm >= typicalRecovery ? .strong : .adequate
        }

        /// Deliberately not "good"/"bad". The cut-point is a population hazard
        /// ratio, not a diagnosis, and one reading below it on one workout is
        /// not a finding about a person.
        public var phrase: String {
            switch self {
            case .attenuated: return "below the usual mark"
            case .adequate: return "in the usual range"
            case .strong: return "a strong drop"
            }
        }
    }

    /// One signal, its latest value and how it has moved.
    public struct Signal: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let value: Double
        /// Change per week over the window, in the metric's own units. `nil`
        /// when there are too few readings to fit a line through.
        public let perWeek: Double?
        public let higherIsBetter: Bool

        public var id: MetricType { metric }

        /// Whether the direction it is moving is the wanted one. `nil` where it
        /// is not moving enough to call — the same floor the legend uses, so
        /// the two cannot disagree about whether something is drifting.
        public var isImproving: Bool? {
            guard let perWeek, abs(perWeek) >= movementFloor(for: metric) else { return nil }
            return (perWeek > 0) == higherIsBetter
        }

        public init(metric: MetricType, value: Double, perWeek: Double?,
                    higherIsBetter: Bool) {
            self.metric = metric
            self.value = value
            self.perWeek = perWeek
            self.higherIsBetter = higherIsBetter
        }
    }

    /// The smallest weekly change worth calling a direction, in each metric's
    /// own units. A tenth of a beat a week is arithmetic, not a trend, and the
    /// device cannot resolve it — the same reasoning as the 3% floor on
    /// substance response and the ±5 mmHg floor on blood-pressure drift.
    static func movementFloor(for metric: MetricType) -> Double {
        switch metric {
        case .restingHeartRate: return 0.3        // bpm/week
        case .heartRateVariabilityRMSSD: return 0.5   // ms/week
        default: return 0.1
        }
    }

    public struct Output: Sendable, Equatable {
        /// Beats dropped in the first minute after the last hard effort.
        public let recovery: Double?
        public let recoveryBand: RecoveryBand?
        /// Resting heart rate and rMSSD, in that order, where each has a
        /// reading. The pair is the point — see the type's own note.
        public let autonomic: [Signal]

        public var isEmpty: Bool { recovery == nil && autonomic.isEmpty }

        public init(recovery: Double?, recoveryBand: RecoveryBand?,
                    autonomic: [Signal]) {
            self.recovery = recovery
            self.recoveryBand = recoveryBand
            self.autonomic = autonomic
        }

        /// The one-line reading of the pair, which is the part neither signal
        /// can say alone.
        ///
        /// Both drifting the wrong way at once is the only combination worth
        /// naming: rate and variability come off the same beat-to-beat stream
        /// and move together under load, so agreement is evidence in a way
        /// either one alone is not. Everything else gets no sentence rather
        /// than a hedged one.
        public var autonomicSentence: String? {
            guard autonomic.count == 2 else { return nil }
            let verdicts = autonomic.compactMap(\.isImproving)
            guard verdicts.count == 2 else { return nil }
            if verdicts.allSatisfy({ $0 == false }) {
                return "Your resting rate is drifting up while your variability "
                    + "drifts down. They come off the same signal and usually move "
                    + "together like this under training load, poor sleep or "
                    + "illness — worth watching rather than acting on."
            }
            if verdicts.allSatisfy({ $0 }) {
                return "Your resting rate is falling while your variability rises. "
                    + "That is the pair moving the way it does when recovery is "
                    + "going well."
            }
            return nil
        }
    }

    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date(),
                                windowDays: Int = 90,
                                calendar: Calendar = .current) -> Output {
        // `.none`: `.value` and nothing else — the trailing `?.value` is the
        // whole use, so the baseline this would have shifted is never read.
        let recovery = VitalReader.reading(.heartRateRecovery, from: samples, now: now,
                                           freshWithin: recoveryFreshness,
                                           gap: .none, calendar: calendar)?.value

        func signal(_ metric: MetricType, higherIsBetter: Bool) -> Signal? {
            let series = VitalReader.dailySeries(metric, from: samples, days: windowDays,
                                                 now: now, calendar: calendar)
            guard let latest = series.last else { return nil }
            var perWeek: Double?
            if series.count >= 4, let first = series.first?.date {
                let x = series.map { $0.date.timeIntervalSince(first) / 86_400 }
                perWeek = Baseline.linearRegression(x: x, y: series.map(\.value))
                    .map { $0.slope * 7 }
            }
            return Signal(metric: metric, value: latest.value, perWeek: perWeek,
                          higherIsBetter: higherIsBetter)
        }

        let autonomic = [
            signal(.restingHeartRate, higherIsBetter: false),
            signal(.heartRateVariabilityRMSSD, higherIsBetter: true)
        ].compactMap { $0 }

        return Output(recovery: recovery,
                      recoveryBand: recovery.map(RecoveryBand.of),
                      autonomic: autonomic)
    }
}
