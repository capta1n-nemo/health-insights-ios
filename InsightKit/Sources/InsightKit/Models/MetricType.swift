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
    case respiratoryRate           // breaths/min
    case oxygenSaturation          // % SpO2 (Whoop, Hume, Apple Watch)
    case dayStrain                 // 0–21 cumulative cardiovascular load (Whoop)

    // Blood pressure (measured, e.g. from a cuff synced into Health / Withings)
    case bloodPressureSystolic     // mmHg
    case bloodPressureDiastolic    // mmHg

    // Body composition (Withings scale, Health)
    case bodyMass                  // kg
    case bodyFatPercentage         // fraction 0…1
    case leanBodyMass              // kg
    case height                    // m

    // Activity & sleep
    case stepCount                 // count
    case activeEnergyBurned        // kcal
    case sleepDurationHours        // hours
    case bodyTemperature           // °C absolute (reconstructed or measured)
    case skinTemperatureDeviation  // °C deviation from personal baseline (Oura/Whoop/Hume)

    /// Human-readable label for UI.
    public var displayName: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .walkingHeartRateAverage: return "Walking Heart Rate"
        case .heartRateVariabilitySDNN: return "HRV (SDNN)"
        case .heartRateVariabilityRMSSD: return "HRV (rMSSD)"
        case .vo2Max: return "Cardio Fitness (VO₂max)"
        case .respiratoryRate: return "Respiratory Rate"
        case .oxygenSaturation: return "Blood Oxygen"
        case .dayStrain: return "Day Strain"
        case .bloodPressureSystolic: return "Systolic BP"
        case .bloodPressureDiastolic: return "Diastolic BP"
        case .bodyMass: return "Weight"
        case .bodyFatPercentage: return "Body Fat"
        case .leanBodyMass: return "Lean Body Mass"
        case .height: return "Height"
        case .stepCount: return "Steps"
        case .activeEnergyBurned: return "Active Energy"
        case .sleepDurationHours: return "Sleep Duration"
        case .bodyTemperature: return "Body Temperature"
        case .skinTemperatureDeviation: return "Skin Temp Deviation"
        }
    }

    /// Canonical unit label for UI. The stored value is always in this unit.
    public var unit: String {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage: return "bpm"
        case .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD: return "ms"
        case .vo2Max: return "mL/kg·min"
        case .respiratoryRate: return "br/min"
        case .oxygenSaturation: return "%"
        case .dayStrain: return ""
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "mmHg"
        case .bodyMass, .leanBodyMass: return "kg"
        case .bodyFatPercentage: return "%"
        case .height: return "m"
        case .stepCount: return "steps"
        case .activeEnergyBurned: return "kcal"
        case .sleepDurationHours: return "h"
        case .bodyTemperature, .skinTemperatureDeviation: return "°C"
        }
    }
}
