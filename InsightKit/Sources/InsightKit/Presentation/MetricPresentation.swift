import Foundation

/// How a metric should be shown, because one layout does not suit them all.
///
/// Weight wants a smoothed trend and a change velocity; heart rate wants a daily
/// range; blood pressure is a pair of numbers, not one; height is a fact about
/// you rather than a time series at all.
public enum MetricPresentation: String, Sendable, CaseIterable {
    /// Moves slowly and meaningfully in one direction. Weight, body composition.
    case cumulativeTrend
    /// Varies constantly within a personal band. Heart rate, HRV, SpO₂, sleep.
    case fluctuatingRange
    /// Accumulates through the day and is only meaningful as a daily total.
    case cumulativeTotal
    /// Two numbers that are meaningless apart. Blood pressure.
    case discreteBivariate
    /// A standing fact, not a trend. Height.
    case staticAttribute

    /// A log axis only helps where values span orders of magnitude.
    public var allowsLogScale: Bool {
        switch self {
        case .fluctuatingRange, .cumulativeTotal: return true
        case .cumulativeTrend, .discreteBivariate, .staticAttribute: return false
        }
    }

    public var allowsTimeframeSelection: Bool { self != .staticAttribute }
    public var showsChart: Bool { self != .staticAttribute }
}

/// Metrics that measure the same underlying system.
///
/// Two uses, both of which need the same grouping. It stops the patterns card
/// reporting tautologies — "on days when heart rate changes, resting heart rate
/// tends to as well" is a fact about how resting heart rate is derived, not an
/// observation about the person — and it is what an overlay chart colours by
/// once there are more metrics than there are distinguishable hues.
public enum MetricFamily: String, Sendable, CaseIterable {
    case cardiac, autonomic, respiratory, thermal, circulatory
    case metabolic, mobility, body, activity, sleep

    public var displayName: String {
        switch self {
        case .cardiac: return "Heart rate"
        case .autonomic: return "Heart rate variability"
        case .respiratory: return "Breathing"
        case .thermal: return "Temperature"
        case .circulatory: return "Circulation"
        case .metabolic: return "Metabolic"
        case .mobility: return "Mobility"
        case .body: return "Body composition"
        case .activity: return "Activity"
        case .sleep: return "Sleep"
        }
    }
}

public extension MetricType {
    /// Which system this metric measures. Exhaustive, like the rest of this file.
    var family: MetricFamily {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage,
             .atrialFibrillationBurden: return .cardiac
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
             .heartRateRecovery: return .autonomic
        case .respiratoryRate, .oxygenSaturation: return .respiratory
        case .bodyTemperature, .skinTemperatureDeviation: return .thermal
        case .bloodPressureSystolic, .bloodPressureDiastolic, .vascularAge,
             .peripheralPerfusionIndex: return .circulatory
        case .bloodGlucose: return .metabolic
        case .walkingSteadiness, .walkingAsymmetry: return .mobility
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .height: return .body
        case .stepCount, .activeEnergyBurned, .vo2Max, .dayStrain: return .activity
        case .sleepDurationHours: return .sleep
        }
    }

    /// This metric's position in the chart's identity scale.
    ///
    /// Hue alone cannot carry identity here. Eight validated hues is the most a
    /// categorical palette supports, and a Vitals Check chart now shows
    /// seventeen signals — worse, when every pair may be compared freely rather
    /// than only adjacent ones, **no** seven-hue subset of the palette clears
    /// the colour-blind separation floor. That was measured, not assumed: the
    /// first shipped version put two greens on one chart.
    ///
    /// So identity is a **pair**: hue from this index, line dash from it too.
    /// Because the index is globally unique per metric, every metric has a
    /// unique (hue, dash) — which means *any* subset of metrics is automatically
    /// collision-free, on any chart, without a per-insight rule to maintain.
    /// Adding a metric to an insight can no longer silently make two series
    /// look alike.
    ///
    /// Fixed per metric rather than assigned by position in whatever list is on
    /// screen: a chart that repaints its surviving series when one drops out for
    /// want of data can't be read across two glances.
    ///
    /// The order below front-loads the vitals that share the Vitals Check chart,
    /// so they take the eight distinct hues before any dash is reused.
    ///
    /// Exhaustive with no `default:`, like the rest of this file.
    var chartStyleIndex: Int {
        switch self {
        case .heartRate: return 0
        case .heartRateVariabilityRMSSD: return 1
        case .oxygenSaturation: return 2
        case .bodyTemperature: return 3
        case .bloodPressureSystolic: return 4
        case .bloodGlucose: return 5
        case .restingHeartRate: return 6
        case .walkingSteadiness: return 7
        case .respiratoryRate: return 8
        case .heartRateVariabilitySDNN: return 9
        case .peripheralPerfusionIndex: return 10
        case .skinTemperatureDeviation: return 11
        case .bloodPressureDiastolic: return 12
        case .sleepDurationHours: return 13
        case .walkingHeartRateAverage: return 14
        case .walkingAsymmetry: return 15
        case .heartRateRecovery: return 16
        case .atrialFibrillationBurden: return 17
        case .vo2Max: return 18
        case .vascularAge: return 19
        case .bodyMass: return 20
        case .bodyFatPercentage: return 21
        case .leanBodyMass: return 22
        case .muscleMass: return 23
        case .boneMass: return 24
        case .bodyWaterPercentage: return 25
        case .height: return 26
        case .stepCount: return 27
        case .activeEnergyBurned: return 28
        case .dayStrain: return 29
        }
    }

    /// Which of the eight hues this metric wears.
    var colourSlot: Int { chartStyleIndex % 8 }
    /// Which line dash it wears, so two metrics sharing a hue still differ.
    var dashIndex: Int { chartStyleIndex / 8 }

    /// Deliberately exhaustive with no `default:` — adding a `MetricType` then
    /// fails to compile until someone decides how it should be presented.
    var presentation: MetricPresentation {
        switch self {
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage:
            return .cumulativeTrend

        case .heartRate, .restingHeartRate, .walkingHeartRateAverage,
             .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD,
             .vo2Max, .vascularAge, .respiratoryRate, .oxygenSaturation, .dayStrain,
             .bodyTemperature, .skinTemperatureDeviation, .sleepDurationHours,
             .bloodGlucose, .peripheralPerfusionIndex, .atrialFibrillationBurden,
             .heartRateRecovery, .walkingSteadiness, .walkingAsymmetry:
            // Sleep belongs here, not with the daily totals: it already arrives
            // as one value per night, so summing it is a no-op, and "total hours
            // slept this month" is not a number anyone wants — "average 7.1 h,
            // range 5.4–8.9 h" is.
            return .fluctuatingRange

        case .stepCount, .activeEnergyBurned:
            return .cumulativeTotal

        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return .discreteBivariate

        case .height:
            return .staticAttribute
        }
    }

    /// Height and friends are facts about you, not trends — charting them
    /// invites nonsense like a "past week" view of a number that never moves.
    var isStaticAttribute: Bool { presentation == .staticAttribute }

    /// Longest gap that may be drawn as one continuous line.
    ///
    /// Beyond it the line breaks, because joining two readings across the gap
    /// asserts a trend that was never measured — a heart rate from last night
    /// joined to one this afternoon, or a weight from four years ago.
    var maxValidInterval: TimeInterval {
        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600
        let day: TimeInterval = 24 * hour
        switch self {
        case .heartRate, .oxygenSaturation, .respiratoryRate,
             .peripheralPerfusionIndex, .bloodGlucose:
            // Continuously sensed, so a gap of more than half an hour is a gap.
            // Blood glucose belongs here for CGM wearers; a fingerstick user
            // simply gets a broken line, which is the honest rendering.
            return 30 * minute
        case .restingHeartRate, .walkingHeartRateAverage,
             .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD,
             .sleepDurationHours, .bodyTemperature, .skinTemperatureDeviation,
             .dayStrain, .stepCount, .activeEnergyBurned,
             .atrialFibrillationBurden, .heartRateRecovery:
            return day
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .vo2Max, .vascularAge,
             .bloodPressureSystolic, .bloodPressureDiastolic, .height,
             // Apple computes the walking measures over a rolling window and
             // publishes them irregularly, so a fortnight is not a gap.
             .walkingSteadiness, .walkingAsymmetry:
            return 14 * day
        }
    }

    /// How several readings inside one bucket collapse to a single plotted point.
    var bucketStatistic: BucketStatistic {
        switch self {
        // A median ignores the one water-weight morning that a mean would let
        // drag the whole week.
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage:
            return .median
        // Partial samples through the day only mean anything added up.
        case .stepCount, .activeEnergyBurned:
            return .sum
        default:
            return .mean
        }
    }
}
