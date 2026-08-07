import XCTest
@testable import InsightKit

/// **The ledger as an input to a score** — backlog B7 H2/H6/H7.
///
/// ⚠️ Every title here is invented; no real calendar appears in fixtures.
final class LeaveRecencyTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func day(_ n: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(-Double(n) * 86_400))
    }

    private func period(from: Int, to: Int,
                        source: HolidayLedger.Period.Source = .entered)
        -> HolidayLedger.Period {
        HolidayLedger.Period(firstDay: day(from), lastDay: day(to), source: source)
    }

    private func recency(_ periods: [HolidayLedger.Period]) -> LeaveRecency {
        LeaveRecency.read(HolidayLedger(entered: periods, calendar: utc),
                          asOf: now, calendar: utc)
    }

    // MARK: - The guard the whole type is built around

    /// **Silence is not a finding.** A reader who has never told the app about a
    /// holiday must not be scored as somebody who has not had one — that is the
    /// single mistake this file exists to prevent, and it would be invisible
    /// once shipped because the number would look perfectly reasonable.
    func testNothingRecordedScoresNothing() {
        let empty = recency([])
        XCTAssertNil(empty.score, "an empty ledger must produce no score at all")
        XCTAssertNil(empty.daysSinceLastLeave)
        XCTAssertEqual(empty.standing, .unrecorded)
        XCTAssertFalse(empty.hasAnyRecord)
        XCTAssertNil(empty.derivedOutput,
                     "a series with no reading behind it links to an empty page")
    }

    /// **A booking is not a break**, and it is the case that would slip through:
    /// the ledger genuinely holds a period, so a naive `periods.isEmpty` test
    /// would call it grounded and score a fortnight that has not happened.
    func testLeaveBookedAheadIsStillUnrecorded() {
        let booked = recency([period(from: -30, to: -24)])
        XCTAssertNil(booked.score, "future leave must not answer a recovery question")
        XCTAssertEqual(booked.standing, .unrecorded)
        XCTAssertTrue(booked.hasAnyRecord, "the entry is real, it just has not happened")
        // 24 rather than 30: `day(_:)` counts backward, so `from: -30, to: -24`
        // is a week starting 24 days out, and `Period.init` normalises the ends.
        XCTAssertEqual(booked.nextLeaveInDays, 24)
        XCTAssertTrue(booked.driverLine(share: 0.1).contains("not scoring it"))
    }

    /// The two unrecorded cases say different things, because "you told me
    /// nothing" and "you have a week booked" are different states.
    func testTheTwoUnrecordedCasesReadDifferently() {
        XCTAssertTrue(recency([]).driverLine(share: 0.1)
            .contains("cannot tell a year without a break"))
        XCTAssertFalse(recency([period(from: -30, to: -24)]).driverLine(share: 0.1)
            .contains("cannot tell a year without a break"))
    }

    // MARK: - Reading the ledger

    func testDaysSinceAndTheYearsContext() {
        let out = recency([period(from: 200, to: 194), period(from: 40, to: 36)])
        XCTAssertEqual(out.daysSinceLastLeave, 36)
        XCTAssertEqual(out.periodsInLastYear, 2)
        XCTAssertEqual(out.daysOffInLastYear, 12, "seven days plus five, both inclusive")
        XCTAssertEqual(out.standing, .aWhileAgo)
    }

    /// Days off in the last year count **days that have happened**. A booking
    /// inside the window must not inflate the figure the copy prints beside a
    /// score it did not earn.
    func testDaysOffInTheLastYearExcludeWhatIsStillBooked() {
        let out = recency([period(from: 20, to: 16), period(from: -10, to: -4)])
        XCTAssertEqual(out.daysOffInLastYear, 5)
        XCTAssertEqual(out.periodsInLastYear, 1)
    }

    func testOnLeaveTodayReadsAsZero() {
        let out = recency([period(from: 2, to: -2)])
        XCTAssertEqual(out.daysSinceLastLeave, 0)
        XCTAssertEqual(out.standing, .onLeaveNow)
        XCTAssertEqual(out.score, LeaveRecency.score(daysSince: 0))
    }

    // MARK: - The curve

    /// Monotonic, continuous and **floored**. The floor is the honesty claim:
    /// a diary alone must not be able to take a card to the bottom, which is the
    /// same argument `WorkImpactModel.exposureScore` makes about meeting hours.
    func testTheCurveDecaysAndThenFlattensAboveTheFloor() {
        var previous = Double.infinity
        for days in stride(from: 0, through: 500, by: 5) {
            let score = LeaveRecency.score(daysSince: days)
            XCTAssertLessThanOrEqual(score, previous + 1e-9,
                                     "the curve must never rise with time: \(days)d")
            XCTAssertGreaterThanOrEqual(score, LeaveRecency.floorScore - 1e-9,
                                        "\(days)d fell through the floor")
            previous = score
        }
        XCTAssertEqual(LeaveRecency.score(daysSince: 2_000),
                       LeaveRecency.floorScore, accuracy: 1e-9,
                       "past a year, more days are the same finding — older")
    }

    /// No cliff anywhere. The repo's standing defect is a `switch` over a
    /// measurement putting twenty points between two readings a day apart.
    func testNoStepAnywhereInTheCurve() {
        for days in 0..<730 {
            let step = abs(LeaveRecency.score(daysSince: days + 1)
                            - LeaveRecency.score(daysSince: days))
            XCTAssertLessThan(step, 1, "a \(step)-point step at \(days) days")
        }
    }

    // MARK: - The fold

    /// The shares still account for the whole number — the claim "How this is
    /// weighted" makes on screen, and the thing a fold that scaled only one
    /// group would break.
    func testTheFoldKeepsTheSharesSummingToOne() throws {
        let contributions = [
            MetricContribution(metric: .restingHeartRate, higherIsBetter: false,
                               weight: 0.5, detail: "a"),
            MetricContribution(metric: .heartRateVariabilityRMSSD, higherIsBetter: true,
                               weight: 0.3, detail: "b"),
        ]
        let factors = [ScoreFactor.derived(DerivedSeriesID(.workImpact, "x"),
                                           name: "X", weight: 0.2, detail: "c")]
        let out = LeaveBlend.fold(score: 70, contributions: contributions,
                                  factors: factors,
                                  recency: recency([period(from: 200, to: 196)]),
                                  on: .workImpact, share: 0.12)
        XCTAssertTrue(out.didScore)
        let total = out.contributions.reduce(0) { $0 + $1.weight }
            + out.factors.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(total, 1, accuracy: 1e-9)

        let row = try XCTUnwrap(out.factors.last)
        XCTAssertEqual(row.weight, 0.12, accuracy: 1e-9)
        XCTAssertEqual(row.derivedSeries,
                       DerivedSeriesID(.workImpact, LeaveRecency.daysSinceLeaveKey))
        // The basis has to be on the row itself: this is where a reader goes to
        // ask why a share exists, and "we made it up" must not be the answer
        // they cannot rule out.
        XCTAssertTrue(row.detail.contains("no published figure"), row.detail)
    }

    /// **A card with nothing recorded comes back untouched** — same score, same
    /// weights, no row. That is what keeps every score already recorded
    /// comparable for a reader who never enters a holiday.
    func testTheFoldIsAnIdentityWhenNothingIsRecorded() {
        let contributions = [MetricContribution(metric: .restingHeartRate,
                                                higherIsBetter: false,
                                                weight: 1, detail: "a")]
        let out = LeaveBlend.fold(score: 70, contributions: contributions,
                                  factors: [], recency: recency([]),
                                  on: .sustainedLoad, share: 0.1)
        XCTAssertFalse(out.didScore)
        XCTAssertEqual(out.score, 70)
        XCTAssertEqual(out.contributions, contributions)
        XCTAssertTrue(out.factors.isEmpty)
    }

    /// The fold moves the number in the right direction and by no more than the
    /// share allows — the ceiling that keeps a diary from outvoting a body.
    func testTheFoldMovesTheNumberByAtMostItsShare() {
        let long = recency([period(from: 400, to: 396)])
        let fresh = recency([period(from: 3, to: 1)])
        let share = 0.12
        let a = LeaveBlend.fold(score: 70, contributions: [], factors: [],
                                recency: long, on: .workImpact, share: share)
        let b = LeaveBlend.fold(score: 70, contributions: [], factors: [],
                                recency: fresh, on: .workImpact, share: share)
        XCTAssertLessThan(a.score, b.score, "a longer stretch without leave scores lower")
        for out in [a, b] {
            XCTAssertLessThanOrEqual(abs(out.score - 70), 100 * share)
        }
    }

    // MARK: - H2: whose absence, and what it costs

    /// **The ruling H2 was left open on, pinned: somebody else's OOO is zero and
    /// never negative.** The reduction a colleague's absence causes is already
    /// in the calendar — their meetings are simply not there — so subtracting
    /// hours as well would remove the same meetings twice.
    func testAnAbsenceIsNeverLoadAndNeverNegativeLoad() {
        for occasion in [CalendarEventClassification.Occasion.leave, .absence] {
            let classification = CalendarEventClassification(
                context: .work, occasion: occasion, presence: .unstated,
                formality: .standard, hours: 8)
            XCTAssertEqual(classification.loadHours, 0,
                           "\(occasion) must cost nothing and credit nothing")
        }
    }

    /// **The fallback H1 does not get to remove.** With no identity configured,
    /// an absence marker is ambiguous — and ambiguous is never work, never a
    /// meeting and never load.
    func testWithoutIdentityAnAbsenceIsAmbiguousAndNeverWork() {
        let event = CalendarEvent(
            id: "ooo-1", start: day(3), end: day(2), isAllDay: true,
            timeZoneIdentifier: "UTC", calendarName: "Work", kind: .allDay,
            title: "OOO", location: nil, hasVideoLink: false)
        let classification = CalendarEventClassifier.classify(event)
        XCTAssertEqual(classification.occasion, .absence,
                       "no identity means the app cannot say whose absence it is")
        XCTAssertEqual(classification.loadHours, 0)
        XCTAssertNotEqual(CalendarEventBucket(classification), .work,
                          "an unresolved absence must never land in the work bucket")
    }
}
