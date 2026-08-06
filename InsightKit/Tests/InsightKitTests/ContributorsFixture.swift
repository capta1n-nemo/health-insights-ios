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

    /// ⚠️ **130, not 20, and the default is the whole point.**
    ///
    /// Three sweeps in `ScoreAttributionTests` took this default while every
    /// other caller passed 130, and each sweep opens with
    /// `guard result.score != nil else { continue }`. So the two newest cards —
    /// Sustained Load (28 days against the 90 before) and Gait (28 against the
    /// previous year) — returned nil on a 20-day fixture and were **silently
    /// skipped by the very tests that exist to prove every scoring card explains
    /// its own number.** Found by an audit, not by a failure, because a guard
    /// that skips is a guard that hides.
    ///
    /// "Full coverage" has to mean enough *history* for every registered card,
    /// not just enough metrics. A card whose window is longer than this needs
    /// this raised again, and `testEveryRegisteredModelScoresOnTheFixture` is
    /// what will say so.
    static func fullCoverage(days: Int = 130, now: Date) -> [HealthMetricSample] {
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
            // Charted by Sleep at weight 0 (backlog #30/S9). Here for the same
            // reason the medication level and calories are: a declared
            // candidate has to be reachable as a contributor on this fixture,
            // or `CandidateReachabilityTests` calls the declaration dead.
            // A single-digit index value, deliberately not round.
            .breathingDisturbanceIndex: 5.7,
            // The vitals promoted out of the raw layer. Present here so
            // "full coverage" stays literally true — without them Vitals Check
            // correctly charts only what it measured, and the equality checks
            // in `ContributorsTests` would be asserting something the fixture
            // never supplied.
            .bloodGlucose: 5.2, .peripheralPerfusionIndex: 2.0,
            .atrialFibrillationBurden: 0.5, .heartRateRecovery: 25,
            .walkingSteadiness: 85, .walkingAsymmetry: 2,
            // The gait triad, promoted on 2026-08-05. Values near the middle of
            // an unremarkable adult's range, and deliberately not round: a
            // fixture sitting on a threshold lets a wrong curve pass.
            .walkingSpeed: 1.32, .walkingStepLength: 74, .walkingDoubleSupport: 27,
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
            .dietaryCaffeine: 180,
            // Promoted 2026-08-06 (backlog §B5 #35). Consistent with the 9,000
            // steps above rather than picked independently — a fixture whose
            // distance and step count disagree would let a card that reads one
            // as a proxy for the other pass.
            .distanceWalkingRunning: 6.4, .flightsClimbed: 11
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
            // ⚠️ **Effort intensity cannot go in the loop above, and the reason
            // is the whole point of the metric.** Every other sample here is a
            // point reading; `EffortIntensityModel` measures *time*, from each
            // sample's own interval, so a zero-length sample contributes no
            // minutes and the card would score a fully-covered fixture at the
            // sedentary floor. Two intervals a day — a working day at rest and
            // half an hour of walking — which puts the week at 210
            // moderate-equivalent minutes, inside the WHO band and deliberately
            // not on either edge of it.
            let day = now.addingTimeInterval(-Double(i) * 86_400)
            out.append(.init(type: .physicalEffort, value: 1.4, start: day,
                             end: day.addingTimeInterval(600 * 60), source: .oura))
            out.append(.init(type: .physicalEffort, value: 4.4,
                             start: day.addingTimeInterval(601 * 60),
                             end: day.addingTimeInterval(631 * 60), source: .oura))
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
