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

    /// **Which canonical metric a native HealthKit identifier becomes.**
    ///
    /// Derived from `readMap` itself rather than written out again, because a
    /// second copy of this table is a copy that drifts — and the reader is the
    /// one who would find out. It exists for the Data tab: `TypeSightingLedger`
    /// records an identifier in whatever vocabulary it arrived in, so the same
    /// subject can sit in the ledger under `HKQuantityTypeIdentifierDietary…`
    /// from before it was promoted and under `dietaryVitaminA` from after, and
    /// a screen asking "have I ever seen this?" has to be able to join the two.
    ///
    /// Empty on a platform without HealthKit — the app target only ships to
    /// iOS, but this file compiles anywhere and the callers must not need a
    /// `#if` of their own.
    static let canonicalMetricByNativeIdentifier: [String: MetricType] = {
        #if canImport(HealthKit)
        return Dictionary(readMap.map { ($0.0.rawValue, $0.1) }) { first, _ in first }
        #else
        return [:]
        #endif
    }()

    #if canImport(HealthKit)
    /// The quantity types we read, paired with their canonical metric + unit.
    ///
    /// `static`, so the reverse mapping above can be built from it without an
    /// instance — and so it is stated exactly once. Computed rather than
    /// stored: `HKUnit` is a non-`Sendable` class, and a stored static of one
    /// is global mutable state as far as Swift 6 is concerned.
    private static var readMap: [(HKQuantityTypeIdentifier, MetricType, HKUnit)] {
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
            // **Apple Health already holds a waist**, and reading it costs one
            // line. It is the single measurement `BuildAssessmentModel` needs,
            // so a reader who has ever typed one into Health — or owns a scale
            // or tape app that writes one — gets the RFM route without ever
            // opening this app's scanner. Centimetres, because that is what
            // `MetricType.waistCircumference` is defined in and the conversion
            // belongs at this boundary rather than in the model.
            (.waistCircumference, .waistCircumference, .meterUnit(with: .centi)),
            (.stepCount, .stepCount, .count()),
            (.activeEnergyBurned, .activeEnergyBurned, .kilocalorie()),
            // What went in, beside what was burned. Anyone whose food app
            // writes to Health — Shotsy does, and so do the calorie trackers —
            // gets this without importing a file, which is the "graceful
            // population" rule doing its job. Charted, never scored: see
            // `MetricType.dietaryEnergy`.
            (.dietaryEnergyConsumed, .dietaryEnergy, .kilocalorie()),
            // The macros and the six the published guidance names, promoted
            // out of the raw pile with dietary energy's rationale: each has a
            // reader now (the nutrition card) and four of them carry a real
            // band. Grams, milligrams and litres — the conversion belongs at
            // this boundary, not in a model.
            (.dietaryProtein, .dietaryProtein, .gram()),
            (.dietaryCarbohydrates, .dietaryCarbohydrates, .gram()),
            (.dietaryFatTotal, .dietaryFat, .gram()),
            (.dietaryFatSaturated, .dietarySaturatedFat, .gram()),
            (.dietarySugar, .dietarySugar, .gram()),
            (.dietaryFiber, .dietaryFibre, .gram()),
            (.dietarySodium, .dietarySodium, .gramUnit(with: .milli)),
            (.dietaryPotassium, .dietaryPotassium, .gramUnit(with: .milli)),
            (.dietaryWater, .dietaryWater, .liter()),
            (.dietaryCaffeine, .dietaryCaffeine, .gramUnit(with: .milli)),
            // **The eleven micronutrients, promoted 2026-08-05.** The unit is
            // the whole risk in this group and it is stated once, here, at the
            // boundary: HealthKit stores mass canonically and converts on read,
            // so asking for the wrong prefix silently rescales by a thousand.
            // `plausibleRange` is set tightly enough on each to reject that
            // slip rather than chart it.
            (.dietaryFatMonounsaturated, .dietaryMonounsaturatedFat, .gram()),
            (.dietaryFatPolyunsaturated, .dietaryPolyunsaturatedFat, .gram()),
            (.dietaryCholesterol, .dietaryCholesterol, .gramUnit(with: .milli)),
            (.dietaryCalcium, .dietaryCalcium, .gramUnit(with: .milli)),
            (.dietaryIron, .dietaryIron, .gramUnit(with: .milli)),
            (.dietaryMagnesium, .dietaryMagnesium, .gramUnit(with: .milli)),
            (.dietaryZinc, .dietaryZinc, .gramUnit(with: .milli)),
            (.dietaryVitaminC, .dietaryVitaminC, .gramUnit(with: .milli)),
            // Micrograms — vitamin A as RAE, D as mcg rather than IU (the
            // modern label figure), B12 as mcg.
            (.dietaryVitaminA, .dietaryVitaminA, .gramUnit(with: .micro)),
            (.dietaryVitaminD, .dietaryVitaminD, .gramUnit(with: .micro)),
            (.dietaryVitaminB12, .dietaryVitaminB12, .gramUnit(with: .micro)),
            // Promoted out of the raw pile because it earned a score: Apple's
            // exercise minute accrues at brisk-walk intensity and above, which
            // is the WHO guideline's own moderate-intensity definition, so the
            // Fitness card can weigh the week's dose against a published band
            // (`ActivityDoseModel`). Removed from `otherQuantityIdentifiers`
            // below — a metric must not arrive through both routes.
            (.appleExerciseTime, .exerciseMinutes, .minute()),
            // **Backlog §B5 #34–35, the reader's own reversal.** Distance,
            // flights and effort intensity were scraped into the raw pile from
            // the beginning and read by nothing. Measured on their export
            // 2026-08-06: distance 91 of the last 90 days, flights 78, effort
            // 14. All three are removed from `otherQuantityIdentifiers` below
            // in the same edit — a metric arriving through both routes ingests
            // every sample twice, which is what promoting `appleExerciseTime`
            // had to fix.
            //
            // Kilometres, so the readMap does the conversion once here rather
            // than in every reader.
            (.distanceWalkingRunning, .distanceWalkingRunning,
             .meterUnit(with: .kilo)),
            (.flightsClimbed, .flightsClimbed, .count()),
            // kcal/hr·kg *is* the MET, so this is a rename rather than a
            // conversion. HealthKit spells the unit `kcal/hr·kg`.
            (.physicalEffort, .physicalEffort,
             HKUnit.kilocalorie()
                .unitDivided(by: HKUnit.hour().unitMultiplied(by: .gramUnit(with: .kilo)))),
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
            (.walkingAsymmetryPercentage, .walkingAsymmetry, .percent()),
            // The gait triad, promoted out of the raw pile on 2026-08-05. It had
            // been scraped since the beginning and read by nothing, while being
            // — measured against the reader's own export — the densest signal
            // in the app: 1,093 days each, 91 of the last 90, from the phone
            // alone. Store metres per second and centimetres, so the readMap
            // does the conversion once here rather than every reader doing it.
            (.walkingSpeed, .walkingSpeed,
             HKUnit.meter().unitDivided(by: .second())),
            (.walkingStepLength, .walkingStepLength, .meterUnit(with: .centi)),
            (.walkingDoubleSupportPercentage, .walkingDoubleSupport, .percent())
        ]
    }

    /// Metrics HealthKit hands over as a 0–1 fraction and we store as 0–100.
    private static let percentageMetrics: Set<MetricType> = [
        .bodyFatPercentage, .oxygenSaturation, .peripheralPerfusionIndex,
        .atrialFibrillationBurden, .walkingSteadiness, .walkingAsymmetry,
        .walkingDoubleSupport
    ]

    /// Additional quantity types we import as raw "other" data (not yet modelled
    /// as canonical metrics). Listed as raw identifier strings so unknown ones on
    /// older SDKs simply resolve to nil and are skipped. This is how we "scrape
    /// everything" — activity, respiratory, nutrition, environmental, etc.
    private static let otherQuantityIdentifiers: [String] = [
        // Activity & mobility
        //
        // ⚠️ **Walking/running distance, flights climbed and physical effort
        // moved to `readMap` above on 2026-08-06 (backlog §B5 #34–35).**
        // Leaving them here as well would ingest every sample twice, once
        // canonical and once raw, and the Data tab would list each identifier
        // in two places. Cycling, swimming, wheelchair and snow-sports distance
        // stay raw: the reader records none of them, and a metric with no
        // reader is a chart nobody asked for.
        "HKQuantityTypeIdentifierDistanceCycling",
        "HKQuantityTypeIdentifierDistanceSwimming", "HKQuantityTypeIdentifierDistanceWheelchair",
        "HKQuantityTypeIdentifierDistanceDownhillSnowSports", "HKQuantityTypeIdentifierBasalEnergyBurned",
        "HKQuantityTypeIdentifierAppleStandTime", "HKQuantityTypeIdentifierAppleMoveTime",
        "HKQuantityTypeIdentifierPushCount", "HKQuantityTypeIdentifierSwimmingStrokeCount",
        // The gait triad moved to `readMap` above on 2026-08-05 — leaving it
        // here as well would ingest every sample twice, once canonical and once
        // raw, and the Data tab would list each identifier in two places.
        "HKQuantityTypeIdentifierSixMinuteWalkTestDistance", "HKQuantityTypeIdentifierStairAscentSpeed",
        "HKQuantityTypeIdentifierStairDescentSpeed", "HKQuantityTypeIdentifierRunningSpeed",
        "HKQuantityTypeIdentifierRunningPower", "HKQuantityTypeIdentifierRunningStrideLength",
        "HKQuantityTypeIdentifierRunningVerticalOscillation", "HKQuantityTypeIdentifierRunningGroundContactTime",
        "HKQuantityTypeIdentifierCyclingSpeed", "HKQuantityTypeIdentifierCyclingPower",
        "HKQuantityTypeIdentifierCyclingCadence",
        "HKQuantityTypeIdentifierNumberOfTimesFallen",
        // Cardio / respiratory / other vitals
        "HKQuantityTypeIdentifierForcedVitalCapacity",
        // ⚠️ **Apnoea, added 2026-08-06 to make a claim measurable rather than
        // to build on.** Backlog #30 was refused partly on "the reader has no
        // apnoea data" — which was unfalsifiable, because neither identifier was
        // being requested, so HealthKit would have returned nothing even if the
        // Watch had been recording it for a year. Two strings; unknown
        // identifiers resolve to nil on older SDKs, so this is safe on any
        // device. Count the rows before building any UI on it.
        "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances",
        "HKQuantityTypeIdentifierForcedExpiratoryVolume1", "HKQuantityTypeIdentifierPeakExpiratoryFlowRate",
        "HKQuantityTypeIdentifierInhalerUsage", "HKQuantityTypeIdentifierBasalBodyTemperature", "HKQuantityTypeIdentifierBloodAlcoholContent", "HKQuantityTypeIdentifierElectrodermalActivity",
        "HKQuantityTypeIdentifierInsulinDelivery", "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages",
        // Body
        "HKQuantityTypeIdentifierBodyMassIndex", "HKQuantityTypeIdentifierWaistCircumference",
        // Environment
        //
        // ⚠️ The two audio-exposure identifiers stay in this raw list **on
        // purpose**, unlike the gait triad and the micronutrients above, which
        // moved out when they were promoted. Their per-interval dBA samples
        // never became canonical metrics — a decibel level cannot be averaged,
        // so promoting the raw series would hand the baseline machinery
        // arithmetic it must not do. `SoundDoseModel` reads them from this
        // pile and derives the two daily LEQ metrics
        // (`environmentalSoundDose`, `headphoneSoundDose`) on the ingest
        // path; the "both routes" duplication rule doesn't bite because the
        // raw rows and the derived days are different quantities.
        "HKQuantityTypeIdentifierUVExposure", "HKQuantityTypeIdentifierEnvironmentalAudioExposure",
        "HKQuantityTypeIdentifierHeadphoneAudioExposure", "HKQuantityTypeIdentifierEnvironmentalSoundReduction",
        "HKQuantityTypeIdentifierTimeInDaylight", "HKQuantityTypeIdentifierUnderwaterDepth",
        "HKQuantityTypeIdentifierWaterTemperature",
        // **Nutrition is entirely canonical as of 2026-08-05 — nothing dietary
        // is left in this list.** The eleven micronutrients that used to sit
        // here are `MetricType`s now, at the reader's decision, and a metric
        // must not arrive through both routes (the removal `appleExerciseTime`
        // needed when it was promoted).
        //
        // The rationale they were kept out under — "no card reads a vitamin,
        // and a metric with no reader is a chart nobody asked for" — was sound
        // and had a consequence nobody costed: raw groups carry no category, so
        // the Data tab's Nutrition section is generated from `MetricType`
        // alone, and 686 rows of the reader's own record filed under "Other
        // data" at the very bottom of the tab. Being unscored was the intent;
        // being unfindable was not.
    ]

    /// Category (event/state) types imported as raw "other" data.
    private static let otherCategoryIdentifiers: [String] = [
        "HKCategoryTypeIdentifierMindfulSession", "HKCategoryTypeIdentifierAppleStandHour",
        "HKCategoryTypeIdentifierHighHeartRateEvent", "HKCategoryTypeIdentifierLowHeartRateEvent",
        "HKCategoryTypeIdentifierIrregularHeartRhythmEvent", "HKCategoryTypeIdentifierAudioExposureEvent",
        "HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent", "HKCategoryTypeIdentifierHeadphoneAudioExposureEvent",
        "HKCategoryTypeIdentifierToothbrushingEvent", "HKCategoryTypeIdentifierHandwashingEvent",
        "HKCategoryTypeIdentifierSexualActivity", "HKCategoryTypeIdentifierMenstrualFlow",
        "HKCategoryTypeIdentifierSleepApneaEvent",
        "HKCategoryTypeIdentifierLowCardioFitnessEvent", "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent",
        "HKCategoryTypeIdentifierNausea", "HKCategoryTypeIdentifierHeadache", "HKCategoryTypeIdentifierFatigue",
        "HKCategoryTypeIdentifierDizziness", "HKCategoryTypeIdentifierFever", "HKCategoryTypeIdentifierCoughing",
        "HKCategoryTypeIdentifierShortnessOfBreath", "HKCategoryTypeIdentifierChestTightnessOrPain",
        "HKCategoryTypeIdentifierAbdominalCramps", "HKCategoryTypeIdentifierBloating",
        "HKCategoryTypeIdentifierHeartburn", "HKCategoryTypeIdentifierSleepChanges",
        "HKCategoryTypeIdentifierMoodChanges", "HKCategoryTypeIdentifierHotFlashes",
        "HKCategoryTypeIdentifierVomiting", "HKCategoryTypeIdentifierDiarrhea"
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
        for (id, _, _) in Self.readMap {
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
        for (id, metric, unit) in Self.readMap {
            guard let qType = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            result.samples += await fetchQuantity(qType, metric: metric, unit: unit,
                                                  start: lookbackStart(for: metric))
        }
        let sleep = await fetchSleep(start: lookbackStart(for: .sleepDurationHours))
        result.samples += sleep.nightly
        // The per-stage segments travel too, so the hypnogram has an Apple lane.
        // They used to be mapped and then dropped on the floor — see `fetchSleep`.
        result.other += sleep.segments
        result.other += await fetchOtherQuantities(start: otherLookbackStart)
        result.other += await fetchOtherCategories(start: otherLookbackStart)
        logReadOutcome(result)
        return result
        #else
        return SyncedData()
        #endif
    }

    #if canImport(HealthKit)
    /// **A read of nothing is not a pass.** Backlog D10.
    ///
    /// This line was an unconditional green tick — *"Read 0 samples + 0 other
    /// data points"*, filed under Passed — which is the log agreeing with the
    /// Settings row that everything is fine. It is the one place in the app
    /// that can notice Apple Health went quiet, so it has to be the place that
    /// says so.
    ///
    /// ⚠️ **It cannot say *why*, and must not pretend to.** HealthKit hides
    /// read refusal by design: a type the reader declined and a type they have
    /// never recorded return the same empty array, and there is no API that
    /// separates them. So this states the ambiguity rather than picking a side
    /// — naming both causes and where to check — which is the honest version
    /// and the only one available.
    private func logReadOutcome(_ result: SyncedData) {
        guard result.samples.isEmpty && result.other.isEmpty else {
            DiagnosticsLog.shared.ok("Apple Health",
                "Read \(result.samples.count) samples + \(result.other.count) other data points")
            return
        }
        DiagnosticsLog.shared.null("Apple Health", "Read nothing — every type came back empty",
            detail: """
                \(readTypes.count) types were asked for and all \(readTypes.count) returned no \
                samples. Two very different things look exactly like this and HealthKit does \
                not let an app tell them apart:

                · Read access was declined. Tapping \u{201C}Don't Allow\u{201D} on the Health \
                permission sheet, or switching a category off later, makes that data invisible \
                to this app — it is never told, and reads an empty list instead.
                · There genuinely is nothing recorded, on a new phone or one with no watch.

                Check in Health ▸ your profile ▸ Apps & Services ▸ Health Insights. Everything \
                listed there as off is data this app cannot see, whatever the cards say.
                """)
    }
    #endif

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

    /// The identifier every Apple sleep-stage segment is catalogued under.
    ///
    /// One identifier with the stage in the value, rather than an identifier per
    /// stage: the Data tab's "Other data" would otherwise gain five rows saying
    /// the same thing, and `NightSleepDetail` wants them as one stream anyway.
    static let appleSleepSegmentIdentifier = "apple_health.sleep_segment"

    /// Nightly figures **and** the per-stage segments behind them.
    ///
    /// **The segments used to be mapped and then thrown away.** This function
    /// translated HealthKit's category values into `SleepSegment`, handed them
    /// to `SleepNights` for the nightly totals, and dropped the segments on the
    /// floor — so `NightSleepDetail` had nothing to build an Apple lane from and
    /// fell through to `windowLanes`, which draws one flat `stage: nil` band.
    /// That is why an Apple night rendered as a featureless grey bar while an
    /// Oura night showed its hypnogram, even though Apple has recorded
    /// core/deep/REM since iOS 16 and the reader's own export carries stage
    /// minutes on 132 nights.
    ///
    /// `SleepNights` remains the **sole** authority on nightly figures; the
    /// segments travel beside them as raw catalogue rows purely so the chart can
    /// draw what was already fetched.
    private func fetchSleep(start: Date) async -> (nightly: [HealthMetricSample],
                                                   segments: [RawMetricSample]) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return ([], [])
        }
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
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                let mapped = categorySamples.compactMap { s -> SleepSegment? in
                    guard let kind = Self.sleepKind(of: s.value) else { return nil }
                    return SleepSegment(kind: kind, start: s.startDate, end: s.endDate)
                }
                // The same segments, kept. `.text` carries the stage because the
                // hypnogram needs to know *which* stage, and a numeric code
                // would be unreadable in the Data tab's raw listing.
                let segments = categorySamples.compactMap { s -> RawMetricSample? in
                    guard let kind = Self.sleepKind(of: s.value) else { return nil }
                    return RawMetricSample(
                        identifier: Self.appleSleepSegmentIdentifier,
                        displayName: "Sleep stage",
                        value: .text(kind.rawValue),
                        unit: "",
                        start: s.startDate, end: s.endDate,
                        source: .appleHealthDevice(s.sourceRevision.source.name))
                }
                continuation.resume(returning: (
                    SleepNights.samples(from: mapped, source: .appleHealth,
                                        calendar: Calendar.current),
                    segments))
            }
            store.execute(query)
        }
    }
    #endif
}
