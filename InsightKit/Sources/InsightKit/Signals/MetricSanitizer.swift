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
        // A day with no screen time is a real day, not a missing reading —
        // the same reason steps and active energy are excluded.
        case .screenTimeMinutes: return false
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage,
             .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD, .vo2Max,
             .vascularAge,
             .respiratoryRate, .oxygenSaturation,
             .bloodPressureSystolic, .bloodPressureDiastolic,
             .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .height,
             .bodyTemperature, .skinTemperature,
             // A living person cannot read zero on any of these; a zero is a
             // provider placeholder.
             .bloodGlucose, .peripheralPerfusionIndex, .heartRateRecovery,
             .walkingSteadiness:
            return true
        case .dayStrain, .stepCount, .activeEnergyBurned,
             // A day with no exercise is a real day.
             .exerciseMinutes,
             // Zero is midnight exactly, and negative is any evening bedtime —
             // for this metric a positivity rule would throw away every reading
             // before 00:00, which is most of them.
             .sleepDurationHours, .sleepOnset,
             // Zero minutes of REM is a real night, and a night with no deep
             // sleep recorded is exactly the night worth seeing. Zero latency
             // is falling asleep the moment you lie down — a real (and
             // clinically interesting) night.
             .sleepEfficiency, .sleepDeepMinutes, .sleepRemMinutes,
             .sleepLatencyMinutes,
             .skinTemperatureDeviation,
             // Zero is the *good* value for both of these: no time in atrial
             // fibrillation, and a perfectly symmetric gait.
             .atrialFibrillationBurden, .walkingAsymmetry,
             // Zero is the honest reading before the first dose and long after
             // the last — dropping it would make the curve start mid-air.
             .activeMedicationLevel:
            return false
        }
    }
}

public extension MetricType {
    /// The range a reading has to fall in to be a reading at all.
    ///
    /// **Why an upper bound was needed.** Until this existed the only rule was
    /// `value > 0`, and the user's own data export showed why that is not
    /// enough: their modelled resting heart rate ran to **119 bpm** against a
    /// median of 56 — one degenerate Oura record whose entire surviving
    /// heart-rate series was a single sample taken while awake. A baseline is a
    /// 28-day rolling window, so one such value inflates the standard deviation
    /// roughly tenfold and **silences the resting-heart-rate anomaly detector
    /// for four weeks**. Readiness, the multi-signal early warning and the
    /// vitals scan all read that z-score. A bad reading does not just show a
    /// wrong number; it stops the app noticing anything.
    ///
    /// **These are survival limits, not clinical ones**, and that distinction is
    /// the whole design. The job is to reject values a living person cannot
    /// produce, never to reject values that are merely *bad news*. A resting
    /// heart rate of 95 is a finding and is kept; 119 as a sleeping low is an
    /// artefact. Where a real reading and an artefact genuinely overlap the
    /// bound goes wide, because a missed anomaly is recoverable and a discarded
    /// real measurement is not.
    ///
    /// `nil` means unbounded above — for metrics where no honest ceiling exists
    /// (a step count, a duration) or where `requiresPositiveValue` already says
    /// everything worth saying.
    var plausibleRange: ClosedRange<Double>? {
        switch self {
        // Heart. Documented human resting extremes run from ~27 bpm (endurance
        // athletes, and lower in case reports) to tachycardia; a *resting* or
        // *sleeping* figure above 120 is a measurement of something other than
        // rest. Instantaneous heart rate gets the wide band, because a real
        // maximum during exercise reaches it.
        case .restingHeartRate: return 25...120
        case .walkingHeartRateAverage: return 30...180
        case .heartRate: return 25...240
        // HRV. rMSSD and SDNN both live in single-to-triple-digit milliseconds;
        // a reading past ~400 ms is an artefact of a dropped beat, not autonomic
        // tone.
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN: return 1...400
        case .heartRateRecovery: return 0...100
        // Respiration and oxygenation. SpO₂ below 70 is outside what consumer
        // pulse oximetry is validated to report at all, and above 100 is
        // impossible.
        case .respiratoryRate: return 4...60
        case .oxygenSaturation: return 70...100
        // Pressure. Above these a cuff is misreporting; a hypertensive crisis is
        // well inside the band and must stay inside it.
        case .bloodPressureSystolic: return 60...300
        case .bloodPressureDiastolic: return 30...200
        // Temperature, in °C. Survivable core temperature, generously bounded.
        case .bodyTemperature, .skinTemperature: return 25...45
        // Body. Deliberately wide: these are the metrics where being wrong about
        // somebody's body is worst, and a scale reporting a real 200 kg must be
        // believed.
        case .bodyMass, .leanBodyMass, .muscleMass: return 20...400
        case .boneMass: return 0.5...10
        case .bodyFatPercentage, .bodyWaterPercentage: return 1...80
        case .height: return 0.5...2.6
        case .bloodGlucose: return 1...40
        // Percentages that are percentages.
        case .walkingSteadiness, .walkingAsymmetry, .sleepEfficiency,
             .atrialFibrillationBurden, .peripheralPerfusionIndex:
            return 0...100
        // Fitness and provider estimates.
        case .vo2Max: return 5...100
        case .vascularAge: return 10...120
        case .dayStrain: return 0...21          // Whoop's own scale
        // Generous: the highest rung of any GLP-1 ladder here is 15 mg, and a
        // weekly injectable accumulates to several times a single dose before
        // it plateaus. 200 mg is not reachable by any regimen this app models,
        // so anything past it is a unit error rather than a body.
        case .activeMedicationLevel: return 0...200
        // A day has 1440 minutes, so this ceiling is arithmetic rather than
        // clinical. Zero is legitimate — a day away from the phone.
        case .screenTimeMinutes: return 0...1440
        // No honest ceiling, or none needed. Sleep duration is bounded by the
        // day; a very long recorded sleep is usually a real illness or a real
        // device error, and the app should show it rather than hide it.
        case .sleepDurationHours: return 0...24
        case .sleepOnset: return -12...12       // the encoding's own range
        case .sleepDeepMinutes, .sleepRemMinutes: return 0...(24 * 60)
        // Twelve hours awake in bed is an extraordinary night, not an
        // impossible one; the bound rejects only what a night cannot hold.
        case .sleepLatencyMinutes: return 0...(12 * 60)
        case .skinTemperatureDeviation: return -15...15
        case .stepCount, .activeEnergyBurned: return nil
        // A single sample is an accrual interval, and a day holds 1,440 minutes.
        case .exerciseMinutes: return 0...1440
        }
    }
}

public extension Array where Element == HealthMetricSample {
    /// Drop samples that can't be real — a non-positive value for a metric that
    /// must be positive, or one outside the metric's `plausibleRange`. Keeps
    /// everything else untouched. This prevents "0 bpm" resting-heart-rate tiles
    /// (e.g. from an Oura day with no HR data), stops placeholder zeros from
    /// dragging multi-source averages down, and stops a single artefact from
    /// setting a baseline nothing can then depart from.
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
            let positiveEnough = !sample.type.requiresPositiveValue || sample.value > 0
            let inRange = sample.type.plausibleRange.map { $0.contains(sample.value) } ?? true
            if positiveEnough && inRange {
                kept.append(sample)
            } else {
                dropped.append(sample)
            }
        }
        return (kept, dropped)
    }
}
