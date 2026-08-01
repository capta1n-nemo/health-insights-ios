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
        case .bodyTemperature, .skinTemperature, .skinTemperatureDeviation: return .thermal
        case .bloodPressureSystolic, .bloodPressureDiastolic, .vascularAge,
             .peripheralPerfusionIndex: return .circulatory
        case .bloodGlucose: return .metabolic
        case .walkingSteadiness, .walkingAsymmetry: return .mobility
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .height: return .body
        case .stepCount, .activeEnergyBurned, .exerciseMinutes, .vo2Max,
             .dayStrain: return .activity
        case .sleepDurationHours, .sleepOnset, .sleepEfficiency,
             .sleepDeepMinutes, .sleepRemMinutes, .sleepLatencyMinutes: return .sleep
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
        // Appended rather than slotted next to `.bodyTemperature`, because
        // `testStyleIndicesAreContiguousFromZero` pins this list to 0..<count
        // and inserting would renumber twenty-seven cases for no gain. The cost
        // is a preferred hue shared with resting heart rate, which
        // `MetricPalette.slots` resolves per chart.
        case .skinTemperature: return 30
        // Appended for the same reason `.skinTemperature` was: the contiguity
        // test pins this list to 0..<count, and slotting it beside
        // `.sleepDurationHours` would renumber eighteen cases so that two
        // metrics which never share a chart could each keep a preferred hue.
        case .sleepOnset: return 31
        case .sleepEfficiency: return 32
        case .sleepDeepMinutes: return 33
        case .sleepRemMinutes: return 34
        // Appended, like the two blocks above: the contiguity test pins this
        // list to 0..<count, and this metric's usual chart is Fitness's
        // overlay, where hues resolve per chart anyway.
        case .exerciseMinutes: return 35
        case .sleepLatencyMinutes: return 36
        }
    }

    /// Whether a relationship between these two metrics would describe how
    /// they are *derived* rather than anything about the person.
    ///
    /// Same family is the obvious case — body temperature and skin-temperature
    /// deviation are one measurement reported two ways. The non-obvious one is
    /// heart rate against heart-rate variability: both are computed from the
    /// same beat-to-beat interval stream, so a shorter interval is both a higher
    /// rate and less room to vary. "HRV and resting heart rate move in opposite
    /// directions (r = −0.71)" is arithmetic. It reads like a finding, and it
    /// crowds real cross-system observations off the card.
    ///
    /// They stay in separate *families* because families also decide colour
    /// grouping and how the app talks about systems, where the distinction is
    /// real. This is the narrower question of shared origin.
    func sharesMeasurementBasis(with other: MetricType) -> Bool {
        if family == other.family { return true }
        let beatToBeat: Set<MetricFamily> = [.cardiac, .autonomic]
        return beatToBeat.contains(family) && beatToBeat.contains(other.family)
    }

    /// Metrics that are one quantity reported in different units or by
    /// different devices, so a card declaring several of them and reading
    /// whichever its own device provides has read all of them.
    ///
    /// **Much narrower than `sharesMeasurementBasis`**, and the difference is
    /// the point. That one is family-wide, so it would let a card declare
    /// VO₂max, never read it, and pass on the strength of having read a resting
    /// heart rate. This says only *these two are the same measurement* —
    /// rMSSD and SDNN are both heart-rate variability, and an absolute skin
    /// temperature, an absolute body temperature and a nightly deviation are one
    /// thermometer reported three ways.
    ///
    /// Exists for `ContributorsTests.testEveryDeclaredInputWithDataIsActuallyRead`,
    /// which is otherwise unwritable: "a card must read what it declares" is
    /// true except for alternatives, and the alternative to stating them here is
    /// a per-model exception list, which only ever catches the models somebody
    /// remembered to leave out of it.
    var interchangeable: Set<MetricType> {
        for group in Self.interchangeableGroups where group.contains(self) {
            return group.subtracting([self])
        }
        return []
    }

    static let interchangeableGroups: [Set<MetricType>] = [
        [.heartRateVariabilityRMSSD, .heartRateVariabilitySDNN],
        [.skinTemperatureDeviation, .skinTemperature, .bodyTemperature]
    ]

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
             .bodyTemperature, .skinTemperature, .skinTemperatureDeviation,
             .sleepDurationHours, .sleepOnset, .sleepEfficiency,
             .sleepDeepMinutes, .sleepRemMinutes, .sleepLatencyMinutes,
             .bloodGlucose, .peripheralPerfusionIndex, .atrialFibrillationBurden,
             .heartRateRecovery, .walkingSteadiness, .walkingAsymmetry:
            // Sleep belongs here, not with the daily totals: it already arrives
            // as one value per night, so summing it is a no-op, and "total hours
            // slept this month" is not a number anyone wants — "average 7.1 h,
            // range 5.4–8.9 h" is.
            return .fluctuatingRange

        case .stepCount, .activeEnergyBurned, .exerciseMinutes:
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
             .sleepDurationHours, .sleepOnset, .sleepEfficiency,
             .sleepDeepMinutes, .sleepRemMinutes, .sleepLatencyMinutes,
             .bodyTemperature, .skinTemperature,
             .skinTemperatureDeviation,
             .dayStrain, .stepCount, .activeEnergyBurned, .exerciseMinutes,
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

    /// The published range an ordinary reading sits in, or `nil` where no such
    /// range exists — which is most metrics, and is the honest answer for them.
    ///
    /// Exhaustive with no `default:`, like the rest of this file. A silent `nil`
    /// for a new metric is the failure mode this repo keeps paying for; being
    /// made to write `case .newThing: return nil  // because …` is the point.
    ///
    /// Sex- and age-dependent ranges (body fat, VO₂max) are deliberately absent.
    /// They need a `UserHealthProfile`, which a property on `MetricType` has no
    /// access to; when they arrive they get a `referenceRange(for:)` rather than
    /// a fudge here.
    var referenceRange: MetricReferenceRange? {
        typealias R = MetricReferenceRange
        typealias B = MetricReferenceRange.Band
        switch self {
        case .oxygenSaturation:
            return R(normal: B(low: 95, high: 100),
                     cautionBelow: B(low: 90, high: 95),
                     caption: "95–100% is the usual range for a healthy adult at sea level. Below 90% is low enough to act on.",
                     provenance: "Standard clinical reference range — the same 95–100% Apple Health shows for Blood Oxygen. The Vitals check's own attention line is 94%.")

        case .respiratoryRate:
            return R(normal: B(low: 12, high: 20),
                     cautionBelow: B(low: 9, high: 12),
                     cautionAbove: B(low: 20, high: 25),
                     caption: "12–20 breaths a minute at rest.",
                     provenance: "Standard adult vital-sign range; NEWS2 scores 12–20 as normal and ≤8 or ≥25 as its highest-risk arms.")

        case .bodyTemperature:
            // CORE only. Skin runs two to three degrees cooler and gets no band.
            return R(normal: B(low: 36.1, high: 37.2),
                     cautionBelow: B(low: 35.0, high: 36.1),
                     cautionAbove: B(low: 37.2, high: 38.0),
                     caption: "36.1–37.2 °C is the ordinary core range. 38.0 °C and up is fever; below 35.0 °C is hypothermia.",
                     provenance: "Conventional oral reference range. Mackowiak's 1992 re-appraisal of 98.6 °F put the 99th centile of normal oral temperature at 37.7 °C, which is where the Vitals check's 37.8 alarm line comes from.")

        case .bloodGlucose:
            return R(normal: B(low: 3.9, high: 10.0),
                     cautionBelow: B(low: 3.0, high: 3.9),
                     cautionAbove: B(low: 10.0, high: 13.9),
                     caption: "3.9–10.0 mmol/L is the time-in-range target across the whole day, meals included. It is not a fasting normal — fasting normal is 3.9–5.5 mmol/L.",
                     provenance: "Battelino et al., 'Clinical Targets for Continuous Glucose Monitoring Data Interpretation', Diabetes Care 2019 (70–180 mg/dL). Fasting figure from the ADA; level-2 hypo <3.0 and level-2 hyper >13.9 set the shoulders.")

        case .sleepOnset:
            // No band, and not because nobody has published one. Sleep-timing
            // guidance is about *regularity* and about alignment with your own
            // chronotype, not about a clock reading: a shift worker asleep at
            // 09:00 and a lark asleep at 21:30 are both fine, and shading
            // 22:00–00:00 as "normal" would tell most of the world their
            // bedtime is abnormal. `CircadianConsistency` scores the spread
            // instead, which is the thing the evidence is actually about.
            return nil

        case .sleepEfficiency:
            return R(normal: B(low: 85, high: 100),
                     cautionBelow: B(low: 75, high: 85),
                     caption: "85% and up is the usual figure for a healthy sleeper — the share of time in bed actually spent asleep.",
                     provenance: "The ≥85% criterion is the long-standing clinical threshold for normal sleep efficiency, and the one the National Sleep Foundation's sleep-quality consensus panel adopted (Ohayon et al., Sleep Health 2017).")

        case .sleepDeepMinutes, .sleepRemMinutes:
            // No band. The published figures are *shares of a night* (deep
            // roughly 13–23%, REM 20–25%), and both shift with age — so a fixed
            // band in minutes would tell a short sleeper their perfectly normal
            // proportions are abnormal. `SleepQualityInsight` scores the share
            // instead, which is the form the evidence is in.
            return nil

        case .sleepLatencyMinutes:
            return R(normal: B(low: 0, high: 15),
                     cautionAbove: B(low: 15, high: 30),
                     caption: "Falling asleep within 15 minutes is the consensus figure for a healthy sleeper; over 30 minutes regularly is worth attention.",
                     provenance: "Ohayon et al., National Sleep Foundation sleep-quality consensus (Sleep Health 2017): ≤15 min appropriate, 16–30 uncertain, >30 inappropriate — the same panel the efficiency band comes from.")

        case .restingHeartRate:
            // No low shoulder on purpose: `concernWhenLow` is false for this
            // spec, and shading under 60 would paint every trained user's chart
            // as a problem.
            return R(normal: B(low: 60, high: 100),
                     cautionAbove: B(low: 100, high: 120),
                     caption: "60–100 bpm is the standard adult resting range. Regularly trained people sit below it, which is why nothing is shaded underneath.",
                     provenance: "American Heart Association adult resting heart-rate range. The Vitals check's 38 bpm floor is a bradycardia alarm, not a normal floor.")

        case .heartRateRecovery:
            return R(normal: B(low: 12),
                     cautionBelow: B(high: 12),
                     caption: "A drop of 12 bpm or more in the first minute after exertion is the normal response. Higher is better, and there is no upper limit worth drawing.",
                     provenance: "Cole et al., New England Journal of Medicine 1999 — a one-minute recovery of ≤12 bpm predicted mortality. Apple Watch reports the one-minute figure.")

        case .walkingSteadiness:
            return R(normal: B(low: 50, high: 100),
                     cautionBelow: B(low: 20, high: 50),
                     caption: "Apple rates 50% and above as OK, 20–50% as Low, and below 20% as Very Low.",
                     provenance: "Apple's published Walking Steadiness classification — the same bands Vitals Check already scores against.")

        case .sleepDurationHours:
            return R(normal: B(low: 7, high: 9),
                     cautionBelow: B(low: 6, high: 7),
                     cautionAbove: B(low: 9, high: 10),
                     caption: "7–9 hours a night is the recommended range for an adult.",
                     provenance: "National Sleep Foundation duration recommendations (2015); the AASM/SRS consensus states 7 hours or more.")

        // The bounds that exist for heart rate (40–100) are for the *day's
        // representative value*. This chart plots raw samples at any window up to
        // a day and a half, workouts included, and a 60–100 band drawn over a run
        // is a chart that lies.
        case .heartRate: return nil
        // Alarm ceiling only; no published normal floor.
        case .walkingHeartRateAverage: return nil
        // "No absolute bound is defensible — rMSSD spans roughly 15–150 ms with
        // age, fitness and device." The same holds for SDNN.
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN: return nil
        // Nightly wrist skin temperature tracks ambient warmth and bedding, which
        // is exactly why every vendor publishes a deviation instead.
        case .skinTemperature: return nil
        // The zero point *is* the personal baseline, so a fixed band here would
        // be a band around a moving target.
        case .skinTemperatureDeviation: return nil
        // 0.5% is an alarm floor; published perfusion index spans roughly 0.3–10%
        // with no agreed normal band.
        case .peripheralPerfusionIndex: return nil
        // Zero is the healthy value, and a degenerate 0–0 band shades nothing.
        case .atrialFibrillationBurden: return nil
        // The 10% ceiling is this app's attention line; Apple publishes no
        // classification for asymmetry the way it does for steadiness.
        case .walkingAsymmetry: return nil
        // The ACC/AHA bands live in exactly one place —
        // `BloodPressureEstimator.Category` — and `BloodPressureSections` draws
        // them from there. Two copies of a clinical threshold is one too many.
        case .bloodPressureSystolic, .bloodPressureDiastolic: return nil
        // Age- and sex-dependent. `HeartHealthScore` already holds reference
        // tables for these and a fixed band here would contradict them.
        case .vo2Max, .bodyFatPercentage: return nil
        // No published "normal" that means anything without a person attached.
        case .vascularAge, .bodyMass, .leanBodyMass, .muscleMass, .boneMass,
             .bodyWaterPercentage, .height, .stepCount, .activeEnergyBurned,
             .dayStrain:
            return nil
        // A published band exists — WHO's 150–300 min — but it is *weekly*, and
        // this chart plots daily totals. Dividing by seven would draw a daily
        // target the guideline deliberately does not state: the whole dose can
        // legitimately land on two weekend days. `ActivityDoseModel` scores the
        // weekly figure, which is the form the evidence is in.
        case .exerciseMinutes: return nil
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
        case .stepCount, .activeEnergyBurned, .exerciseMinutes:
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
