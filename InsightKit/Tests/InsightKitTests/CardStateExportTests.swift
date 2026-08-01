import XCTest
@testable import InsightKit

final class CardStateExportTests: XCTestCase {

    private let now = TestClock.now

    private func realisticSamples() -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        for day in 0..<30 {
            samples.append(.init(type: .restingHeartRate, value: 52 + Double(day % 5),
                                 start: TestClock.day(day), source: .oura))
            samples.append(.init(type: .sleepDurationHours, value: 7.1,
                                 start: TestClock.day(day), source: .oura))
        }
        return samples
    }

    private func export(results: [InsightResult]? = nil,
                        samples: [HealthMetricSample]? = nil) -> String {
        let engine = InsightEngine()
        let allSamples = samples ?? realisticSamples()
        var profile = UserHealthProfile()
        profile.set(.init(kind: .dateOfBirth,
                          value: now.addingTimeInterval(-40 * 365.2425 * 86_400).timeIntervalSince1970,
                          recordedAt: now))
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        let computed = results ?? engine.evaluateAll(samples: allSamples,
                                                     profile: profile, now: now)
        let candidates = Dictionary(uniqueKeysWithValues:
            engine.models.map { ($0.id, $0.candidateMetrics) })
        return CardStateExport.markdown(
            results: computed, candidates: candidates,
            histories: [.sleep: (0..<40).map {
                ScorePoint(date: TestClock.day(39 - $0), score: 60 + Double($0 % 20),
                           confidence: .moderate, contributorCount: 4)
            }],
            samples: allSamples, profile: profile,
            buildStamp: "abc1234 · build 512", now: now,
            calendar: TestClock.utc)
    }

    /// The whole point of the document: every card, its number, its wording,
    /// and the data behind its declared inputs — from a named build.
    func testEveryEvaluatedCardAppearsWithItsScoreAndInputs() {
        let text = export()
        for result in InsightEngine().evaluateAll(samples: realisticSamples(),
                                                  profile: .init(), now: now) {
            XCTAssertTrue(text.contains("## \(result.title)"), result.title)
        }
        XCTAssertTrue(text.contains("abc1234"), "the build stamp settles which build produced this")
        XCTAssertTrue(text.contains("Declared inputs and their data"))
        XCTAssertTrue(text.contains("| Resting Heart Rate | 30 "),
                      "an input with data shows its count")
        XCTAssertTrue(text.contains("| Cardio Fitness (VO₂max) | 0 |"),
                      "an input with no data must say 0, not vanish — that row is the diagnosis")
    }

    func testGroundingFactsRenderThroughTheirOwnFormatter() {
        let text = export()
        XCTAssertTrue(text.contains("Date of birth: 40 years old"),
                      "an epoch printed raw is the failure this formatter exists for")
        XCTAssertTrue(text.contains("Biological sex: Male"))
    }

    func testHistoryTailIsBoundedAndTheTotalIsStated() {
        let text = export()
        XCTAssertTrue(text.contains("40 days stored, last \(CardStateExport.historyTailDays)"),
                      "the bound keeps the file small; the stated total says what was left out")
    }

    /// Size is a design constraint — the document must stay paste-sized
    /// however long the underlying history is.
    func testExportStaysSmall() {
        var samples = realisticSamples()
        for day in 0..<720 {
            for reading in 0..<70 {
                samples.append(.init(type: .heartRate, value: 60 + Double(reading % 40),
                                     start: TestClock.day(day).addingTimeInterval(Double(reading) * 600),
                                     source: .appleHealthDevice("Apple Watch")))
            }
        }
        let text = export(samples: samples)
        XCTAssertLessThan(text.utf8.count, 200_000,
                          "aggregates only — raw readings belong to the full export")
    }

    /// "A pending replay is not no-data" — eight of nine cards read "none
    /// stored yet" on the document's first real use, while their replays were
    /// still queued. The two states get different sentences.
    func testAPendingReplayIsNotReportedAsNoData() {
        let engine = InsightEngine()
        let results = engine.evaluateAll(samples: realisticSamples(), profile: .init(), now: now)
        let text = CardStateExport.markdown(
            results: results, candidates: [:], histories: [:],
            pendingHistories: Set(results.map(\.id)),
            samples: [], profile: .init(), buildStamp: "dev", now: now,
            calendar: TestClock.utc)
        XCTAssertTrue(text.contains("replay still computing"))
        XCTAssertFalse(text.contains("none stored yet"),
                       "a queued replay must not read as an empty history")
    }

    func testEmptyStateDoesNotCrashAndSaysSo() {
        let text = CardStateExport.markdown(
            results: [], candidates: [:], histories: [:], samples: [],
            profile: .init(), buildStamp: "dev", now: now, calendar: TestClock.utc)
        XCTAssertTrue(text.contains("none entered"))
        XCTAssertTrue(text.contains("0 canonical readings"))
    }
}
