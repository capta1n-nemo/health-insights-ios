import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
import InsightKit

/// Reads Apple Health data and normalises it into `InsightKit` canonical samples.
/// All HealthKit specifics live here; the rest of the app only sees
/// `HealthMetricSample`. Wrapped in `canImport` so the pure package and any
/// non-HealthKit platform still compile.
@MainActor
final class HealthKitService {
    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    /// Whether HealthKit is usable on this device (false on iPad/Mac/simulator w/o data).
    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    #if canImport(HealthKit)
    /// The quantity types we read, paired with their canonical metric + unit.
    private var readMap: [(HKQuantityTypeIdentifier, MetricType, HKUnit)] {
        [
            (.heartRate, .heartRate, HKUnit.count().unitDivided(by: .minute())),
            (.restingHeartRate, .restingHeartRate, HKUnit.count().unitDivided(by: .minute())),
            (.walkingHeartRateAverage, .walkingHeartRateAverage, HKUnit.count().unitDivided(by: .minute())),
            (.heartRateVariabilitySDNN, .heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli)),
            (.vo2Max, .vo2Max, HKUnit(from: "ml/kg*min")),
            (.respiratoryRate, .respiratoryRate, HKUnit.count().unitDivided(by: .minute())),
            (.oxygenSaturation, .oxygenSaturation, .percent()),
            (.bloodPressureSystolic, .bloodPressureSystolic, .millimeterOfMercury()),
            (.bloodPressureDiastolic, .bloodPressureDiastolic, .millimeterOfMercury()),
            (.bodyMass, .bodyMass, .gramUnit(with: .kilo)),
            (.bodyFatPercentage, .bodyFatPercentage, .percent()),
            (.leanBodyMass, .leanBodyMass, .gramUnit(with: .kilo)),
            (.height, .height, .meter()),
            (.stepCount, .stepCount, .count()),
            (.activeEnergyBurned, .activeEnergyBurned, .kilocalorie()),
            // Promoted out of the raw pile because it earned a score: Apple's
            // exercise minute accrues at brisk-walk intensity and above, which
            // is the WHO guideline's own moderate-intensity definition, so the
            // Fitness card can weigh the week's dose against a published band
            // (`ActivityDoseModel`). Removed from `otherQuantityIdentifiers`
            // below — a metric must not arrive through both routes.
            (.appleExerciseTime, .exerciseMinutes, .minute()),
            // Promoted out of the raw "other data" pile: these are measurements
            // with real units and real baselines, and Vitals Check now reads
            // them.
            //
            // A genuine core reading — an oral or temporal thermometer. This is
            // the only route into `.bodyTemperature` from Apple Health, which is
            // what lets that metric keep clinical bounds.
            (.bodyTemperature, .bodyTemperature, .degreeCelsius()),
            // Apple Watch Series 8 and later records an absolute wrist
            // temperature every night, and the app read it nowhere — not in this
            // map, not in the raw identifiers below, dropped entirely. Skin, so
            // `.skinTemperature`: through core bounds it would report every
            // wearer as hypothermic, which is precisely the bug this change
            // exists to fix.
            (.appleSleepingWristTemperature, .skinTemperature, .degreeCelsius()),
            (.bloodGlucose, .bloodGlucose,
             HKUnit.moleUnit(withMolarMass: HKUnitMolarMassBloodGlucose)
                .unitDivided(by: .liter())),
            (.peripheralPerfusionIndex, .peripheralPerfusionIndex, .percent()),
            (.atrialFibrillationBurden, .atrialFibrillationBurden, .percent()),
            (.heartRateRecoveryOneMinute, .heartRateRecovery,
             HKUnit.count().unitDivided(by: .minute())),
            (.appleWalkingSteadiness, .walkingSteadiness, .percent()),
            (.walkingAsymmetryPercentage, .walkingAsymmetry, .percent())
        ]
    }

    /// Metrics HealthKit hands over as a 0–1 fraction and we store as 0–100.
    private static let percentageMetrics: Set<MetricType> = [
        .bodyFatPercentage, .oxygenSaturation, .peripheralPerfusionIndex,
        .atrialFibrillationBurden, .walkingSteadiness, .walkingAsymmetry
    ]

    /// Additional quantity types we import as raw "other" data (not yet modelled
    /// as canonical metrics). Listed as raw identifier strings so unknown ones on
    /// older SDKs simply resolve to nil and are skipped. This is how we "scrape
    /// everything" — activity, respiratory, nutrition, environmental, etc.
    private static let otherQuantityIdentifiers: [String] = [
        // Activity & mobility
        "HKQuantityTypeIdentifierDistanceWalkingRunning", "HKQuantityTypeIdentifierDistanceCycling",
        "HKQuantityTypeIdentifierDistanceSwimming", "HKQuantityTypeIdentifierDistanceWheelchair",
        "HKQuantityTypeIdentifierDistanceDownhillSnowSports", "HKQuantityTypeIdentifierBasalEnergyBurned",
        "HKQuantityTypeIdentifierFlightsClimbed",
        "HKQuantityTypeIdentifierAppleStandTime", "HKQuantityTypeIdentifierAppleMoveTime",
        "HKQuantityTypeIdentifierPushCount", "HKQuantityTypeIdentifierSwimmingStrokeCount",
        "HKQuantityTypeIdentifierWalkingSpeed", "HKQuantityTypeIdentifierWalkingStepLength",
        "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage",
        "HKQuantityTypeIdentifierSixMinuteWalkTestDistance", "HKQuantityTypeIdentifierStairAscentSpeed",
        "HKQuantityTypeIdentifierStairDescentSpeed", "HKQuantityTypeIdentifierRunningSpeed",
        "HKQuantityTypeIdentifierRunningPower", "HKQuantityTypeIdentifierRunningStrideLength",
        "HKQuantityTypeIdentifierRunningVerticalOscillation", "HKQuantityTypeIdentifierRunningGroundContactTime",
        "HKQuantityTypeIdentifierCyclingSpeed", "HKQuantityTypeIdentifierCyclingPower",
        "HKQuantityTypeIdentifierCyclingCadence", "HKQuantityTypeIdentifierPhysicalEffort",
        "HKQuantityTypeIdentifierNumberOfTimesFallen",
        // Cardio / respiratory / other vitals
        "HKQuantityTypeIdentifierForcedVitalCapacity",
        "HKQuantityTypeIdentifierForcedExpiratoryVolume1", "HKQuantityTypeIdentifierPeakExpiratoryFlowRate",
        "HKQuantityTypeIdentifierInhalerUsage", "HKQuantityTypeIdentifierBasalBodyTemperature", "HKQuantityTypeIdentifierBloodAlcoholContent", "HKQuantityTypeIdentifierElectrodermalActivity",
        "HKQuantityTypeIdentifierInsulinDelivery", "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages",
        // Body
        "HKQuantityTypeIdentifierBodyMassIndex", "HKQuantityTypeIdentifierWaistCircumference",
        // Environment
        "HKQuantityTypeIdentifierUVExposure", "HKQuantityTypeIdentifierEnvironmentalAudioExposure",
        "HKQuantityTypeIdentifierHeadphoneAudioExposure", "HKQuantityTypeIdentifierEnvironmentalSoundReduction",
        "HKQuantityTypeIdentifierTimeInDaylight", "HKQuantityTypeIdentifierUnderwaterDepth",
        "HKQuantityTypeIdentifierWaterTemperature",
        // Nutrition
        "HKQuantityTypeIdentifierDietaryEnergyConsumed", "HKQuantityTypeIdentifierDietaryCarbohydrates",
        "HKQuantityTypeIdentifierDietaryFiber", "HKQuantityTypeIdentifierDietarySugar",
        "HKQuantityTypeIdentifierDietaryFatTotal", "HKQuantityTypeIdentifierDietaryFatSaturated",
        "HKQuantityTypeIdentifierDietaryFatMonounsaturated", "HKQuantityTypeIdentifierDietaryFatPolyunsaturated",
        "HKQuantityTypeIdentifierDietaryCholesterol", "HKQuantityTypeIdentifierDietaryProtein",
        "HKQuantityTypeIdentifierDietarySodium", "HKQuantityTypeIdentifierDietaryPotassium",
        "HKQuantityTypeIdentifierDietaryCalcium", "HKQuantityTypeIdentifierDietaryIron",
        "HKQuantityTypeIdentifierDietaryWater", "HKQuantityTypeIdentifierDietaryCaffeine",
        "HKQuantityTypeIdentifierDietaryVitaminC", "HKQuantityTypeIdentifierDietaryVitaminD",
        "HKQuantityTypeIdentifierDietaryVitaminA", "HKQuantityTypeIdentifierDietaryVitaminB12",
        "HKQuantityTypeIdentifierDietaryMagnesium", "HKQuantityTypeIdentifierDietaryZinc"
    ]

    /// Category (event/state) types imported as raw "other" data.
    private static let otherCategoryIdentifiers: [String] = [
        "HKCategoryTypeIdentifierMindfulSession", "HKCategoryTypeIdentifierAppleStandHour",
        "HKCategoryTypeIdentifierHighHeartRateEvent", "HKCategoryTypeIdentifierLowHeartRateEvent",
        "HKCategoryTypeIdentifierIrregularHeartRhythmEvent", "HKCategoryTypeIdentifierAudioExposureEvent",
        "HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent", "HKCategoryTypeIdentifierHeadphoneAudioExposureEvent",
        "HKCategoryTypeIdentifierToothbrushingEvent", "HKCategoryTypeIdentifierHandwashingEvent",
        "HKCategoryTypeIdentifierSexualActivity", "HKCategoryTypeIdentifierMenstrualFlow",
        "HKCategoryTypeIdentifierLowCardioFitnessEvent", "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent",
        "HKCategoryTypeIdentifierNausea", "HKCategoryTypeIdentifierHeadache", "HKCategoryTypeIdentifierFatigue",
        "HKCategoryTypeIdentifierDizziness", "HKCategoryTypeIdentifierFever", "HKCategoryTypeIdentifierCoughing",
        "HKCategoryTypeIdentifierShortnessOfBreath", "HKCategoryTypeIdentifierChestTightnessOrPain",
        "HKCategoryTypeIdentifierAbdominalCramps", "HKCategoryTypeIdentifierBloating",
        "HKCategoryTypeIdentifierHeartburn", "HKCategoryTypeIdentifierSleepChanges",
        "HKCategoryTypeIdentifierMoodChanges", "HKCategoryTypeIdentifierHotFlashes"
    ]

    private var otherQuantityTypes: [HKQuantityType] {
        Self.otherQuantityIdentifiers.compactMap {
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: $0))
        }
    }

    private var otherCategoryTypes: [HKCategoryType] {
        Self.otherCategoryIdentifiers.compactMap {
            HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: $0))
        }
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for (id, _, _) in readMap {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        // Characteristics used to pre-fill the onboarding "basics" step.
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        if let blood = HKObjectType.characteristicType(forIdentifier: .bloodType) { types.insert(blood) }
        if let skin = HKObjectType.characteristicType(forIdentifier: .fitzpatrickSkinType) { types.insert(skin) }
        // Everything else — request read access so we can import it all.
        otherQuantityTypes.forEach { types.insert($0) }
        otherCategoryTypes.forEach { types.insert($0) }
        return types
    }
    #endif

    /// Read the user's date-of-birth and biological sex from Apple Health, if
    /// they've been entered there and access was granted. Used to pre-fill (and
    /// let the user confirm) the onboarding basics — never fabricated.
    func biologicalCharacteristics() -> (dateOfBirth: Date?, sex: BiologicalSex?) {
        #if canImport(HealthKit)
        guard isAvailable else { return (nil, nil) }
        var dob: Date?
        if let comps = try? store.dateOfBirthComponents() {
            dob = Calendar.current.date(from: comps)
        }
        var sex: BiologicalSex?
        if let hkSex = try? store.biologicalSex().biologicalSex {
            switch hkSex {
            case .male: sex = .male
            case .female: sex = .female
            default: sex = nil
            }
        }
        return (dob, sex)
        #else
        return (nil, nil)
        #endif
    }

    /// Request read authorization for all supported types.
    func requestAuthorization() async throws {
        #if canImport(HealthKit)
        guard isAvailable else {
            DiagnosticsLog.shared.null("Apple Health", "Not available on this device")
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            DiagnosticsLog.shared.ok("Apple Health", "Authorization requested for \(readTypes.count) types")
        } catch {
            DiagnosticsLog.shared.fail("Apple Health", "Authorization failed: \(error.localizedDescription)")
            throw error
        }
        #endif
    }

    /// Metrics we pull the *full* history for (blood pressure, body composition,
    /// labs) — sparse data where every past reading is valuable. Read back years,
    /// not the shorter recent window used for high-frequency vitals.
    private static let longHistoryMetrics: Set<MetricType> = [
        .bloodPressureSystolic, .bloodPressureDiastolic, .bodyMass, .bodyFatPercentage,
        .leanBodyMass, .muscleMass, .boneMass, .bodyWaterPercentage, .height
    ]

    /// High-frequency metrics capped to a shorter window so the import stays fast
    /// and the cache reasonable (heart rate can be hundreds of samples per day).
    private static let highFrequencyMetrics: Set<MetricType> = [.heartRate]

    #if canImport(HealthKit)
    private func lookbackStart(for metric: MetricType, now: Date = Date()) -> Date {
        let cal = Calendar.current
        if Self.longHistoryMetrics.contains(metric) {
            return cal.date(byAdding: .year, value: -10, to: now) ?? now
        }
        if Self.highFrequencyMetrics.contains(metric) {
            return cal.date(byAdding: .day, value: -180, to: now) ?? now
        }
        return cal.date(byAdding: .year, value: -2, to: now) ?? now
    }

    private var otherLookbackStart: Date {
        Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
    }
    #endif

    /// Fetch **everything**: canonical mapped samples plus raw "other" data for
    /// every additional quantity/category type. High-frequency vitals use a
    /// shorter window; sparse data goes back years.
    func fetchAllData() async -> SyncedData {
        #if canImport(HealthKit)
        guard isAvailable else { return SyncedData() }
        var result = SyncedData()
        for (id, metric, unit) in readMap {
            guard let qType = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            result.samples += await fetchQuantity(qType, metric: metric, unit: unit,
                                                  start: lookbackStart(for: metric))
        }
        result.samples += await fetchSleep(start: lookbackStart(for: .sleepDurationHours))
        result.other += await fetchOtherQuantities(start: otherLookbackStart)
        result.other += await fetchOtherCategories(start: otherLookbackStart)
        DiagnosticsLog.shared.ok("Apple Health",
            "Read \(result.samples.count) samples + \(result.other.count) other data points")
        return result
        #else
        return SyncedData()
        #endif
    }

    #if canImport(HealthKit)
    /// Read arbitrary quantity types using each type's preferred unit, emitting
    /// raw samples for the "Other data" browser.
    private func fetchOtherQuantities(start: Date) async -> [RawMetricSample] {
        let types = otherQuantityTypes
        guard !types.isEmpty else { return [] }
        let units: [HKQuantityType: HKUnit]
        do { units = try await store.preferredUnits(for: Set(types)) } catch { return [] }
        var out: [RawMetricSample] = []
        for type in types {
            guard let unit = units[type] else { continue }
            out += await fetchRawQuantity(type, unit: unit, start: start)
        }
        return out
    }

    private func fetchRawQuantity(_ type: HKQuantityType, unit: HKUnit, start: Date) async -> [RawMetricSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let mapped: [RawMetricSample] = (samples as? [HKQuantitySample])?.compactMap { s in
                    guard s.quantity.`is`(compatibleWith: unit) else { return nil }
                    return RawMetricSample(identifier: type.identifier,
                                           displayName: Self.humanize(type.identifier),
                                           value: s.quantity.doubleValue(for: unit),
                                           unit: unit.unitString,
                                           start: s.startDate, end: s.endDate,
                                           source: .appleHealthDevice(s.sourceRevision.source.name))
                } ?? []
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    private func fetchOtherCategories(start: Date) async -> [RawMetricSample] {
        var out: [RawMetricSample] = []
        for type in otherCategoryTypes {
            out += await fetchRawCategory(type, start: start)
        }
        return out
    }

    private func fetchRawCategory(_ type: HKCategoryType, start: Date) async -> [RawMetricSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let mapped: [RawMetricSample] = (samples as? [HKCategorySample])?.map { s in
                    // For "event/session" types the value is often not-applicable;
                    // fall back to the duration in minutes so there's something useful.
                    let minutes = s.endDate.timeIntervalSince(s.startDate) / 60
                    let usesDuration = s.value == 0 && minutes > 0   // 0 = notApplicable
                    return RawMetricSample(identifier: type.identifier,
                                           displayName: Self.humanize(type.identifier),
                                           value: usesDuration ? minutes : Double(s.value),
                                           unit: usesDuration ? "min" : "",
                                           start: s.startDate, end: s.endDate,
                                           source: .appleHealthDevice(s.sourceRevision.source.name))
                } ?? []
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// Turn "HKQuantityTypeIdentifierDietaryVitaminC" into "Dietary Vitamin C".
    static func humanize(_ identifier: String) -> String {
        var s = identifier
        for prefix in ["HKQuantityTypeIdentifier", "HKCategoryTypeIdentifier"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        var out = ""
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            if i > 0, ch.isUppercase || ch.isNumber, !(chars[i - 1].isUppercase || chars[i - 1].isNumber) {
                out.append(" ")
            }
            out.append(ch)
        }
        return out.isEmpty ? identifier : out
    }

    private func fetchQuantity(_ type: HKQuantityType, metric: MetricType, unit: HKUnit, start: Date) async -> [HealthMetricSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let mapped: [HealthMetricSample] = (samples as? [HKQuantitySample])?.compactMap { s in
                    guard s.quantity.`is`(compatibleWith: unit) else { return nil }
                    var value = s.quantity.doubleValue(for: unit)
                    // HealthKit reports `.percent()` as a 0–1 fraction. Every
                    // metric we store as a percentage needs the same scaling —
                    // missing one here shows up as "0 %" on a card rather than
                    // as an obvious error.
                    if Self.percentageMetrics.contains(metric) { value *= 100 }
                    // Preserve the underlying device (Apple Watch, Oura, iPhone…)
                    // so the app can overlay and de-duplicate sources.
                    return HealthMetricSample(type: metric, value: value,
                                              start: s.startDate, end: s.endDate,
                                              source: .appleHealthDevice(s.sourceRevision.source.name))
                } ?? []
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// HealthKit's category value → the stage vocabulary InsightKit understands.
    ///
    /// No `#available` branch: the deployment target is iOS 18, so the
    /// `asleepCore` / `asleepDeep` / `asleepREM` split Apple shipped in iOS 16 is
    /// always present. The pre-16 fallback this replaced tested
    /// `HKCategoryValueSleepAnalysis.asleep`, which has been unreachable here
    /// since the target moved — and which is the same raw value (1) as
    /// `asleepUnspecified` anyway, so nothing is lost by naming only the latter.
    ///
    /// An unrecognised value returns `nil` and the segment is ignored, rather
    /// than being counted as some default stage.
    ///
    /// `nonisolated` because the class is `@MainActor` — which would isolate a
    /// static member to the main actor too — and `HKSampleQuery`'s completion
    /// handler runs on an arbitrary queue. It is a pure `Int` → enum mapping
    /// touching no state, so there is nothing for the isolation to protect.
    nonisolated private static func sleepKind(of value: Int) -> SleepSegment.Kind? {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .unspecified
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        default: return nil
        }
    }

    private func fetchSleep(start: Date) async -> [HealthMetricSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                // This function's only job is to translate HealthKit's category
                // values into `SleepSegment`. **Every rule about what a night is
                // lives in `SleepNights`, in InsightKit**, because the rules can
                // be wrong and the app target has no test target.
                //
                // It used to aggregate here, keying each nightly figure on
                // `Calendar.startOfDay(for: segment.startDate)` — the day the
                // segment itself began. A night from 23:00 to 07:00 is written
                // by Apple Health as a run of stage segments, so the ones before
                // midnight were filed under one day and the rest under the next:
                // one night became two, the smaller a sliver. That is where the
                // data export's 0.01 h minimum sleep duration came from, and
                // — efficiency having split its numerator and denominator
                // independently — its 2% minimum efficiency as well.
                let mapped = (samples as? [HKCategorySample])?.compactMap { s -> SleepSegment? in
                    guard let kind = Self.sleepKind(of: s.value) else { return nil }
                    return SleepSegment(kind: kind, start: s.startDate, end: s.endDate)
                } ?? []
                continuation.resume(returning: SleepNights.samples(from: mapped,
                                                                   source: .appleHealth,
                                                                   calendar: Calendar.current))
            }
            store.execute(query)
        }
    }
    #endif
}
