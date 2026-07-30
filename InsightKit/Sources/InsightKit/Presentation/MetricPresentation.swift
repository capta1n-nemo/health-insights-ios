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
    case cardiac, autonomic, respiratory, thermal, circulatory, body, activity, sleep

    public var displayName: String {
        switch self {
        case .cardiac: return "Heart rate"
        case .autonomic: return "Heart rate variability"
        case .respiratory: return "Breathing"
        case .thermal: return "Temperature"
        case .circulatory: return "Circulation"
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
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage: return .cardiac
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN: return .autonomic
        case .respiratoryRate, .oxygenSaturation: return .respiratory
        case .bodyTemperature, .skinTemperatureDeviation: return .thermal
        case .bloodPressureSystolic, .bloodPressureDiastolic, .vascularAge: return .circulatory
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .height: return .body
        case .stepCount, .activeEnergyBurned, .vo2Max, .dayStrain: return .activity
        case .sleepDurationHours: return .sleep
        }
    }

    /// Which slot of the eight-hue categorical palette this metric wears on an
    /// overlay chart.
    ///
    /// Fixed per metric rather than assigned by position in whatever list is on
    /// screen: a chart that repaints its surviving series when one drops out for
    /// want of data can't be read across two glances.
    ///
    /// Twenty-four metrics share eight hues, which is only safe because a slot
    /// is reused **solely between metrics that never appear on the same chart**.
    /// What co-occurs is decided by each insight's `candidateMetrics`, not here,
    /// so `MetricColourSlotTests` checks every insight for a collision rather
    /// than trusting this table to stay correct on its own. Adding a metric to
    /// an insight can therefore break a test in a file you didn't touch — that
    /// is the point.
    ///
    /// Exhaustive with no `default:`, like the rest of this file.
    var colourSlot: Int {
        switch self {
        case .restingHeartRate, .bodyMass, .vascularAge: return 0
        case .heartRateVariabilityRMSSD, .bodyFatPercentage: return 1
        case .sleepDurationHours, .walkingHeartRateAverage, .stepCount, .leanBodyMass: return 2
        case .oxygenSaturation, .vo2Max, .muscleMass: return 3
        case .respiratoryRate, .bloodPressureSystolic, .boneMass: return 4
        case .skinTemperatureDeviation, .bodyTemperature, .activeEnergyBurned,
             .bloodPressureDiastolic, .bodyWaterPercentage: return 5
        case .heartRate, .height: return 6
        case .heartRateVariabilitySDNN, .dayStrain: return 7
        }
    }

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
             .bodyTemperature, .skinTemperatureDeviation, .sleepDurationHours:
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
        case .heartRate, .oxygenSaturation, .respiratoryRate:
            return 30 * minute
        case .restingHeartRate, .walkingHeartRateAverage,
             .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD,
             .sleepDurationHours, .bodyTemperature, .skinTemperatureDeviation,
             .dayStrain, .stepCount, .activeEnergyBurned:
            return day
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .vo2Max, .vascularAge,
             .bloodPressureSystolic, .bloodPressureDiastolic, .height:
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
