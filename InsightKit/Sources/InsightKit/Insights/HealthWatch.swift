import Foundation

/// Whether several signals are moving together in the way a body does a day or
/// two before you notice anything.
///
/// This is the feature people screenshot. "My ring told me I was getting sick
/// before I felt it" is the single most repeated story in wearable communities,
/// and it is repeated because it is the only moment these devices tell you
/// something you could not have worked out yourself.
///
/// ## Why this is not Vitals Check again
///
/// Vitals Check asks "is any one signal unusual today". This asks the different
/// and harder question: **are several signals leaning the same way at once**. The
/// distinction matters because that is the actual shape of an immune response —
/// resting heart rate up, HRV down, skin temperature up, breathing faster, oxygen
/// saturation down — each one individually within the noise, and all five
/// together not remotely a coincidence.
///
/// ## The baseline excludes the window it is judging
///
/// This is the part that makes it work, and it came out of a real defect. The
/// golden-dataset fixture showed that a *sustained* departure hides in its own
/// rolling baseline: by the fourth day of a fever, three of those nights are
/// inside the 28-day window the fourth is compared against, so the mean lifts,
/// the spread inflates, and the z-score sinks back under the threshold exactly
/// when the person is most unwell.
///
/// So the reference period here stops well before the recent window starts. The
/// last few days are judged against a fortnight that ended before they began, and
/// a run that has been going for a week is *more* visible rather than less.
public enum HealthWatchModel {

    /// How many recent days are treated as "now".
    public static let recentDays = 3
    /// The gap between the recent window and the reference period. Without it,
    /// yesterday would help set the baseline that judges today.
    public static let referenceGapDays = 4
    /// How long the reference period runs.
    public static let referenceDays = 21
    /// Daily values a signal needs in the reference period before it can vote.
    public static let minimumReferenceDays = 7
    /// How far a signal must move before it counts as leaning at all.
    public static let leaningZ = 1.0
    /// And how far before it is leaning hard.
    public static let strongZ = 2.0

    /// One signal's verdict.
    public struct Signal: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let recent: Double
        public let reference: Double
        public let zScore: Double
        /// True when the movement is in the direction illness pushes it.
        public let isConcerning: Bool
        public var id: MetricType { metric }

        public var isLeaning: Bool {
            isConcerning && abs(zScore) >= HealthWatchModel.leaningZ
        }
    }

    public struct Output: Sendable, Equatable {
        public let signals: [Signal]
        /// 0–100, higher is better — nothing stirring.
        public let score: Double
        public var leaning: [Signal] { signals.filter(\.isLeaning) }
    }

    /// The direction illness pushes each signal, and how much weight its vote
    /// carries.
    ///
    /// Weights are not equal because the signals are not equally specific.
    /// Skin temperature rising is close to a thermometer; a slightly lower
    /// oxygen saturation happens for a dozen ordinary reasons.
    static let watched: [(metric: MetricType, risingIsConcerning: Bool, weight: Double)] = [
        (.skinTemperatureDeviation, true, 1.0),
        (.skinTemperature, true, 1.0),
        (.restingHeartRate, true, 0.9),
        (.heartRateVariabilityRMSSD, false, 0.9),
        (.heartRateVariabilitySDNN, false, 0.8),
        (.respiratoryRate, true, 0.8),
        (.oxygenSaturation, false, 0.5)
    ]

    public static func evaluate(samples: [HealthMetricSample], now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        var signals: [Signal] = []
        for entry in watched {
            if let signal = signal(for: entry, samples: samples, now: now, calendar: calendar) {
                signals.append(signal)
            }
        }
        // The two HRV metrics and the two thermal ones are each one signal
        // reported two ways; letting both vote would double-weight them.
        signals = collapsingDuplicates(signals)
        guard signals.count >= 2 else { return nil }
        return Output(signals: signals, score: score(signals))
    }

    static func signal(for entry: (metric: MetricType, risingIsConcerning: Bool, weight: Double),
                       samples: [HealthMetricSample], now: Date,
                       calendar: Calendar) -> Signal? {
        let daily = VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                            calendar: calendar)
        guard !daily.isEmpty else { return nil }

        let recentStart = now.addingTimeInterval(-Double(recentDays) * 86_400)
        let referenceEnd = now.addingTimeInterval(-Double(referenceGapDays) * 86_400)
        let referenceStart = referenceEnd.addingTimeInterval(-Double(referenceDays) * 86_400)

        let recentValues = daily.filter { $0.date >= recentStart }.map(\.value)
        let referenceValues = daily
            .filter { $0.date >= referenceStart && $0.date < referenceEnd }
            .map(\.value)

        guard !recentValues.isEmpty,
              referenceValues.count >= minimumReferenceDays,
              let recent = Baseline.mean(recentValues),
              let reference = Baseline.mean(referenceValues),
              let spread = Baseline.standardDeviation(referenceValues), spread > 0
        else { return nil }

        let z = (recent - reference) / spread
        let concerning = entry.risingIsConcerning ? z > 0 : z < 0
        return Signal(metric: entry.metric, recent: recent, reference: reference,
                      zScore: z, isConcerning: concerning)
    }

    /// One signal, one vote. Where a person has both HRV metrics or both thermal
    /// ones, keep whichever is leaning hardest.
    static func collapsingDuplicates(_ signals: [Signal]) -> [Signal] {
        var out: [Signal] = []
        for signal in signals {
            if let index = out.firstIndex(where: {
                $0.metric.sharesMeasurementBasis(with: signal.metric)
            }) {
                if abs(signal.zScore) > abs(out[index].zScore) { out[index] = signal }
            } else {
                out.append(signal)
            }
        }
        return out
    }

    /// 0–100, higher is better.
    ///
    /// Deliberately *not* worst-offender-dominant, which is the rule everywhere
    /// else in this app. One signal off is an ordinary Tuesday — the whole point
    /// here is agreement, so the votes accumulate and a single outlier barely
    /// registers. Four signals at z = 1.2 should worry you considerably more than
    /// one at z = 3.
    static func score(_ signals: [Signal]) -> Double {
        let concern = signals.reduce(0.0) { total, signal in
            guard signal.isLeaning else { return total }
            guard let weight = watched.first(where: { $0.metric == signal.metric })?.weight
            else { return total }
            // Full weight at `strongZ`, and nothing below `leaningZ`.
            let magnitude = Swift.min(1, (abs(signal.zScore) - leaningZ) / (strongZ - leaningZ))
            return total + weight * magnitude
        }
        // Two signals fully leaning is already a strong finding.
        return Swift.max(0, Swift.min(100, 100 - concern / 2 * 100))
    }
}

/// The Today card.
public struct HealthWatchInsight: InsightModel {
    public let id: InsightID = .healthWatch
    public let title = "Health Watch"
    public init() {}

    public var requirements: [GroundingRequirement] { [] }
    public var candidateMetrics: [MetricType] { HealthWatchModel.watched.map { $0.metric } }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let output = HealthWatchModel.evaluate(samples: samples, now: now) else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "Building baseline",
                score: nil, confidence: .low,
                explanation: "This watches several signals at once — resting heart rate, HRV, temperature, breathing, blood oxygen — for the pattern a body shows a day or two before you feel anything. It needs about a month of nights from at least two of them.",
                drivers: [], unmetRequirements: [])
        }

        let leaning = output.leaning
        let headline: String
        switch leaning.count {
        case 0: headline = "All clear"
        case 1: headline = "1 signal stirring"
        default: headline = "\(leaning.count) signals leaning"
        }

        var drivers: [InsightDriver] = leaning.map { signal in
            InsightDriver(
                text: String(format: "%@ %@ %.1f SD from your baseline fortnight (%@ → %@)",
                             signal.metric.displayName,
                             signal.zScore > 0 ? "up" : "down", abs(signal.zScore),
                             MetricValueFormatter.string(signal.reference, signal.metric),
                             MetricValueFormatter.string(signal.recent, signal.metric)),
                isNotable: true)
        }
        for signal in output.signals where !signal.isLeaning {
            drivers.append(.routine("\(signal.metric.displayName): steady"))
        }

        let explanation: String
        switch leaning.count {
        case 0:
            explanation = "\(output.signals.count) signals watched, none of them leaning. This compares the last \(HealthWatchModel.recentDays) days against a fortnight that ended before they started — so a run that has been building for a week shows up more clearly rather than disappearing into its own average."
        case 1:
            explanation = "One signal has moved and the rest haven't. That happens on ordinary days — a late night, a hard session, a warm room. Worth knowing, not worth acting on."
        default:
            explanation = "\(leaning.count) signals are leaning the same way at once. Individually each is within the noise; together they are the pattern a body tends to show a day or two before an illness announces itself. This is an observation about your own numbers, not a diagnosis — if you feel unwell, treat that as the better information."
        }

        return InsightResult(
            id: id, title: title, primaryValue: Double(leaning.count),
            headline: headline, score: output.score,
            confidence: output.signals.count >= 4 ? .high : .moderate,
            explanation: explanation,
            driverLines: drivers, unmetRequirements: [],
            // Weight 0: the score is a count of agreement, not a weighted blend
            // of these values, and claiming a share of it would invent one.
            contributors: output.signals.map { signal in
                MetricContribution(
                    metric: signal.metric,
                    higherIsBetter: HealthWatchModel.watched
                        .first { $0.metric == signal.metric }
                        .map { !$0.risingIsConcerning },
                    weight: 0,
                    detail: MetricValueFormatter.detailedString(signal.recent, signal.metric))
            })
    }
}
