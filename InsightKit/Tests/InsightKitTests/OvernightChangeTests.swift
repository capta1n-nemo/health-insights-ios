import XCTest
@testable import InsightKit

private let changeNow = TestClock.now
private let changeCalendar = TestClock.utc

/// **"What changed while you slept"** — backlog S5, the reader's own request,
/// and the whole difficulty is in the word *changed*.
///
/// A section that printed six overnight numbers would be a summary of the
/// night, which is what four other sleep sections already are. This one has to
/// answer a comparison, and a comparison across channels measured in
/// milliseconds, breaths, degrees and percent only means anything if each is
/// divided by **its own** night-to-night spread. These tests hold that, and
/// hold the two ways it could quietly become dishonest: a spread estimated from
/// too few nights, and a night compared against a window containing itself.
final class OvernightChangeTests: XCTestCase {

    // MARK: - Fixtures

    /// A nightly series ending last night, oldest first.
    private func series(_ metric: MetricType, _ values: [Double]) -> OvernightChange.Series {
        OvernightChange.Series(metric: metric, nights: values.enumerated().map { index, value in
            OvernightChange.Series.Point(day: TestClock.day(values.count - 1 - index),
                                         value: value)
        })
    }

    /// Twenty steady nights either side of a mean, then one final night at
    /// `last`. The scatter is deliberately not zero — a flat reference would
    /// make every divisor degenerate and every test pass for the wrong reason.
    private func steady(_ metric: MetricType, around mean: Double, scatter: Double,
                        last: Double) -> OvernightChange.Series {
        var values = (0..<20).map { mean + (Double($0 % 4) - 1.5) * scatter }
        values.append(last)
        return series(metric, values)
    }

    private func build(_ all: [OvernightChange.Series]) -> OvernightChange.Output? {
        OvernightChange.build(all, now: changeNow, calendar: changeCalendar)
    }

    // MARK: - The comparison itself

    /// The core claim: the same absolute move is ordinary on a noisy channel
    /// and notable on a quiet one, and only dividing by each channel's own
    /// spread can say so.
    func testTheSameMoveIsOrdinaryOnANoisyChannelAndNotableOnAQuietOne() throws {
        let output = try XCTUnwrap(build([
            // Overnight HRV genuinely swings; 8 ms is a Tuesday.
            steady(.heartRateVariabilityRMSSD, around: 48, scatter: 8, last: 56),
            // Respiratory rate does not; 0.8 is not.
            steady(.respiratoryRate, around: 14, scatter: 0.25, last: 14.8)
        ]))
        let hrv = try XCTUnwrap(output.channels.first { $0.metric == .heartRateVariabilityRMSSD })
        let breathing = try XCTUnwrap(output.channels.first { $0.metric == .respiratoryRate })

        XCTAssertTrue(hrv.isOrdinary,
                      "an 8 ms swing on a channel that swings 8 ms was called a change")
        XCTAssertFalse(breathing.isOrdinary,
                       "0.8 breaths on a channel steady to a quarter of one was called ordinary")
        XCTAssertGreaterThan(abs(breathing.z), abs(hrv.z))
    }

    /// ⚠️ **The reference must exclude the night being judged.** With a short
    /// history a night inside its own window drags the mean toward itself and
    /// inflates the spread, which is precisely how a real departure hides.
    func testTheNightBeingJudgedIsNotInItsOwnReference() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 64)
        ]))
        let channel = try XCTUnwrap(output.channels.first)
        XCTAssertEqual(channel.referenceNights, 20,
                       "the night under test was counted in the nights it is compared against")
        XCTAssertEqual(channel.reference, 55, accuracy: 0.75)
        XCTAssertGreaterThan(channel.z, 2, "the departure was absorbed by its own baseline")
    }

    /// A channel with too little history behind it is **named, not dropped** —
    /// "we have not watched this long enough" must never render as "this did
    /// not move".
    func testAChannelWithTooFewNightsIsCarriedRatherThanJudged() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 56),
            series(.oxygenSaturation, [96, 97, 96, 97])
        ]))
        XCTAssertEqual(output.channels.map(\.metric), [.restingHeartRate])
        XCTAssertEqual(output.waiting, [.oxygenSaturation])
        let sentence = try XCTUnwrap(output.waitingSentence)
        XCTAssertTrue(sentence.contains("oxygen"), sentence)
        XCTAssertTrue(sentence.contains("\(OvernightChange.minimumReferenceNights)"), sentence)
    }

    /// The gate is on the count of *prior* nights, not on the length of the
    /// series — one night short must not be judged.
    func testOneNightShortOfTheGateIsStillNotJudged() throws {
        let short = (0..<OvernightChange.minimumReferenceNights).map { 14 + Double($0 % 3) * 0.2 }
        let output = try XCTUnwrap(build([series(.respiratoryRate, short)]))
        XCTAssertTrue(output.channels.isEmpty)
        XCTAssertEqual(output.waiting, [.respiratoryRate])
    }

    // MARK: - Which night, and whose day it is filed under

    /// Sources disagree about which calendar day a night belongs to — a ring
    /// writes at wake, a thermometer is stamped that morning, some providers
    /// key a night to the evening it began. A neighbouring day still belongs to
    /// the night, and the channel keeps its own date so a view can say so.
    func testAChannelFiledADayEitherSideStillBelongsToTheNight() throws {
        var lagged = steady(.skinTemperatureDeviation, around: 0, scatter: 0.1, last: 0.15)
        lagged = OvernightChange.Series(
            metric: lagged.metric,
            nights: lagged.nights.map {
                .init(day: $0.day.addingTimeInterval(-86_400), value: $0.value)
            })
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 56),
            lagged
        ]))
        XCTAssertEqual(Set(output.channels.map(\.metric)),
                       [.restingHeartRate, .skinTemperatureDeviation])
        let thermal = try XCTUnwrap(output.channels.first { $0.metric == .skinTemperatureDeviation })
        XCTAssertLessThan(thermal.day, output.night,
                          "the lagged channel lost its own date")
    }

    /// And a channel that stopped reporting a week ago is **not** last night's,
    /// however much history it has. Reporting it under a "while you slept"
    /// heading would attribute an old reading to a night it was not taken on.
    func testAStaleChannelIsNotReportedAsLastNights() throws {
        var stale = steady(.oxygenSaturation, around: 96, scatter: 0.5, last: 92)
        stale = OvernightChange.Series(
            metric: stale.metric,
            nights: stale.nights.map {
                .init(day: $0.day.addingTimeInterval(-7 * 86_400), value: $0.value)
            })
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 56),
            stale
        ]))
        XCTAssertEqual(output.channels.map(\.metric), [.restingHeartRate])
        XCTAssertFalse(output.waiting.contains(.oxygenSaturation),
                       "a week-old reading was listed as waiting for history it already has")
    }

    // MARK: - Wording

    /// **"Nothing moved" is a finding and is said out loud.** A section that
    /// only speaks when something is wrong teaches the reader to read its
    /// silence as an all-clear it never gave.
    func testAQuietNightSaysSoRatherThanSayingNothing() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1.2, last: 55.4),
            steady(.respiratoryRate, around: 14, scatter: 0.3, last: 14.1),
            steady(.oxygenSaturation, around: 96, scatter: 0.6, last: 96.2)
        ]))
        XCTAssertTrue(output.moved.isEmpty)
        let headline = OvernightChange.headline(output)
        XCTAssertTrue(headline.contains("ordinary night-to-night range"), headline)
        XCTAssertTrue(headline.contains("3"), headline)
    }

    /// ⚠️ **It must not read as a verdict.** Several channels leaning together
    /// is the symptom radar's calibrated claim; this one has no weighting, no
    /// collapsing and no score, and the headline says so the moment it reports
    /// more than one channel moving.
    func testTheHeadlineDefersToTheRadarRatherThanImplyingAVerdict() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 62),
            steady(.respiratoryRate, around: 14, scatter: 0.25, last: 15.2),
            steady(.oxygenSaturation, around: 96, scatter: 0.5, last: 96.1)
        ]))
        XCTAssertEqual(output.moved.count, 2)
        let headline = OvernightChange.headline(output)
        XCTAssertTrue(headline.lowercased().contains("symptom radar"), headline)
        // Hardest first, so the row a reader's eye lands on is the biggest one.
        XCTAssertGreaterThanOrEqual(abs(output.moved[0].z), abs(output.moved[1].z))
    }

    /// Every sentence carries the spread and the number of nights it rests on.
    /// A multiple with no divisor beside it is the shape of a confident claim
    /// about a number nobody can check.
    func testEverySentenceCarriesItsOwnErrorBar() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 62),
            steady(.respiratoryRate, around: 14, scatter: 0.3, last: 14.05)
        ]))
        for channel in output.channels {
            let sentence = OvernightChange.sentence(for: channel)
            XCTAssertTrue(sentence.contains("scatter by about"), sentence)
            XCTAssertTrue(sentence.contains("\(channel.referenceNights) nights"), sentence)
        }
        let ordinary = try XCTUnwrap(output.channels.first { $0.isOrdinary })
        XCTAssertTrue(OvernightChange.sentence(for: ordinary)
            .contains("inside ordinary night-to-night variation"),
                      OvernightChange.sentence(for: ordinary))
    }

    /// A unit must appear once. `MetricValueFormatter` already renders a
    /// saturation as "97%", and the first draft appended the unit again.
    func testAPercentIsNotPrintedTwice() throws {
        let output = try XCTUnwrap(build([
            steady(.oxygenSaturation, around: 96, scatter: 0.5, last: 93)
        ]))
        let sentence = OvernightChange.sentence(for: try XCTUnwrap(output.channels.first))
        XCTAssertFalse(sentence.contains("% %"), sentence)
        XCTAssertFalse(sentence.contains("%%"), sentence)
    }

    /// A sub-unit difference on an integer metric must not print as "0" — the
    /// row would be calling a change notable while showing nothing changing.
    func testASubUnitDifferenceKeepsADecimal() {
        XCTAssertEqual(OvernightChange.formatted(0.4, .restingHeartRate), "0.4 bpm")
        XCTAssertFalse(OvernightChange.formatted(0.4, .restingHeartRate).hasPrefix("0 "))
    }

    // MARK: - Precision, all three found by looking at the simulator

    /// ⚠️ **"14 br/min … 0.5 below your usual 14 br/min"** reached the screen.
    /// `MetricValueFormatter` renders a respiratory rate as an integer, which
    /// is right on an axis and wrong in a sentence about a difference: the rule
    /// is to print finer than the scatter being divided by.
    func testAChannelPrintsFinerThanTheScatterItIsDividedBy() throws {
        let output = try XCTUnwrap(build([
            steady(.respiratoryRate, around: 14, scatter: 0.25, last: 13.5)
        ]))
        let channel = try XCTUnwrap(output.channels.first)
        XCTAssertGreaterThan(channel.decimals, 0,
                             "a channel scattering by a quarter of a breath printed whole breaths")
        let sentence = OvernightChange.sentence(for: channel)
        XCTAssertFalse(sentence.contains("your usual 14 br/min"), sentence)
        XCTAssertTrue(sentence.contains("14."), sentence)
    }

    /// And a channel with a wide scatter must not grow decimals it has not
    /// earned: five bpm of night-to-night noise does not justify "56.34".
    func testAWideScatterKeepsWholeNumbers() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 8, last: 56.34)
        ]))
        XCTAssertEqual(try XCTUnwrap(output.channels.first).decimals, 0)
    }

    /// ⚠️ **"0.2 °C below your usual 0.2 °C"** — the deviation case, where one
    /// decimal is not enough to separate the move from the middle it moved
    /// from, and the sentence reads as a tautology while being arithmetically
    /// exact.
    func testANarrowScatterEarnsASecondDecimalSoTheTwoFiguresDiffer() throws {
        let output = try XCTUnwrap(build([
            steady(.skinTemperatureDeviation, around: 0.2, scatter: 0.2, last: -0.04)
        ]))
        let channel = try XCTUnwrap(output.channels.first)
        XCTAssertEqual(channel.decimals, 2)
        let sentence = OvernightChange.sentence(for: channel)
        XCTAssertFalse(sentence.contains("0.2 °C below your usual 0.2 °C"), sentence)
    }

    /// ⚠️ **"-0.0 °C"** — a skin temperature deviation of −0.04 rendered as a
    /// signed zero on the shipped section. True, useless, and it reads as a
    /// typing error.
    func testAValueThatRoundsToZeroNeverKeepsItsMinusSign() {
        XCTAssertEqual(OvernightChange.formatted(-0.04, .skinTemperatureDeviation, decimals: 1),
                       "0.0 °C")
        XCTAssertEqual(OvernightChange.formatted(-0.0001, .skinTemperatureDeviation, decimals: 2),
                       "0.00 °C")
    }

    // MARK: - How much of this is noise

    /// ⚠️ **The section has to say how many channels move by chance**, or "4 of
    /// 7 moved" reads as a finding when a body doing nothing produces about two.
    /// The symptom radar states a false-alarm budget for exactly this reason.
    func testTheHeadlineSaysHowManyMoveOnAnOrdinaryNight() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 62),
            steady(.respiratoryRate, around: 14, scatter: 0.25, last: 15.2),
            steady(.oxygenSaturation, around: 96, scatter: 0.5, last: 96.1)
        ]))
        XCTAssertTrue(OvernightChange.headline(output).contains("on an ordinary night"),
                      OvernightChange.headline(output))
        // And on a quiet night too — nothing moving is only a finding once the
        // reader knows how many normally do.
        let quiet = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1.2, last: 55.2),
            steady(.respiratoryRate, around: 14, scatter: 0.3, last: 14.05)
        ]))
        XCTAssertTrue(OvernightChange.headline(quiet).contains("on an ordinary night"),
                      OvernightChange.headline(quiet))
    }

    /// ⚠️ **Every channel that moved is named.** The first version listed three
    /// under a count of four, so the sentence read as a complete list and was
    /// not one.
    func testTheHeadlineNamesEveryChannelItCounts() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 62),
            steady(.respiratoryRate, around: 14, scatter: 0.25, last: 15.2),
            steady(.oxygenSaturation, around: 96, scatter: 0.5, last: 94),
            steady(.skinTemperatureDeviation, around: 0, scatter: 0.1, last: 0.4)
        ]))
        let headline = OvernightChange.headline(output)
        XCTAssertEqual(output.moved.count, 4)
        for channel in output.moved {
            XCTAssertTrue(headline.contains(channel.metric.displayName.lowercased()),
                          "\(channel.metric) was counted and not named: \(headline)")
        }
    }

    // MARK: - Degenerate input

    /// A source repeating one number has no spread, and dividing by nothing
    /// would make the flattest channel the loudest thing on the section.
    func testAChannelThatHasNeverMovedIsNotTheLoudestThingOnTheSection() throws {
        let output = try XCTUnwrap(build([
            series(.respiratoryRate, Array(repeating: 14, count: 20) + [16])
        ]))
        let channel = try XCTUnwrap(output.channels.first)
        XCTAssertEqual(channel.spread, 0, accuracy: 1e-9)
        XCTAssertEqual(channel.z, 0, accuracy: 1e-9)
        XCTAssertTrue(channel.isOrdinary)
    }

    func testNothingAtAllIsNil() {
        XCTAssertNil(build([]))
        XCTAssertNil(build([OvernightChange.Series(metric: .restingHeartRate, nights: [])]))
    }

    /// The direction illness pushes each channel comes from the health watch
    /// rather than being decided here, so the two cannot disagree about what
    /// "up" means — and a channel the watch does not watch says nothing about
    /// direction at all rather than guessing.
    func testDirectionComesFromTheHealthWatchAndIsAbsentWhereItHasNoOpinion() throws {
        let output = try XCTUnwrap(build([
            steady(.restingHeartRate, around: 55, scatter: 1, last: 56),
            steady(.sleepEfficiency, around: 90, scatter: 2, last: 91)
        ]))
        let rhr = try XCTUnwrap(output.channels.first { $0.metric == .restingHeartRate })
        let efficiency = try XCTUnwrap(output.channels.first { $0.metric == .sleepEfficiency })
        XCTAssertEqual(rhr.risingIsConcerning, true)
        XCTAssertNil(efficiency.risingIsConcerning)
    }
}
