import XCTest
@testable import InsightKit

/// The app's own biological age.
///
/// **Three of these pin defects found by opening the card on the reader's real
/// record**, none of which any test would have caught, because each is a claim
/// about what the number *means* rather than about what it equals. The first
/// build published "biological age 22" for a reader whose fitness scores 33 and
/// whose blood pressure is 144/88, and the section built to explain the card
/// explained it in one line: *"heart-rate variability carries 95% of it."*
final class BiologicalAgeTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func profile(age: Double, male: Bool = true) -> UserHealthProfile {
        var p = UserHealthProfile()
        let dob = now.addingTimeInterval(-age * 365.2425 * 86_400)
        p.set(.init(kind: .dateOfBirth, value: dob.timeIntervalSince1970, recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: now))
        return p
    }

    /// Daily samples of one metric at a constant value, over `days`.
    private func series(_ metric: MetricType, _ value: Double,
                        days: Int = 120) -> [HealthMetricSample] {
        (0..<days).map { day in
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            return HealthMetricSample(type: metric, value: value, start: date, end: date,
                                      source: .appleHealth)
        }
    }

    /// A record built to read as exactly its own age on every marker, so any
    /// departure in a test below is the thing that test is about.
    private func typicalRecord(for age: Double, male: Bool = true,
                               days: Int = 400) -> [HealthMetricSample] {
        let sex: BiologicalSex = male ? .male : .female
        var out: [HealthMetricSample] = []
        for metric in [MetricType.vo2Max, .heartRateVariabilityRMSSD,
                       .bloodPressureSystolic, .bodyFatPercentage, .walkingSpeed] {
            guard let value = BiologicalAgeModel.expected(metric, age: age, sex: sex)
            else { continue }
            out += series(metric, value, days: days)
        }
        return out
    }

    // MARK: - The combination rule

    func testAPersonAtEveryNormReadsAsTheirOwnAge() throws {
        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: typicalRecord(for: 45), profile: profile(age: 45),
            now: now, calendar: utc))
        XCTAssertEqual(out.biologicalAge, 45, accuracy: 1.5,
                       "someone sitting on every published norm should read as their own age")
    }

    func testTheWeightsSumToOne() throws {
        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: typicalRecord(for: 50), profile: profile(age: 50),
            now: now, calendar: utc))
        XCTAssertEqual(out.markers.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.001)
    }

    /// The design's central claim: a marker whose norm curve is flatter is
    /// trusted less, automatically, with nobody choosing that.
    ///
    /// Walking speed barely moves between forty and fifty, so it can pin an age
    /// only loosely; HRV falls steeply over the same stretch. Neither fact is
    /// written anywhere as a weight — both fall out of the tables.
    func testAFlatterCurveEarnsLessWeightWithoutAnyoneChoosingIt() throws {
        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: typicalRecord(for: 45), profile: profile(age: 45),
            now: now, calendar: utc))
        let gait = try XCTUnwrap(out.markers.first { $0.metric == .walkingSpeed })
        let hrv = try XCTUnwrap(out.markers.first { $0.metric == .heartRateVariabilityRMSSD })
        XCTAssertLessThan(gait.weight, hrv.weight,
                          "gait speed is nearly flat in middle age and must not outvote a steep marker")
        XCTAssertGreaterThan(gait.uncertaintyYears, hrv.uncertaintyYears)
    }

    /// The same marker gets *more* say later in life, because its curve steepens.
    /// Nothing in the code says so; the norm table does.
    ///
    /// **And at forty it does not appear at all**, which was a surprise worth
    /// keeping: usual gait speed is so nearly flat between twenty-five and
    /// forty-five that inverting it gives an age good to about two centuries,
    /// and the model drops anything past 120 years rather than draw a 0% row.
    /// So a reader in middle age sees no walking-speed row on this card, and one
    /// at eighty sees it near the top — from one table and no special case.
    func testGaitSpeedIsUselessAtFortyAndStrongAtEighty() throws {
        let young = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: typicalRecord(for: 40), profile: profile(age: 40),
            now: now, calendar: utc))
        XCTAssertFalse(young.markers.contains { $0.metric == .walkingSpeed },
                       "gait speed cannot separate a forty-year-old from a fifty-year-old and must not pretend to")

        let old = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: typicalRecord(for: 80), profile: profile(age: 80),
            now: now, calendar: utc))
        let oldGait = try XCTUnwrap(old.markers.first { $0.metric == .walkingSpeed })
        XCTAssertGreaterThan(oldGait.weight, 0.15,
                             "past seventy the curve steepens and gait becomes one of the better markers there is")
    }

    // MARK: - The three defects the simulator found

    /// ⚠️ **Defect 1.** The first build answered with two markers, one carrying
    /// 95%, and called the result a biological age. That is a single measurement
    /// under a grander name — the same opacity as a vendor's black box, reached
    /// from the other direction.
    func testItRefusesToAnswerOnFewerThanThreeMarkers() {
        var samples = series(.heartRateVariabilityRMSSD, 36)
        samples += series(.walkingSpeed, 1.35)
        XCTAssertNil(BiologicalAgeModel.evaluate(samples: samples, profile: profile(age: 40),
                                                 now: now, calendar: utc),
                     "two markers is not a composite, and a composite is the whole argument for this card")
    }

    /// And the refusal is not a wall: the card must be able to say which marker
    /// is missing and what closes it.
    func testTheEmptyStateNamesTheMissingMarkersRatherThanSayingNoData() {
        var samples = series(.heartRateVariabilityRMSSD, 36)
        samples += series(.walkingSpeed, 1.35)
        let have = BiologicalAgeModel.availability(samples: samples, now: now, calendar: utc)
        XCTAssertTrue(have.absent.contains(.vo2Max))
        XCTAssertTrue(have.absent.contains(.bloodPressureSystolic))
        for metric in have.absent {
            XCTAssertFalse(BiologicalAgeModel.remedy(metric).isEmpty,
                           "\(metric) is reported missing with nothing the reader can do about it")
        }
    }

    /// ⚠️ **Defect 2, and the one that took two rounds to get right.**
    ///
    /// Round one clamped a past-the-end value to the bound, then read its slope
    /// *at* the bound — out in the tail where the curve is steepest. Steepest
    /// slope means smallest σ means largest weight, so the marker the model knew
    /// least about carried the most. Round two excluded clamped markers
    /// entirely, which was safe and, opened on the reader's real record, **threw
    /// away two of their five markers** — body fat 32% and overnight rMSSD 69,
    /// both ordinary readings for a real adult.
    ///
    /// The resolution is that these curves are *medians*: for several markers
    /// the whole span of adult ageing is narrower than the spread between people
    /// at one age, so a large share of ordinary readers sit outside the curve.
    /// Their information is imprecise, not absent — and σ already prices
    /// imprecision. So it extrapolates and weighs.
    func testAnOrdinaryReadingPastTheEndOfTheCurveStillCounts() throws {
        var samples = typicalRecord(for: 45)
        samples.removeAll { $0.type == .bodyFatPercentage }
        samples += series(.bodyFatPercentage, 32)   // high, common, past the male curve

        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: samples, profile: profile(age: 45), now: now, calendar: utc))
        let fat = try XCTUnwrap(out.markers.first { $0.metric == .bodyFatPercentage })
        XCTAssertTrue(fat.isExtrapolated, "past the table's end, and the row must say so")
        XCTAssertGreaterThan(fat.ageEquivalent, 60,
                             "32% body fat is older than the median forty-five-year-old man")
        XCTAssertGreaterThan(fat.weight, 0, "imprecise is not the same as absent")
    }

    /// But a value that is not a person at all is still refused — that is a
    /// units mistake or a sensor fault, and weighing it would let one broken
    /// import move the whole card.
    func testAValueThatIsNotAPersonIsStillRefused() throws {
        var samples = typicalRecord(for: 45)
        samples.removeAll { $0.type == .heartRateVariabilityRMSSD }
        samples += series(.heartRateVariabilityRMSSD, 200)

        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: samples, profile: profile(age: 45), now: now, calendar: utc))
        XCTAssertFalse(out.markers.contains { $0.metric == .heartRateVariabilityRMSSD })
        XCTAssertTrue(out.outOfRange.contains { $0.metric == .heartRateVariabilityRMSSD },
                      "and it is reported, because 'check this at source' is the useful answer")
        XCTAssertEqual(out.biologicalAge, 45, accuracy: 2,
                       "the rest of the card must be undisturbed by it")
    }

    /// ⚠️ **The guard both `ContributorsTests` and `CandidateReachabilityTests`
    /// fired on.** Every candidate this card declares must come back either as a
    /// weighted marker or as an unused one with a reason. A declared input that
    /// appears nowhere charts under "How you compare" while "What goes into
    /// this" says it was never read — the card contradicting itself across two
    /// sections.
    func testEveryDeclaredMarkerComesBackEitherWeightedOrExplained() throws {
        // Deliberately awkward: a woman whose VO₂max and body fat both sit off
        // the ends of the female curves, which is exactly the fixture that
        // caught this.
        var samples = typicalRecord(for: 45, male: false)
        samples.removeAll { $0.type == .vo2Max || $0.type == .bodyFatPercentage }
        samples += series(.vo2Max, 46)
        samples += series(.bodyFatPercentage, 18)

        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: samples, profile: profile(age: 45, male: false),
            now: now, calendar: utc))
        let accounted = Set(out.markers.map(\.metric)).union(out.unused.map(\.metric))
        for metric in BiologicalAgeModel.candidates {
            XCTAssertTrue(accounted.contains(metric),
                          "\(metric) is declared by this card and comes back neither weighted nor explained")
        }
        for skipped in out.unused {
            XCTAssertFalse(skipped.sentence.isEmpty,
                           "\(skipped.metric) is dropped with no reason given")
        }
    }

    /// ⚠️ **Defect 3.** One window for every marker deleted three of the five on
    /// the reader's real record: VO₂max and cuff readings do not arrive daily,
    /// and ninety days with a five-day floor excludes them almost always.
    func testTheSparseMarkersAreReadOverALongerWindow() throws {
        XCTAssertGreaterThan(BiologicalAgeModel.lookbackDays(.vo2Max),
                             BiologicalAgeModel.lookbackDays(.heartRateVariabilityRMSSD))
        XCTAssertGreaterThan(BiologicalAgeModel.lookbackDays(.bloodPressureSystolic),
                             BiologicalAgeModel.lookbackDays(.walkingSpeed))

        // Monthly VO₂max and monthly cuff readings — realistic, and invisible to
        // a ninety-day window.
        var samples = series(.heartRateVariabilityRMSSD, 36)
        samples += series(.walkingSpeed, 1.35)
        for month in 0..<10 {
            let date = now.addingTimeInterval(-Double(month) * 30 * 86_400)
            samples.append(HealthMetricSample(type: .vo2Max, value: 38, start: date,
                                              end: date, source: .appleHealth))
            samples.append(HealthMetricSample(type: .bloodPressureSystolic, value: 124,
                                              start: date, end: date, source: .appleHealth))
        }
        let out = BiologicalAgeModel.evaluate(samples: samples, profile: profile(age: 45),
                                              now: now, calendar: utc)
        XCTAssertNotNil(out, "ten monthly readings of two markers is enough to answer")
        XCTAssertTrue(out?.markers.contains { $0.metric == .vo2Max } ?? false)
    }

    /// No single marker may quietly become the card. With the full set present
    /// the heaviest must still be a minority, or the composite is decorative.
    func testNoSingleMarkerDominatesTheAnswer() throws {
        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: typicalRecord(for: 45), profile: profile(age: 45),
            now: now, calendar: utc))
        let heaviest = try XCTUnwrap(out.markers.map(\.weight).max())
        XCTAssertLessThan(heaviest, 0.7,
                          "one marker at 95% is a measurement wearing a biological age's name")
    }

    // MARK: - Honesty

    /// The error bar is wide, and that is the point. A build that quietly
    /// shrinks it — by folding chronological age in, which is what the published
    /// method and every commercial version do — would be the first thing to
    /// notice here.
    func testTheStatedErrorIsHonestlyWide() throws {
        let out = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: typicalRecord(for: 45), profile: profile(age: 45),
            now: now, calendar: utc))
        XCTAssertGreaterThan(out.uncertaintyYears, 5,
                             "these markers cannot pin an age to better than about a decade, and the card must not pretend otherwise")
    }

    /// Chronological age is not an input to the arithmetic. Change the birthday,
    /// and the biological age must not move at all.
    func testTheBirthdayDoesNotMoveTheAnswer() throws {
        let samples = typicalRecord(for: 45)
        let asForty = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: samples, profile: profile(age: 40), now: now, calendar: utc))
        let asSixty = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: samples, profile: profile(age: 60), now: now, calendar: utc))
        XCTAssertEqual(asForty.biologicalAge, asSixty.biologicalAge, accuracy: 0.001,
                       "including chronological age is what makes every vendor's version hug the birthday")
    }

    /// The headline compares the gap with the error, not with zero. A three-year
    /// gap on a ±11 estimate is not a finding and must not be printed as one.
    func testAGapSmallerThanTheErrorIsNotReportedAsAFinding() {
        let out = BiologicalAgeModel.Output(
            biologicalAge: 42, uncertaintyYears: 11, chronologicalAge: 46,
            yearsYounger: 4, markers: [])
        XCTAssertFalse(BiologicalAgeModel.headline(out).contains("years younger"),
                       "four years inside an eleven-year error is noise, not news")
    }

    /// Every norm curve must be invertible, or the whole method is unavailable
    /// for that marker. A non-monotonic table would make bisection return
    /// nonsense rather than fail.
    func testEveryNormCurveIsStrictlyMonotonicAndInvertible() throws {
        for sex in [BiologicalSex.male, .female] {
            for metric in BiologicalAgeModel.candidates {
                guard BiologicalAgeModel.anchors(metric, sex: sex) != nil else { continue }
                var previous = try XCTUnwrap(
                    BiologicalAgeModel.expected(metric, age: 18, sex: sex))
                let rising = try XCTUnwrap(
                    BiologicalAgeModel.expected(metric, age: 95, sex: sex)) > previous
                for age in stride(from: 19.0, through: 95.0, by: 1) {
                    let here = try XCTUnwrap(
                        BiologicalAgeModel.expected(metric, age: age, sex: sex))
                    XCTAssertEqual(here > previous, rising,
                                   "\(metric) \(sex) reverses direction at \(age), so it cannot be inverted")
                    previous = here
                }
                // Round trip: the age a norm value came from is the age it
                // inverts back to.
                for age in [25.0, 45, 65, 85] {
                    let value = try XCTUnwrap(
                        BiologicalAgeModel.expected(metric, age: age, sex: sex))
                    let back = try XCTUnwrap(
                        BiologicalAgeModel.invert(metric, value: value, sex: sex))
                    XCTAssertEqual(back.age, age, accuracy: 0.1,
                                   "\(metric) \(sex) does not round-trip at \(age)")
                }
            }
        }
    }

    /// Every marker states how its instrument differs from the laboratory the
    /// norms were built in. A systematic bias does not cancel in the pace
    /// figure the way random error does, so an unstated one is a number wrong in
    /// one direction for years.
    func testEveryMarkerCarriesItsInstrumentCaveat() {
        for metric in BiologicalAgeModel.candidates {
            XCTAssertFalse(BiologicalAgeModel.instrumentCaveat(metric).isEmpty,
                           "\(metric) is compared against a laboratory norm with nothing said about the difference")
        }
    }

    /// The dial must not lurch as the gap crosses zero.
    func testTheScoreCurveHasNoCliff() {
        var previous = BiologicalAgeModel.score(yearsYounger: -20)
        for step in stride(from: -20.0, through: 20.0, by: 0.05) {
            let here = BiologicalAgeModel.score(yearsYounger: step)
            XCTAssertLessThan(abs(here - previous), 1,
                              "the score jumps at \(step) years")
            previous = here
        }
    }
}
