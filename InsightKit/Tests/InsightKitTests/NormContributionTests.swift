import XCTest
@testable import InsightKit

/// The shape a norm would be built from — summarised, cohort-stratified, and
/// incapable of carrying free text.
///
/// ⚠️ **Nothing is sent in this build**, and these tests are about what the
/// payload *could* contain if it ever were. The interesting assertions are
/// therefore negative: no title, no date, no raw series.
final class NormContributionTests: XCTestCase {

    /// A UTC midnight that is also a week-bucket boundary, so a fixture can put
    /// several days in one bucket without guessing where the boundary fell.
    /// 1970-01-01 was a Thursday, so `Telemetry.weekBucket` rolls on Thursdays.
    private let weekStart = Date(timeIntervalSince1970: 2810 * 7 * 24 * 3600)
    private var week: Int { Telemetry.weekBucket(weekStart) }
    private let utc = TestClock.utc

    private func inWeek(_ dayOffset: Int, hour: Int = 12) -> Date {
        weekStart.addingTimeInterval(Double(dayOffset) * 86_400 + Double(hour) * 3600)
    }

    private func samples(_ metric: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            let at = inWeek(index / 4, hour: 1 + (index % 4) * 4)
            return HealthMetricSample(type: metric, value: value, start: at, end: at,
                                      source: .appleHealth)
        }
    }

    private var profile: UserHealthProfile {
        var p = UserHealthProfile()
        let now = TestClock.now
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-34 * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        return p
    }

    // MARK: - The statistics

    /// **Hand-checked.** Ten readings 1…10, R type-7 interpolation:
    /// p10 sits at position 0.9 → 1 + 0.9·(2−1) = 1.9; p25 at 2.25 → 3.25;
    /// the median at 4.5 → 5.5; p75 at 6.75 → 7.75; p90 at 8.1 → 9.1.
    func testTheSummaryStatisticsMatchAHandCheckedFixture() {
        let contribution = NormContributionBuilder.build(
            samples: samples(.bodyMass, (1...10).map(Double.init)),
            derived: DerivedSeriesStore(), profile: profile,
            weekBucket: week, now: TestClock.now)

        let summary = try? XCTUnwrap(contribution.metrics.first { $0.metric == .bodyMass }?.summary)
        XCTAssertEqual(summary?.n, 10)
        XCTAssertEqual(summary?.p10 ?? .nan, 1.9, accuracy: 1e-9)
        XCTAssertEqual(summary?.p25 ?? .nan, 3.25, accuracy: 1e-9)
        XCTAssertEqual(summary?.median ?? .nan, 5.5, accuracy: 1e-9)
        XCTAssertEqual(summary?.p75 ?? .nan, 7.75, accuracy: 1e-9)
        XCTAssertEqual(summary?.p90 ?? .nan, 9.1, accuracy: 1e-9)
    }

    /// The order of arrival must not change the answer — the builder sorts, and
    /// a quantile read off an unsorted array is the classic way this breaks.
    func testTheSummaryIsIndependentOfTheOrderTheReadingsArriveIn() {
        let ascending = NormContributionBuilder.summarise((1...10).map(Double.init))
        let shuffled = NormContributionBuilder.summarise([7, 2, 10, 4, 1, 9, 3, 8, 5, 6])
        XCTAssertEqual(ascending, shuffled)
    }

    /// Non-finite readings are dropped before the count, so a NaN cannot push a
    /// thin quantity over the floor.
    func testANonFiniteReadingCountsForNothing() {
        XCTAssertNil(NormContributionBuilder.summarise([1, 2, 3, 4, .nan]))
        XCTAssertEqual(NormContributionBuilder.summarise([1, 2, 3, 4, 5, .infinity])?.n, 5)
    }

    // MARK: - The floor

    /// **A summary from four readings is not a summary.** Below the floor the
    /// quantity contributes nothing at all — not a thin summary, not a null.
    func testAQuantityBelowTheMinimumContributesNothing() {
        let thin = samples(.bodyMass, [80, 81, 82, 83])
        let thick = samples(.restingHeartRate, [50, 51, 52, 53, 54])
        let contribution = NormContributionBuilder.build(
            samples: thin + thick, derived: DerivedSeriesStore(), profile: profile,
            weekBucket: week, now: TestClock.now)

        XCTAssertEqual(NormContributionBuilder.minimumSampleCount, 5,
                       "the floor is quoted in the doc comment with its reason — move both together")
        XCTAssertNil(contribution.metrics.first { $0.metric == .bodyMass },
                     "four readings became a published-looking distribution")
        XCTAssertNotNil(contribution.metrics.first { $0.metric == .restingHeartRate })

        let json = String(data: try! JSONEncoder().encode(contribution), encoding: .utf8)!
        XCTAssertFalse(json.contains("bodyMass"),
                       "the dropped quantity is still named in the payload, which says the reader has it")
    }

    /// A week with nothing over the floor produces nothing, rather than an empty
    /// envelope — an envelope is still a record that this cohort existed.
    func testAWeekWithNothingOverTheFloorIsOmittedEntirely() {
        let all = NormContributionBuilder.buildAll(
            samples: samples(.bodyMass, [80, 81, 82]), derived: DerivedSeriesStore(),
            profile: profile, now: TestClock.now)
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - What cannot get in

    /// **The calendar contributes its quantities and never its words.**
    ///
    /// The fixture is a real work-impact evaluation over events whose titles and
    /// locations are as identifying as this app ever holds. The card's component
    /// scores reach the contribution; nothing the events said does — and it is
    /// structural rather than careful, because `NormContributionBuilder.build`
    /// has no parameter that could take a `CalendarEvent` and
    /// `NormContribution` has no field that could hold a string of the reader's.
    func testACalendarFixtureLeavesNoTitleAnywhereInTheEncodedContribution() throws {
        let secretTitle = "Oncology review with Dr Patel"
        let secretPlace = "Royal Marsden, Fulham Road"
        let secretCalendar = "Work"

        var store = DerivedSeriesStore()
        let result = WorkImpactInsight(events: workEvents(title: secretTitle,
                                                          location: secretPlace,
                                                          calendarName: secretCalendar),
                                       judgements: [])
            .evaluate(samples: workVitals(), profile: profile, now: TestClock.now)
        XCTAssertFalse(result.contributors.isEmpty,
                       "the fixture never reached a real evaluation, so this test proves nothing")
        // Six days inside one week bucket: the floor is 5, so the series really
        // has to clear it or the assertion below would be vacuous.
        for offset in 0...5 { store.record(result, on: inWeek(offset), calendar: utc) }

        let contribution = NormContributionBuilder.build(
            samples: [], derived: store, profile: profile,
            weekBucket: week, now: TestClock.now)
        XCTAssertFalse(contribution.derived.isEmpty,
                       "no derived series cleared the floor, so nothing was actually tested")
        XCTAssertTrue(contribution.derived.allSatisfy { $0.producedBy == .workImpact })

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(contribution), encoding: .utf8))
        for forbidden in [secretTitle, secretPlace, "Patel", "Marsden", "Fulham"] {
            XCTAssertFalse(json.contains(forbidden),
                           "\"\(forbidden)\" reached the norm payload")
        }
    }

    /// **A canary for free text.** Every string this type can encode is an
    /// identifier from the app's own source or a cohort bucket, and not one of
    /// them contains a space. Anything a human typed almost always does.
    ///
    /// Not a proof — the proof is that `NormContribution` has no field for a
    /// name, a label or a note — but it is the check that would fire first if
    /// somebody added one.
    func testNoEncodedStringValueLooksLikeSomethingSomebodyTyped() throws {
        var store = DerivedSeriesStore()
        let result = WorkImpactInsight(events: workEvents(title: "Standup", location: nil,
                                                          calendarName: "Work"),
                                       judgements: [])
            .evaluate(samples: workVitals(), profile: profile, now: TestClock.now)
        for offset in 0...5 { store.record(result, on: inWeek(offset), calendar: utc) }

        let contribution = NormContributionBuilder.build(
            samples: samples(.restingHeartRate, [50, 51, 52, 53, 54, 55]),
            derived: store, profile: profile, weekBucket: week, now: TestClock.now)
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(contribution))

        for string in Self.stringValues(in: object) {
            XCTAssertFalse(string.contains(" "),
                           "\"\(string)\" is free text, not an identifier or a cohort bucket")
            // An ISO-8601 date would mean a per-day timeline had crept back in,
            // which is the rule this type exists to make impossible.
            XCTAssertFalse(string.contains("T") && string.contains("Z"),
                           "\"\(string)\" looks like a timestamp — the coarsest time here is a week bucket")
        }
    }

    /// The only time this type can express is a week bucket, so there is nowhere
    /// for a dated series to hide.
    func testTheOnlyTimeInThePayloadIsTheWeekBucket() throws {
        let contribution = NormContributionBuilder.build(
            samples: samples(.bodyMass, (1...10).map(Double.init)),
            derived: DerivedSeriesStore(), profile: profile,
            weekBucket: week, now: TestClock.now)
        XCTAssertEqual(contribution.weekBucket, week)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(contribution), encoding: .utf8))
        for dated in ["\"day\"", "\"date\"", "\"start\"", "\"recordedAt\"", "\"generatedAt\""] {
            XCTAssertFalse(json.contains(dated), "\(dated) is a per-day timeline in disguise")
        }
    }

    /// The cohort is the strata the norm itself is built on, so it has to be
    /// there — a contribution with no cohort is a value with nothing to compare
    /// it against.
    func testTheCohortTravelsWithTheSummaries() {
        let contribution = NormContributionBuilder.build(
            samples: samples(.bodyMass, (1...10).map(Double.init)),
            derived: DerivedSeriesStore(), profile: profile,
            weekBucket: week, now: TestClock.now)
        XCTAssertEqual(contribution.cohort.sex, "male")
        XCTAssertEqual(contribution.cohort.ageBand, "30-39")
    }

    // MARK: - Fixtures

    /// Fifty-six days of working events at five different lengths, so the
    /// model's own median split produces a heavy and a light half that both
    /// clear `WorkImpactModel.minimumDaysPerHalf`.
    private func workEvents(title: String, location: String?,
                            calendarName: String) -> [CalendarEvent] {
        (1...WorkImpactModel.windowDays).map { offset in
            let start = utc.startOfDay(for: TestClock.now.addingTimeInterval(Double(-offset) * 86_400))
                .addingTimeInterval(9 * 3600)
            let hours = 2 + Double(offset % 5)
            return CalendarEvent(id: "event-\(offset)", start: start,
                                 end: start.addingTimeInterval(hours * 3600),
                                 isAllDay: false, timeZoneIdentifier: "Europe/London",
                                 calendarName: calendarName, kind: .timed,
                                 title: title, location: location, hasVideoLink: true)
        }
    }

    /// Two watched channels with real spread — a constant series has a robust
    /// scale of zero and the model correctly refuses to read it.
    private func workVitals() -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for offset in 0...70 {
            let at = utc.startOfDay(for: TestClock.now.addingTimeInterval(Double(-offset) * 86_400))
                .addingTimeInterval(6 * 3600)
            out.append(.init(type: .restingHeartRate, value: 54 + Double(offset % 7),
                             start: at, end: at, source: .appleHealth))
            out.append(.init(type: .heartRateVariabilityRMSSD, value: 40 + Double(offset % 5) * 2,
                             start: at, end: at, source: .appleHealth))
        }
        return out
    }

    /// Every string *value* in a decoded JSON tree — keys excluded, since a key
    /// is the app's own vocabulary by definition.
    private static func stringValues(in object: Any) -> [String] {
        switch object {
        case let string as String: return [string]
        case let array as [Any]: return array.flatMap { stringValues(in: $0) }
        case let dictionary as [String: Any]:
            return dictionary.values.flatMap { stringValues(in: $0) }
        default: return []
        }
    }
}
