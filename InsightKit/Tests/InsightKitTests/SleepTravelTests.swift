import XCTest
@testable import InsightKit

/// The reader's own journey, 2026-08-07: Manila → Sydney, asleep across the
/// change. Every fixture here uses two *real* zones with a two-hour difference,
/// and **nothing is pinned to UTC** — a UTC-pinned test of UTC-pinned code
/// agrees with itself, which is the failure `verify.sh` bans the shape for.
final class SleepTravelTests: XCTestCase {

    private let manila = TimeZone(identifier: "Asia/Manila")!       // UTC+8, no DST
    private let sydney = TimeZone(identifier: "Australia/Sydney")!  // UTC+10 in August

    private func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private func instant(_ zone: TimeZone, _ y: Int, _ mo: Int, _ d: Int,
                         _ h: Int, _ mi: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c.date(from: DateComponents(year: y, month: mo, day: d,
                                           hour: h, minute: mi))!
    }

    // MARK: - The hinge: a stored onset is an instant in disguise

    /// Everything in this file depends on the recovery being exact, so it is
    /// tested first and in both signs.
    func testOnsetInstantRoundTripsAnEveningBedtime() {
        let manilaCal = calendar(manila)
        let bedtime = instant(manila, 2026, 8, 6, 23, 10)
        let stored = SleepOnset.samples(fromSegmentStarts: [bedtime],
                                        source: .oura, calendar: manilaCal)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(SleepTravel.onsetInstant(of: stored[0])!.timeIntervalSince1970,
                       bedtime.timeIntervalSince1970, accuracy: 1)
    }

    func testOnsetInstantRoundTripsAnAfterMidnightBedtime() {
        let manilaCal = calendar(manila)
        let bedtime = instant(manila, 2026, 8, 7, 1, 30)
        let stored = SleepOnset.samples(fromSegmentStarts: [bedtime],
                                        source: .oura, calendar: manilaCal)
        XCTAssertEqual(SleepTravel.onsetInstant(of: stored[0])!.timeIntervalSince1970,
                       bedtime.timeIntervalSince1970, accuracy: 1)
    }

    func testOnsetInstantRefusesAnythingThatIsNotAnOnset() {
        let sample = HealthMetricSample(type: .sleepDurationHours, value: 7,
                                        start: Date(), source: .oura)
        XCTAssertNil(SleepTravel.onsetInstant(of: sample))
    }

    // MARK: - Problem 1: a Manila night, viewed from Sydney

    /// The defect in one assertion. A night stored in Manila reads 23:10 there
    /// and must read 01:10 for a reader now in Sydney — the reader's explicit
    /// instruction, *"report in MY current timezone"*.
    func testAManilaBedtimeRendersInSydneyTimeOnceTheReaderIsHome() {
        let bedtime = instant(manila, 2026, 8, 6, 23, 10)
        let stored = SleepOnset.samples(fromSegmentStarts: [bedtime],
                                        source: .oura, calendar: calendar(manila))[0]

        // What was stored: −0.833 h, i.e. 23:10 Manila.
        XCTAssertEqual(stored.value, -50.0 / 60, accuracy: 0.01)
        // What a reader in Sydney must now be shown: +1.166 h, i.e. 01:10.
        XCTAssertEqual(SleepTravel.onsetHours(of: stored, in: calendar(sydney))!,
                       70.0 / 60, accuracy: 0.01)
    }

    /// Re-rendering must not re-apply the ±6 h admission test. A night admitted
    /// in Sydney and viewed from London is still a night.
    func testRenderingNeverErasesANightBecauseTheReaderMoved() {
        let london = TimeZone(identifier: "Europe/London")!
        let bedtime = instant(sydney, 2026, 8, 6, 23, 0)
        let stored = SleepOnset.samples(fromSegmentStarts: [bedtime],
                                        source: .oura, calendar: calendar(sydney))[0]
        // 23:00 Sydney is 14:00 London — far outside SleepOnset's ±6 h band…
        XCTAssertNil(SleepOnset.hoursFromMidnight(bedtime, calendar: calendar(london)))
        // …and it must still render, rather than vanish from the reader's
        // history. 14:00 encodes as −10: ten hours before the following midnight.
        XCTAssertEqual(SleepTravel.onsetHours(of: stored, in: calendar(london))!,
                       -10, accuracy: 0.01)
    }

    /// The consequence of the line above, asserted so no chart can assume it
    /// away: re-rendering a far-travelled night produces values **outside the
    /// ±6 h band `SleepOnsetChart` was built for**. The full range is [−12, +12).
    func testRenderedOnsetCanLeaveTheSixHourBand() {
        let london = TimeZone(identifier: "Europe/London")!
        let bedtime = instant(sydney, 2026, 8, 6, 23, 0)
        let stored = SleepOnset.samples(fromSegmentStarts: [bedtime],
                                        source: .oura, calendar: calendar(sydney))[0]
        let rendered = SleepTravel.onsetHours(of: stored, in: calendar(london))!
        XCTAssertGreaterThan(abs(rendered), SleepOnset.plausibleHours)
        XCTAssertLessThan(rendered, 12)
        XCTAssertGreaterThanOrEqual(rendered, -12)
    }

    /// The day a night is called survives being read from two hours away.
    func testNightDayLabelSurvivesTheManilaToSydneyMove() {
        let key = instant(manila, 2026, 8, 7, 0)   // a Manila-minted night key
        XCTAssertEqual(SleepTravel.nightDay(of: key, calendar: calendar(sydney)),
                       instant(sydney, 2026, 8, 7, 0))
    }

    // MARK: - Problem 2: elapsed is right, the clock is not

    func testZoneSpanMeasuresTheOvernightShift() {
        let span = SleepTravel.ZoneSpan(atSleep: 8 * 3600, atWake: 10 * 3600)
        XCTAssertEqual(span.shiftHours, 2, accuracy: 0.001)
        XCTAssertTrue(span.crossed)
    }

    func testStayingPutIsNotACrossing() {
        let span = SleepTravel.ZoneSpan(atSleep: 10 * 3600, atWake: 10 * 3600)
        XCTAssertFalse(span.crossed)
        XCTAssertEqual(span.shiftHours, 0)
    }

    /// 23:00 Manila → 07:00 Sydney: six hours passed, the clock says eight.
    func testWallClockOverstatesAnEastwardNight() {
        let sleep = instant(manila, 2026, 8, 6, 23, 0)
        let wake = instant(sydney, 2026, 8, 7, 7, 0)
        let elapsed = wake.timeIntervalSince(sleep) / 3600
        XCTAssertEqual(elapsed, 6, accuracy: 0.001)

        let span = SleepTravel.ZoneSpan(atSleep: 8 * 3600, atWake: 10 * 3600)
        XCTAssertEqual(SleepTravel.wallClockHours(elapsedHours: elapsed, span: span),
                       8, accuracy: 0.001)
    }

    /// `SleepNights` reports elapsed, and elapsed is the travel-proof one. This
    /// asserts the property the card's caption is allowed to claim.
    func testSleepNightsReportsElapsedNotWallClock() {
        let sleep = instant(manila, 2026, 8, 6, 23, 0)
        let wake = instant(sydney, 2026, 8, 7, 7, 0)
        let samples = SleepNights.samples(from: [SleepSegment(kind: .core, start: sleep, end: wake)],
                                          source: .appleHealth,
                                          calendar: calendar(sydney))
        let duration = samples.first { $0.type == .sleepDurationHours }
        XCTAssertEqual(duration?.value ?? 0, 6, accuracy: 0.01,
                       "the duration must be the six hours that passed, not the eight the clock moved")
    }

    // MARK: - Problem 3: plane sleep

    /// The four hours `SleepNights` silently discards, made visible without
    /// changing what it discards.
    func testDaytimeSleepIsSurfacedRatherThanLost() {
        let cal = calendar(sydney)
        let start = instant(sydney, 2026, 8, 7, 14, 0)
        let segments = [SleepSegment(kind: .core, start: start,
                                     end: start.addingTimeInterval(4 * 3600))]

        XCTAssertTrue(SleepNights.samples(from: segments, source: .appleHealth, calendar: cal).isEmpty,
                      "the night rule still refuses it — this fix must not change that")
        XCTAssertEqual(SleepTravel.daytimeSleepHours(from: segments, calendar: cal)[
            cal.startOfDay(for: start)] ?? 0, 4, accuracy: 0.01)
    }

    func testNightSleepIsNotCountedAsDaytimeSleep() {
        let cal = calendar(sydney)
        let start = instant(sydney, 2026, 8, 6, 23, 0)
        let segments = [SleepSegment(kind: .core, start: start,
                                     end: start.addingTimeInterval(7 * 3600))]
        XCTAssertTrue(SleepTravel.daytimeSleepHours(from: segments, calendar: cal).isEmpty)
    }

    /// A plane night is two dozes and a meal service, not one block.
    func testFragmentedSleepIsCountedAsSeparateEpisodes() {
        let first = instant(manila, 2026, 8, 6, 23, 0)
        let segments = [
            SleepSegment(kind: .core, start: first, end: first.addingTimeInterval(3600)),
            // Contiguous stage change — the same bout, not a new one.
            SleepSegment(kind: .deep, start: first.addingTimeInterval(3600),
                         end: first.addingTimeInterval(2 * 3600)),
            // Two hours later: a genuinely separate sleep.
            SleepSegment(kind: .core, start: first.addingTimeInterval(4 * 3600),
                         end: first.addingTimeInterval(6 * 3600)),
        ]
        XCTAssertEqual(SleepTravel.episodes(in: segments), 2)
    }

    func testNoSleepIsNoEpisodes() {
        XCTAssertEqual(SleepTravel.episodes(in: []), 0)
        XCTAssertEqual(SleepTravel.episodes(in: [SleepSegment(kind: .awake,
                                                             start: Date(), end: Date())]), 0)
    }

    // MARK: - The offset the ingestion path used to delete

    func testUTCOffsetIsReadOffAnOuraBedtime() {
        XCTAssertEqual(PayloadDate.utcOffsetSeconds("2026-08-06T23:10:00+08:00"), 8 * 3600)
        XCTAssertEqual(PayloadDate.utcOffsetSeconds("2026-08-07T07:00:00+10:00"), 10 * 3600)
        XCTAssertEqual(PayloadDate.utcOffsetSeconds("2026-08-06T23:10:00+0800"), 8 * 3600)
        XCTAssertEqual(PayloadDate.utcOffsetSeconds("2026-08-06T23:10:00.500-05:00"), -5 * 3600)
        XCTAssertEqual(PayloadDate.utcOffsetSeconds("2026-08-06T23:10:00+05:45"), 5 * 3600 + 45 * 60)
        XCTAssertEqual(PayloadDate.utcOffsetSeconds("2026-08-06T23:10:00Z"), 0)
    }

    /// **Unknown is not zero.** A naive timestamp or a bare day said nothing
    /// about a zone, and treating that silence as UTC is the exact shear
    /// `DayStamp` was written to describe.
    func testAValueWithNoZoneReportsUnknownRatherThanUTC() {
        XCTAssertNil(PayloadDate.utcOffsetSeconds("2026-08-06T23:10:00"))
        XCTAssertNil(PayloadDate.utcOffsetSeconds("2026-08-06"))
        XCTAssertNil(PayloadDate.utcOffsetSeconds(1_754_500_000))
        XCTAssertNil(PayloadDate.utcOffsetSeconds("not a date"))
        XCTAssertNil(PayloadDate.utcOffsetSeconds("2026-08-06T23:10:00+99:00"))
    }

    /// End to end: the offsets survive the generic ingestor and reach the
    /// catalogue, which is where they were being destroyed.
    func testOuraSleepPayloadCarriesItsZoneIntoTheCatalogue() throws {
        let json = """
        {"data":[{"id":"a","day":"2026-08-07",
                  "bedtime_start":"2026-08-06T23:00:00+08:00",
                  "bedtime_end":"2026-08-07T07:00:00+10:00",
                  "type":"long_sleep","total_sleep_duration":21600}]}
        """.data(using: .utf8)!
        let ingestor = GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: .oura)
        let payload = IngestPayload(source: .oura, endpoint: "sleep", data: json)
        let documents = ingestor.documents(from: payload, calendar: calendar(sydney))

        XCTAssertEqual(documents.count, 1)
        let fields = Dictionary(uniqueKeysWithValues:
            documents[0].fields.map { ($0.path, $0.value.doubleValue) })
        XCTAssertEqual(fields[PayloadDate.startZoneOffsetField], 8 * 3600)
        XCTAssertEqual(fields[PayloadDate.endZoneOffsetField], 10 * 3600)
    }

    func testASourceWithoutAZoneEmitsNoOffsetFieldAtAll() throws {
        let json = """
        {"data":[{"id":"a","day":"2026-08-07","total_sleep_duration":21600}]}
        """.data(using: .utf8)!
        let ingestor = GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: .oura)
        let documents = ingestor.documents(
            from: IngestPayload(source: .oura, endpoint: "sleep", data: json),
            calendar: calendar(sydney))
        XCTAssertEqual(documents.count, 1)
        XCTAssertFalse(documents[0].fields.contains { $0.path == PayloadDate.startZoneOffsetField })
    }

    // MARK: - Spans, joined back to nights

    func testSpansAreKeyedToTheNightTheyDescribe() {
        let cal = calendar(sydney)
        let bedtime = instant(manila, 2026, 8, 6, 23, 0)
        let raw = [
            RawMetricSample(identifier: "oura.sleep.\(PayloadDate.startZoneOffsetField)",
                            displayName: "Zone Offset Seconds", value: 8 * 3600.0,
                            unit: "", start: bedtime, source: .oura),
            RawMetricSample(identifier: "oura.sleep.\(PayloadDate.endZoneOffsetField)",
                            displayName: "Zone Offset Seconds At End", value: 10 * 3600.0,
                            unit: "", start: bedtime, source: .oura),
        ]
        let spans = SleepTravel.spans(raw: raw, calendar: cal)
        let day = SleepTravel.nightDay(of: SleepOnset.night(of: bedtime, calendar: cal),
                                       calendar: cal)
        XCTAssertEqual(spans[day]?.shiftHours ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(spans[day]?.crossed, true)
    }

    /// Half a span cannot say whether anything moved.
    func testAnUnpairedOffsetProducesNoSpan() {
        let raw = [RawMetricSample(identifier: "oura.sleep.\(PayloadDate.startZoneOffsetField)",
                                   displayName: "Zone Offset Seconds", value: 8 * 3600.0,
                                   unit: "", start: Date(), source: .oura)]
        XCTAssertTrue(SleepTravel.spans(raw: raw, calendar: calendar(sydney)).isEmpty)
    }

    // MARK: - The whole night, as a card would show it

    func testTheFlightNightReportsElapsedAndSaysWhy() {
        let cal = calendar(sydney)
        let bedtime = instant(manila, 2026, 8, 6, 23, 0)
        let stored = SleepOnset.samples(fromSegmentStarts: [bedtime],
                                        source: .oura, calendar: calendar(manila))
            + [HealthMetricSample(type: .sleepDurationHours, value: 6,
                                  start: SleepOnset.night(of: bedtime, calendar: calendar(manila)),
                                  source: .oura)]
        let raw = [
            RawMetricSample(identifier: "oura.sleep.\(PayloadDate.startZoneOffsetField)",
                            displayName: "", value: 8 * 3600.0, unit: "",
                            start: bedtime, source: .oura),
            RawMetricSample(identifier: "oura.sleep.\(PayloadDate.endZoneOffsetField)",
                            displayName: "", value: 10 * 3600.0, unit: "",
                            start: bedtime, source: .oura),
        ]

        let nights = SleepTravel.nights(samples: stored, raw: raw, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        let night = nights[0]

        // Elapsed, unchanged by the journey.
        XCTAssertEqual(night.elapsedHours ?? 0, 6, accuracy: 0.001)
        // The clock either side of it read eight.
        XCTAssertEqual(night.wallClockHours ?? 0, 8, accuracy: 0.001)
        // Bedtime in the reader's current zone, as instructed…
        XCTAssertEqual(night.onsetHoursHere ?? 0, 1, accuracy: 0.01)
        // …and the clock they actually went to bed by.
        XCTAssertEqual(night.onsetHoursThere ?? 0, -1, accuracy: 0.01)
        XCTAssertEqual(night.crossedZones, true)

        let note = try? XCTUnwrap(night.note)
        XCTAssertTrue(note?.contains("2 hours forward") ?? false, note ?? "no note")
        XCTAssertTrue(note?.contains("23:00") ?? false, note ?? "no note")
    }

    /// A night nothing recorded a zone for must read *unknown*, never
    /// *stayed put* — the standing "honest version, always" rule.
    func testANightWithNoRecordedZoneIsUnknownNotUnmoved() {
        let cal = calendar(sydney)
        let bedtime = instant(sydney, 2026, 8, 5, 23, 0)
        let stored = SleepOnset.samples(fromSegmentStarts: [bedtime],
                                        source: .appleHealth, calendar: cal)
        let nights = SleepTravel.nights(samples: stored, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertNil(nights[0].crossedZones)
        XCTAssertNil(nights[0].onsetHoursThere)
        XCTAssertNil(nights[0].wallClockHours)
        XCTAssertNil(nights[0].note, "nothing to explain, so nothing is said")
    }

    func testClockTextRendersSignedHoursAsAClock() {
        XCTAssertEqual(SleepTravel.Night.clockText(-1), "23:00")
        XCTAssertEqual(SleepTravel.Night.clockText(1.5), "01:30")
        XCTAssertEqual(SleepTravel.Night.clockText(0), "00:00")
    }

    func testHoursTextReadsLikeEnglish() {
        XCTAssertEqual(SleepTravel.Night.hoursText(2), "2 hours")
        XCTAssertEqual(SleepTravel.Night.hoursText(1), "1 hour")
        XCTAssertEqual(SleepTravel.Night.hoursText(1.5), "1 hour 30 minutes")
        XCTAssertEqual(SleepTravel.Night.hoursText(0), "0 minutes")
    }
}
