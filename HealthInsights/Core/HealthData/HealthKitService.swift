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
            (.activeEnergyBurned, .activeEnergyBurned, .kilocalorie())
        ]
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

    /// Fetch recent samples for all mapped types within `days`.
    func fetchRecentSamples(days: Int = 90) async -> [HealthMetricSample] {
        #if canImport(HealthKit)
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var results: [HealthMetricSample] = []
        for (id, metric, unit) in readMap {
            guard let qType = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            let samples = await fetchQuantity(qType, metric: metric, unit: unit, start: start)
            results.append(contentsOf: samples)
        }
        results.append(contentsOf: await fetchSleep(start: start))
        DiagnosticsLog.shared.ok("Apple Health", "Read \(results.count) samples over \(days)d")
        return results
        #else
        return []
        #endif
    }

    #if canImport(HealthKit)
    private func fetchQuantity(_ type: HKQuantityType, metric: MetricType, unit: HKUnit, start: Date) async -> [HealthMetricSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let mapped: [HealthMetricSample] = (samples as? [HKQuantitySample])?.compactMap { s in
                    guard s.quantity.`is`(compatibleWith: unit) else { return nil }
                    var value = s.quantity.doubleValue(for: unit)
                    if metric == .bodyFatPercentage || metric == .oxygenSaturation { value *= 100 } // fraction → %
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

    private func fetchSleep(start: Date) async -> [HealthMetricSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                // Aggregate "asleep" segments per night into hours.
                let asleep = (samples as? [HKCategorySample])?.filter { s in
                    if #available(iOS 16.0, *) {
                        return [HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue].contains(s.value)
                    } else {
                        return s.value == HKCategoryValueSleepAnalysis.asleep.rawValue
                    }
                } ?? []

                // Group by calendar day of the segment start.
                var byDay: [Date: TimeInterval] = [:]
                let cal = Calendar.current
                for s in asleep {
                    let day = cal.startOfDay(for: s.startDate)
                    byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
                }
                let mapped = byDay.map { day, seconds in
                    HealthMetricSample(type: .sleepDurationHours, value: seconds / 3600,
                                       start: day, end: day, source: .appleHealth)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }
    #endif
}
