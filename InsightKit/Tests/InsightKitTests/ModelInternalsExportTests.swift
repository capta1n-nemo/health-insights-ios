import XCTest
@testable import InsightKit

/// The model-internals export exists to answer three questions the other
/// exports stopped short of, so each test is one of those questions.
final class ModelInternalsExportTests: XCTestCase {

    /// Anchored to a day boundary so "today at 8 am" is always before `now`
    /// (8 pm) — a raw epoch constant lands at an arbitrary time of day and can
    /// put same-day samples in the future, where the reader ignores them.
    private let anchor = Calendar.current.startOfDay(
        for: Date(timeIntervalSince1970: 1_780_000_000))
    private var now: Date { anchor.addingTimeInterval(20 * 3600) }

    private func daysAgo(_ days: Double, hour: Double = 8) -> Date {
        anchor.addingTimeInterval(-days * 86_400 + hour * 3600)
    }

    private func export(samples: [HealthMetricSample],
                        events: [SubstanceEvent] = [],
                        raw: [RawMetricSample] = []) -> String {
        ModelInternalsExport.markdown(samples: samples, events: events, raw: raw,
                                      buildStamp: "test-build", now: now)
    }

    private func rawSleep(_ identifier: String, _ value: RawValue,
                          start: Date, hours: Double = 4) -> RawMetricSample {
        RawMetricSample(id: UUID(), identifier: identifier,
                        displayName: identifier, value: value, unit: "",
                        start: start, end: start.addingTimeInterval(hours * 3600),
                        source: .oura)
    }

    /// The instrument for a night the two sources cannot agree on: the raw
    /// segments, typed, with whether each counted. Shaped like 2026-07-29 —
    /// a 4.3 h `long_sleep` plus a 4.2 h `late_nap` at 8 am, which the parser
    /// now counts into the night (the user's morning re-sleep ruling), while
    /// an afternoon nap still says it was left out.
    func testDisagreeingNightExportsItsSegmentsWithTypes() {
        let nightStart = daysAgo(3, hour: 2)
        let reSleepStart = daysAgo(3, hour: 8)
        let siestaStart = daysAgo(3, hour: 15)
        let raw = [
            rawSleep("oura.sleep.total_sleep_duration", .number(4.3 * 3600),
                     start: nightStart, hours: 4.3),
            rawSleep("oura.sleep.type", .text("long_sleep"), start: nightStart),
            rawSleep("oura.sleep.total_sleep_duration", .number(4.2 * 3600),
                     start: reSleepStart, hours: 4.2),
            rawSleep("oura.sleep.type", .text("late_nap"), start: reSleepStart),
            rawSleep("oura.sleep.total_sleep_duration", .number(1.0 * 3600),
                     start: siestaStart, hours: 1.0),
            rawSleep("oura.sleep.type", .text("late_nap"), start: siestaStart)
        ]
        let text = export(samples: [], raw: raw)
        XCTAssertTrue(text.contains("Oura sleep segments"), text)
        XCTAssertTrue(text.contains("long_sleep"), text)
        XCTAssertTrue(text.contains("yes — morning re-sleep"),
                      "the 8 am block counts, and says why")
        XCTAssertTrue(text.contains("no — nap"),
                      "the siesta says it was left out")
        XCTAssertTrue(text.contains("4.2 h"), text)
    }

    /// An ordinary single-segment night is not worth a row — the section only
    /// lists the days that need explaining, and vanishes entirely when none do.
    func testOrdinaryNightsProduceNoSegmentsSection() {
        let raw = [
            rawSleep("oura.sleep.total_sleep_duration", .number(7.5 * 3600),
                     start: daysAgo(2, hour: 1), hours: 7.5),
            rawSleep("oura.sleep.type", .text("long_sleep"), start: daysAgo(2, hour: 1))
        ]
        let text = export(samples: [], raw: raw)
        XCTAssertFalse(text.contains("Oura sleep segments"), text)
    }

    /// The floors section quotes the constants in force rather than restating
    /// them, so a changed floor changes the document.
    func testFloorsSectionQuotesTheRealConstants() {
        let text = export(samples: [])
        XCTAssertTrue(text.contains("below \(VitalSignsCheck.minimumBaselineDays) days"))
        XCTAssertTrue(text.contains("last \(VitalSignsCheck.baselineDays) days"))
        XCTAssertTrue(text.contains("last \(Int(SubstanceResponseAnalyzer.comparisonWindowDays)) days"))
    }

    /// "Not enough history yet" must arrive with its own arithmetic: how many
    /// days the baseline holds against the floor it needs. This is the
    /// diastolic-BP question from the user's 2026-08-02 export, made answerable.
    func testAShortBaselineStatesItsCountAndTheFloor() {
        // Three recent daily readings — fresh, but under the judgement floor.
        // Today's value is the one being judged, so the baseline behind it
        // holds the two *prior* days.
        let samples = (0..<3).map {
            HealthMetricSample(type: .restingHeartRate, value: 60,
                               start: daysAgo(Double($0)), source: .oura)
        }
        let text = export(samples: samples)
        XCTAssertTrue(text.contains("2 of \(VitalSignsCheck.baselineDays) days (needs \(VitalSignsCheck.minimumBaselineDays))"),
                      "the shortfall must be stated, not inferable: \(text)")
        XCTAssertTrue(text.contains("insufficientHistory"))
    }

    /// A judged vital exports the baseline it was judged against.
    func testAJudgedVitalExportsItsBaselineAndZ() {
        var samples = (1...20).map {
            HealthMetricSample(type: .restingHeartRate, value: 55,
                               start: daysAgo(Double($0)), source: .oura)
        }
        samples.append(HealthMetricSample(type: .restingHeartRate, value: 70,
                                          start: daysAgo(0), source: .oura))
        let text = export(samples: samples)
        XCTAssertTrue(text.contains("| Resting Heart Rate | 70 bpm |"),
                      "today's value and its unit lead the row: \(text)")
        // **Eighteen, not twenty.** `referenceGapDays` holds the two most
        // recent days out of the window, so a departure cannot age into the
        // baseline that judges it — and the exported count states the window
        // that was actually used rather than the history that exists.
        let used = 20 - VitalSignsCheck.referenceGapDays
        XCTAssertTrue(text.contains("\(used) of \(VitalSignsCheck.baselineDays) days"),
                      "the exported baseline count must be the window actually used: \(text)")
    }

    /// "+31 after use" is a finding or noise depending on the pool sizes, so
    /// the pools export with the delta.
    func testSubstancePoolSizesAreExported() {
        var samples: [HealthMetricSample] = []
        // Ten clean mornings around 55 bpm (jittered so the SD is real),
        // then three mornings after evening logs at 70.
        for d in 5...14 {
            samples.append(HealthMetricSample(type: .restingHeartRate,
                                              value: 55 + Double(d % 3),
                                              start: daysAgo(Double(d)), source: .oura))
        }
        var events: [SubstanceEvent] = []
        for d in 1...3 {
            events.append(SubstanceEvent(substance: .alcohol,
                                         timestamp: daysAgo(Double(d), hour: -2)))
            samples.append(HealthMetricSample(type: .restingHeartRate, value: 70,
                                              start: daysAgo(Double(d)), source: .oura))
        }
        let text = export(samples: samples, events: events)
        XCTAssertTrue(text.contains("| Resting Heart Rate | 10 | 3 |"),
                      "clean and after-use pool sizes must both be visible: \(text)")
    }

    /// Nothing logged is a stated absence, not an empty table.
    func testNoSubstanceLogSaysSo() {
        let text = export(samples: [])
        XCTAssertTrue(text.contains("nothing logged, so there is nothing to compare"))
    }

    /// One night reported by two sources is two rows under one date — the
    /// layout that made the midnight-crossing defect visible is the point.
    func testNightsTableSplitsSources() {
        let night = daysAgo(1, hour: 10)
        let samples = [
            HealthMetricSample(type: .sleepDurationHours, value: 7.3,
                               start: night, source: .oura),
            HealthMetricSample(type: .sleepDurationHours, value: 7.1,
                               start: night, source: .appleHealth)
        ]
        let text = export(samples: samples)
        XCTAssertTrue(text.contains("| Oura | 7.3 h |"))
        XCTAssertTrue(text.contains("| Apple Health | 7.1 h |"))
    }
}
