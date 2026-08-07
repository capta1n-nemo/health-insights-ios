import XCTest
@testable import InsightKit

/// Backlog D43 — **the app announced a discovery for data it then threw away.**
///
/// `AppModel.observeArrivals` records what arrived *before* the sanitiser runs,
/// so the reader's single out-of-range vitamin A reading was announced as "New
/// since you last looked" and then dropped. Ruled 2026-08-07: keep the order and
/// store *why* it was dropped, so the row can say "arrived, but outside the
/// plausible range".
///
/// The order is the thing being protected. Observing after sanitising would make
/// a metric arriving persistently out of range indistinguishable from nothing
/// arriving at all — which is the exact state that means a device has started
/// sending garbage.
final class ArrivalOutcomeTests: XCTestCase {

    private let now = TestClock.now

    private func sample(_ type: MetricType, _ value: Double) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value, start: now, source: .oura)
    }

    /// The reader's case, end to end: one reading, outside the range, nothing
    /// else. The sighting stands and the ledger knows what became of it.
    func testAnArrivalThatWasEntirelyDiscardedSaysWhy() {
        // Positive, so not a placeholder zero — just far above `dietaryVitaminA`'s
        // plausible ceiling of 100,000 mcg RAE. This is the refusal the reader's
        // row has to name.
        let fresh = [sample(.dietaryVitaminA, 250_000)]
        let (kept, dropped) = fresh.partitionedVitals()
        XCTAssertTrue(kept.isEmpty, "fixture no longer exercises the sanitiser")

        var ledger = TypeSightingLedger()
        ledger.observe(MetricType.dietaryVitaminA.rawValue, at: now)
        ledger.recordSanitisation(kept: kept, dropped: dropped)

        XCTAssertEqual(ledger.newlyArrived(asOf: now), [MetricType.dietaryVitaminA.rawValue],
                       "the sighting must survive — something really did arrive")
        XCTAssertNotNil(ledger.discardedOutcome(for: MetricType.dietaryVitaminA.rawValue))
        XCTAssertEqual(
            ledger.discardedOutcome(for: MetricType.dietaryVitaminA.rawValue)?.rowNote,
            "arrived, but outside the plausible range")
    }

    /// A type that delivered anything usable is not a discarded arrival, however
    /// much junk came with it. One good reading means the type produced data,
    /// and that is what the row should say.
    func testOneGoodReadingAmongBadOnesIsNotADiscardedArrival() {
        let fresh = [sample(.restingHeartRate, 0), sample(.restingHeartRate, 58)]
        let (kept, dropped) = fresh.partitionedVitals()

        var ledger = TypeSightingLedger()
        ledger.observe(MetricType.restingHeartRate.rawValue, at: now)
        ledger.recordSanitisation(kept: kept, dropped: dropped)

        XCTAssertNil(ledger.discardedOutcome(for: MetricType.restingHeartRate.rawValue))
    }

    /// The note describes the **last** arrival, not the worst one ever seen —
    /// otherwise a metric that recovers carries the qualifier forever.
    func testARecoveredMetricStopsSayingItWasDiscarded() {
        var ledger = TypeSightingLedger()
        ledger.observe(MetricType.bodyMass.rawValue, at: now)

        let bad = [sample(.bodyMass, 0)].partitionedVitals()
        ledger.recordSanitisation(kept: bad.kept, dropped: bad.dropped)
        XCTAssertNotNil(ledger.discardedOutcome(for: MetricType.bodyMass.rawValue))

        let good = [sample(.bodyMass, 82)].partitionedVitals()
        ledger.recordSanitisation(kept: good.kept, dropped: good.dropped)
        XCTAssertNil(ledger.discardedOutcome(for: MetricType.bodyMass.rawValue))
    }

    /// A placeholder zero and a wild reading are different faults, and the row
    /// says which. `.notPositive` only when *every* rejected reading was a zero.
    func testTheTwoRefusalsAreNamedApart() {
        var ledger = TypeSightingLedger()
        ledger.observe(MetricType.bodyMass.rawValue, at: now)
        let zeros = [sample(.bodyMass, 0), sample(.bodyMass, 0)].partitionedVitals()
        ledger.recordSanitisation(kept: zeros.kept, dropped: zeros.dropped)
        XCTAssertEqual(ledger.discardedOutcome(for: MetricType.bodyMass.rawValue), .notPositive)
        XCTAssertEqual(ledger.discardedOutcome(for: MetricType.bodyMass.rawValue)?.rowNote,
                       "arrived, but every reading was zero or below")

        // A genuinely out-of-range value among the zeros is the more informative
        // fault: a provider sending 900 kg is not sending nothing.
        let mixed = [sample(.bodyMass, 0), sample(.bodyMass, 900)].partitionedVitals()
        ledger.recordSanitisation(kept: mixed.kept, dropped: mixed.dropped)
        XCTAssertEqual(ledger.discardedOutcome(for: MetricType.bodyMass.rawValue),
                       .outsidePlausibleRange)
    }

    /// A verdict without a sighting is a judgement on something that never
    /// arrived. Nothing should appear in the ledger.
    func testAnOutcomeNeverInventsASighting() {
        var ledger = TypeSightingLedger()
        let dropped = [sample(.bodyMass, 0)].partitionedVitals().dropped
        ledger.recordSanitisation(kept: [], dropped: dropped)
        XCTAssertTrue(ledger.sightings.isEmpty)
    }

    /// **"Not judged" is not "judged fine".** A raw field is never sanitised, so
    /// its sighting keeps a nil outcome and its row prints no qualifier.
    func testAnUnjudgedSightingCarriesNoNote() {
        var ledger = TypeSightingLedger()
        ledger.observe("oura.sleep.rem", at: now)
        XCTAssertNil(ledger.sightings["oura.sleep.rem"]?.outcome)
        XCTAssertNil(ledger.discardedOutcome(for: "oura.sleep.rem"))
    }

    /// The ledger lives in `UserDefaults`, so the new field must round trip —
    /// and a ledger written before D43 shipped must still decode, with its
    /// sightings unjudged rather than silently called usable.
    func testItRoundTripsAndDecodesALedgerWrittenBeforeThisShipped() throws {
        var ledger = TypeSightingLedger()
        ledger.observe(MetricType.dietaryVitaminA.rawValue, at: now)
        ledger.record(.outsidePlausibleRange, for: MetricType.dietaryVitaminA.rawValue)
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(TypeSightingLedger.self, from: data), ledger)

        let legacy = Data("""
        {"sightings":{"oura.sleep.rem":{"firstImported":0,"lastImported":0,\
        "seededFromHistory":false}}}
        """.utf8)
        let decoded = try JSONDecoder().decode(TypeSightingLedger.self, from: legacy)
        XCTAssertNil(decoded.sightings["oura.sleep.rem"]?.outcome)
    }
}
