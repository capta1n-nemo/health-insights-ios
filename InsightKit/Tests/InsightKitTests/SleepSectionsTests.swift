import XCTest
@testable import InsightKit

/// The four sleep models added on 2026-08-07 for backlog `S11`, `B18-6`,
/// `B18-7` and `B18-8`.
///
/// **The confound tests are the point of this file.** `testAWeekendOnlyPattern…`
/// and `testADriverThatIsOnlyTheDaysActivity…` each construct data in which a
/// naive method finds a strong, wrong answer, and assert that these models find
/// nothing. They are the executable form of the review that refuted the
/// substance card on this reader's own record — where an apparent effect fell
/// from min|z| 0.91 to 0.03 the moment same-day step count entered the model.
final class SleepSectionsTests: XCTestCase {

    private let cal = TestClock.utc
    private let now = TestClock.now

    // MARK: - Fixtures

    /// One night, as the two canonical series stamp it: both at the night's key,
    /// which is the morning it ends on.
    private func night(_ daysAgo: Int, bedtime: Double, hours: Double)
        -> [HealthMetricSample] {
        let key = cal.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86_400))
        return [
            HealthMetricSample(type: .sleepOnset, value: bedtime,
                               start: key, end: key, source: .oura),
            HealthMetricSample(type: .sleepDurationHours, value: hours,
                               start: key, end: key, source: .oura)
        ]
    }

    private func nights(_ count: Int,
                        bedtime: (Int) -> Double,
                        hours: (Int) -> Double) -> [HealthMetricSample] {
        (0..<count).flatMap { night($0, bedtime: bedtime($0), hours: hours($0)) }
    }

    // MARK: - S11 · Sleep Regularity Index

    func testAnIdenticalScheduleEveryNightScoresNearlyPerfectRegularity() throws {
        let samples = nights(40, bedtime: { _ in -1 }, hours: { _ in 8 })
        let output = try XCTUnwrap(
            SleepRegularityIndex.evaluate(samples: samples, days: 90, now: now,
                                          calendar: cal))
        XCTAssertGreaterThan(output.index, 97,
                             "the same 23:00–07:00 every night is the definition of regular")
        XCTAssertEqual(output.pairsSkipped, 0)
        XCTAssertGreaterThan(SleepRegularityIndex.score(index: output.index), 95)
    }

    /// The case the two estimators it replaced were both blind to.
    ///
    /// Every night is **exactly eight hours** — so the night-length spread is
    /// zero and the old consistency term scored a perfect 100 — and the bedtime
    /// alternates by six hours, which is the thing that actually matters.
    func testAnAlternatingScheduleScoresBadlyEvenThoughEveryNightIsEightHours() throws {
        let samples = nights(40, bedtime: { $0.isMultiple(of: 2) ? -3 : 3 },
                             hours: { _ in 8 })
        let output = try XCTUnwrap(
            SleepRegularityIndex.evaluate(samples: samples, days: 90, now: now,
                                          calendar: cal))
        XCTAssertLessThan(output.index, 60,
                          "a six-hour swing every night is irregular however even the durations are")
        // The estimator it replaces sees nothing at all here, which is the whole
        // argument for the swap.
        let spread = Baseline.standardDeviation((0..<40).map { _ in 8.0 }) ?? 0
        XCTAssertEqual(spread, 0, accuracy: 1e-9)
    }

    func testTooFewConsecutiveNightsReturnsNothingRatherThanAWeakNumber() {
        let samples = nights(4, bedtime: { _ in -1 }, hours: { _ in 8 })
        XCTAssertNil(SleepRegularityIndex.evaluate(samples: samples, days: 90,
                                                   now: now, calendar: cal))
    }

    /// A holiday from the ring must not read as catastrophic irregularity.
    func testMissingNightsAreSkippedAndCountedRatherThanScoredAsBeingAwake() throws {
        var samples = nights(30, bedtime: { _ in -1 }, hours: { _ in 8 })
        // Drop a fortnight out of the middle.
        let missing = (10...16).map { daysAgo -> Date in
            cal.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86_400))
        }
        samples.removeAll { missing.contains($0.start) }
        let output = try XCTUnwrap(
            SleepRegularityIndex.evaluate(samples: samples, days: 90, now: now,
                                          calendar: cal))
        XCTAssertGreaterThan(output.index, 97,
                             "the nights that were recorded are identical; the gap is unknown, not awake")
        XCTAssertGreaterThan(output.pairsSkipped, 0, "and the gap is reported rather than hidden")
    }

    func testTheScoreCurveIsMonotoneInTheIndex() {
        var previous = -1.0
        for index in stride(from: 0.0, through: 100.0, by: 2.5) {
            let score = SleepRegularityIndex.score(index: index)
            XCTAssertGreaterThanOrEqual(score, previous,
                                        "a more regular sleeper cannot score lower")
            previous = score
        }
    }

    /// S11's own arithmetic claim: the swap moves no weight.
    func testTheRegularityTermCarriesExactlyWhatTheTwoEstimatorsCarried() {
        XCTAssertEqual(SleepInsight.Weight.regularity, 0.18, accuracy: 1e-9)
        XCTAssertEqual(SleepInsight.Weight.consistency, 0, accuracy: 1e-9)
    }

    // MARK: - B18-7 · The sleep-debt ledger

    func testTheLedgerNamesItsBaselineAndLearnsItFromTheReadersOwnNights() throws {
        // Nine hours most nights, so the learned need is well above eight and
        // could not have come from the fallback.
        let samples = nights(40, bedtime: { _ in -1 },
                             hours: { $0.isMultiple(of: 5) ? 6 : 9 })
        let ledger = try XCTUnwrap(SleepDebtModel.ledger(samples: samples, days: 60,
                                                         now: now, calendar: cal))
        XCTAssertEqual(ledger.basis, .learnedFromYourOwnNights)
        XCTAssertGreaterThan(ledger.needHours, 8,
                             "a reader who reliably takes nine hours is in debt at eight")
        XCTAssertEqual(ledger.publishedBand, 7...9,
                       "the published band is carried for context and never becomes the baseline")
    }

    func testEveryNightIsScoredAsShortOrOverAndNeverBoth() throws {
        let samples = nights(30, bedtime: { _ in -1 },
                             hours: { $0.isMultiple(of: 3) ? 5 : 8.5 })
        let ledger = try XCTUnwrap(SleepDebtModel.ledger(samples: samples, days: 60,
                                                         now: now, calendar: cal))
        for night in ledger.nights {
            XCTAssertTrue(night.shortfall == 0 || night.surplus == 0,
                          "a night cannot be both short of the need and over it")
            XCTAssertEqual(night.shortfall - night.surplus,
                           ledger.needHours - night.hours, accuracy: 1e-9)
        }
    }

    /// A long night adds nothing rather than paying anything back — the
    /// published shape of the quantity, and the thing the section says out loud.
    func testASurplusNightNeverReducesTheBalance() throws {
        var hours: [Int: Double] = [:]
        for index in 0..<30 { hours[index] = index == 15 ? 12 : 8 }
        let samples = nights(30, bedtime: { _ in -1 }, hours: { hours[$0] ?? 8 })
        let ledger = try XCTUnwrap(SleepDebtModel.ledger(samples: samples, days: 60,
                                                         now: now, calendar: cal))
        XCTAssertTrue(ledger.nights.allSatisfy { $0.debtAfter >= 0 },
                      "the balance is a sum of shortfalls and can never go negative")
    }

    // MARK: - B18-8 · The ideal sleep window

    private func onsets(_ count: Int, _ value: (Int) -> Double) -> [VitalReader.DailyValue] {
        (0..<count).map {
            .init(date: cal.startOfDay(for: now.addingTimeInterval(-Double($0) * 86_400)),
                  value: value($0))
        }
    }

    func testItRefusesToNameAWindowBeforeThereAreEnoughNights() {
        let days = onsets(10) { _ in -1 }
        let output = IdealSleepWindow.evaluate(
            onsets: days, outcome: days.map { .init(date: $0.date, value: 70) },
            outcomeName: "next-day Readiness", calendar: cal)
        guard case let .notEnoughNights(have, need) = output.verdict else {
            return XCTFail("expected a refusal, got \(output.verdict)")
        }
        XCTAssertEqual(have, 10)
        XCTAssertEqual(need, IdealSleepWindow.minimumNights)
    }

    /// ⚠️ **The weekend confound, made executable.**
    ///
    /// Weekends have a bedtime an hour later *and* an outcome ten points higher,
    /// and inside each block bedtime does nothing at all. A method that pooled
    /// the days would report "late nights precede good days" with a big effect.
    /// This one must report that nothing separates the bins.
    func testAWeekendOnlyPatternIsNotReportedAsABedtimeFinding() {
        var bedtimes: [VitalReader.DailyValue] = []
        var outcomes: [VitalReader.DailyValue] = []
        for index in 0..<180 {
            let day = cal.startOfDay(for: now.addingTimeInterval(-Double(index) * 86_400))
            let isWeekend = cal.isDateInWeekend(day)
            bedtimes.append(.init(date: day, value: isWeekend ? -0.25 : -1.25))
            outcomes.append(.init(date: day, value: isWeekend ? 80 : 70))
        }
        let output = IdealSleepWindow.evaluate(
            onsets: bedtimes, outcome: outcomes, outcomeName: "next-day Readiness",
            calendar: cal)
        XCTAssertEqual(output.verdict, .nothingSeparates,
                       "the whole difference is the weekend, and the weekend is folded out first")
        XCTAssertNotNil(output.socialJetlagHours,
                        "and the shift it folded out is reported rather than silently absorbed")
    }

    /// The opposite case: a real effect *within* each day type must survive.
    func testAWithinBlockBedtimeEffectIsFound() {
        var bedtimes: [VitalReader.DailyValue] = []
        var outcomes: [VitalReader.DailyValue] = []
        for index in 0..<180 {
            let day = cal.startOfDay(for: now.addingTimeInterval(-Double(index) * 86_400))
            // Three bedtimes on a fixed rotation, independent of day type, and a
            // large, clean penalty for the latest one.
            let slot = index % 3
            let bedtime = [-1.75, -1.25, 0.25][slot]
            bedtimes.append(.init(date: day, value: bedtime))
            outcomes.append(.init(date: day, value: slot == 2 ? 55 : 80))
        }
        let output = IdealSleepWindow.evaluate(
            onsets: bedtimes, outcome: outcomes, outcomeName: "next-day Readiness",
            calendar: cal)
        guard case let .window(from, to, betterBy) = output.verdict else {
            return XCTFail("a 25-point difference on 180 nights should be found, got \(output.verdict)")
        }
        XCTAssertLessThan(from, 0, "the good window is the earlier bedtimes")
        XCTAssertLessThanOrEqual(to, 0.25)
        XCTAssertEqual(betterBy, 25, accuracy: 3)
    }

    // MARK: - B18-6 · What's impacting your sleep

    private func series(_ count: Int, _ value: (Int) -> Double) -> [VitalReader.DailyValue] {
        (0..<count).map {
            .init(date: cal.startOfDay(for: now.addingTimeInterval(-Double($0) * 86_400)),
                  value: value($0))
        }
    }

    /// The night that *begins* on waking day D is keyed to the morning of D+1.
    private func nightsAfter(_ count: Int, _ value: (Int) -> Double) -> [VitalReader.DailyValue] {
        (0..<count).map {
            .init(date: cal.startOfDay(for: now.addingTimeInterval(-Double($0 - 1) * 86_400)),
                  value: value($0))
        }
    }

    /// Deterministic pseudo-noise, so a "nothing here" test cannot pass or fail
    /// on the machine's mood.
    ///
    /// ⚠️ **It has to be a real generator, not arithmetic on the index.** The
    /// first version of this was `(index * k + seed * m) % 1000`, which is a
    /// *periodic* sequence: two such series correlate strongly with each other,
    /// and a circular shift of one can re-align it with itself exactly. Both
    /// "pure noise" tests below failed against it — not because the model was
    /// wrong, but because the fixture was not noise. SplitMix64, hashed per
    /// index, has neither property.
    private func noise(_ seed: Int) -> (Int) -> Double {
        { index in
            var z = UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15
            z = z &+ UInt64(bitPattern: Int64(seed)) &* 0xD1B5_4A32_D192_ED03
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z % 1_000_000) / 1_000_000
        }
    }

    func testPureNoiseYieldsNoFindings() {
        let output = SleepInfluences.evaluate(
            outcome: nightsAfter(200, noise(7)),
            outcomeName: "how long you slept", outcomeUnit: "h",
            drivers: (0..<6).map { seed in
                .init(id: "d\(seed)", name: "Driver \(seed)",
                      values: series(200, noise(seed + 11)))
            },
            activity: series(200, noise(3)),
            calendar: cal)
        XCTAssertEqual(output.verdict, .nothingStandsOut)
        XCTAssertEqual(output.tested, 6, "and it says how many candidates that was over")
    }

    /// ⚠️ **The same-day-activity confound, made executable.**
    ///
    /// The driver *is* the day's step count, and the night's sleep is also a
    /// function of the day's step count. There is no relationship between the
    /// driver and sleep once activity is held fixed — and an unadjusted
    /// correlation between them is nearly perfect. This is the exact shape that
    /// collapsed the substance finding from min|z| 0.91 to 0.03.
    func testADriverThatIsOnlyTheDaysActivityIsNotReported() {
        let steps = series(200, noise(23))
        let driver = SleepInfluences.Driver(
            id: "steps.echo", name: "An echo of the day's activity",
            values: steps.map { .init(date: $0.date, value: $0.value * 3 + 1) })
        let sleep = nightsAfter(200) { index in
            // Sleep is entirely explained by that day's activity.
            6 + 2 * self.noise(23)(index)
        }
        let output = SleepInfluences.evaluate(
            outcome: sleep, outcomeName: "how long you slept", outcomeUnit: "h",
            drivers: [driver], activity: steps, calendar: cal)
        XCTAssertEqual(output.verdict, .nothingTestable,
                       "with activity in the model there is nothing left for this to explain")
        XCTAssertEqual(output.untested.first?.reason, .alreadyExplainedByYourActivity,
                       "and the reader is told why, not just that nothing was found")

        // And the unadjusted version really would have found it — otherwise the
        // assertion above is passing for the wrong reason.
        let raw = Baseline.correlation(x: driver.values.map(\.value),
                                       y: steps.map(\.value)) ?? 0
        XCTAssertGreaterThan(abs(raw), 0.99)
    }

    /// A real effect, independent of activity, must still be found — otherwise
    /// the guards above are just a way of never saying anything.
    func testARealEffectIndependentOfActivityIsFound() {
        let activity = series(200, noise(31))
        let driverValues = series(200, noise(41))
        let sleep = nightsAfter(200) { index in
            // Two hours less sleep across the driver's full range, plus a
            // genuine activity term the model has to strip out, plus jitter.
            8 - 2 * self.noise(41)(index) + 0.5 * self.noise(31)(index)
                + 0.05 * self.noise(97)(index)
        }
        let output = SleepInfluences.evaluate(
            outcome: sleep, outcomeName: "how long you slept", outcomeUnit: "h",
            drivers: [.init(id: "real", name: "A real one", values: driverValues)],
            activity: activity, calendar: cal)
        XCTAssertEqual(output.verdict, .found)
        let finding = try? XCTUnwrap(output.findings.first)
        XCTAssertLessThan(finding?.effectPerSD ?? 0, 0, "more of it, less sleep")
        XCTAssertLessThanOrEqual(finding?.adjustedP ?? 1, SleepInfluences.alpha)
    }

    /// **No activity series means no findings, not unadjusted findings.**
    func testWithNoActivityReadingsNothingIsTestedAtAll() {
        let output = SleepInfluences.evaluate(
            outcome: nightsAfter(200, noise(7)),
            outcomeName: "how long you slept", outcomeUnit: "h",
            drivers: [.init(id: "d", name: "Driver", values: series(200, noise(9)))],
            activity: [], calendar: cal)
        XCTAssertEqual(output.tested, 0)
        if case .found = output.verdict {
            XCTFail("a finding was reported with no activity adjustment available")
        }
    }

    /// A section whose findings flicker between launches is worse than one with
    /// none, so the permutation draw is seeded.
    func testTheAnswerIsIdenticalOnASecondRun() {
        func run() -> SleepInfluences.Output {
            SleepInfluences.evaluate(
                outcome: nightsAfter(120, noise(5)),
                outcomeName: "how long you slept", outcomeUnit: "h",
                drivers: (0..<4).map { .init(id: "d\($0)", name: "D\($0)",
                                             values: series(120, noise($0 + 2))) },
                activity: series(120, noise(13)), calendar: cal)
        }
        XCTAssertEqual(run(), run())
    }

    /// Under 30 paired days a driver is named as untestable rather than tested.
    func testAThinDriverIsNamedRatherThanQuietlyDropped() {
        let output = SleepInfluences.evaluate(
            outcome: nightsAfter(60, noise(7)),
            outcomeName: "how long you slept", outcomeUnit: "h",
            drivers: [.init(id: "thin", name: "Only a fortnight of it",
                            values: series(14, noise(17)))],
            activity: series(60, noise(19)), calendar: cal)
        XCTAssertEqual(output.untested.map(\.name), ["Only a fortnight of it"])
        XCTAssertEqual(output.untested.first?.reason, .tooFewDays(14))
        guard case let .notEnoughDays(best, need) = output.verdict else {
            return XCTFail("expected a refusal, got \(output.verdict)")
        }
        XCTAssertLessThan(best, need)
    }
}
