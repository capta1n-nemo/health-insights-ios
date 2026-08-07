import XCTest
@testable import InsightKit

/// The dose arithmetic behind "Sound you took on" (backlog §B3 #22 / §B5 #33),
/// pinned against hand-computed figures rather than against the model's own
/// formula — which would only prove it agrees with itself.
final class SoundExposureTests: XCTestCase {

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Midnight UTC, 2024-08-08. `now` sits at noon so a "today" sample is
    /// inside the window without the window's edge being exercised by accident.
    private let now = Date(timeIntervalSince1970: 19_942 * 86_400 + 43_200)

    /// One derived dose sample, exactly as `SoundDoseModel` writes them: value
    /// is the day's LEQ, and the **span is the measured time**.
    private func dose(_ metric: MetricType, level: Double, hours: Double,
                      daysAgo: Int) -> HealthMetricSample {
        let day = Date(timeIntervalSince1970:
                        Double(19_942 - daysAgo) * 86_400)
        return HealthMetricSample(type: metric, value: level, start: day,
                                  end: day.addingTimeInterval(hours * 3600),
                                  source: .calculated)
    }

    // MARK: - The span is the dose's other half

    /// **The regression this whole design exists for.** `SoundDoseModel` used
    /// to write a point sample, so the measured time — the multiplier every
    /// published limit is stated in terms of — was thrown away at the moment it
    /// was computed.
    func testTheDerivedSampleCarriesTheMeasuredTimeInItsSpan() throws {
        let raw = [
            RawMetricSample(identifier: SoundDoseModel.headphoneIdentifier,
                            displayName: "test", value: 85, unit: "dBASPL",
                            start: Date(timeIntervalSince1970: 19_942 * 86_400 + 9 * 3600),
                            end: Date(timeIntervalSince1970: 19_942 * 86_400 + 13 * 3600),
                            source: .appleHealthDevice("iPhone")),
        ]
        let sample = try XCTUnwrap(SoundDoseModel.dailySamples(from: raw, calendar: utc).first)
        XCTAssertEqual(sample.value, 85, accuracy: 1e-9)
        XCTAssertEqual(SoundDoseModel.measuredSeconds(of: sample), 4 * 3600, accuracy: 1e-6)
    }

    /// **Two days at the same level and different lengths are the same LEQ and
    /// different doses.** The single sentence that says why a level cannot be
    /// weighed against a limit on its own.
    func testTheSameLevelForLongerIsAProportionallyLargerDose() {
        let short = SoundExposureModel.Day(date: now, level: 85, hours: 1)
        let long = SoundExposureModel.Day(date: now, level: 85, hours: 10)
        XCTAssertEqual(short.allowanceHoursUsed * 10, long.allowanceHoursUsed,
                       accuracy: 1e-9)
    }

    // MARK: - The allowance arithmetic, by hand

    /// An hour at the allowance level costs exactly one allowance-hour, by
    /// definition — the identity any correct implementation satisfies exactly.
    func testAnHourAtTheAllowanceLevelCostsOneAllowanceHour() {
        let day = SoundExposureModel.Day(date: now,
                                         level: SoundExposureModel.allowanceLevel,
                                         hours: 1)
        XCTAssertEqual(day.allowanceHoursUsed, 1, accuracy: 1e-9)
    }

    /// **Three decibels doubles the rate**, which is the whole reason a dose is
    /// not an average. By hand: 10^(3/10) = 1.9953.
    func testThreeDecibelsAboveTheAllowanceCostsTwiceAsFast() {
        let quiet = SoundExposureModel.Day(date: now, level: 80, hours: 1)
        let loud = SoundExposureModel.Day(date: now, level: 83, hours: 1)
        XCTAssertEqual(loud.allowanceHoursUsed / quiet.allowanceHoursUsed,
                       1.9953, accuracy: 0.001)
    }

    /// NIOSH's own published table, which is the cheapest possible check that
    /// the exchange rate is the right way up: 85 dB(A) → 8 h, 88 → 4 h,
    /// 91 → 2 h, 100 → 15 minutes.
    func testNIOSHPermittedTimesMatchThePublishedTable() {
        func hours(_ level: Double) -> Double {
            SoundExposureModel.Day(date: now, level: level, hours: 1).nioshPermittedHours
        }
        XCTAssertEqual(hours(85), 8, accuracy: 1e-9)
        XCTAssertEqual(hours(88), 4, accuracy: 1e-9)
        XCTAssertEqual(hours(91), 2, accuracy: 1e-9)
        XCTAssertEqual(hours(100), 0.25, accuracy: 1e-9)
    }

    /// Forty hours at 80 dB(A) across the week is exactly the allowance, and a
    /// week carrying the same energy in fewer, louder hours is the same figure.
    /// **Equal energy, equal dose** — the property the card's headline claims.
    func testEqualEnergyWeeksReachTheSameFigureHoweverTheyAreSpread() throws {
        let even = (0..<5).map { dose(.headphoneSoundDose, level: 80, hours: 8, daysAgo: $0) }
        // 4 hours at 90 dB(A) is ten times the rate, so 40 allowance-hours.
        let spiky = [dose(.headphoneSoundDose, level: 90, hours: 4, daysAgo: 1)]

        let a = try XCTUnwrap(SoundExposureModel.evaluate(samples: even, now: now, calendar: utc))
        let b = try XCTUnwrap(SoundExposureModel.evaluate(samples: spiky, now: now, calendar: utc))
        XCTAssertEqual(a.allowanceHoursUsed, 40, accuracy: 1e-6)
        XCTAssertEqual(b.allowanceHoursUsed, 40, accuracy: 1e-6)
        XCTAssertEqual(a.score, b.score, accuracy: 1e-9)
        // …and the two weeks are *not* the same to a reader, which is why the
        // listening hours are reported separately and carry no weight.
        XCTAssertEqual(a.listeningHours, 40, accuracy: 1e-6)
        XCTAssertEqual(b.listeningHours, 4, accuracy: 1e-6)
    }

    // MARK: - Never one figure

    /// The surviving rule of the original refusal, held here as well as in
    /// `SoundDoseModel`: environmental exposure never enters the total.
    func testEnvironmentalSoundIsNeverAddedToTheHeadphoneTotal() throws {
        let headphones = [dose(.headphoneSoundDose, level: 80, hours: 1, daysAgo: 1)]
        let both = headphones + (0..<3).map {
            dose(.environmentalSoundDose, level: 95, hours: 12, daysAgo: $0)
        }

        let alone = try XCTUnwrap(SoundExposureModel.evaluate(samples: headphones, now: now, calendar: utc))
        let together = try XCTUnwrap(SoundExposureModel.evaluate(samples: both, now: now, calendar: utc))

        XCTAssertEqual(alone.allowanceHoursUsed, together.allowanceHoursUsed, accuracy: 1e-9)
        XCTAssertEqual(alone.score, together.score, accuracy: 1e-9)
        // It is *reported*, though — shown beside, never added.
        XCTAssertNil(alone.environment)
        XCTAssertEqual(try XCTUnwrap(together.environment).daysMeasured, 3)
    }

    /// The coverage sentence is what makes the environmental figure honest, so
    /// it must always name both halves: how many days, and how long a day.
    func testTheCoverageSentenceStatesBothHalvesOfWhatWasMissed() throws {
        let samples = (0..<3).map {
            dose(.environmentalSoundDose, level: 62, hours: 6, daysAgo: $0)
        } + [dose(.headphoneSoundDose, level: 70, hours: 1, daysAgo: 1)]
        let out = try XCTUnwrap(SoundExposureModel.evaluate(samples: samples, now: now, calendar: utc))
        let environment = try XCTUnwrap(out.environment)
        let phrase = SoundExposureModel.coveragePhrase(environment)
        XCTAssertTrue(phrase.contains("3 of the last 90 days"), phrase)
        XCTAssertTrue(phrase.contains("6.0 hours"), phrase)
        XCTAssertTrue(phrase.contains("invent"), phrase)
    }

    // MARK: - A quiet week is not a missing week

    /// ⚠️ **The distinction the whole card rests on.** Headphone exposure is
    /// written by the device doing the playing, so a week with nothing in it is
    /// a real zero — *provided* the reader has history showing their phone
    /// writes these at all.
    func testAQuietWeekScoresRatherThanVanishing() throws {
        let old = dose(.headphoneSoundDose, level: 90, hours: 3, daysAgo: 60)
        let out = try XCTUnwrap(SoundExposureModel.evaluate(samples: [old], now: now, calendar: utc))
        XCTAssertEqual(out.recordedDays, 0)
        XCTAssertEqual(out.allowanceHoursUsed, 0, accuracy: 1e-9)
        XCTAssertEqual(out.score, 100, accuracy: 1e-9)
        XCTAssertEqual(out.historyDays, 1)
    }

    /// With no headphone history at all there is nothing to say, and the card
    /// asks instead of reporting a perfect week.
    func testNoHistoryAtAllProducesNothing() {
        XCTAssertNil(SoundExposureModel.evaluate(samples: [], now: now, calendar: utc))
        let card = SoundExposureInsight().evaluate(
            samples: [], profile: UserHealthProfile(), now: now)
        XCTAssertNil(card.score)
        XCTAssertTrue(card.invitesInput)
        XCTAssertTrue(card.isWorthShowing)
    }

    /// A dose sample with no span predates the span being carried. It holds a
    /// real level and no measurable exposure, and assuming a duration for it is
    /// precisely the invention this domain refuses.
    func testASpanlessSampleIsNeverGivenAnAssumedDuration() throws {
        let spanless = HealthMetricSample(type: .headphoneSoundDose, value: 95,
                                          start: Date(timeIntervalSince1970: 19_941 * 86_400),
                                          source: .calculated)
        let out = try XCTUnwrap(SoundExposureModel.evaluate(samples: [spanless], now: now, calendar: utc))
        XCTAssertEqual(out.recordedDays, 0)
        XCTAssertEqual(out.allowanceHoursUsed, 0, accuracy: 1e-9)
    }

    // MARK: - The score

    /// Exactly the published allowance is the top of `fair`: there is no
    /// headroom left in the week, and calling that `good` would make the card
    /// congratulate somebody sitting on the limit.
    func testSittingExactlyOnTheAllowanceIsNotGood() {
        let score = SoundExposureModel.score(allowanceUsed: 1)
        XCTAssertLessThan(score, ScoreBand.goodFloor)
        XCTAssertEqual(ScoreBand(score: score), .fair)
        // Half the allowance is unremarkable and scores like it.
        XCTAssertEqual(ScoreBand(score: SoundExposureModel.score(allowanceUsed: 0.5)), .good)
    }

    func testTheScoreFallsAsTheAllowanceIsSpent() {
        let scores = [0.1, 0.5, 1.0, 2.0, 4.0, 10.0]
            .map { SoundExposureModel.score(allowanceUsed: $0) }
        XCTAssertEqual(scores, scores.sorted(by: >), "\(scores)")
        XCTAssertEqual(SoundExposureModel.score(allowanceUsed: 0), 100, accuracy: 1e-9)
        // Flat rather than extrapolated past the last anchor — a score of −40
        // is how a curve leaves its own evidence behind.
        XCTAssertEqual(SoundExposureModel.score(allowanceUsed: 1_000), 0, accuracy: 1e-9)
    }

    // MARK: - What the card says

    func testTheCardStatesItsWeightingAndItsUnweightedRowSaysWhy() throws {
        let samples = (0..<4).map { dose(.headphoneSoundDose, level: 84, hours: 2, daysAgo: $0) }
            + (0..<2).map { dose(.environmentalSoundDose, level: 66, hours: 5, daysAgo: $0) }
        let card = SoundExposureInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: now)

        XCTAssertNotNil(card.score)
        if case .singleMeasure = card.weighting {} else {
            XCTFail("expected singleMeasure, got \(card.weighting)")
        }
        // The weighted picture is the headphone dose and nothing else.
        XCTAssertEqual(card.weightedFactors.count, 1)
        XCTAssertEqual(card.weightedFactors.first?.metric, .headphoneSoundDose)
        // …and every row carrying nothing says why, in the shape
        // `ScoreAttributionTests` enforces app-wide.
        for factor in card.unweightedFactors {
            XCTAssertTrue(factor.detail.contains("—"), factor.name)
        }
        // Both declared metrics are read, which is what stops the card claiming
        // to look at something it does not.
        XCTAssertEqual(Set(card.contributors.metrics),
                       Set(SoundExposureInsight().candidateMetrics))
    }

    /// Every derived factor names a series the same result produces — the
    /// property `DerivedFactorIdentityTests` sweeps for, checked here at the
    /// one call site so a failure names this card rather than the sweep.
    func testEveryDerivedFactorNamesASeriesThisCardProduces() {
        let samples = (0..<4).map { dose(.headphoneSoundDose, level: 84, hours: 2, daysAgo: $0) }
        let card = SoundExposureInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: now)
        let produced = Set(card.derivedOutputs.map { DerivedSeriesID(card.id, $0.key) })
        for factor in card.otherFactors {
            let id = factor.derivedSeries
            XCTAssertNotNil(id, factor.name)
            XCTAssertTrue(produced.contains(id!), "\(factor.name) names \(id!)")
        }
    }
}
