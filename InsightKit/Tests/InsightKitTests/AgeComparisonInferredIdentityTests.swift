import XCTest
@testable import InsightKit

/// **Backlog D20 — the first number in this app whose *identity* is inferred.**
///
/// Withings has sent `withings.measure.227` on more distinct days than Oura has
/// sent a vascular age, and the section built to show every product's answer
/// could not see it: the field was never promoted to a `MetricType`. The ruling
/// was relay it, labelled as inferred — and the label is the whole item.
/// Withings publishes no table of what its measure types mean, so the app named
/// the field by matching the range its values sit in. Every other row on that
/// section is a number whose *width* is uncertain; this one's *subject* is.
///
/// Its own file rather than a fifth class in `AgeComparisonTests`: the rule
/// being pinned here is not "does the section list every source" but "does a
/// row ever claim more than the app can support", and a reader looking for the
/// second should not have to read four classes about the first.
final class AgeComparisonInferredIdentityTests: XCTestCase {

    private let now = TestClock.now
    private let utc = TestClock.utc

    private func metabolicAge(_ value: Double, daysAgo: Int = 1,
                              source: MetricSource = .withings) -> [RawMetricSample] {
        (0..<5).map { offset in
            let date = now.addingTimeInterval(-Double(daysAgo + offset) * 86_400)
            return RawMetricSample(identifier: "withings.measure.227",
                                   displayName: "Metabolic age",
                                   value: value, unit: "", start: date, source: source)
        }
    }

    private func estimates(_ raw: [RawMetricSample]) -> [AgeComparison.Estimate] {
        AgeComparison.estimates(chronological: 40, fitness: nil, heart: nil, sex: .male,
                                samples: [], raw: raw, now: now, calendar: utc)
    }

    private func row(_ raw: [RawMetricSample]) throws -> AgeComparison.Estimate {
        try XCTUnwrap(estimates(raw).first { $0.identity != nil },
                      "the Withings age never reached the section")
    }

    /// The relay itself: a field with no `MetricType` behind it still gets a
    /// row, attributed to Withings.
    func testTheWithingsAgeReachesTheSectionAtAll() throws {
        let estimate = try row(metabolicAge(30))
        XCTAssertEqual(estimate.years, 30)
        XCTAssertTrue(estimate.attribution.hasPrefix("Withings"), estimate.attribution)
    }

    /// ⚠️ **The item.** It must not inherit the standard modelled caveat: the
    /// row says we believe this *is* their metabolic age and that Withings
    /// publishes nothing that would confirm it.
    func testTheRowStatesTheFieldMappingIsAnInferenceAndNotOnlyThatItIsModelled() throws {
        let note = try XCTUnwrap(row(metabolicAge(30)).identityNote)
        XCTAssertTrue(note.contains("inference"), note)
        XCTAssertTrue(note.contains("Withings"), note)
        XCTAssertTrue(note.contains("confirms it"), note)
        // And says outright that this caveat is a different kind from the four
        // "±N years" notes above it, which a reader would otherwise skim past.
        XCTAssertTrue(note.contains("the subject"), note)
    }

    /// The two doubts are both true of this row and are stated separately: the
    /// vendor publishes no error **and** no field table. Folding the identity
    /// doubt into `Uncertainty` would have `disagreement(_:)` read it as a
    /// width, which is a question it was never asked.
    func testTheIdentityDoubtIsNotDressedAsAnErrorBar() throws {
        let estimate = try row(metabolicAge(30))
        XCTAssertNil(estimate.uncertainty.years,
                     "an error was invented for a number the vendor publishes bare")
        XCTAssertTrue(estimate.uncertainty.note.contains("without an error"),
                      estimate.uncertainty.note)
    }

    /// ⚠️ **The strip above the rows draws the label and nothing else**, so a
    /// row labelled plainly "Metabolic age" would put the app's strongest
    /// unverified claim on a chart with no caveat attached to it at all.
    func testTheLabelItselfSaysTheFieldIsUnconfirmed() throws {
        let label = try row(metabolicAge(30)).label
        XCTAssertTrue(label.contains("unconfirmed"), label)
    }

    /// Relayed, never merged, and never read as the app's own — the strip tints
    /// any row whose attribution begins "This app" as ours.
    func testTheRelayedRowIsNeverAttributedToThisApp() throws {
        XCTAssertFalse(try row(metabolicAge(30)).attribution.hasPrefix("This app"))
    }

    /// The identification **is** the value range, so a value that leaves the
    /// age band withdraws the evidence for it. The row disappears rather than
    /// printing a number under a name that number has just refuted.
    func testAValueThatCannotBeAnAgeRemovesTheRowRatherThanPrintingIt() {
        XCTAssertTrue(estimates(metabolicAge(2_580)).allSatisfy { $0.identity == nil },
                      "a basal-metabolic-rate-shaped number was printed as an age")
    }

    /// A relayed reading that has gone quiet is shown with its age, exactly as
    /// the vascular row is — hiding it and pretending it is fresh are both
    /// wrong.
    func testAnOldWithingsReadingSaysHowOldItIs() throws {
        let stale = try XCTUnwrap(row(metabolicAge(30, daysAgo: 400)).staleness(now: now))
        XCTAssertTrue(stale.lowercased().contains("year"), stale)
    }

    /// ⚠️ **A finding built on an inferred identity has to say so.** The
    /// disagreement sentence's whole force is "this gap is real", and it is not
    /// if one endpoint might not be the quantity the app has called it.
    func testTheDisagreementSentenceNamesTheInferredEndpoint() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: (0..<10).map {
                HealthMetricSample(type: .vascularAge, value: 60,
                                   start: now.addingTimeInterval(-Double($0) * 86_400),
                                   source: .oura)
            },
            raw: metabolicAge(28), now: now, calendar: utc)
        let sentence = try XCTUnwrap(AgeComparison.disagreement(estimates),
                                     "a thirty-year gap was not called a disagreement")
        XCTAssertTrue(sentence.contains("wrong label"), sentence)
    }

    /// The row is not excluded from the spread to keep the arithmetic tidy: a
    /// sentence qualifying an endpoint the chart above has already drawn is
    /// honest, and silently dropping the row would leave the two disagreeing.
    func testTheRelayedRowStillCountsTowardsTheSpread() throws {
        let vascular = (0..<10).map {
            HealthMetricSample(type: .vascularAge, value: 60,
                               start: now.addingTimeInterval(-Double($0) * 86_400),
                               source: .oura)
        }
        func spread(raw: [RawMetricSample]) -> Double? {
            AgeComparison.spread(AgeComparison.estimates(
                chronological: 40, fitness: nil, heart: nil, sex: .male,
                samples: vascular, raw: raw, now: now, calendar: utc))
        }
        // Without the row there is one estimate and no spread at all; with it,
        // the spread reaches the relayed number rather than stopping short.
        XCTAssertNil(spread(raw: []))
        XCTAssertEqual(try XCTUnwrap(spread(raw: metabolicAge(28))), 32, accuracy: 0.001)
    }

    /// Nothing in the raw catalogue means no row, and no crash reading an empty
    /// group.
    func testAnEmptyRawCatalogueAddsNothing() {
        XCTAssertTrue(estimates([]).allSatisfy { $0.identity == nil })
    }

    /// Every identifier the section relays out of the raw catalogue must have a
    /// mapping behind it. A raw field's name is by definition not a canonical
    /// metric's name, so anything arriving through this lane is a field whose
    /// identity the app worked out — and must be labelled as such.
    func testEveryRelayedRawAgeCarriesAnInferredMapping() {
        for identifier in AgeComparison.relayedRawAgeIdentifiers {
            XCTAssertNotNil(RawFieldPresentation.inferredMapping(forPath: identifier),
                            "\(identifier) would be printed as an age with nothing behind its name")
        }
    }
}
