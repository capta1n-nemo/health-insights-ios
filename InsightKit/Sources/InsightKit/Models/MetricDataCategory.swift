import Foundation

/// Which group a metric appears under in the Data tab.
///
/// ## Why this is an exhaustive switch and not a list in the view
///
/// The user's rule after the cross-card audit: *"the more connectors we have, the
/// more populated into the data section… make rules so a new source gracefully
/// populates across the cards."* The Data tab's metric list **was** a
/// hand-written array in the app target, and it had already drifted — sleep
/// latency and vascular age were real metrics with data that appeared nowhere on
/// it, because adding a `MetricType` and adding it to that array were two steps
/// and the second was forgotten.
///
/// So the mapping lives here, exhaustive over `MetricType`. A new connector's
/// metric cannot compile without a category, and the moment it has one it appears
/// in the Data tab automatically — the "graceful population" the rule asks for,
/// enforced by the compiler rather than by memory. `MetricDataCategoryTests`
/// pins the two that had silently gone missing.
public enum MetricDataCategory: String, Sendable, CaseIterable {
    case heart = "Heart & circulation"
    case body = "Body"
    case sleepRecovery = "Sleep & recovery"
    case activity = "Activity & mobility"
    /// Its own group rather than a row under Activity: what went in and what
    /// was burned are different questions, and a reader looking for what they
    /// ate should not have to find it under exercise.
    case nutrition = "Nutrition"
    /// Sound exposure — the two daily dose figures, plus the raw audio fields
    /// `RawFieldGrouping.Group.hearing` files beside them. "Hearing" rather
    /// than "Sound" because it is the word Apple Health uses for the same
    /// section, so it is the heading the reader has already learnt to look
    /// under. Before the doses existed this section lived only on the raw side
    /// (`canonicalCategory: nil`); promoting the metrics without moving the raw
    /// fields in with them would have made two "Hearing" headings — the exact
    /// two-taxonomies bug the nutrition section already paid for.
    case hearing = "Hearing"
    /// Not in the grouped metric list because it has its own Data-tab section:
    /// blood pressure is a paired reading (its own domain), and the modelled
    /// medication level lives in the medication domain. Kept as an explicit case
    /// rather than an exclusion so a new metric has to *decide* it belongs to
    /// another section — silence is not an option.
    case ownDomain

    /// The four groups the Data tab actually renders, in order.
    public static var listed: [MetricDataCategory] {
        allCases.filter { $0 != .ownDomain }
    }
}

public extension MetricType {
    /// The Data-tab group this metric appears in.
    var dataCategory: MetricDataCategory {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage,
             .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
             .heartRateRecovery, .atrialFibrillationBurden, .vo2Max,
             .vascularAge, .respiratoryRate, .oxygenSaturation,
             .peripheralPerfusionIndex:
            return .heart
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
             .boneMass, .bodyWaterPercentage, .height, .bloodGlucose,
             // Circumferences sit with the rest of the body, not in a domain of
             // their own: the scan they come from gets its own Data-tab section,
             // but a waist measurement read off a tape belongs beside a weight.
             .waistCircumference, .hipCircumference, .chestCircumference,
             .neckCircumference, .shoulderWidth, .thighCircumference,
             .upperArmCircumference:
            return .body
        case .sleepDurationHours, .sleepOnset, .sleepEfficiency,
             .sleepDeepMinutes, .sleepRemMinutes, .sleepLatencyMinutes,
             .bodyTemperature, .skinTemperature, .skinTemperatureDeviation,
             .dayStrain:
            return .sleepRecovery
        case .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat,
             .dietarySaturatedFat, .dietarySugar, .dietaryFibre,
             .dietarySodium, .dietaryPotassium, .dietaryWater,
             .dietaryCaffeine,
             .dietaryMonounsaturatedFat, .dietaryPolyunsaturatedFat,
             .dietaryCholesterol, .dietaryCalcium, .dietaryIron,
             .dietaryMagnesium, .dietaryZinc, .dietaryVitaminC,
             .dietaryVitaminA, .dietaryVitaminD, .dietaryVitaminB12:
            return .nutrition
        case .stepCount, .activeEnergyBurned, .exerciseMinutes,
             .distanceWalkingRunning, .flightsClimbed, .physicalEffort,
             .walkingSteadiness, .walkingAsymmetry,
             .walkingSpeed, .walkingStepLength, .walkingDoubleSupport,
             .screenTimeMinutes:
            return .activity
        case .bloodPressureSystolic, .bloodPressureDiastolic, .activeMedicationLevel:
            return .ownDomain
        // Not `.activity` and not `.sleepRecovery`: hearing is its own subject,
        // Apple Health gives it its own section, and the raw dBA fields these
        // are computed from already group under a "Hearing" heading — the dose
        // belongs beside its own ingredients.
        case .environmentalSoundDose, .headphoneSoundDose:
            return .hearing
        }
    }

    /// Metrics in one Data-tab group, in the enum's own declaration order — the
    /// same order the Data tab has always listed them.
    static func metrics(in category: MetricDataCategory) -> [MetricType] {
        allCases.filter { $0.dataCategory == category }
    }
}
