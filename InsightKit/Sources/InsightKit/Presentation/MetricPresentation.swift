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

    /// This metric's place in the ordering the palette assigns hues from.
    ///
    /// Eight validated hues is the ceiling for a categorical palette, and a
    /// Vitals Check chart can hold seventeen signals — so identity was once a
    /// (hue, dash) pair, which made every metric distinguishable from every
    /// other by construction. It was measurably safe and practically wrong: a
    /// dashed line reads as an estimate or a gap in the data, not as a different
    /// signal. Charts now keep the number of visible series inside what hue
    /// alone can carry instead (see `MetricPalette`).
    ///
    /// The order below front-loads the vitals that share the Vitals Check chart,
    /// so the signals most likely to appear together get first claim on the
    /// eight hues and rarely have to be shifted off their own.
    ///
    /// Fixed per metric rather than assigned by position in whatever list is on
    /// screen: a chart that repaints its surviving series when one drops out for
    /// want of data can't be read across two glances.
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

    /// The hue this metric prefers. Not necessarily the one it gets — see
    /// `MetricPalette.slots(for:)`, which resolves collisions per chart.
    var colourSlot: Int { chartStyleIndex % MetricPalette.hueCount }

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

/// Which hue each series on a chart wears.
///
/// Identity used to be a (hue, dash) pair, because eight validated hues cannot
/// separate thirty metrics and a dash could carry the rest. That was measurably
/// safe and practically wrong: a dashed line reads as an *estimate or a gap*,
/// not as a different signal, so the dashes were being read as missing data.
///
/// So hue alone now, and the chart keeps the number of visible series inside
/// what hue alone can carry — all of them when there are few, only the ones
/// away from baseline when there are many, with the rest a toggle away.
///
/// Assignment is per chart rather than global. A metric keeps its own preferred
/// hue wherever that hue is free, so the same signal usually looks the same from
/// one card to the next; where two would collide, the later one steps to the
/// next free hue. Global assignment alone could not promise distinctness once
/// dash was gone, and distinctness within the chart in front of you is the
/// property that actually matters.
public enum MetricPalette {

    /// Hues in the validated categorical palette.
    public static let hueCount = 8

    /// Comfortably distinguishable at once. Above this a chart shows only the
    /// series away from baseline unless asked for all of them.
    public static let comfortableSeriesCount = 6

    /// Hue per metric for one chart, in the order the series are drawn.
    ///
    /// Beyond `hueCount` metrics a repeat is unavoidable; the caller is expected
    /// not to get there, and this returns a usable answer rather than trapping
    /// if it does.
    public static func slots(for metrics: [MetricType]) -> [MetricType: Int] {
        var used = Set<Int>()
        var out: [MetricType: Int] = [:]
        for metric in metrics where out[metric] == nil {
            var slot = metric.colourSlot
            var tried = 0
            while used.contains(slot) && tried < hueCount {
                slot = (slot + 1) % hueCount
                tried += 1
            }
            used.insert(slot)
            out[metric] = slot
        }
        return out
    }
}
