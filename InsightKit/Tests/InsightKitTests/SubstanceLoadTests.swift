import XCTest
@testable import InsightKit

private let loadNow = TestClock.now
private let loadCalendar = TestClock.utc
// Exact hours back rather than day-snapped: the decay kernel is continuous, and
// snapping to midday would quantise every half-life assertion.
private func loadDay(_ daysAgo: Double) -> Date { TestClock.hours(daysAgo * 24) }

private func event(_ substance: SubstanceClass, daysAgo: Double) -> SubstanceEvent {
    SubstanceEvent(substance: substance, timestamp: loadDay(daysAgo))
}

/// The roadmap asked for "cardio strain from stimulants as a first-class trend".
/// The fortnight figure that already existed was a box-car — full weight for
/// fourteen days, then nothing — which is serviceable as one number and draws a
/// staircase of the calendar as a series.
final class SubstanceLoadTests: XCTestCase {

    func testDecayHalvesAtTheHalfLife() {
        XCTAssertEqual(SubstanceLoad.decay(daysAgo: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(SubstanceLoad.decay(daysAgo: SubstanceLoad.halfLifeDays), 0.5, accuracy: 1e-12)
        XCTAssertEqual(SubstanceLoad.decay(daysAgo: 2 * SubstanceLoad.halfLifeDays), 0.25, accuracy: 1e-12)
    }

    /// A replayed past day must not see a log entry recorded after it, or a
    /// score-over-time chart rewrites its own history every time the user logs.
    func testAFutureEventContributesNothing() {
        XCTAssertEqual(SubstanceLoad.decay(daysAgo: -1), 0)
        XCTAssertEqual(SubstanceLoad.load(events: [event(.stimulant, daysAgo: -3)], at: loadNow), 0)
    }

    /// The two figures have to be one answer. Saturation is derived from the
    /// box-car's own constants, so sustained use at the rate that saturates the
    /// fortnight figure reads 100 here too.
    func testTheDecayedScaleAgreesWithTheFortnightFigureAtSteadyState() {
        // The saturating rate: `loadSaturationUnits` over `loadWindowDays`,
        // delivered daily for long enough to reach equilibrium.
        let perDay = SubstanceResponseAnalyzer.loadSaturationUnits
            / Double(SubstanceResponseAnalyzer.loadWindowDays)
        // Stimulant weight is exactly 1.0, so `perDay` events a day is the rate.
        var events: [SubstanceEvent] = []
        for day in 0..<200 {
            // Fractional rate expressed as a whole event every 1/perDay days.
            let spacing = 1 / perDay
            events.append(event(.stimulant, daysAgo: Double(day) * spacing))
        }
        XCTAssertEqual(SubstanceLoad.load(events: events, at: loadNow), 100, accuracy: 6)
    }

    /// The point of the change: the old window dropped an event outright on day
    /// fourteen. The kernel still carries a quarter of it there.
    func testAnEventDoesNotVanishAtTheOldWindowEdge() {
        let one = [event(.stimulant, daysAgo: 14)]
        let load = SubstanceLoad.load(events: one, at: loadNow)
        XCTAssertGreaterThan(load, 0, "the fortnight cliff is back")
        let fresh = SubstanceLoad.load(events: [event(.stimulant, daysAgo: 0)], at: loadNow)
        XCTAssertEqual(load / fresh, 0.25, accuracy: 1e-9)
    }

    func testSeriesIsDenseAndEndsToday() {
        let series = SubstanceLoad.series(events: [event(.stimulant, daysAgo: 20)],
                                          days: 30, now: loadNow, calendar: loadCalendar)
        XCTAssertEqual(series.count, 30, "load is defined on days with no logs")
        XCTAssertEqual(series.last?.date, loadCalendar.startOfDay(for: loadNow))
        // Oldest first.
        XCTAssertEqual(series.map(\.date), series.map(\.date).sorted())
    }

    /// After the last event the series only falls — that is what a decay is.
    func testLoadFallsMonotonicallyAfterTheLastEvent() {
        let series = SubstanceLoad.series(events: [event(.mdma, daysAgo: 25)],
                                          days: 20, now: loadNow, calendar: loadCalendar)
        for (a, b) in zip(series, series.dropFirst()) {
            XCTAssertLessThan(b.load, a.load, "load rose with no new event")
        }
    }

    func testEventCountMarksOnlyTheDayItWasLogged() {
        let series = SubstanceLoad.series(events: [event(.alcohol, daysAgo: 3)],
                                          days: 10, now: loadNow, calendar: loadCalendar)
        XCTAssertEqual(series.filter { $0.eventCount > 0 }.count, 1)
        XCTAssertGreaterThan(series.filter { $0.load > 0 }.count, 1,
                             "the tail is the whole point")
    }

    func testAnEmptyLogHasNoSeries() {
        XCTAssertTrue(SubstanceLoad.series(events: [], days: 30, now: loadNow).isEmpty)
    }

    /// One band function, so the card's word and the chart's word can never
    /// disagree about the same number.
    func testBandsMatchTheCardsOwnThresholds() {
        XCTAssertEqual(SubstanceResponseAnalyzer.band(for: 19.9), "light")
        XCTAssertEqual(SubstanceResponseAnalyzer.band(for: 20), "moderate")
        XCTAssertEqual(SubstanceResponseAnalyzer.band(for: 50), "considerable")
        XCTAssertEqual(SubstanceResponseAnalyzer.band(for: 80), "high")
    }
}

final class SubstanceImpactModelTests: XCTestCase {

    private func nights(_ metric: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: loadDay(Double(values.count - 1 - index)), source: .oura)
        }
    }

    /// The defect in one line: the engine registered eleven models and this
    /// wasn't one of them, so everything applied "to every insight" skipped it.
    func testTheEngineRegistersSubstanceImpact() {
        XCTAssertTrue(InsightEngine().models.contains { $0.id == .substanceImpact })
    }

    /// Rebinding must replace, not append — the app applies it on every
    /// recompute.
    func testRebindingTheLogIsIdempotent() {
        let engine = InsightEngine()
            .withSubstanceLog([event(.stimulant, daysAgo: 1)])
            .withSubstanceLog([event(.alcohol, daysAgo: 2)])
        XCTAssertEqual(engine.models.filter { $0.id == .substanceImpact }.count, 1)
        let model = engine.models.compactMap { $0 as? SubstanceImpactInsight }.first
        XCTAssertEqual(model?.events.count, 1)
        XCTAssertEqual(model?.events.first?.substance, .alcohol)
    }

    /// `ScoreHistory` replays a past day by handing the model that day as `now`.
    /// A log entry from after it must not set that day's load.
    func testReplayingAPastDayIgnoresLaterLogs() {
        let insight = SubstanceImpactInsight(events: [event(.stimulant, daysAgo: 1)])
        let tenDaysAgo = loadDay(10)
        let result = insight.evaluate(samples: [], profile: .init(), now: tenDaysAgo)
        XCTAssertNil(result.score, "a log entry from nine days later scored a past day")
    }

    func testAnEmptyLogHasNoScore() {
        let result = SubstanceImpactInsight()
            .evaluate(samples: [], profile: .init(), now: loadNow)
        XCTAssertNil(result.score)
    }

    /// Higher is better, like every other dial in this app — a heavy fortnight
    /// must not paint green.
    func testHeavyUseScoresLowerThanLightUse() {
        let heavy = SubstanceImpactInsight(
            events: (0..<10).map { event(.stimulant, daysAgo: Double($0)) })
        let light = SubstanceImpactInsight(events: [event(.caffeine, daysAgo: 6)])
        let heavyScore = heavy.evaluate(samples: [], profile: .init(), now: loadNow).score
        let lightScore = light.evaluate(samples: [], profile: .init(), now: loadNow).score
        XCTAssertLessThan(try XCTUnwrap(heavyScore), try XCTUnwrap(lightScore))
    }

    /// Severity is measured in the user's own baseline spread, not in an
    /// invented per-metric threshold: the same 4 bpm shift means different
    /// things to two different people.
    func testSeverityIsMeasuredInTheUsersOwnSpread() {
        let steady = SubstanceResponseAnalyzer.MetricEffect(
            metric: .restingHeartRate, baseline: 55, afterUse: 59,
            deltaAbsolute: 4, deltaPercent: 7.3, affectedNights: 3, baselineNights: 10,
            isAdverse: true, baselineSD: 1)
        let variable = SubstanceResponseAnalyzer.MetricEffect(
            metric: .restingHeartRate, baseline: 55, afterUse: 59,
            deltaAbsolute: 4, deltaPercent: 7.3, affectedNights: 3, baselineNights: 10,
            isAdverse: true, baselineSD: 8)
        XCTAssertGreaterThan(SubstanceResponseAnalyzer.severity(steady),
                             SubstanceResponseAnalyzer.severity(variable))
    }

    /// A delta against a flat baseline is unjudgeable, not infinitely severe.
    func testAFlatBaselineYieldsNoEffectSize() {
        let effect = SubstanceResponseAnalyzer.MetricEffect(
            metric: .restingHeartRate, baseline: 55, afterUse: 59,
            deltaAbsolute: 4, deltaPercent: 7.3, affectedNights: 3, baselineNights: 10,
            isAdverse: true, baselineSD: 0)
        XCTAssertNil(effect.effectSize)
        XCTAssertEqual(SubstanceResponseAnalyzer.severity(effect), 0)
    }

    /// A favourable move is not a penalty.
    func testAFavourableResponseCostsNothing() {
        let effect = SubstanceResponseAnalyzer.MetricEffect(
            metric: .heartRateVariabilityRMSSD, baseline: 45, afterUse: 55,
            deltaAbsolute: 10, deltaPercent: 22, affectedNights: 3, baselineNights: 10,
            isAdverse: false, baselineSD: 4)
        XCTAssertEqual(SubstanceResponseAnalyzer.severity(effect), 0)
    }

    func testCandidateMetricsMatchWhatTheAnalyserCompares() {
        XCTAssertEqual(SubstanceImpactInsight().candidateMetrics,
                       SubstanceResponseAnalyzer.comparedMetrics)
    }
}

/// The watched set had not changed since it was written, and a metric added to
/// it without a matching sentence would be measured and then silently dropped
/// from the card.
final class SubstanceWatchedMetricsTests: XCTestCase {

    private func nightly(_ metric: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: loadDay(Double(values.count - 1 - index)), source: .oura)
        }
    }

    func testTheComparedListIsDerivedFromTheWatchedList() {
        // Two hand-maintained copies of one list is how they drift apart.
        XCTAssertFalse(SubstanceResponseAnalyzer.comparedMetrics.isEmpty)
        XCTAssertEqual(Set(SubstanceResponseAnalyzer.comparedMetrics).count,
                       SubstanceResponseAnalyzer.comparedMetrics.count)
    }

    /// Every watched metric must declare a direction, or the detail chart can't
    /// say which way is better. Temperature is the deliberate exception —
    /// nearest the baseline is best, and neither end is an improvement.
    func testEveryWatchedMetricDeclaresItsDirection() {
        for metric in SubstanceResponseAnalyzer.comparedMetrics where metric.family != .thermal {
            XCTAssertNotNil(SubstanceResponseAnalyzer.higherIsBetter(metric),
                            "\(metric) has no better direction")
        }
    }

    /// The additions have to reach the card, not just the maths. The driver
    /// switch has a `default: nil`, so a new metric fails silently.
    func testEveryMeasuredEffectReachesADriverLine() {
        var events: [SubstanceEvent] = []
        var samples: [HealthMetricSample] = []
        for day in [1.0, 3, 5] { events.append(event(.alcohol, daysAgo: day)) }
        for metric in SubstanceResponseAnalyzer.comparedMetrics {
            samples += nightly(metric, (0..<10).map { 50 + Double($0) })
        }
        let result = SubstanceResponseAnalyzer.insightResult(
            events: events, samples: samples, now: loadNow)
        let analysis = SubstanceResponseAnalyzer.analyze(
            events: events, samples: samples, now: loadNow)
        XCTAssertFalse(analysis.effects.isEmpty, "the fixture measured nothing")
        // One "after use" line per measured effect, plus the load line.
        let afterUseLines = result.drivers.filter { $0.contains("after use") }
        XCTAssertEqual(afterUseLines.count, analysis.effects.count,
                       "a measured effect reached no driver line: \(result.drivers)")
    }

    /// Blood pressure and AFib burden are sparse for most people. The analyser
    /// should say nothing rather than guess.
    func testASparseMetricProducesNoEffect() {
        let analysis = SubstanceResponseAnalyzer.analyze(
            events: [event(.alcohol, daysAgo: 1)],
            samples: nightly(.bloodPressureSystolic, [120, 122]), now: loadNow)
        XCTAssertTrue(analysis.effects.isEmpty)
    }
}

/// The after-window, as something a chart can draw. It has always been *stated*
/// on the card and never shown, which left the reader doing date arithmetic
/// against a chart to see which readings the sentence was about.
final class SubstanceWindowTests: XCTestCase {

    private let after = SubstanceResponseAnalyzer.afterWindow

    func testOneEventBecomesOneWindowOfTheStatedLength() throws {
        let windows = SubstanceResponseAnalyzer.affectedWindows(
            events: [event(.alcohol, daysAgo: 2)])
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), after, accuracy: 1)
        XCTAssertEqual(window.substances, [.alcohol])
    }

    /// The design question. Three coffees across a morning produce three
    /// near-identical eighteen-hour spans; drawn as three rectangles they stack,
    /// and stacked translucent fills compound into a band darker than a single
    /// one — so the chart would encode *how many logs* in a channel meant to say
    /// only *affected or not*.
    func testOverlappingWindowsMergeIntoOne() throws {
        let windows = SubstanceResponseAnalyzer.affectedWindows(events: [
            event(.caffeine, daysAgo: 2),
            event(.caffeine, daysAgo: 2 - 2.0 / 24),   // two hours later
            event(.caffeine, daysAgo: 2 - 4.0 / 24)
        ])
        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        // The span runs from the first log to eighteen hours past the last.
        XCTAssertEqual(window.end.timeIntervalSince(window.start), after + 4 * 3600,
                       accuracy: 1)
    }

    /// A later event with a window that ends *earlier* must not shorten a span
    /// already open — the `max` in the merge, which a plain assignment would get
    /// wrong and nothing else would catch.
    func testAMergedSpanIsNeverShortenedByALaterEvent() throws {
        let windows = SubstanceResponseAnalyzer.affectedWindows(events: [
            event(.alcohol, daysAgo: 2),
            event(.caffeine, daysAgo: 2 - 1.0 / 24)
        ], after: after)
        let window = try XCTUnwrap(windows.first)
        XCTAssertGreaterThanOrEqual(window.end.timeIntervalSince(window.start), after)
    }

    /// Which substances went into a span is kept rather than collapsed: the
    /// caption names them, and "alcohol and caffeine" is a different read from
    /// "alcohol".
    func testAMergedSpanRemembersEverySubstanceInIt() throws {
        let windows = SubstanceResponseAnalyzer.affectedWindows(events: [
            event(.alcohol, daysAgo: 2),
            event(.caffeine, daysAgo: 2 - 3.0 / 24),
            event(.alcohol, daysAgo: 2 - 5.0 / 24)
        ])
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(Set(window.substances), [.alcohol, .caffeine])
        XCTAssertEqual(window.substances.count, 2, "a repeat should not be listed twice")
    }

    func testWellSeparatedEventsStaySeparateWindows() {
        XCTAssertEqual(SubstanceResponseAnalyzer.affectedWindows(events: [
            event(.alcohol, daysAgo: 8),
            event(.alcohol, daysAgo: 2)
        ]).count, 2)
    }

    func testAnEmptyLogShadesNothing() {
        XCTAssertTrue(SubstanceResponseAnalyzer.affectedWindows(events: []).isEmpty)
    }

    /// The overlap test the chart filters on, including the case where the
    /// window straddles the visible range entirely.
    func testOverlapIsInclusiveAndHandlesAStraddle() {
        let window = SubstanceWindow(start: loadDay(5), end: loadDay(1),
                                     substances: [.alcohol])
        XCTAssertTrue(window.overlaps(loadDay(4)...loadDay(2)), "range inside the window")
        XCTAssertTrue(window.overlaps(loadDay(6)...loadDay(0)), "window inside the range")
        XCTAssertTrue(window.overlaps(loadDay(6)...loadDay(5)), "touching at one edge")
        XCTAssertFalse(window.overlaps(loadDay(9)...loadDay(6)))
    }

    /// Events arriving newest-first must produce the same windows as
    /// oldest-first — the store's order is not something this may depend on.
    func testTheLogsOrderDoesNotMatter() {
        let events = [event(.alcohol, daysAgo: 2), event(.caffeine, daysAgo: 6),
                      event(.nicotine, daysAgo: 2 - 1.0 / 24)]
        XCTAssertEqual(SubstanceResponseAnalyzer.affectedWindows(events: events),
                       SubstanceResponseAnalyzer.affectedWindows(events: events.reversed()))
    }
}
