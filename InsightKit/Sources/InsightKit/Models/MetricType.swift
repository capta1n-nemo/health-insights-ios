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

    // Body dimensions — a tape measure, or a camera/LiDAR scan.
    //
    // Seven of the fourteen-to-twenty locations a dedicated scanner takes. The
    // rest — left and right separately, forearm, calf, underbust, inseam — live
    // inside `BodyScan` and are surfaced on the scan's own page. A `MetricType`
    // is for what earns a chart, a Data-tab row and a reference range; the rest
    // is scan data, and promoting all twenty would cost nine exhaustive
    // switches each to draw twenty near-identical lines.
    //
    // A paired site (thigh, upper arm) carries the **mean of left and right**
    // here, with the difference reported by `BodySymmetry` instead: two lines a
    // centimetre apart say less than one line and a symmetry figure.
    case waistCircumference        // cm
    case hipCircumference          // cm
    case chestCircumference        // cm
    case neckCircumference         // cm
    case shoulderWidth             // cm
    case thighCircumference        // cm — mean of left and right
    case upperArmCircumference     // cm — mean of left and right

    // Activity & sleep
    case stepCount                 // count
    case activeEnergyBurned        // kcal
    /// Minutes of at-least-moderate activity (Apple's "exercise minute" accrues
    /// at brisk-walk intensity and above, which is the WHO guideline's own
    /// moderate-intensity definition — that match is why this one, alone of the
    /// activity metrics, can be scored against a published dose).
    case exerciseMinutes           // min

    // Nutrition
    /// What the reader ate, as energy. **The one dietary quantity the app
    /// models**, and it is charted rather than scored: there is no calorie
    /// figure this app can call better or worse without knowing what somebody
    /// is aiming for, and a band drawn on this chart would be a target the app
    /// has no business setting. Arrives from Shotsy's backup in joules.
    case dietaryEnergy             // kcal
    // The macros and the six the published guidance actually names. Everything
    // past these — the vitamins, the minerals beyond sodium and potassium, the
    // unsaturated fat splits — stays in the raw layer, visible in the Data tab
    // and unscored: a metric no card consults is a chart nobody asked for.
    case dietaryProtein            // g
    case dietaryCarbohydrates      // g
    case dietaryFat                // g — total
    case dietarySaturatedFat       // g
    case dietarySugar              // g
    case dietaryFibre              // g
    case dietarySodium             // mg
    case dietaryPotassium          // mg
    case dietaryWater              // L
    case dietaryCaffeine           // mg
    // **The eleven micronutrients, promoted 2026-08-05 at the reader's
    // decision.** The comment above says they stay raw because "a metric no
    // card consults is a chart nobody asked for", and that was the right call
    // while nothing read them — but it also meant 686 rows of the reader's own
    // record filed under "Other data" at the very bottom of the Data tab,
    // because the Nutrition section is generated from `MetricType` alone.
    //
    // ⚠️ **Every one of these has a `referenceRange` of nil, and the reason is
    // the same for all eleven**: published intakes are sex-specific and several
    // are age-specific too (iron is 8 mg for men and 18 mg for women — a single
    // band would be wrong for half its readers by more than twofold). This
    // switch has no sex, exactly as it has none for waist circumference, which
    // was decided the same way on 2026-08-03. The bands belong in the Nutrition
    // card's own table, where the profile is in scope — the same place protein
    // per kilogram and the sex-specific water figure already live.
    case dietaryMonounsaturatedFat // g
    case dietaryPolyunsaturatedFat // g
    case dietaryCholesterol        // mg
    case dietaryCalcium            // mg
    case dietaryIron               // mg
    case dietaryMagnesium          // mg
    case dietaryZinc               // mg
    case dietaryVitaminC           // mg
    // The three reported in micrograms rather than milligrams. Getting this
    // wrong by a factor of a thousand is the whole hazard of this group, so the
    // unit is on the case, in `unit`, and in `plausibleRange` — three places
    // that would have to agree on a mistake.
    case dietaryVitaminA           // mcg RAE
    case dietaryVitaminD           // mcg
    case dietaryVitaminB12         // mcg
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
    /// The three gait measures the iPhone computes from ordinary walking.
    ///
    /// **Measured on 2026-08-05: 1,093 days each, 91 of the last 90 and 366 of
    /// the last 365** — the densest unused signal in the reader's whole export
    /// by a wide margin, and nothing else is close. They come from the phone in
    /// a pocket, so they are the only vitals here that survive a night the ring
    /// spent on charge and a week the watch spent in a drawer.
    ///
    /// ⚠️ **They describe walking the phone saw, not all walking.** A day
    /// carrying it in a bag, a session on a treadmill holding the rails, an hour
    /// of gym work — each looks like less walking rather than different walking.
    /// Anything reading these has to say so, because "your walking speed is
    /// declining" is heard as a statement about ageing.
    case walkingSpeed              // m/s — average over the phone's walking bouts
    case walkingStepLength         // cm — distance between successive heel strikes
    case walkingDoubleSupport      // % of the gait cycle with both feet down
    /// mg of GLP-1 still active, from the reader's logged doses and the
    /// compound's published half-life.
    ///
    /// **Modelled, not measured, and the only metric here that is.** Nothing
    /// on the phone can sense a drug level; `PharmacokineticsModel` computes
    /// this from doses the reader entered and a published half-life. It earns a
    /// `MetricType` anyway because the reader asked to see it *against* their
    /// weight and body fat on the one chart that draws contributors — and that
    /// chart, the baseline machinery and the overlay all speak `MetricType`.
    ///
    /// Two things keep it honest: every sample carries `MetricSource.calculated`
    /// rather than a device, and it is scored at **weight 0** on the one card
    /// that reads it. See `BodyCompositionInsight.trackedNotScored`.
    case activeMedicationLevel     // mg of GLP-1 still active — modelled
    /// Minutes of screen time in a day.
    ///
    /// **Entered, not sensed, and it cannot be otherwise.** Apple sandboxes
    /// Screen Time deliberately: `DeviceActivityReportExtension` runs read-only
    /// so its numbers cannot reach the containing app (App Groups and shared
    /// files all fail by design), the entitlement needs a paid team, and the
    /// licence forbids the data leaving the device. Researched 2026-08-02 — see
    /// `docs/activeContext.md` before attempting an automatic integration.
    ///
    /// So the reader supplies it, by hand or from a Shortcuts automation, and
    /// the source is `.manual`. It earns a `MetricType` because it is a real
    /// daily series the sleep-onset model reads as a driver — the reader's own
    /// question, "is it tech time?".
    case screenTimeMinutes         // min/day — entered by the reader

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
        case .waistCircumference: return "Waist"
        case .hipCircumference: return "Hips"
        case .chestCircumference: return "Chest"
        case .neckCircumference: return "Neck"
        case .shoulderWidth: return "Shoulders"
        case .thighCircumference: return "Thigh"
        case .upperArmCircumference: return "Upper Arm"
        case .stepCount: return "Steps"
        case .activeEnergyBurned: return "Active Energy"
        case .exerciseMinutes: return "Exercise Minutes"
        case .dietaryEnergy: return "Calories Eaten"
        case .dietaryProtein: return "Protein"
        case .dietaryCarbohydrates: return "Carbohydrates"
        case .dietaryFat: return "Fat"
        case .dietarySaturatedFat: return "Saturated Fat"
        case .dietarySugar: return "Sugar"
        case .dietaryFibre: return "Fibre"
        case .dietarySodium: return "Sodium"
        case .dietaryPotassium: return "Potassium"
        case .dietaryMonounsaturatedFat: return "Monounsaturated Fat"
        case .dietaryPolyunsaturatedFat: return "Polyunsaturated Fat"
        case .dietaryCholesterol: return "Dietary Cholesterol"
        case .dietaryCalcium: return "Calcium"
        case .dietaryIron: return "Iron"
        case .dietaryMagnesium: return "Magnesium"
        case .dietaryZinc: return "Zinc"
        case .dietaryVitaminC: return "Vitamin C"
        case .dietaryVitaminA: return "Vitamin A"
        case .dietaryVitaminD: return "Vitamin D"
        case .dietaryVitaminB12: return "Vitamin B12"
        case .dietaryWater: return "Water"
        case .dietaryCaffeine: return "Caffeine"
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
        case .walkingSpeed: return "Walking Speed"
        case .walkingStepLength: return "Step Length"
        // Not "Double Support Percentage". The share of each stride with both
        // feet on the ground — it rises when someone is being careful, which is
        // the whole reason to watch it.
        case .walkingDoubleSupport: return "Double Support"
        // "On board" was the pharmacology jargon and nobody outside it reads
        // that as "still in you". The user, 2026-08-02: *"renamed to something
        // more understandable, like 'medication in your blood' or something
        // just better."* "In your system" rather than "in your blood" because
        // the model is a whole-body compartment, not a plasma assay.
        case .activeMedicationLevel: return "Medication In Your System"
        case .screenTimeMinutes: return "Screen Time"
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
        case .waistCircumference, .hipCircumference, .chestCircumference,
             .neckCircumference, .shoulderWidth, .thighCircumference,
             .upperArmCircumference:
            return "cm"
        case .stepCount: return "steps"
        case .activeEnergyBurned: return "kcal"
        case .exerciseMinutes: return "min"
        case .dietaryEnergy: return "kcal"
        case .dietaryProtein, .dietaryCarbohydrates, .dietaryFat,
             .dietarySaturatedFat, .dietarySugar, .dietaryFibre,
             .dietaryMonounsaturatedFat, .dietaryPolyunsaturatedFat:
            return "g"
        case .dietarySodium, .dietaryPotassium, .dietaryCaffeine,
             .dietaryCholesterol, .dietaryCalcium, .dietaryIron,
             .dietaryMagnesium, .dietaryZinc, .dietaryVitaminC:
            return "mg"
        // Micrograms, and the thousandfold gap to the line above is why the
        // three are listed separately rather than folded in.
        case .dietaryVitaminA, .dietaryVitaminD, .dietaryVitaminB12: return "mcg"
        case .dietaryWater: return "L"
        case .sleepDurationHours: return "h"
        // Empty: the formatter renders this as a clock time, and "23:12 h" is
        // not a thing.
        case .sleepOnset: return ""
        case .sleepEfficiency: return "%"
        case .sleepDeepMinutes, .sleepRemMinutes, .sleepLatencyMinutes: return "min"
        case .screenTimeMinutes: return "min"
        case .bodyTemperature, .skinTemperature, .skinTemperatureDeviation: return "°C"
        case .bloodGlucose: return "mmol/L"
        case .peripheralPerfusionIndex, .atrialFibrillationBurden,
             .walkingSteadiness, .walkingAsymmetry, .walkingDoubleSupport: return "%"
        case .walkingSpeed: return "m/s"
        // Centimetres, like the circumferences and unlike height. 72 cm is a
        // step; 0.72 m is a sentence about a step.
        case .walkingStepLength: return "cm"
        case .activeMedicationLevel: return "mg"
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
