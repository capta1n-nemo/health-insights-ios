import XCTest
@testable import InsightKit

private let coverageNow = TestClock.now
private let coverageCalendar = TestClock.utc

/// **A quiet night and an unworn night are not the same night.** Backlog B3-19.
///
/// Every card in the app refuses to score on data it does not have. What none
/// of them did was say what they had — so a green radar was ambiguous between
/// *nothing stirred* and *the ring was on the charger*, and the reader had no
/// way to tell. These tests pin the distinction and the denominator.
final class InstrumentCoverageTests: XCTestCase {

    private var startOfToday: Date { coverageCalendar.startOfDay(for: coverageNow) }

    /// A reading at 02:00 on the night `nightsAgo` nights back — comfortably
    /// inside any sane night window, so the tests are about coverage rather
    /// than about boundary arithmetic.
    private func sample(_ family: MetricSource, type: MetricType = .heartRateVariabilityRMSSD,
                        nightsAgo: Int) -> HealthMetricSample {
        HealthMetricSample(
            type: type, value: 50,
            start: startOfToday.addingTimeInterval(2 * 3_600 - Double(nightsAgo) * 86_400),
            source: family)
    }

    private func coverage(_ samples: [HealthMetricSample],
                          nights: Int = 90) -> InstrumentCoverage {
        InstrumentCoverage.night(samples: samples, now: coverageNow,
                                 calendar: coverageCalendar, nightsAssessed: nights)
    }

    // MARK: - The point of the whole thing

    func testASilentInstrumentIsListedRatherThanOmitted() throws {
        // Oura on 20 nights, but not last night. Apple Watch on all of them.
        var samples = (1...20).map { sample(.oura, nightsAgo: $0) }
        samples += (0...20).map { sample(.appleHealthDevice("Apple Watch"), nightsAgo: $0) }

        let out = coverage(samples)
        let oura = try XCTUnwrap(out.instruments.first { $0.family == "oura" })
        XCTAssertFalse(oura.reported)
        XCTAssertEqual(oura.nightsCovered, 20)
        XCTAssertEqual(out.reporting.count, 1)
        XCTAssertEqual(out.silent.map(\.family), ["oura"])
    }

    /// The sentence a quiet card cannot be trusted without.
    func testTheCaveatSaysNotScoredRatherThanClear() throws {
        var samples = (1...20).map { sample(.oura, nightsAgo: $0) }
        samples += (0...20).map { sample(.appleHealthDevice("Apple Watch"), nightsAgo: $0) }
        let caveat = try XCTUnwrap(coverage(samples).caveat)
        XCTAssertTrue(caveat.contains("not being scored"))
        XCTAssertFalse(caveat.lowercased().contains("charg"),
                       "nothing on this phone knows why an instrument was silent")
    }

    /// A met requirement says nothing. Same rule as `CoverageGate.sentence`.
    func testAFullNightCarriesNoCaveat() {
        let samples = (0...20).map { sample(.oura, nightsAgo: $0) }
        let out = coverage(samples)
        XCTAssertNil(out.caveat)
        XCTAssertTrue(out.silent.isEmpty)
    }

    // MARK: - The denominator

    func testCoverageCountsNightsNotReadings() {
        // Eight readings, all on the same three nights.
        let samples = [0, 0, 0, 1, 1, 2, 2, 2].map { sample(.oura, nightsAgo: $0) }
        let out = coverage(samples)
        XCTAssertEqual(out.instruments.first?.nightsCovered, 3)
        XCTAssertEqual(out.instruments.first?.samplesInWindow, 3)
    }

    func testTheDenominatorIsTheAssessedWindowAndIsStated() throws {
        let samples = (0..<40).map { sample(.oura, nightsAgo: $0) }
        let report = try XCTUnwrap(coverage(samples, nights: 30).instruments.first)
        XCTAssertEqual(report.nightsAssessed, 30)
        XCTAssertEqual(report.nightsCovered, 30, "nights beyond the window do not count")
        XCTAssertEqual(report.coverageSentence, "Reported on 30 of the last 30 nights.")
    }

    /// Without a floor, one stray reading from somebody else's scale becomes a
    /// permanent accusing row about a device the reader never owned.
    func testAOneOffReadingDoesNotBecomeAKnownInstrument() {
        let samples = [sample(.withings, type: .bodyMass, nightsAgo: 40)]
            + (0...20).map { sample(.oura, nightsAgo: $0) }
        XCTAssertEqual(coverage(samples).instruments.map(\.family), ["oura"])
    }

    // MARK: - What counts as an instrument

    /// A figure this app worked out cannot be on a charger, and a hand-typed
    /// reading cannot be unworn. Listing either turns a coverage report into a
    /// chore list.
    ///
    /// `shotsy` and `screenshot` are the ones that got through the first build:
    /// both classify as `directAPI` because they have their own source ids, and
    /// both sat in the silent list on a simulator accusing the reader of not
    /// importing a file last night.
    func testModelledAndHandedOverSourcesAreNotInstruments() {
        let samples = (0...20).flatMap { night in
            [sample(.calculated, nightsAgo: night),
             sample(.manual, nightsAgo: night),
             sample(.document, nightsAgo: night),
             sample(.shotsy, type: .bodyMass, nightsAgo: night),
             sample(.screenshot, type: .screenTimeMinutes, nightsAgo: night)]
        }
        XCTAssertTrue(coverage(samples).isEmpty)
    }

    /// A quiet night lists every instrument the reader owns, and a paragraph of
    /// device names buries the sentence that matters.
    func testTheCaveatCapsHowManyItNames() throws {
        let families: [MetricSource] = [
            .oura, .withings, .whoop, .hume,
            .appleHealthDevice("Apple Watch"), .appleHealthDevice("iPhone"),
        ]
        let samples = families.flatMap { family in
            (1...20).map { sample(family, nightsAgo: $0) }
        }
        let out = coverage(samples)
        XCTAssertEqual(out.silent.count, families.count)
        let caveat = try XCTUnwrap(out.caveat)
        XCTAssertTrue(caveat.contains("and \(families.count - 3) more"), caveat)
    }

    /// The label must not depend on which sample the loop saw last.
    func testTheShortestNameWinsWhateverTheSampleOrder() {
        let forwards = (0...20).flatMap { night in
            [sample(.oura, nightsAgo: night), sample(.appleHealthDevice("Oura"), nightsAgo: night)]
        }
        XCTAssertEqual(coverage(forwards).instruments.first?.displayName, "Oura")
        XCTAssertEqual(coverage(forwards.reversed()).instruments.first?.displayName, "Oura")
    }

    /// One physical ring reaching the app by two routes is one instrument. The
    /// alternative overstates coverage and would let a broken direct sync hide
    /// behind an Apple Health mirror.
    func testTheSameDeviceOnTwoRoutesIsOneInstrument() {
        let samples = (0...20).flatMap { night in
            [sample(.oura, nightsAgo: night),
             sample(.appleHealthDevice("Oura"), nightsAgo: night)]
        }
        XCTAssertEqual(coverage(samples).instruments.count, 1)
    }

    // MARK: - Copy

    /// D19's rule: a sentence never states a count the code does not have.
    func testTheHeadlineCountsWhatIsActuallyThere() {
        var samples = (1...20).map { sample(.oura, nightsAgo: $0) }
        samples += (0...20).map { sample(.appleHealthDevice("Apple Watch"), nightsAgo: $0) }
        XCTAssertEqual(coverage(samples).headline, "1 of 2 instruments reported.")

        let all = (0...20).flatMap { night in
            [sample(.oura, nightsAgo: night),
             sample(.appleHealthDevice("Apple Watch"), nightsAgo: night)]
        }
        XCTAssertEqual(coverage(all).headline, "All 2 instruments reported.")
    }

    func testNothingKnownYetDoesNotDraw() {
        XCTAssertTrue(coverage([]).isEmpty)
    }

    func testTheWindowIsTheNightThatJustEnded() {
        let out = coverage((0...5).map { sample(.oura, nightsAgo: $0) })
        XCTAssertLessThan(out.window.start, startOfToday)
        XCTAssertLessThanOrEqual(out.window.end, coverageNow)
        XCTAssertGreaterThan(out.window.end, startOfToday)
    }
}
