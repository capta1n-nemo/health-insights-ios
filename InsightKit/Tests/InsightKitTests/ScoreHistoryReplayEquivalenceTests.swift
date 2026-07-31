import XCTest
@testable import InsightKit

/// `ScoreHistory.replay` grows its visible prefix instead of rebuilding it.
///
/// The version before it rebuilt everything on every replayed day —
/// `Array(sorted[..<cut])` for the samples, `Set(visible.map(\.type))` to count
/// the metrics, `events.filter` for the events. Three full passes over the whole
/// visible history, ninety times, per model, with seventeen models replaying
/// concurrently. On the user's phone that froze the Insights tab for four to
/// six seconds at a time while scrolling, which is how it was found.
///
/// The optimisation is only sound because `cut` moves monotonically forward, and
/// "only sound because of an invariant" is exactly the kind of change that
/// quietly alters results. So the contract these pin is not "it is faster" but
/// **"it returns precisely what the obvious implementation returns"**, checked
/// against a naive reference kept here in the tests.
final class ScoreHistoryReplayEquivalenceTests: XCTestCase {

    private let utc = TestClock.utc
    private let referenceNow = TestClock.now

    /// The implementation that was replaced, kept verbatim in shape so the
    /// comparison means something. Deliberately naive: rebuild everything, every
    /// day, and let the optimised one prove it agrees.
    private func naiveReplay(model: any InsightModel,
                             samples: [HealthMetricSample],
                             events: [VitalEvent] = [],
                             profile: UserHealthProfile,
                             days: Int) -> [ScorePoint] {
        guard days > 0 else { return [] }
        let relevant = Set(model.candidateMetrics)
        guard !relevant.isEmpty else { return [] }
        let sorted = samples.filter { relevant.contains($0.type) }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var points: [ScorePoint] = []
        let today = utc.startOfDay(for: referenceNow)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = utc.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = utc.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let asOf = min(dayEnd, referenceNow)
            guard asOf > dayStart else { continue }

            let cut = ScoreHistory.firstIndex(in: sorted, atOrAfter: asOf)
            guard cut > 0 else { continue }

            let visible = Array(sorted[..<cut])
            let present = Set(visible.map(\.type)).count
            guard present >= ScoreHistory.minimumContributors else { continue }

            let result = model.evaluate(samples: visible,
                                        events: events.filter { $0.date < asOf },
                                        profile: profile, now: asOf)
            guard let score = result.score else { continue }
            // Mirrors `ScoreHistory.replay`: a weight-0 contribution is reported,
            // not scored, so it cannot be what makes a day well-founded. This
            // reference exists to check the *optimisation* is faithful, so it
            // has to restate the rule rather than an older version of it.
            let weighted = result.contributors.filter { $0.weight > 0 }.count
            let used = result.contributors.isEmpty
                ? present
                : (weighted > 0 ? weighted : result.contributors.count)
            guard used >= ScoreHistory.minimumContributors else { continue }

            points.append(ScorePoint(date: dayStart, score: score,
                                     confidence: result.confidence,
                                     contributorCount: used))
        }
        return points
    }

    private func assertAgrees(_ model: any InsightModel,
                              samples: [HealthMetricSample],
                              events: [VitalEvent] = [],
                              days: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        let profile = UserHealthProfile()
        let fast = ScoreHistory.replay(model: model, samples: samples, events: events,
                                       profile: profile, days: days,
                                       calendar: utc, now: referenceNow)
        let slow = naiveReplay(model: model, samples: samples, events: events,
                               profile: profile, days: days)
        XCTAssertEqual(fast.count, slow.count, "point count", file: file, line: line)
        for (a, b) in zip(fast, slow) {
            XCTAssertEqual(a.date, b.date, file: file, line: line)
            XCTAssertEqual(a.score, b.score, accuracy: 1e-9, "score on \(a.date)",
                           file: file, line: line)
            XCTAssertEqual(a.contributorCount, b.contributorCount,
                           "contributors on \(a.date)", file: file, line: line)
            XCTAssertEqual(a.confidence, b.confidence, file: file, line: line)
        }
    }

    // MARK: - Sample shapes

    /// Dense, every day — the ordinary case and the one that used to cost most.
    private func dense(days: Int) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            let date = TestClock.day(i)
            let jitter = Double(i % 5) - 2
            out.append(.init(type: .heartRateVariabilityRMSSD, value: 45 + jitter,
                             start: date, source: .oura))
            out.append(.init(type: .restingHeartRate, value: 58 + jitter * 0.4,
                             start: date, source: .oura))
            out.append(.init(type: .sleepDurationHours, value: 7.2 + jitter * 0.1,
                             start: date, source: .oura))
        }
        return out
    }

    func testAgreesOnADenseHistory() {
        assertAgrees(ReadinessInsight(), samples: dense(days: 45), days: 45)
    }

    /// Gaps are where an incremental prefix is most likely to drift: several
    /// days in a row add nothing, so `cut` stands still and the bookkeeping has
    /// to cope with consuming an empty range.
    func testAgreesWhenWholeWeeksAreMissing() {
        let full = dense(days: 60)
        let gapped = full.filter { sample in
            let day = utc.dateComponents([.day], from: sample.start, to: referenceNow).day ?? 0
            return !(20...34).contains(day)
        }
        assertAgrees(ReadinessInsight(), samples: gapped, days: 60)
    }

    /// Many samples landing on the same instant, which is what a multi-source
    /// sync actually produces.
    func testAgreesWhenManySamplesShareOneTimestamp() {
        var out = dense(days: 30)
        let date = TestClock.day(10)
        for i in 0..<50 {
            out.append(.init(type: .heartRate, value: 60 + Double(i % 7),
                             start: date, source: .appleHealth))
        }
        assertAgrees(ReadinessInsight(), samples: out, days: 30)
    }

    /// The metric-count pre-check is the part that changed representation —
    /// from a `Set` rebuilt per day to a running tally — so a history whose
    /// metric coverage *widens* partway through is the case that matters.
    func testAgreesWhenNewMetricsAppearPartwayThrough() {
        var out: [HealthMetricSample] = []
        for i in stride(from: 39, through: 0, by: -1) {
            let date = TestClock.day(i)
            out.append(.init(type: .restingHeartRate, value: 60, start: date, source: .oura))
            if i < 30 {
                out.append(.init(type: .heartRateVariabilityRMSSD, value: 45,
                                 start: date, source: .oura))
            }
            if i < 15 {
                out.append(.init(type: .sleepDurationHours, value: 7.5,
                                 start: date, source: .oura))
            }
        }
        assertAgrees(ReadinessInsight(), samples: out, days: 40)
    }

    /// Events are truncated on the same contract as samples and were being
    /// re-filtered every day; they are now a grown prefix too.
    func testAgreesWithEventsInterleaved() {
        let events = (0..<12).map { i in
            VitalEvent(kind: .highHeartRate, date: TestClock.day(i * 3), sourceName: "Apple Watch")
        }
        assertAgrees(ReadinessInsight(), samples: dense(days: 40),
                     events: events, days: 40)
    }

    /// A history shorter than the window: most days have nothing at all, so the
    /// loop spends its time in the `cut == 0` and `cut == consumed` branches.
    func testAgreesWhenHistoryIsShorterThanTheWindow() {
        assertAgrees(ReadinessInsight(), samples: dense(days: 6), days: 90)
    }

    /// Different models read different metric sets, so they take different paths
    /// through the pre-filter and the contributor count.
    func testAgreesAcrossModels() {
        let samples = dense(days: 40)
        assertAgrees(ReadinessInsight(), samples: samples, days: 40)
        assertAgrees(ReadinessInsight(), samples: samples, days: 40)
        assertAgrees(SleepInsight(), samples: samples, days: 40)
    }

    /// The invariant the optimisation rests on, asserted directly rather than
    /// left implicit: the cut never moves backwards as the replay walks forward.
    func testTheCutIsMonotonicWhichIsWhatMakesTheOptimisationSound() {
        let sorted = dense(days: 60)
            .filter { ReadinessInsight().candidateMetrics.contains($0.type) }
            .sorted { $0.start < $1.start }
        let today = utc.startOfDay(for: referenceNow)
        var previous = 0
        for offset in stride(from: 59, through: 0, by: -1) {
            guard let dayStart = utc.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = utc.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let asOf = min(dayEnd, referenceNow)
            guard asOf > dayStart else { continue }
            let cut = ScoreHistory.firstIndex(in: sorted, atOrAfter: asOf)
            XCTAssertGreaterThanOrEqual(cut, previous, "cut went backwards at offset \(offset)")
            previous = cut
        }
    }

    /// The event search is new code, so it gets its own boundary check rather
    /// than being covered only through the replay.
    func testEventBinarySearchMatchesALinearScan() {
        let events = (0..<40).map { i in
            VitalEvent(kind: .highHeartRate, date: TestClock.day(39 - i), sourceName: "Apple Watch")
        }.sorted { $0.date < $1.date }
        for probe in stride(from: -2, through: 42, by: 1) {
            let date = TestClock.day(probe)
            let expected = events.filter { $0.date < date }.count
            XCTAssertEqual(ScoreHistory.firstIndexOfEvent(in: events, atOrAfter: date),
                           expected, "probe \(probe)")
        }
    }
}
