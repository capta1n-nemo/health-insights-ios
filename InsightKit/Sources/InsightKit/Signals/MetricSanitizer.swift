import Foundation

public extension MetricType {
    /// Whether a physiologically-valid reading of this metric must be strictly
    /// positive. Vitals like heart rate, HRV, VO₂max, blood pressure, weight and
    /// body temperature can never legitimately be zero or negative, so a `0`
    /// (usually a missing-data placeholder from a provider) should be dropped
    /// rather than shown as "0 bpm" or poured into a consensus/average.
    ///
    /// Metrics that *can* legitimately be zero (steps, active energy, day strain,
    /// sleep duration) — or signed (skin-temperature deviation) — are excluded.
    var requiresPositiveValue: Bool {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage,
             .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD, .vo2Max,
             .vascularAge,
             .respiratoryRate, .oxygenSaturation,
             .bloodPressureSystolic, .bloodPressureDiastolic,
             .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .height, .bodyTemperature:
            return true
        case .dayStrain, .stepCount, .activeEnergyBurned,
             .sleepDurationHours, .skinTemperatureDeviation:
            return false
        }
    }
}

public extension Array where Element == HealthMetricSample {
    /// Drop samples that can't be real — a non-positive value for a metric that
    /// must be positive. Keeps everything else untouched. This prevents "0 bpm"
    /// resting-heart-rate tiles (e.g. from an Oura day with no HR data) and stops
    /// placeholder zeros from dragging multi-source averages and graphs down.
    func sanitizedVitals() -> [HealthMetricSample] {
        partitionedVitals().kept
    }

    /// The same split, but keeping what was thrown away so the diagnostics log
    /// can say *which* metric from *which* source sent placeholder zeros. A bare
    /// "dropped 77 samples" can't tell a harmless provider quirk from a metric
    /// that has quietly stopped reporting.
    func partitionedVitals() -> (kept: [HealthMetricSample], dropped: [HealthMetricSample]) {
        var kept: [HealthMetricSample] = []
        var dropped: [HealthMetricSample] = []
        kept.reserveCapacity(count)
        for sample in self {
            if !sample.type.requiresPositiveValue || sample.value > 0 {
                kept.append(sample)
            } else {
                dropped.append(sample)
            }
        }
        return (kept, dropped)
    }
}
