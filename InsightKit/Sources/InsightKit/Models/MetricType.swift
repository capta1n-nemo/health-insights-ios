import Foundation

/// The canonical, vendor-neutral catalogue of health metrics the app reasons
/// about. Every integration (Apple Health, Oura, Withings, …) normalises its raw
/// data into `HealthMetricSample`s tagged with one of these types, so the
/// insight engine never has to know which device a number came from.
///
/// Adding a metric here is the first step to teaching the app a new signal.
public enum MetricType: String, Codable, Sendable, CaseIterable {
    // Cardiovascular / heart
    case heartRate                 // bpm, instantaneous / averaged
    case restingHeartRate          // bpm
    case walkingHeartRateAverage   // bpm
    case heartRateVariabilitySDNN  // ms (Apple reports SDNN)
    case heartRateVariabilityRMSSD // ms (Oura reports rMSSD)
    case vo2Max                    // mL/(kg·min) — Apple "Cardio Fitness"
    case vascularAge               // years — a provider's own cardiovascular-age estimate
    case respiratoryRate           // breaths/min
    case oxygenSaturation          // % SpO2 (Whoop, Hume, Apple Watch)
    case dayStrain                 // 0–21 cumulative cardiovascular load (Whoop)

    // Blood pressure (measured, e.g. from a cuff synced into Health / Withings)
    case bloodPressureSystolic     // mmHg
    case bloodPressureDiastolic    // mmHg

    // Body composition (Withings scale, Health)
    case bodyMass                  // kg
    case bodyFatPercentage         // %
    case leanBodyMass              // kg
    case muscleMass                // kg
    case boneMass                  // kg
    case bodyWaterPercentage       // %
    case height                    // m

    // Activity & sleep
    case stepCount                 // count
    case activeEnergyBurned        // kcal
    /// Minutes of at-least-moderate activity (Apple's "exercise minute" accrues
    /// at brisk-walk intensity and above, which is the WHO guideline's own
    /// moderate-intensity definition — that match is why this one, alone of the
    /// activity metrics, can be scored against a published dose).
    case exerciseMinutes           // min
    case sleepDurationHours        // hours
    /// **Hours from local midnight, signed, with the branch cut at midday.**
    /// −1.5 is 22:30, +0.5 is 00:30, 0 is midnight exactly.
    ///
    /// The obvious encoding is a clock hour in [0, 24), and it is wrong here:
    /// the mean of 23:30 and 00:30 is midnight, not noon, so every consumer
    /// would need circular statistics. This app's whole baseline machinery —
    /// `Baseline.mean`, `zScore`, the regressions, the charts — is linear, and
    /// making one metric the exception would mean every one of them has to know
    /// which metric it is holding.
    ///
    /// Putting the wrap at *midday* instead makes it linear by construction:
    /// nobody's sleep onset crosses noon, so no real series ever meets the
    /// branch cut, and the arithmetic mean is the circular mean. A value outside
    /// (−12, +12] is not a late night, it is a bug.
    case sleepOnset                // h from local midnight (negative = before)
    case sleepEfficiency           // % of time in bed actually asleep
    case sleepDeepMinutes          // minutes of deep (slow-wave) sleep
    case sleepRemMinutes           // minutes of REM sleep
    /// Minutes from getting into bed to falling asleep. Emitted by the typed
    /// Oura parser only for real nights — the generic pipeline must not feed
    /// this, because the sleep endpoint's nap and rest segments carry a
    /// latency too, and a nap's latency is not a night's.
    case sleepLatencyMinutes       // minutes to fall asleep
    // Three thermal metrics, deliberately distinct. Core and skin are measured
    // in different places, sit two to three degrees apart, and mean different
    // things — judging one against the other's bounds was reporting every
    // wearable user as hypothermic and hiding real fevers.
    case bodyTemperature           // °C absolute CORE (thermometer, Withings 71/12)
    case skinTemperature           // °C absolute SKIN (Whoop, Withings 73, Apple wrist, reconstructed)
    case skinTemperatureDeviation  // °C deviation from personal baseline (Oura/Hume)

    // Vitals Apple Health has always collected and the app imported only as raw
    // "other data" — measurements with real units and real baselines, so they
    // belong here rather than in the untyped layer.
    case bloodGlucose              // mmol/L
    case peripheralPerfusionIndex  // % — perfusion, off the same sensor as SpO2
    case atrialFibrillationBurden  // % of time in AFib (Apple Watch)
    case heartRateRecovery         // bpm drop one minute after exertion
    case walkingSteadiness         // % — Apple's fall-risk measure
    case walkingAsymmetry          // % of walking time with uneven gait

    /// Human-readable label for UI.
    public var displayName: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .walkingHeartRateAverage: return "Walking Heart Rate"
        case .heartRateVariabilitySDNN: return "HRV (SDNN)"
        case .heartRateVariabilityRMSSD: return "HRV (rMSSD)"
        case .vo2Max: return "Cardio Fitness (VO₂max)"
        case .vascularAge: return "Vascular Age"
        case .respiratoryRate: return "Respiratory Rate"
        case .oxygenSaturation: return "Blood Oxygen"
        case .dayStrain: return "Day Strain"
        case .bloodPressureSystolic: return "Systolic BP"
        case .bloodPressureDiastolic: return "Diastolic BP"
        case .bodyMass: return "Weight"
        case .bodyFatPercentage: return "Body Fat"
        case .leanBodyMass: return "Lean Body Mass"
        case .muscleMass: return "Muscle Mass"
        case .boneMass: return "Bone Mass"
        case .bodyWaterPercentage: return "Body Water"
        case .height: return "Height"
        case .stepCount: return "Steps"
        case .activeEnergyBurned: return "Active Energy"
        case .exerciseMinutes: return "Exercise Minutes"
        case .sleepDurationHours: return "Sleep Duration"
        case .sleepOnset: return "Sleep Onset"
        case .sleepEfficiency: return "Sleep Efficiency"
        case .sleepDeepMinutes: return "Deep Sleep"
        case .sleepRemMinutes: return "REM Sleep"
        case .sleepLatencyMinutes: return "Sleep Latency"
        case .bodyTemperature: return "Body Temperature"
        case .skinTemperature: return "Skin Temperature"
        case .skinTemperatureDeviation: return "Skin Temp Deviation"
        case .bloodGlucose: return "Blood Glucose"
        case .peripheralPerfusionIndex: return "Perfusion Index"
        case .atrialFibrillationBurden: return "AFib Burden"
        case .heartRateRecovery: return "Heart Rate Recovery"
        case .walkingSteadiness: return "Walking Steadiness"
        case .walkingAsymmetry: return "Walking Asymmetry"
        }
    }

    /// Canonical unit label for UI. The stored value is always in this unit.
    public var unit: String {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage: return "bpm"
        case .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD: return "ms"
        case .vo2Max: return "mL/kg·min"
        case .vascularAge: return "years"
        case .respiratoryRate: return "br/min"
        case .oxygenSaturation: return "%"
        case .dayStrain: return ""
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "mmHg"
        case .bodyMass, .leanBodyMass, .muscleMass, .boneMass: return "kg"
        case .bodyFatPercentage, .bodyWaterPercentage: return "%"
        case .height: return "m"
        case .stepCount: return "steps"
        case .activeEnergyBurned: return "kcal"
        case .exerciseMinutes: return "min"
        case .sleepDurationHours: return "h"
        // Empty: the formatter renders this as a clock time, and "23:12 h" is
        // not a thing.
        case .sleepOnset: return ""
        case .sleepEfficiency: return "%"
        case .sleepDeepMinutes, .sleepRemMinutes, .sleepLatencyMinutes: return "min"
        case .bodyTemperature, .skinTemperature, .skinTemperatureDeviation: return "°C"
        case .bloodGlucose: return "mmol/L"
        case .peripheralPerfusionIndex, .atrialFibrillationBurden,
             .walkingSteadiness, .walkingAsymmetry: return "%"
        case .heartRateRecovery: return "bpm"
        }
    }

    /// The display name as it should read mid-sentence.
    ///
    /// Not `displayName.lowercased()`, which mangles the acronyms — that is how
    /// "on days when hrv (rmssd) changes" reached the screen. A word is
    /// lowercased only when it looks like ordinary prose; anything carrying an
    /// inner capital or a digit (HRV, rMSSD, SDNN, VO₂max) is left as written.
    public var inSentence: String {
        displayName.split(separator: " ").map { word -> String in
            let letters = word.drop { !$0.isLetter && !$0.isNumber }
            let looksLikeAnAcronym = letters.dropFirst().contains { $0.isUppercase || $0.isNumber }
            return looksLikeAnAcronym ? String(word) : word.lowercased()
        }
        .joined(separator: " ")
    }
}
