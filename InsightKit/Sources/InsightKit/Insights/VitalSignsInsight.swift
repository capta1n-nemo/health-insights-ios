import Foundation

/// A daily scan of every sensed vital against the user's own recent baseline.
///
/// This exists because several metrics the app collects in quantity had no
/// reader at all: heart rate (tens of thousands of samples), walking heart
/// rate, blood oxygen and body temperature were stored, charted, and then
/// ignored by every insight. Readiness answers "how recovered am I"; this
/// answers the different and more clinical question "is anything off today",
/// which is what a vitals panel is for.
///
/// Deliberately not a weighted score. A vitals check should report the
/// *outliers*, not average an abnormal SpO₂ against a normal heart rate until
/// the abnormality disappears.
public enum VitalSignsCheck {

    /// One vital, judged against the personal baseline.
    public struct Reading: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            case normal, watch, unusual
        }
        public let metric: MetricType
        public let value: Double
        public let baseline: Double?
        public let zScore: Double?
        public let status: Status
        public let note: String
    }

    public struct Output: Sendable, Equatable {
        public let readings: [Reading]
        public var unusual: [Reading] { readings.filter { $0.status == .unusual } }
        public var watch: [Reading] { readings.filter { $0.status == .watch } }
        public var headline: String {
            if !unusual.isEmpty { return "\(unusual.count) unusual" }
            if !watch.isEmpty { return "\(watch.count) to watch" }
            return "All normal"
        }
    }

    /// Vitals to scan, and which direction is a concern.
    ///
    /// `concernWhenHigh` / `concernWhenLow` mark the clinically meaningful
    /// direction; a departure the other way is reported as "watch" rather than
    /// "unusual", because a resting heart rate below baseline is usually good
    /// news and shouldn't read like an alarm.
    struct Spec {
        let metric: MetricType
        let concernWhenHigh: Bool
        let concernWhenLow: Bool
        /// Absolute bounds that mean something regardless of personal baseline.
        let hardLow: Double?
        let hardHigh: Double?
        let format: String
    }

    static let specs: [Spec] = [
        Spec(metric: .heartRate, concernWhenHigh: true, concernWhenLow: false,
             hardLow: 40, hardHigh: 120, format: "%.0f"),
        Spec(metric: .restingHeartRate, concernWhenHigh: true, concernWhenLow: false,
             hardLow: 38, hardHigh: 100, format: "%.0f"),
        Spec(metric: .walkingHeartRateAverage, concernWhenHigh: true, concernWhenLow: false,
             hardLow: nil, hardHigh: 130, format: "%.0f"),
        Spec(metric: .oxygenSaturation, concernWhenHigh: false, concernWhenLow: true,
             hardLow: 92, hardHigh: nil, format: "%.0f"),
        Spec(metric: .respiratoryRate, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 8, hardHigh: 22, format: "%.0f"),
        Spec(metric: .bodyTemperature, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 35.5, hardHigh: 37.8, format: "%.1f"),
        Spec(metric: .heartRateVariabilityRMSSD, concernWhenHigh: false, concernWhenLow: true,
             hardLow: nil, hardHigh: nil, format: "%.0f")
    ]

    /// z beyond this is "unusual"; beyond the smaller one is "watch".
    static let unusualZ = 2.0
    static let watchZ = 1.25

    public static func evaluate(samples: [HealthMetricSample], now: Date = Date()) -> Output {
        var readings: [Reading] = []
        for spec in specs {
            // Daily-representative value: the mean of today's readings for a
            // continuously-sampled vital, so one high minute during a run
            // doesn't get reported as the day's heart rate.
            let series = samples.samples(of: spec.metric)
            guard let latest = series.last else { continue }
            let history = Array(series.dropLast().suffix(60).map(\.value))
            let deviation = Baseline.deviation(latest: latest.value, history: history)
            let z = deviation?.zScore

            var status = Reading.Status.normal
            var note = "in your normal range"

            if let z {
                let magnitude = abs(z)
                let high = z > 0
                let concerning = (high && spec.concernWhenHigh) || (!high && spec.concernWhenLow)
                if magnitude >= unusualZ {
                    status = concerning ? .unusual : .watch
                    note = high ? "well above your baseline" : "well below your baseline"
                } else if magnitude >= watchZ {
                    status = concerning ? .watch : .normal
                    note = high ? "a little above your baseline" : "a little below your baseline"
                }
            }

            // An absolute bound overrides a personal one: a baseline built from
            // consistently low oxygen saturation would otherwise normalise it.
            if let hardLow = spec.hardLow, latest.value < hardLow {
                status = .unusual
                note = "below the usual healthy range"
            }
            if let hardHigh = spec.hardHigh, latest.value > hardHigh {
                status = .unusual
                note = "above the usual healthy range"
            }

            readings.append(Reading(metric: spec.metric, value: latest.value,
                                    baseline: deviation?.baseline, zScore: z,
                                    status: status, note: note))
        }
        return Output(readings: readings)
    }

    static func describe(_ reading: Reading) -> String {
        let spec = specs.first { $0.metric == reading.metric }
        let formatted = String(format: spec?.format ?? "%.1f", reading.value)
        let unit = reading.metric.unit
        var text = "\(reading.metric.displayName): \(formatted)\(unit.isEmpty ? "" : " \(unit)")"
        if let baseline = reading.baseline {
            text += String(format: " (baseline %@)", String(format: spec?.format ?? "%.1f", baseline))
        }
        return "\(text) — \(reading.note)"
    }
}

/// `InsightModel` adapter — a Today card.
public struct VitalSignsInsight: InsightModel {
    public let id: InsightID = .vitalSigns
    public let title = "Vitals Check"
    public init() {}
    public var requirements: [GroundingRequirement] { [] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let output = VitalSignsCheck.evaluate(samples: samples, now: now)
        guard !output.readings.isEmpty else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "No data yet", score: nil,
                confidence: .low,
                explanation: "Connect a wearable or Apple Health to have your vitals checked against your own baseline each day.",
                drivers: [], unmetRequirements: [])
        }

        // Score is "how normal is today", so the dial reads well next to
        // Readiness: every vital normal is 100, each flag costs.
        let penalty = Double(output.unusual.count) * 25 + Double(output.watch.count) * 10
        let score = max(0, 100 - penalty)

        let flagged = output.unusual + output.watch
        let explanation: String
        if flagged.isEmpty {
            explanation = "All \(output.readings.count) vitals measured today sit in your normal range."
        } else {
            let names = flagged.map { $0.metric.displayName.lowercased() }
            explanation = "\(listPhrase(names).capitalizedFirst) \(flagged.count == 1 ? "is" : "are") away from your usual pattern today. Everything else is normal."
        }

        return InsightResult(
            id: id, title: title, primaryValue: Double(output.readings.count),
            headline: output.headline, score: score,
            confidence: output.readings.count >= 4 ? .high : .moderate,
            explanation: explanation,
            // Flagged vitals first — the point of a vitals panel is the outlier.
            drivers: (flagged + output.readings.filter { $0.status == .normal })
                .map(VitalSignsCheck.describe),
            unmetRequirements: [])
    }

    private func listPhrase(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
