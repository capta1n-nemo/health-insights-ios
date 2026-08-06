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
             .waistCircumference, .hipCircumference, .chestCircumference,
             .neckCircumference, .shoulderWidth, .thighCircumference,
             .upperArmCircumference,
             .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .height,
             .bodyTemperature, .skinTemperature,
             // A living person cannot read zero on any of these; a zero is a
             // provider placeholder.
             .bloodGlucose, .peripheralPerfusionIndex, .heartRateRecovery,
             .walkingSteadiness,
             // Nobody walks at nought metres a second, takes a step of no
             // length, or spends none of a stride on two feet. All three zeros
             // are the provider saying "no walking bouts", which is a missing
             // day and not a very slow one.
             .walkingSpeed, .walkingStepLength, .walkingDoubleSupport,
             // Nobody eats nothing. A zero on any of these is a day the reader
             // did not log — every one is a sum of logged items, so an absent
             // log and a genuine zero are indistinguishable, and charting the
             // zero would draw a fast that never happened.
             .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat,
             .dietarySaturatedFat, .dietarySugar, .dietaryFibre,
             .dietarySodium, .dietaryPotassium, .dietaryWater,
             .dietaryCaffeine,
             .dietaryMonounsaturatedFat, .dietaryPolyunsaturatedFat,
             .dietaryCholesterol, .dietaryCalcium, .dietaryIron,
             .dietaryMagnesium, .dietaryZinc, .dietaryVitaminC,
             .dietaryVitaminA, .dietaryVitaminD, .dietaryVitaminB12,
             // 0 dBA is the threshold of hearing — a level neither a wrist
             // microphone nor a headphone output measurement can genuinely
             // report, and one `SoundDoseModel` cannot produce from real
             // samples (it emits nothing for a day with no samples rather
             // than a zero). A zero here is a placeholder, exactly as a
             // 0 bpm heart rate is.
             .environmentalSoundDose, .headphoneSoundDose:
            return true
        case .dayStrain, .stepCount, .activeEnergyBurned,
             // A day with no exercise is a real day.
             .exerciseMinutes,
             // A day at home covers no distance and climbs no stairs, and a
             // watch worn while sitting still records effort at rest. Zero is
             // a reading on all three.
             .distanceWalkingRunning, .flightsClimbed, .physicalEffort,
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
             // And for this one: a night whose breathing never wavered reads
             // zero, and dropping it would hide exactly the calm nights the
             // trend needs for contrast.
             .breathingDisturbanceIndex,
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
        // Dimensions. Wide for the same reason the masses above are: being
        // wrong about somebody's body is worst here, and these bounds exist to
        // reject a unit slip (a waist in metres, or in inches read as cm), not
        // to disagree with a real measurement.
        case .waistCircumference, .hipCircumference, .chestCircumference:
            return 30...250
        case .shoulderWidth: return 25...90
        case .thighCircumference, .upperArmCircumference: return 10...120
        case .neckCircumference: return 20...80
        case .bloodGlucose: return 1...40
        // Percentages that are percentages.
        case .walkingSteadiness, .walkingAsymmetry, .sleepEfficiency,
             .atrialFibrillationBurden, .peripheralPerfusionIndex,
             .walkingDoubleSupport:
            return 0...100
        // A shuffle is around 0.4 m/s and a racewalker manages about 4. Wide
        // enough to hold any real gait, tight enough to catch a value that
        // arrived in km/h.
        case .walkingSpeed: return 0.1...4
        // A toddler's step is roughly 25 cm and the longest adult stride is
        // under a metre. Anything outside this arrived in the wrong unit.
        case .walkingStepLength: return 10...150
        // Fitness and provider estimates.
        case .vo2Max: return 5...100
        case .vascularAge: return 10...120
        case .dayStrain: return 0...21          // Whoop's own scale
        // A proprietary index with no published ceiling (107 nights on the
        // reader's export, 2026-08-06, all comfortably inside this). The bound
        // rejects a value that arrived as something else entirely — a
        // percentage of the night, a count of minutes — never a bad night.
        case .breathingDisturbanceIndex: return 0...100
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
        // A per-bout sample, not a day: the ceiling rejects a metres-for-
        // kilometres unit slip (a 5 km run arriving as 5,000) while leaving
        // room for an ultramarathon logged as one bout.
        case .distanceWalkingRunning: return 0...300
        // Flights, per sample. The record for stair climbing in a day is in
        // the low thousands of floors; this rejects a unit error, nothing else.
        case .flightsClimbed: return 0...5_000
        // METs. Resting is 1 by definition, and the highest sustained human
        // efforts reach roughly 23 (elite distance running). The floor is 0
        // rather than 1 because Apple writes 0 for intervals it could not
        // judge, and `requiresPositiveValue` deliberately lets those through —
        // see `EffortIntensityModel`, which drops them by band rather than by
        // sanitizer, so a zero-effort hour stays visible as data.
        case .physicalEffort: return 0...30
        // A survival bound, not a dietary one. Recorded human intakes reach
        // well past 10,000 kcal in a day (competitive eating, ultra-endurance
        // racing), so the ceiling only rejects a unit error — a joule figure
        // that reached the parser unconverted lands two orders of magnitude
        // above this. `requiresPositiveValue` says the rest.
        case .dietaryEnergy: return 1...25_000
        // Unit-error catchers, not dietary judgements — every one of these
        // arrives in grams from a source that stores kilograms (Shotsy) or in
        // milligrams from one that stores grams, so the bound only has to be
        // below a 1,000x slip and above anything a person could eat.
        case .dietaryProtein, .dietarySaturatedFat: return 1...500
        case .dietaryCarbohydrates: return 1...2_000
        case .dietaryFat: return 1...1_000
        case .dietarySugar: return 1...1_500
        case .dietaryFibre: return 1...300
        case .dietarySodium: return 1...50_000
        case .dietaryPotassium: return 1...30_000
        // Litres. Thirty is past the point where water itself is the emergency.
        case .dietaryWater: return 0.1...30
        case .dietaryCaffeine: return 1...3_000
        // **The micronutrients, and here the bound earns its keep.** The stated
        // rule above is that a range only has to sit below a 1,000× unit slip
        // and above anything a person could eat — and a 1,000× slip is exactly
        // the live hazard in this group, because three of the eleven are in
        // micrograms and the other eight in milligrams. A vitamin D reported in
        // mg rather than mcg is a thousandfold overstatement that would
        // otherwise chart happily.
        case .dietaryMonounsaturatedFat, .dietaryPolyunsaturatedFat: return 1...1_000
        case .dietaryCholesterol: return 1...10_000
        case .dietaryCalcium: return 1...20_000
        case .dietaryIron: return 0.1...1_000
        case .dietaryMagnesium: return 1...10_000
        case .dietaryZinc: return 0.1...1_000
        case .dietaryVitaminC: return 1...50_000
        // Micrograms. A generous supplement is thousands of mcg; a milligram
        // slip lands in the millions and is rejected.
        case .dietaryVitaminA: return 1...100_000
        case .dietaryVitaminD: return 0.1...10_000
        case .dietaryVitaminB12: return 0.1...50_000
        // A single sample is an accrual interval, and a day holds 1,440 minutes.
        case .exerciseMinutes: return 0...1440
        // Survival limits on the decibel scale, wide on both ends. Below
        // 10 dBA is quieter than any room a consumer microphone can resolve —
        // an anechoic-chamber figure, so from these sensors it is an artefact.
        // Above 140 dBA is instant-injury territory (a jet at takeoff
        // distance) that no *day-long equivalent level* can honestly reach:
        // a true LEQ of 140 would mean the whole measured day was spent at
        // it. Real loud days — concerts, power tools — land in the 80s and
        // 90s and must stay inside the band, and they do, five-fold over.
        case .environmentalSoundDose, .headphoneSoundDose: return 10...140
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
