import XCTest
@testable import InsightKit

private let cardNow = TestClock.now
private let cardCalendar = TestClock.utc

/// Fixtures for the four cards added to close the gap against what the top apps
/// in the category actually ship.
private func nightly(_ metric: MetricType, _ values: [Double],
                     source: MetricSource = .oura) -> [HealthMetricSample] {
    values.enumerated().map { index, value in
        HealthMetricSample(type: metric, value: value,
                           start: TestClock.day(values.count - 1 - index), source: source)
    }
}

/// Garmin's Body Battery is the most-loved number in consumer wearables and
/// exists nowhere on iOS. Every other app here reports recovery this morning and
/// then goes quiet, which is a strange thing to do with a sensor that keeps
/// measuring all day.
final class EnergyModelTests: XCTestCase {

    func testSleepLeadsAndRecoveryModifies() {
        let short = EnergyModel.morningCharge(sleepHours: 4, recoveryZ: 0)
        let full = EnergyModel.morningCharge(sleepHours: 8, recoveryZ: 0)
        XCTAssertLessThan(short, full)
        // You cannot recover your way out of four hours.
        let shortButRecovered = EnergyModel.morningCharge(sleepHours: 4, recoveryZ: 2)
        XCTAssertLessThan(shortButRecovered, full)
    }

    /// A person who hasn't slept still gets out of bed.
    func testNoSleepIsNotZero() {
        XCTAssertEqual(EnergyModel.morningCharge(sleepHours: 0, recoveryZ: nil),
                       EnergyModel.minimumMorningCharge, accuracy: 1e-9)
    }

    func testChargeIsBounded() {
        XCTAssertLessThanOrEqual(EnergyModel.morningCharge(sleepHours: 14, recoveryZ: 4), 100)
        XCTAssertGreaterThanOrEqual(EnergyModel.morningCharge(sleepHours: 0, recoveryZ: -6), 0)
    }

    /// The reservoir has to actually empty, or the whole metaphor is decoration.
    func testAHardDayDrainsMoreThanAnIdleOne() throws {
        var idle = nightly(.sleepDurationHours, [7.5, 7.6, 7.4, 7.5])
        idle += nightly(.restingHeartRate, [55, 55, 56, 55])
        var busy = idle
        // 900 kcal of active work today.
        busy.append(HealthMetricSample(type: .activeEnergyBurned, value: 900,
                                       start: TestClock.day(0),
                                       source: .appleHealthDevice("Apple Watch")))

        let idleOut = try XCTUnwrap(EnergyModel.evaluate(samples: idle, now: cardNow,
                                                         calendar: cardCalendar))
        let busyOut = try XCTUnwrap(EnergyModel.evaluate(samples: busy, now: cardNow,
                                                        calendar: cardCalendar))
        XCTAssertLessThan(busyOut.level, idleOut.level)
        XCTAssertGreaterThan(busyOut.spent, idleOut.spent)
    }

    /// The curve is the loved part. It has to exist and stay in range.
    func testTheCurveRunsThroughTheDayAndStaysInRange() throws {
        var samples = nightly(.sleepDurationHours, [7.5, 7.6, 7.4, 7.5])
        samples += nightly(.restingHeartRate, [55, 55, 56, 55])
        let output = try XCTUnwrap(EnergyModel.evaluate(samples: samples, now: cardNow,
                                                        calendar: cardCalendar))
        XCTAssertFalse(output.curve.isEmpty)
        XCTAssertTrue(output.curve.allSatisfy { (0...100).contains($0.level) })
        XCTAssertEqual(output.curve.map(\.date), output.curve.map(\.date).sorted())
        XCTAssertEqual(output.level, output.curve.last?.level)
    }

    /// Time above resting is what catches strain that never became a workout.
    func testTimeAboveRestingCountsAsExertion() throws {
        let dayStart = cardCalendar.startOfDay(for: cardNow)
        var samples: [HealthMetricSample] = []
        for hour in 0..<10 {
            // Half the readings well above a resting baseline of 55.
            samples.append(HealthMetricSample(
                type: .heartRate, value: hour < 5 ? 95 : 58,
                start: dayStart.addingTimeInterval(Double(hour) * 3600),
                source: .appleHealthDevice("Apple Watch")))
        }
        let hours = try XCTUnwrap(EnergyModel.exertionHours(
            samples: samples, restingBaseline: 55, since: dayStart, until: cardNow))
        XCTAssertGreaterThan(hours, 0)
        let elapsed = cardNow.timeIntervalSince(dayStart) / 3600
        XCTAssertEqual(hours, elapsed * 0.5, accuracy: 0.01)
    }

    /// No night behind it means no reservoir to report — not a made-up number.
    func testWithoutSleepThereIsNoEnergy() {
        XCTAssertNil(EnergyModel.evaluate(samples: nightly(.restingHeartRate, [55, 56, 55]),
                                          now: cardNow, calendar: cardCalendar))
        let result = EnergyInsight().evaluate(samples: [], profile: .init(), now: cardNow)
        XCTAssertNil(result.score)
        // Was "No night yet" — the gap named rather than the ask made, and
        // wrong besides for the reader whose ring stopped syncing a fortnight
        // ago, who has plenty of nights and none recent. Two states now.
        XCTAssertEqual(result.headline, "Connect a sleep source")
        XCTAssertTrue(result.isWorthShowing, "the card must stay on Today to ask")
    }

    /// It's a model, not a measurement, and must never claim otherwise.
    func testItNeverClaimsToBeAMeasurement() throws {
        var samples = nightly(.sleepDurationHours, [7.5, 7.6, 7.4, 7.5])
        samples += nightly(.restingHeartRate, [55, 55, 56, 55])
        let result = EnergyInsight().evaluate(samples: samples, profile: .init(), now: cardNow)
        XCTAssertNotEqual(result.confidence, .high)
    }
}

/// "My ring told me I was getting sick before I felt it" is the most repeated
/// story in wearable communities, because it is the only moment these devices
/// tell you something you couldn't have worked out yourself.
final class HealthWatchTests: XCTestCase {

    /// A settled month, optionally with the last few days pushed in the direction
    /// illness moves each signal.
    private func history(illDays: Int = 0) -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        func series(_ metric: MetricType, healthy: Double, ill: Double, jitter: Double) {
            let values = (0..<40).map { index -> Double in
                let daysAgo = 39 - index
                let base = daysAgo < illDays ? ill : healthy
                return base + Double(index % 3) * jitter - jitter
            }
            samples += nightly(metric, values)
        }
        series(.restingHeartRate, healthy: 55, ill: 62, jitter: 1.2)
        series(.heartRateVariabilityRMSSD, healthy: 46, ill: 32, jitter: 2.5)
        series(.skinTemperatureDeviation, healthy: 0, ill: 0.9, jitter: 0.12)
        series(.respiratoryRate, healthy: 14, ill: 16.5, jitter: 0.3)
        return samples
    }

    func testASettledMonthIsAllClear() throws {
        let output = try XCTUnwrap(HealthWatchModel.evaluate(samples: history(),
                                                             now: cardNow,
                                                             calendar: cardCalendar))
        XCTAssertTrue(output.leaning.isEmpty, "leaning: \(output.leaning.map(\.metric))")
        XCTAssertGreaterThan(output.score, 95)
    }

    /// The whole point: several signals leaning together, each individually
    /// unremarkable.
    func testSeveralSignalsLeaningTogetherIsFound() throws {
        let output = try XCTUnwrap(HealthWatchModel.evaluate(samples: history(illDays: 3),
                                                             now: cardNow,
                                                             calendar: cardCalendar))
        XCTAssertGreaterThanOrEqual(output.leaning.count, 3)
        XCTAssertLessThan(output.score, 50)
    }

    /// **The defect this card exists to route around.** A sustained departure
    /// hides in its own rolling baseline — by the fourth day of a fever, three of
    /// those nights are inside the window the fourth is judged against. This
    /// baseline stops before the recent window starts, so a run that has been
    /// building for a week is *more* visible, not less.
    func testASustainedRunStaysVisible() throws {
        let short = try XCTUnwrap(HealthWatchModel.evaluate(samples: history(illDays: 2),
                                                            now: cardNow,
                                                            calendar: cardCalendar))
        let sustained = try XCTUnwrap(HealthWatchModel.evaluate(samples: history(illDays: 6),
                                                                now: cardNow,
                                                                calendar: cardCalendar))
        XCTAssertLessThanOrEqual(sustained.score, short.score,
                                 "a longer run scored better — the baseline is being contaminated")
        XCTAssertGreaterThanOrEqual(sustained.leaning.count, 3)
    }

    /// One signal off is an ordinary Tuesday. Agreement is the finding, so this
    /// is deliberately *not* worst-offender-dominant like the rest of the app.
    func testOneSignalAloneBarelyMovesTheScore() throws {
        var samples = history()
        // Replace resting heart rate with a run of genuinely high days.
        samples.removeAll { $0.type == .restingHeartRate }
        samples += nightly(.restingHeartRate, (0..<40).map { index in
            index >= 37 ? 78 : 55 + Double(index % 3) * 1.2 - 1.2
        })
        let output = try XCTUnwrap(HealthWatchModel.evaluate(samples: samples, now: cardNow,
                                                             calendar: cardCalendar))
        XCTAssertEqual(output.leaning.count, 1)
        XCTAssertGreaterThan(output.score, 50, "a single outlier should not dominate")
    }

    /// Movement the *healthy* way is not a warning.
    func testAFavourableMoveIsNotAWarning() throws {
        var samples = history()
        samples.removeAll { $0.type == .heartRateVariabilityRMSSD }
        // HRV rising is good news.
        samples += nightly(.heartRateVariabilityRMSSD, (0..<40).map { index in
            index >= 37 ? 70 : 46 + Double(index % 3) * 2.5 - 2.5
        })
        let output = try XCTUnwrap(HealthWatchModel.evaluate(samples: samples, now: cardNow,
                                                             calendar: cardCalendar))
        XCTAssertFalse(output.leaning.contains { $0.metric == .heartRateVariabilityRMSSD })
    }

    /// One signal, one vote: the two HRV metrics are one measurement reported
    /// twice and must not both count.
    func testDuplicateSignalsCollapseToOneVote() throws {
        var samples = history(illDays: 3)
        samples += nightly(.heartRateVariabilitySDNN, (0..<40).map { index in
            39 - index < 3 ? 30 : 52 + Double(index % 3)
        })
        let output = try XCTUnwrap(HealthWatchModel.evaluate(samples: samples, now: cardNow,
                                                             calendar: cardCalendar))
        let autonomic = output.signals.filter { $0.metric.family == .autonomic }
        XCTAssertEqual(autonomic.count, 1, "both HRV metrics voted")
    }

    func testTooLittleDataSaysSoRatherThanGuessing() {
        let result = ReadinessInsight().evaluate(samples: nightly(.restingHeartRate, [55, 56]),
                                                   profile: .init(), now: cardNow)
        XCTAssertNil(result.score)
        XCTAssertEqual(result.headline, "Building baseline")
    }

    /// Wording guardrail: this is an observation, never a diagnosis.
    func testItNeverDiagnoses() {
        let result = ReadinessInsight().evaluate(samples: history(illDays: 3),
                                                   profile: .init(), now: cardNow)
        let text = (result.explanation + " " + result.drivers.joined(separator: " ")).lowercased()
        // Naming a cause, or telling someone what to do about it, is where a
        // description becomes a diagnosis. The word "diagnosis" itself is fine —
        // and required — in the disclaimer asserted below.
        for banned in ["you have", "infection", "virus", "you are ill", "you should",
                       "diagnosis of", "suggests you"] {
            XCTAssertFalse(text.contains(banned), "Health Watch diagnosed: \(text)")
        }
        XCTAssertTrue(result.drivers.joined().contains("not a diagnosis"),
                      "the disclaimer must travel with the finding, not only with the card")
    }
}

/// Every sleep feature in every app reports last night. Nobody reports the
/// balance, which is the number people actually feel.
final class SleepDebtTests: XCTestCase {

    func testSleepingYourNeedLeavesNoDebt() throws {
        let output = try XCTUnwrap(SleepDebtModel.evaluate(
            samples: nightly(.sleepDurationHours, Array(repeating: 8, count: 14)),
            now: cardNow, calendar: cardCalendar))
        XCTAssertLessThan(output.debtHours, 1)
        XCTAssertEqual(output.band, "Clear")
    }

    /// Four short nights in a row is a different state from one, and this is the
    /// only thing in the app that can tell them apart.
    func testARunOfShortNightsAccumulates() throws {
        let one = try XCTUnwrap(SleepDebtModel.evaluate(
            samples: nightly(.sleepDurationHours,
                             Array(repeating: 8.0, count: 13) + [5.5]),
            now: cardNow, calendar: cardCalendar))
        let several = try XCTUnwrap(SleepDebtModel.evaluate(
            samples: nightly(.sleepDurationHours,
                             Array(repeating: 8.0, count: 10) + [5.5, 5.5, 5.5, 5.5]),
            now: cardNow, calendar: cardCalendar))
        XCTAssertGreaterThan(several.debtHours, one.debtHours * 2)
    }

    /// The need is learned, not assumed. Someone who reliably takes nine hours is
    /// in debt at eight.
    func testTheNeedIsLearnedFromTheirOwnLongerNights() {
        let longSleeper = SleepDebtModel.need(from: Array(repeating: 9.2, count: 20))
        XCTAssertTrue(longSleeper.learned)
        XCTAssertGreaterThan(longSleeper.hours, 8.5)

        let shortSleeper = SleepDebtModel.need(from: Array(repeating: 6.8, count: 20))
        XCTAssertLessThan(shortSleeper.hours, 7.5)
    }

    func testTheLearnedNeedIsBounded() {
        XCTAssertLessThanOrEqual(SleepDebtModel.need(from: Array(repeating: 14.0, count: 20)).hours,
                                 SleepDebtModel.maximumNeed)
        XCTAssertGreaterThanOrEqual(SleepDebtModel.need(from: Array(repeating: 3.0, count: 20)).hours,
                                    SleepDebtModel.minimumNeed)
    }

    func testTooFewNightsFallsBackAndSaysSo() {
        let fallback = SleepDebtModel.need(from: [7.5, 8.0])
        XCTAssertFalse(fallback.learned)
        XCTAssertEqual(fallback.hours, 8)
    }

    /// Debt fades. A bad night three weeks ago is not still costing you, which is
    /// what stops the number ratcheting to infinity over a busy month.
    func testOldDebtDecays() throws {
        let recent = try XCTUnwrap(SleepDebtModel.evaluate(
            samples: nightly(.sleepDurationHours, Array(repeating: 8.0, count: 13) + [4.0]),
            now: cardNow, calendar: cardCalendar))
        let old = try XCTUnwrap(SleepDebtModel.evaluate(
            samples: nightly(.sleepDurationHours, [4.0] + Array(repeating: 8.0, count: 13)),
            now: cardNow, calendar: cardCalendar))
        XCTAssertGreaterThan(recent.debtHours, old.debtHours * 3)
    }

    func testNightsToClearIsWholeNights() throws {
        let output = try XCTUnwrap(SleepDebtModel.evaluate(
            samples: nightly(.sleepDurationHours, Array(repeating: 5.5, count: 14)),
            now: cardNow, calendar: cardCalendar))
        XCTAssertGreaterThan(output.nightsToClear, 0)
        XCTAssertEqual(Double(output.nightsToClear),
                       (output.debtHours / SleepDebtModel.catchUpPerNight).rounded(.up))
    }
}

/// "Your HRV is 48" means nothing to someone who has never seen anyone else's.
/// The centile is the sentence people send to their friends.
final class PeerStandingTests: XCTestCase {

    private func profile(age: Double, male: Bool) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: cardNow.addingTimeInterval(-age * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: cardNow))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: cardNow))
        return p
    }

    func testTheNormalApproximationIsSane() {
        XCTAssertEqual(PeerStandingModel.normalCDF(0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(PeerStandingModel.normalCDF(1.96), 0.975, accuracy: 1e-3)
        XCTAssertEqual(PeerStandingModel.normalCDF(-1.96), 0.025, accuracy: 1e-3)
    }

    /// A low resting heart rate is a *high* centile, even though it's a low
    /// number. Getting this backwards would be the whole card's credibility.
    func testLowerIsBetterMetricsAreOrientedCorrectly() throws {
        var samples = nightly(.restingHeartRate, Array(repeating: 48.0, count: 10))
        let athlete = try XCTUnwrap(PeerStandingModel.evaluate(
            samples: samples, profile: profile(age: 40, male: true),
            now: cardNow, calendar: cardCalendar))
        XCTAssertGreaterThan(try XCTUnwrap(athlete.standings.first).percentile, 90)

        samples = nightly(.restingHeartRate, Array(repeating: 84.0, count: 10))
        let sedentary = try XCTUnwrap(PeerStandingModel.evaluate(
            samples: samples, profile: profile(age: 40, male: true),
            now: cardNow, calendar: cardCalendar))
        XCTAssertLessThan(try XCTUnwrap(sedentary.standings.first).percentile, 15)
    }

    /// The norms are age-banded, so the same number reads differently at
    /// different ages — which is the entire reason to have them.
    func testTheSameNumberReadsDifferentlyAtDifferentAges() throws {
        let samples = nightly(.heartRateVariabilityRMSSD, Array(repeating: 45.0, count: 10))
        let young = try XCTUnwrap(PeerStandingModel.evaluate(
            samples: samples, profile: profile(age: 25, male: true), now: cardNow,
            calendar: cardCalendar))
        let older = try XCTUnwrap(PeerStandingModel.evaluate(
            samples: samples, profile: profile(age: 60, male: true), now: cardNow,
            calendar: cardCalendar))
        XCTAssertGreaterThan(try XCTUnwrap(older.standings.first).percentile,
                             try XCTUnwrap(young.standings.first).percentile,
                             "45 ms is a better figure at 60 than at 25")
    }

    /// It must never disagree with Cardio Fitness about what average looks like —
    /// both read the same norm line.
    func testVO2SharesItsNormLineWithFitnessAge() throws {
        let reference = FitnessAgeModel.referenceVO2(age: 40, sex: .male)
        let samples = nightly(.vo2Max, [reference], source: .appleHealth)
        let output = try XCTUnwrap(PeerStandingModel.evaluate(
            samples: samples, profile: profile(age: 40, male: true), now: cardNow,
            calendar: cardCalendar))
        XCTAssertEqual(try XCTUnwrap(output.standings.first).percentile, 50, accuracy: 2)
    }

    func testWithoutAgeAndSexThereIsNobodyToCompareTo() {
        let result = HeartHealthInsight().evaluate(
            samples: nightly(.restingHeartRate, Array(repeating: 55.0, count: 10)),
            profile: .init(), now: cardNow)
        XCTAssertNil(result.score)
        XCTAssertTrue(result.unmetRequirements.contains { $0.kind == .dateOfBirth })
    }

    // MARK: - Lean mass via FFMI

    /// Lean mass is placed by fat-free mass index, so it needs a height. With
    /// one it becomes a real centile and labels itself in kg/m²; without one it
    /// falls to the unnormed list rather than being compared in raw kilograms,
    /// which would place a tall person and a short person at the same weight
    /// wrongly.
    func testLeanMassIsComparedByFFMIAndNeedsAHeight() throws {
        // 60 kg lean at 1.80 m → FFMI 18.5, a hair below the young-male mean of
        // 19.0, so a little under the fiftieth centile.
        let withHeight = nightly(.leanBodyMass, Array(repeating: 60.0, count: 3))
            + nightly(.height, [1.80])
        let output = try XCTUnwrap(PeerStandingModel.evaluate(
            metrics: [.leanBodyMass], samples: withHeight,
            profile: profile(age: 30, male: true), now: cardNow, calendar: cardCalendar))
        let lean = try XCTUnwrap(output.standings.first { $0.metric == .leanBodyMass })
        XCTAssertEqual(lean.value, 60.0 / (1.80 * 1.80), accuracy: 0.01)
        // **The comment above is the claim, so the assert has to be able to
        // refute it.** This was `45, accuracy: 12` — anything from 33 to 57, a
        // quarter of the whole scale, so a reading of 57 would have satisfied
        // it while contradicting "a little under the fiftieth centile". The
        // direction is the claim; the band is what makes a drifting norm table
        // visible.
        XCTAssertLessThan(lean.percentile, 50,
                          "FFMI 18.5 is below the young-male mean of 19.0, so it cannot "
                          + "be at or above the fiftieth centile")
        XCTAssertEqual(lean.percentile, 38.9, accuracy: 1,
                       "the male FFMI norm has moved — decide whether that was intended")
        XCTAssertEqual(lean.displayLabel, "18.5 kg/m² (FFMI)")
        XCTAssertTrue(output.unNormed.isEmpty)

        let noHeight = nightly(.leanBodyMass, Array(repeating: 60.0, count: 3))
        let fallback = try XCTUnwrap(PeerStandingModel.evaluate(
            metrics: [.leanBodyMass], samples: noHeight,
            profile: profile(age: 30, male: true), now: cardNow, calendar: cardCalendar))
        XCTAssertTrue(fallback.standings.isEmpty)
        XCTAssertEqual(fallback.unNormed, [.leanBodyMass])
    }

    /// More fat-free mass per height is a higher centile — the same orientation
    /// VO₂max carries, and the check that FFMI is not accidentally lower-is-better.
    func testMoreLeanMassIsAHigherCentile() throws {
        func centile(lean: Double) throws -> Double {
            let samples = nightly(.leanBodyMass, [lean]) + nightly(.height, [1.80])
            let output = try XCTUnwrap(PeerStandingModel.evaluate(
                metrics: [.leanBodyMass], samples: samples,
                profile: profile(age: 30, male: true), now: cardNow, calendar: cardCalendar))
            return try XCTUnwrap(output.standings.first).percentile
        }
        XCTAssertGreaterThan(try centile(lean: 68), try centile(lean: 56))
    }

    // MARK: - Blood pressure is judged, just not by centile

    /// Systolic and diastolic used to sit under "no published norm", which reads
    /// as the app not knowing what a healthy blood pressure is. They are assessed
    /// by ACC/AHA category instead, and belong in their own bucket.
    func testBloodPressureIsAssessedByCategoryNotListedAsUnnormed() throws {
        let samples = nightly(.bloodPressureSystolic, [128]) + nightly(.bloodPressureDiastolic, [82])
        let output = try XCTUnwrap(PeerStandingModel.evaluate(
            metrics: [.bloodPressureSystolic, .bloodPressureDiastolic], samples: samples,
            profile: profile(age: 40, male: true), now: cardNow, calendar: cardCalendar))
        XCTAssertEqual(Set(output.assessedByCategory),
                       [.bloodPressureSystolic, .bloodPressureDiastolic])
        XCTAssertFalse(output.unNormed.contains(.bloodPressureSystolic))
        XCTAssertFalse(output.unNormed.contains(.bloodPressureDiastolic))
    }

    /// A modelled quantity has no population to compare against and must not be
    /// listed as "no published norm yet" — that would imply one is coming.
    func testAModelledMetricIsDroppedFromTheComparisonEntirely() throws {
        let samples = nightly(.restingHeartRate, Array(repeating: 55.0, count: 5))
            + nightly(.activeMedicationLevel, [12.0])
        let output = try XCTUnwrap(PeerStandingModel.evaluate(
            metrics: [.restingHeartRate, .activeMedicationLevel], samples: samples,
            profile: profile(age: 40, male: true), now: cardNow, calendar: cardCalendar))
        XCTAssertFalse(output.unNormed.contains(.activeMedicationLevel))
        XCTAssertFalse(output.assessedByCategory.contains(.activeMedicationLevel))
        XCTAssertFalse(output.standings.contains { $0.metric == .activeMedicationLevel })
    }

    /// A centile describes where you sit, not whether anything is wrong.
    func testItIsHonestAboutBeingAnApproximation() {
        let result = HeartHealthInsight().evaluate(
            samples: nightly(.restingHeartRate, Array(repeating: 55.0, count: 10)),
            profile: profile(age: 40, male: true), now: cardNow)
        XCTAssertTrue(result.explanation.contains("approximation"))
        XCTAssertTrue(result.explanation.contains("not whether anything is wrong"))
    }

    func testItSitsOnTheInsightsTab() {
        XCTAssertEqual(InsightID.heartHealth.cadence, .trend)
    }
}

/// The two registrations that fail silently rather than at compile time.
final class NewCardRegistrationTests: XCTestCase {

    func testEveryNewCardIsRegistered() {
        let ids = Set(InsightEngine().models.map(\.id))
        for id in [InsightID.energy, .readiness, .sleep, .heartHealth] {
            XCTAssertTrue(ids.contains(id), "\(id.rawValue) is not in the engine")
        }
    }

    func testEveryInsightIsRegisteredExactlyOnce() {
        let ids = InsightEngine().models.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(InsightID.allCases),
                       "an InsightID exists with no model behind it, or vice versa")
    }

    func testTheThreeNewDailyCardsLandOnToday() {
        for id in [InsightID.energy, .readiness, .sleep] {
            XCTAssertEqual(id.cadence, .daily, "\(id.rawValue) is on the wrong tab")
        }
    }

    /// Sixteen insights, eight hues. Preferences must stay distinct or the
    /// per-chart resolver has nothing to work with.
    func testTheNewCardsDidNotReintroduceAHueCollision() {
        let preferences = InsightID.allCases.map(\.colourSlot)
        XCTAssertEqual(Set(preferences).count, preferences.count)
    }
}
