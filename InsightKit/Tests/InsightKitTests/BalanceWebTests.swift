import XCTest
@testable import InsightKit

/// The balance web's geometry and its honesty rules.
///
/// In InsightKit because the app target has no test target and SwiftUI does not
/// exist on Linux — so this is the only place the layout of the Insights tab's
/// hero can be falsified at all. See `add-chart` §5.
final class BalanceWebTests: XCTestCase {

    private func result(_ id: InsightID, score: Double?) -> InsightResult {
        InsightResult(id: id, title: "\(id.rawValue) title", primaryValue: score,
                      headline: "h", score: score, confidence: .moderate,
                      explanation: "e", drivers: [], unmetRequirements: [])
    }

    private func change(recent: Double, reference: Double) -> ScoreChange {
        ScoreChange(recent: recent, reference: reference, delta: recent - reference,
                    standardisedDelta: (recent - reference) / 4,
                    recentDays: 28, referenceDays: 90,
                    comparison: "against your quarter",
                    threshold: ScoreChange.trendThreshold)
    }

    // MARK: - Geometry

    /// Index 0 sits at twelve o'clock. In a y-down space that is one radius
    /// *above* the centre, which is the sign that gets flipped by accident.
    func testFirstSpokeIsAtTheTop() {
        let point = BalanceWebGeometry.point(index: 0, count: 6, radiusFraction: 1)
        XCTAssertEqual(point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(point.y, -1, accuracy: 1e-9)
    }

    /// Clockwise on screen: the next spoke of four is to the right.
    func testSpokesRunClockwise() {
        let second = BalanceWebGeometry.point(index: 1, count: 4, radiusFraction: 1)
        XCTAssertEqual(second.x, 1, accuracy: 1e-9)
        XCTAssertEqual(second.y, 0, accuracy: 1e-9)
    }

    /// Every vertex sits on the circle of its own radius — the property that
    /// fails the moment an angle is computed in degrees somewhere.
    func testVerticesLieOnTheirOwnRadius() {
        for count in 3...9 {
            for index in 0..<count {
                let fraction = 0.4
                let point = BalanceWebGeometry.point(index: index, count: count,
                                                     radiusFraction: fraction)
                XCTAssertEqual((point.x * point.x + point.y * point.y).squareRoot(),
                               fraction, accuracy: 1e-9)
            }
        }
    }

    /// No inner floor: a zero belongs at the centre, where the grid says it is.
    func testScoreMapsLinearlyToRadiusWithNoFloor() {
        XCTAssertEqual(BalanceWebGeometry.radiusFraction(forScore: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(BalanceWebGeometry.radiusFraction(forScore: 50), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BalanceWebGeometry.radiusFraction(forScore: 100), 1, accuracy: 1e-9)
    }

    /// A score outside 0–100 is a bug upstream, but it must not draw outside the
    /// outer ring while somebody finds it.
    func testRadiusIsClampedToTheOuterRing() {
        XCTAssertEqual(BalanceWebGeometry.radiusFraction(forScore: 140), 1, accuracy: 1e-9)
        XCTAssertEqual(BalanceWebGeometry.radiusFraction(forScore: -20), 0, accuracy: 1e-9)
    }

    // MARK: - Ordering

    /// The order is `colourSlot` — the daily block, then the trend block —
    /// whatever order the results arrive in.
    ///
    /// Load-bearing rather than tidy: a radar's enclosed area depends on which
    /// spokes are adjacent, so an order that varied between launches would
    /// redraw the shape without a single score moving.
    func testSpokeOrderIsFixedRegardlessOfResultOrder() {
        let forwards = BalanceWebSnapshot.build(
            results: [result(.bodyComposition, score: 40), result(.readiness, score: 60),
                      result(.fitness, score: 50)],
            changes: [:])
        let backwards = BalanceWebSnapshot.build(
            results: [result(.fitness, score: 50), result(.bodyComposition, score: 40),
                      result(.readiness, score: 60)],
            changes: [:])
        XCTAssertEqual(forwards.spokes.map(\.id), backwards.spokes.map(\.id))
        XCTAssertEqual(forwards.spokes.map(\.id), [.readiness, .fitness, .bodyComposition])
    }

    /// An insight with no score is not a spoke at zero — it is not a spoke.
    /// Drawing it at the centre would read as "you scored nothing", which is the
    /// opposite of "we could not score this".
    func testUnscoredInsightsAreNotDrawn() {
        let snapshot = BalanceWebSnapshot.build(
            results: [result(.readiness, score: 60), result(.sleep, score: nil),
                      result(.fitness, score: 50)],
            changes: [:])
        XCTAssertEqual(snapshot.spokes.map(\.id), [.readiness, .fitness])
    }

    // MARK: - The drawable floor

    /// Two scores draw a line segment, not a shape.
    func testTwoSpokesAreNotDrawable() {
        let snapshot = BalanceWebSnapshot.build(
            results: [result(.readiness, score: 60), result(.sleep, score: 70)],
            changes: [:])
        XCTAssertFalse(snapshot.isDrawable)
        XCTAssertTrue(BalanceWebSnapshot.build(
            results: [result(.readiness, score: 60), result(.sleep, score: 70),
                      result(.fitness, score: 50)],
            changes: [:]).isDrawable)
    }

    // MARK: - The reference outline

    /// A closed reference polygon is only honest when every spoke has one —
    /// otherwise its edges run straight past the vertices it has no value for,
    /// and the reader cannot see which were skipped.
    func testReferencePolygonNeedsEverySpoke() {
        let partial = BalanceWebSnapshot.build(
            results: [result(.readiness, score: 60), result(.sleep, score: 70),
                      result(.fitness, score: 50)],
            changes: [.readiness: change(recent: 60, reference: 55)])
        XCTAssertFalse(partial.hasCompleteReference)

        let complete = BalanceWebSnapshot.build(
            results: [result(.readiness, score: 60), result(.sleep, score: 70),
                      result(.fitness, score: 50)],
            changes: [.readiness: change(recent: 60, reference: 55),
                      .sleep: change(recent: 70, reference: 72),
                      .fitness: change(recent: 50, reference: 44)])
        XCTAssertTrue(complete.hasCompleteReference)
    }

    /// The reference is the mean of the window the card is judged against — the
    /// same number the card's own chip is computed from, never the score itself.
    func testReferenceComesFromTheScoreChangeNotTheScore() {
        let snapshot = BalanceWebSnapshot.build(
            results: [result(.readiness, score: 60)],
            changes: [.readiness: change(recent: 60, reference: 55)])
        XCTAssertEqual(snapshot.spokes.first?.reference, 55)
        XCTAssertEqual(snapshot.spokes.first?.referenceFraction ?? 0, 0.55, accuracy: 1e-9)
    }

    /// No stored history is "we cannot say yet", which must stay distinguishable
    /// from "it has not moved".
    func testAbsentChangeLeavesTheReferenceNil() {
        let snapshot = BalanceWebSnapshot.build(results: [result(.readiness, score: 60)],
                                                changes: [:])
        XCTAssertNil(snapshot.spokes.first?.reference)
        XCTAssertNil(snapshot.spokes.first?.direction)
    }

    // MARK: - The summary sentence

    /// It quotes the spread, which is a fact about the reader — never the area,
    /// which is a fact about the axis order.
    func testSummaryQuotesTheSpreadAndItsEnds() throws {
        let snapshot = BalanceWebSnapshot.build(
            results: [result(.readiness, score: 38), result(.sleep, score: 69),
                      result(.fitness, score: 50)],
            changes: [:])
        XCTAssertEqual(snapshot.spread ?? 0, 31, accuracy: 1e-9)
        let summary = try XCTUnwrap(snapshot.summary)
        XCTAssertTrue(summary.contains("31 points"), summary)
        XCTAssertTrue(summary.contains("Sleep"), summary)
        XCTAssertTrue(summary.contains("Readiness"), summary)
    }

    /// A tight cluster gets the other sentence — "span 4 points, Sleep highest
    /// at 69, Fitness lowest at 65" invites a reading of a difference that is
    /// inside the noise these scores are already smoothed against.
    func testATightSpreadReadsAsBalanced() throws {
        let snapshot = BalanceWebSnapshot.build(
            results: [result(.readiness, score: 65), result(.sleep, score: 69),
                      result(.fitness, score: 67)],
            changes: [:])
        let summary = try XCTUnwrap(snapshot.summary)
        XCTAssertTrue(summary.contains("within 4 points"), summary)
    }

    /// The threshold is the amber band's width, not a tuned constant, so it
    /// moves if the bands do.
    func testBalancedThresholdIsTheBandWidth() {
        XCTAssertEqual(BalanceWebSnapshot.balancedSpreadPoints, 15)
    }

    /// Nothing to compare, nothing to say.
    func testEmptySnapshotHasNoSummary() {
        XCTAssertNil(BalanceWebSnapshot.empty.summary)
        XCTAssertNil(BalanceWebSnapshot.empty.spread)
        XCTAssertFalse(BalanceWebSnapshot.empty.isDrawable)
    }

    // MARK: - Labels

    /// Every insight has a word for the chart. The compiler holds this; the test
    /// holds that nobody satisfied the compiler with an empty string or a
    /// duplicate, which would put two identical labels on one circle.
    func testEveryInsightHasADistinctShortTitle() {
        let titles = InsightID.allCases.map(\.shortTitle)
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(titles).count, InsightID.allCases.count)
        XCTAssertTrue(titles.allSatisfy { $0.count <= 11 }, "\(titles)")
    }

    // MARK: - What "usual" means

    private func spoke(_ id: InsightID, score: Double,
                       reference: Double?, referenceDays: Int?) -> BalanceWebSnapshot.Spoke {
        BalanceWebSnapshot.Spoke(id: id, title: id.rawValue, shortTitle: id.shortTitle,
                                 score: score, reference: reference,
                                 direction: nil, referenceDays: referenceDays)
    }

    /// **The legend used to say "Usual" and nothing else**, and the reader asked
    /// what it was averaging over. The honest answer is that it is not one
    /// window: a `.daily` card is judged against the trailing week and a
    /// `.trend` card against the quarter, so the grey shape is a composite and a
    /// legend claiming a single period would be wrong on most of its vertices.
    func testItNamesBothWindowsWhenTheSpokesDisagree() throws {
        let snapshot = BalanceWebSnapshot(spokes: [
            spoke(.readiness, score: 70, reference: 68, referenceDays: 7),
            spoke(.heartHealth, score: 80, reference: 76, referenceDays: 90)
        ])
        let described = try XCTUnwrap(snapshot.referenceDescription)
        XCTAssertTrue(described.contains("week"), described)
        XCTAssertTrue(described.contains("3 months"), described)
    }

    func testItNamesOneWindowWhenEverySpokeAgrees() throws {
        let snapshot = BalanceWebSnapshot(spokes: [
            spoke(.readiness, score: 70, reference: 68, referenceDays: 7),
            spoke(.energy, score: 60, reference: 62, referenceDays: 7)
        ])
        let described = try XCTUnwrap(snapshot.referenceDescription)
        XCTAssertTrue(described.contains("last week"), described)
        XCTAssertFalse(described.contains("months"), described)
    }

    /// Nothing to describe when nothing has a reference — the grey shape is not
    /// drawn either, and a legend for an absent mark is worse than no legend.
    func testThereIsNothingToSayWithNoReference() {
        let snapshot = BalanceWebSnapshot(spokes: [
            spoke(.readiness, score: 70, reference: nil, referenceDays: nil)
        ])
        XCTAssertNil(snapshot.referenceDescription)
    }

    // MARK: - What belongs on the chart at all

    /// **A detector is not a score.** The symptom radar reports 100 when it has
    /// found nothing, so on the reader's real record it drew as the single
    /// highest spoke — silence rendered as excellence, on the one card whose
    /// entire design exists to prevent that. Seen on 2026-08-04 with real data
    /// loaded into a simulator; no synthetic fixture would have shown it,
    /// because it needs every other card to be scoring realistically for the
    /// radar's 100 to stand out.
    func testTheSymptomRadarIsNotDrawnAsAScoreToCompare() {
        let snapshot = BalanceWebSnapshot.build(
            results: [
                InsightResult(id: .symptomRadar, title: "Symptom radar", primaryValue: nil,
                              headline: "Nothing stirring", score: 100, confidence: .moderate,
                              explanation: "", drivers: [], unmetRequirements: []),
                InsightResult(id: .sleep, title: "Sleep", primaryValue: nil,
                              headline: "Poor", score: 49, confidence: .moderate,
                              explanation: "", drivers: [], unmetRequirements: [])
            ],
            changes: [:])
        XCTAssertEqual(snapshot.spokes.map(\.id), [.sleep],
                       "the radar is on the web, where its quiet 100 reads as perfect health")
    }

    /// And the exclusions are narrow — nothing else was swept up with them.
    ///
    /// **Two reasons a card can be off this web, and they are different
    /// arguments.** Written out here rather than left as a set of names, because
    /// `CardVisibilityTests` froze a real bug in exactly this shape: a closed
    /// set populated from what the build happened to do rather than from the
    /// rule it exists to enforce. A third card wanting off has to match one of
    /// these sentences or change them.
    ///
    /// 1. `symptomRadar` — **not a score of the same kind.** It is a detector,
    ///    and its quiet 100 read as perfect health beside genuine scores.
    /// 2. `biologicalAge` — **a composite of spokes already on the chart.** It is
    ///    built from cardio fitness, blood pressure and body fat, so drawing it
    ///    beside them would show one agreement as four independent findings.
    ///    Every other card here reads signals nothing else on the web reads.
    /// 3. `mentalHealth` — **its best answer is "nothing found"**, which is the
    ///    radar's argument reached from a different direction. Its top band means
    ///    four numbers did not move; drawn as "Mind 80" in green beside Fitness
    ///    33 it reads as *your mind is fine and your body is not*, which is the
    ///    one claim that card exists to refuse. Seen on screen, 2026-08-06.
    func testEveryOtherScoringCardStillBelongsOnTheWeb() {
        let excluded: Set<InsightID> = [.symptomRadar, .biologicalAge, .mentalHealth]
        for id in InsightID.allCases where !excluded.contains(id) {
            XCTAssertTrue(id.belongsOnBalanceWeb, "\(id) fell off the comparison chart")
        }
        for id in excluded {
            XCTAssertFalse(id.belongsOnBalanceWeb,
                           "\(id) is listed as a deliberate exclusion and is on the web")
        }
    }

    /// The composite argument, asserted rather than described: every marker
    /// biological age is built from is read by a card that *is* on the web.
    ///
    /// If that ever stops being true — a marker only this card reads — the
    /// exclusion above weakens and this test says so.
    func testBiologicalAgeIsBuiltEntirelyFromSpokesAlreadyOnTheWeb() {
        let onTheWeb = InsightEngine().models
            .filter { $0.id.belongsOnBalanceWeb }
            .flatMap(\.candidateMetrics)
        for metric in BiologicalAgeModel.candidates {
            XCTAssertTrue(onTheWeb.contains(metric),
                          "\(metric) is read only by biological age, so it is not a composite of the web after all")
        }
    }
}
