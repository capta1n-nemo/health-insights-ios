import XCTest
@testable import InsightKit

/// **The honesty rules for the smallest surface in the app.**
///
/// Backlog `D8`. A widget has no room for a caveat, which is exactly why the
/// caveat has to be structural rather than remembered. These tests hold the
/// four claims `WidgetSnapshot`'s doc comment makes, so a later edit that
/// quietly drops one fails here rather than on a home screen.
final class WidgetSnapshotTests: XCTestCase {

    private func result(id: InsightID = .readiness,
                        primaryValue: Double? = 74,
                        headline: String = "74",
                        score: Double? = 74,
                        confidence: InsightConfidence = .high,
                        explanation: String = "Three of three components are in.",
                        drivers: [InsightDriver] = []) -> InsightResult {
        InsightResult(id: id, title: "Readiness", primaryValue: primaryValue,
                      headline: headline, score: score, confidence: confidence,
                      explanation: explanation, driverLines: drivers,
                      unmetRequirements: [])
    }

    // MARK: - A number never travels alone

    /// The whole point of the type. There is no path to the headline that does
    /// not also carry the qualifier, so this is really a test that the shape
    /// has not been flattened back into loose optionals by a later edit.
    func testFigureAlwaysCarriesANonEmptyQualifier() {
        for confidence in [InsightConfidence.high, .moderate, .low, .experimental] {
            let snapshot = WidgetSnapshot.from(result(confidence: confidence),
                                               capturedAt: TestClock.now,
                                               dataThrough: TestClock.now)
            guard case let .figure(figure) = snapshot.content else {
                return XCTFail("a scored card must produce a figure")
            }
            XCTAssertFalse(figure.qualifier.isEmpty,
                           "\(confidence) produced a number with nothing qualifying it")
        }
    }

    /// An empty qualifier is the one way a caller can defeat the type, so it is
    /// repaired rather than trusted.
    func testEmptyQualifierIsRepairedRatherThanStored() {
        let figure = WidgetSnapshot.Figure(headline: "74", qualifier: "   ")
        XCTAssertFalse(figure.qualifier.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// An experimental figure must not read like a measurement.
    func testExperimentalQualifierSaysItIsNotAMeasurement() {
        let snapshot = WidgetSnapshot.from(result(confidence: .experimental),
                                           capturedAt: TestClock.now,
                                           dataThrough: TestClock.now)
        guard case let .figure(figure) = snapshot.content else {
            return XCTFail("expected a figure")
        }
        XCTAssertTrue(figure.qualifier.lowercased().contains("not a measurement"))
    }

    // MARK: - A withheld figure stays withheld

    /// The card's own sentence, not a dash, not a zero, not the last number.
    func testCardWithNoFigureProducesItsOwnWaitingSentence() {
        let waiting = result(primaryValue: nil, headline: "Waiting for today's sync",
                             score: nil, confidence: .low,
                             explanation: "Readiness is about today, and nothing from today has arrived yet.")
        let snapshot = WidgetSnapshot.from(waiting, capturedAt: TestClock.now,
                                           dataThrough: TestClock.now)
        guard case let .withheld(headline, _) = snapshot.content else {
            return XCTFail("a card with no figure must withhold")
        }
        XCTAssertEqual(headline, "Waiting for today's sync")
    }

    /// Every registered card, evaluated against nothing at all — the fresh
    /// install. Not one of them may reach a widget with a number.
    ///
    /// This is the widget half of `CardVisibilityTests`: that suite holds that
    /// an empty card still *says* something, this one holds that what it says
    /// on a home screen is never a figure it does not have.
    func testNoCardInventsAFigureOnAFreshInstall() {
        for model in InsightEngine().models {
            let evaluated = model.evaluate(samples: [], profile: UserHealthProfile(),
                                           now: TestClock.now)
            guard evaluated.primaryValue == nil, evaluated.score == nil else { continue }
            let snapshot = WidgetSnapshot.from(evaluated, capturedAt: TestClock.now,
                                               dataThrough: nil)
            if case .figure = snapshot.content {
                XCTFail("\(evaluated.id) reached a widget with a figure it does not have")
            }
        }
    }

    /// A truncated sentence about health data is worse than no sentence.
    func testLongExplanationIsDroppedRatherThanTruncated() {
        let long = String(repeating: "a very long clause indeed ", count: 12) + "."
        XCTAssertNil(WidgetSnapshot.shortReason(from: long))
        XCTAssertEqual(WidgetSnapshot.shortReason(from: "Short enough. And more."),
                       "Short enough.")
    }

    // MARK: - Staleness

    /// The failure this field exists to stop: a cached timeline entry showing
    /// yesterday's number as though it were this morning's.
    func testYesterdaysDataIsLabelled() {
        let now = TestClock.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let snapshot = WidgetSnapshot.from(result(), capturedAt: yesterday,
                                           dataThrough: yesterday)
        XCTAssertEqual(snapshot.stalenessSentence(now: now), "From yesterday")
        XCTAssertTrue(snapshot.supportingLines(now: now).contains("From yesterday"))
    }

    /// Same morning, rendered in the evening, is not stale — that *is* today's
    /// readiness, and nagging about it would be the `CoverageGate` mistake.
    func testTodaysDataIsNotLabelledStale() {
        // Both anchored to the same *local* calendar day, because that is the
        // boundary the sentence is about — a rolling 24 hours would make this
        // pass or fail depending on the machine's zone.
        let midnight = Calendar.current.startOfDay(for: TestClock.now)
        let morning = midnight.addingTimeInterval(7 * 3_600)
        let evening = midnight.addingTimeInterval(21 * 3_600)
        let snapshot = WidgetSnapshot.from(result(), capturedAt: morning, dataThrough: morning)
        XCTAssertNil(snapshot.stalenessSentence(now: evening))
    }

    /// Staleness outranks the driver line for the one spare row: if the number
    /// is not about today, that is the thing to say.
    func testStalenessOutranksTheDriverLine() {
        let now = TestClock.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let withDriver = result(drivers: [InsightDriver(text: "HRV is well down", isNotable: true)])
        let snapshot = WidgetSnapshot.from(withDriver, capturedAt: yesterday,
                                           dataThrough: yesterday)
        XCTAssertEqual(snapshot.supportingLines(now: now).last, "From yesterday")
    }

    /// A routine driver is not promoted to a widget's one line — the "sixteen
    /// normals hide the one that isn't" failure, one row wide.
    func testOnlyANotableDriverEarnsTheLine() {
        let routine = result(drivers: [InsightDriver(text: "Resting heart rate: normal",
                                                    isNotable: false)])
        XCTAssertNil(WidgetSnapshot.notableDriver(in: routine))
        let unclassified = result(drivers: [InsightDriver(text: "Sleep: 7h 10m")])
        XCTAssertNil(WidgetSnapshot.notableDriver(in: unclassified))
    }

    /// Nothing measured behind it is itself worth saying.
    func testNoReadingBehindItIsStated() {
        let snapshot = WidgetSnapshot.from(result(), capturedAt: TestClock.now,
                                           dataThrough: nil)
        XCTAssertEqual(snapshot.stalenessSentence(now: TestClock.now),
                       "No reading behind this yet")
    }

    // MARK: - The store

    private func temporaryStore() -> WidgetSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("widget-snapshot-tests-\(UUID().uuidString)")
        return WidgetSnapshotStore(directory: directory)
    }

    func testRoundTripThroughTheStore() throws {
        let store = temporaryStore()
        defer { store.clear() }
        let snapshot = WidgetSnapshot.from(result(), capturedAt: TestClock.now,
                                           dataThrough: TestClock.now)
        try store.write(snapshot)
        XCTAssertEqual(store.read(), snapshot)
    }

    /// Two binaries that disagree about the shape must not half-read each
    /// other. A mismatched schema is `nil`, which a widget renders as its
    /// placeholder.
    func testSnapshotFromAnotherSchemaIsRefused() throws {
        let store = temporaryStore()
        defer { store.clear() }
        try store.write(WidgetSnapshot.from(result(), capturedAt: TestClock.now,
                                            dataThrough: TestClock.now))
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL))
            as! [String: Any]
        json["schema"] = WidgetSnapshot.schemaVersion + 1
        try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL)
        XCTAssertNil(store.read())
    }

    func testCorruptFileReadsAsNothingRatherThanThrowing() throws {
        let store = temporaryStore()
        defer { store.clear() }
        try FileManager.default.createDirectory(at: store.directory,
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.read())
    }

    func testMissingFileReadsAsNothing() {
        XCTAssertNil(temporaryStore().read())
    }
}
