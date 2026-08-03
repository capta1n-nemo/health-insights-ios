import Foundation
@testable import InsightKit

/// A sample set covering every metric any insight reads, dense enough for the
/// baseline-dependent components to fire.
///
/// **Shared rather than copied.** It began inside `ContributorsTests`, and the
/// moment a second suite needed to ask "does every card's attribution account
/// for its whole number" over the same nine models, a second fixture would have
/// been a second answer to *what a complete dataset looks like* — free to drift,
/// and drifting silently, since each suite would still pass against its own.
enum ContributorsFixture {

    static func fullCoverage(days: Int = 20, now: Date) -> [HealthMetricSample] {
        let defaults: [MetricType: Double] = [
            .heartRate: 68, .restingHeartRate: 58, .walkingHeartRateAverage: 95,
            .heartRateVariabilitySDNN: 52, .heartRateVariabilityRMSSD: 48,
            .vo2Max: 46, .vascularAge: 34, .respiratoryRate: 14,
            .oxygenSaturation: 97, .dayStrain: 12,
            .bloodPressureSystolic: 118, .bloodPressureDiastolic: 76,
            .bodyMass: 78, .bodyFatPercentage: 18, .leanBodyMass: 62,
            .muscleMass: 58, .boneMass: 3.2, .bodyWaterPercentage: 58,
            .height: 1.83, .stepCount: 9000, .activeEnergyBurned: 520,
            .sleepDurationHours: 7.4, .bodyTemperature: 36.6,
            .skinTemperature: 33.8, .skinTemperatureDeviation: 0.1,
            // The vitals promoted out of the raw layer. Present here so
            // "full coverage" stays literally true — without them Vitals Check
            // correctly charts only what it measured, and the equality checks
            // in `ContributorsTests` would be asserting something the fixture
            // never supplied.
            .bloodGlucose: 5.2, .peripheralPerfusionIndex: 2.0,
            .atrialFibrillationBurden: 0.5, .heartRateRecovery: 25,
            .walkingSteadiness: 85, .walkingAsymmetry: 2,
            // Charted by Body Composition at weight 0. Here for the same
            // reason the promoted vitals are: a card that declares it has to
            // be given something to report, or "full coverage" is not.
            .dietaryEnergy: 2100,
            // A day's eating that lands near the published figures rather than
            // on them — a fixture sitting exactly on every threshold would let
            // a curve with the wrong shape pass.
            .dietaryProtein: 110, .dietaryCarbohydrates: 220, .dietaryFat: 70,
            .dietarySaturatedFat: 20, .dietarySugar: 60, .dietaryFibre: 26,
            .dietarySodium: 2300, .dietaryPotassium: 3200, .dietaryWater: 2.0,
            .dietaryCaffeine: 180
        ]
        var out: [HealthMetricSample] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            for (metric, base) in defaults {
                // A little movement so standard deviations aren't zero.
                let jitter = Double((i * 7) % 5) * 0.01 * base
                out.append(.init(type: metric, value: base + jitter,
                                 start: now.addingTimeInterval(-Double(i) * 86_400),
                                 source: .oura))
            }
        }
        return out
    }

    static func profile(now: Date) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-35 * 365.25 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 1, recordedAt: now))
        return p
    }
}
