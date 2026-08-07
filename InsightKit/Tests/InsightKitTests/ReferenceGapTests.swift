import XCTest
@testable import InsightKit

/// The reference gap: whether the days immediately before today may help set the
/// bar today is judged against.
///
/// ## Why these tests exist
///
/// `VitalReader.reading` grew a `gapDays: Int = 0` parameter on 2026-08-05 and
/// exactly one caller ever passed it. Every other card therefore judged today
/// against a baseline that included yesterday — so an excursion that lasted
/// stopped being an excursion, which the reader reported twice in one day
/// (*"still the same value.. but no longer in danger?"*). Nothing failed,
/// because nothing tested it: the parameter's default silently supplied the
/// wrong answer to twenty-odd call sites.
///
/// `gap` is now required and typed (`ReferenceGap`), so that class cannot
/// recur — a new caller does not compile until it chooses. What a compiler
/// cannot check is whether each caller chose *correctly*, and that is what the
/// second half of this file pins.
final class ReferenceGapTests: XCTestCase {

    private let now = TestClock.now
    private let calendar = TestClock.utc

    /// One value a day, oldest first, ending `endingDaysAgo` days back.
    private func series(_ metric: MetricType, _ values: [Double],
                        endingDaysAgo: Int = 0) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: TestClock.day(endingDaysAgo + values.count - 1 - index),
                               source: .oura)
        }
    }

    private func read(_ samples: [HealthMetricSample], gap: ReferenceGap,
                      minimumDays: Int = VitalReader.defaultMinimumDays) -> VitalReading? {
        VitalReader.reading(.restingHeartRate, from: samples, now: now,
                            minimumDays: minimumDays, gap: gap, calendar: calendar)
    }

    // MARK: - The mechanism

    /// `.none` and `.days(0)` are the same window, so the enum has not smuggled
    /// a behaviour change into the callers that kept today's answer.
    func testNoneIsExactlyAZeroDayGap() throws {
        let samples = series(.restingHeartRate, Array(repeating: 55, count: 20) + [70])
        let plain = try XCTUnwrap(read(samples, gap: .none))
        let zero = try XCTUnwrap(read(samples, gap: .days(0)))
        XCTAssertEqual(plain.history, zero.history)
        XCTAssertEqual(plain.baseline, zero.baseline)
    }

    /// A negative gap is a caller's arithmetic slip, not an instruction to reach
    /// into the future. It must clamp rather than produce an empty window.
    func testANegativeGapIsTreatedAsNone() throws {
        let samples = series(.restingHeartRate, Array(repeating: 55, count: 20) + [70])
        let clamped = try XCTUnwrap(read(samples, gap: .days(-3)))
        XCTAssertEqual(clamped.history, try XCTUnwrap(read(samples, gap: .none)).history)
    }

    /// The gap actually withholds days: two days of gap costs exactly the two
    /// days before today, and no more.
    func testAGapWithholdsExactlyItsOwnDays() throws {
        // 20 quiet days, then two days at 90, then today.
        let samples = series(.restingHeartRate,
                             Array(repeating: 55, count: 20) + [90, 90, 92])
        let ungapped = try XCTUnwrap(read(samples, gap: .none))
        let gapped = try XCTUnwrap(read(samples, gap: .days(2)))
        XCTAssertEqual(ungapped.history.count - gapped.history.count, 2)
        XCTAssertFalse(gapped.history.contains(90),
                       "the two raised days must be out of the window judging today")
        XCTAssertTrue(ungapped.history.contains(90))
    }

    /// **The defect, reproduced.** A departure that has lasted three days is
    /// still a departure. Without the gap the excursion is most of what the
    /// standard deviation is made of, so today sits comfortably inside it and
    /// the card falls silent while the body has not changed at all.
    func testAnExcursionDoesNotAgeIntoItsOwnBaseline() throws {
        // Real jitter on the quiet days, not a flat line: a zero spread has no
        // z-score at all, so a flat fixture would pass this test by refusing to
        // answer rather than by answering correctly.
        let quiet = (0..<21).map { 55 + Double($0 % 3) - 1 }
        let samples = series(.restingHeartRate, quiet + [78, 79, 80])
        let ungapped = try XCTUnwrap(read(samples, gap: .none))
        let gapped = try XCTUnwrap(read(samples, gap: VitalReader.judgementGap))
        let ungappedZ = try XCTUnwrap(ungapped.zScore)
        let gappedZ = try XCTUnwrap(gapped.zScore)
        XCTAssertGreaterThan(abs(gappedZ), abs(ungappedZ),
                             "holding the excursion out must make today more unusual, not less")
        // And the baseline itself is the quiet one it should be: the two raised
        // days had dragged it up toward the value it was supposed to judge.
        XCTAssertLessThan(try XCTUnwrap(gapped.baseline), try XCTUnwrap(ungapped.baseline))
    }

    /// **The gap is affordable, not mandatory.** A reader eight days in has no
    /// history to spare, and refusing to judge them at all would be worse than
    /// the weakness the gap removes. So it is taken only when the window still
    /// clears its own minimum without those days.
    func testTheGapIsGivenUpRatherThanLoseTheJudgementEntirely() throws {
        // Five prior days plus today: a two-day gap would leave three, below the
        // minimum of four, so the ungapped window has to be used instead.
        let samples = series(.restingHeartRate, [54, 55, 56, 55, 54, 70])
        let gapped = try XCTUnwrap(read(samples, gap: .days(2), minimumDays: 4))
        XCTAssertEqual(gapped.history.count, 5, "the gap must be dropped, not the judgement")
        XCTAssertNotNil(gapped.zScore)
    }

    // MARK: - Which caller gets which answer

    /// **The call site backlog P38 was written about.** `VitalDeparture.forCard`
    /// reads its *extra* rows — a card's scored contributors that the clinical
    /// scan has no spec for — straight from `VitalReader`, and every one renders
    /// as "away from your normal" beside the scan's own rows.
    ///
    /// Pinned on the z rather than the value, and against *both* answers: the
    /// value is identical whatever the gap, so asserting on it would pass with
    /// the panel judged the old way. The row must match the gapped read and
    /// differ from the ungapped one.
    func testTheDeparturePanelGivesItsExtraRowsTheJudgementGap() throws {
        let metric = MetricType.sleepDurationHours
        XCTAssertFalse(VitalSignsCheck.coveredMetrics.contains(metric),
                       "fixture assumes this metric reaches the panel as an extra row")
        let quiet = (0..<21).map { 7.5 + Double($0 % 3) * 0.1 }
        let samples = series(metric, quiet + [4.4, 4.3, 4.2])

        let panel = VitalDeparturePanel.forCard(
            VitalSignsCheck.evaluate(samples: samples, now: now, calendar: calendar),
            cardMetrics: nil as [MetricType]?, contributorMetrics: [metric],
            samples: samples, now: now, calendar: calendar)
        let row = try XCTUnwrap(panel.rows.first { $0.metric == metric })

        func z(_ gap: ReferenceGap) throws -> Double {
            try XCTUnwrap(VitalReader.reading(metric, from: samples, now: now,
                                              gap: gap, calendar: calendar)?.zScore)
        }
        XCTAssertEqual(row.z, try z(VitalReader.judgementGap), accuracy: 0.001)
        XCTAssertNotEqual(row.z, try z(.none), accuracy: 0.001)
    }

    /// `VitalSignsCheck` must not keep its own copy of the number. It had one —
    /// a literal `2` beside `VitalReader`'s literal `2` — which is the shape of
    /// a constant that drifts.
    func testTheScanTakesItsGapFromTheSharedConstant() {
        XCTAssertEqual(VitalSignsCheck.referenceGapDays, VitalReader.judgementGap.count)
    }

    /// The illness radar keeps its own, wider gap: it judges a three-day mean
    /// rather than a day, so it needs more clearance. Two constants on purpose,
    /// and this pins that they are meant to differ rather than having drifted.
    func testTheRadarsGapIsDeliberatelyWiderThanTheScans() {
        XCTAssertGreaterThan(HealthWatchModel.referenceGapDays,
                             VitalReader.judgementGap.count)
    }
}
