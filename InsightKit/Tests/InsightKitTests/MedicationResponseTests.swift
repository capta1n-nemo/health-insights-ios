import XCTest
@testable import InsightKit

/// `MedicationResponse` answers "is it working", which is the one question on
/// this card a reader will act on. Everything here is about it either being
/// right or having no number at all — an invented one is worse than a blank.
final class MedicationResponseTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func day(_ offset: Double) -> Date {
        now.addingTimeInterval(offset * 86_400)
    }

    private func weight(_ kg: Double, _ offset: Double) -> HealthMetricSample {
        HealthMetricSample(type: .bodyMass, value: kg, start: day(offset), source: .manual)
    }

    private func dose(_ mg: Double, _ offset: Double,
                      site: String? = nil, inferred: Bool = false) -> AdministeredDose {
        AdministeredDose(takenAt: day(offset), milligrams: mg,
                         isInferred: inferred, site: site)
    }

    // MARK: - Attribution

    func testWeightChangeIsCreditedToTheDoseInEffect() {
        // 2.5 mg for a week, losing 1 kg; then 5 mg for a week, losing 2 kg.
        let doses = [dose(2.5, -14), dose(5, -7)]
        let weights = [weight(100, -14), weight(99, -7), weight(97, 0)]
        let analysis = MedicationResponse.analyze(doses: doses, weights: weights, now: now)

        XCTAssertEqual(analysis.byDose.count, 2)
        XCTAssertEqual(analysis.byDose[0].label, "2.5 mg")
        XCTAssertEqual(analysis.byDose[0].totalChange, -1, accuracy: 0.001)
        XCTAssertEqual(analysis.byDose[1].label, "5 mg")
        XCTAssertEqual(analysis.byDose[1].totalChange, -2, accuracy: 0.001)
    }

    /// The ladder reads in ladder order, not in the order the rows happened to
    /// hash — 4.5 before 5 before 11 before 12.5, whatever the dictionary says.
    func testDoseRowsAreOrderedUpTheLadder() {
        let doses = [dose(12.5, -40), dose(4.5, -30), dose(5, -20), dose(11, -10)]
        let weights = (0...40).map { weight(110 - Double($0) * 0.1, -Double(40 - $0)) }
        let analysis = MedicationResponse.analyze(doses: doses, weights: weights, now: now)
        XCTAssertEqual(analysis.byDose.map(\.milligrams), [4.5, 5, 11, 12.5])
    }

    func testPerWeekIsAWeeklyRateNotATotal() {
        // One dose, two weeks, 3 kg lost → −1.5 kg/week.
        let analysis = MedicationResponse.analyze(
            doses: [dose(7.5, -14)],
            weights: [weight(100, -14), weight(97, 0)], now: now)
        XCTAssertEqual(analysis.byDose[0].perWeek, -1.5, accuracy: 0.01)
    }

    /// A dose step whose weeks were never weighed contributes its days and its
    /// count, but no rate. Reporting kg/week from nothing is the failure mode
    /// worth being loud about.
    func testAPeriodWithNoWeighInsHasNoRate() {
        let doses = [dose(2.5, -60), dose(5, -1)]
        // Nothing within ten days of the first period at all.
        let weights = [weight(100, -1), weight(99.5, 0)]
        let analysis = MedicationResponse.analyze(doses: doses, weights: weights, now: now)
        let first = analysis.byDose.first { $0.milligrams == 2.5 }
        XCTAssertEqual(first?.totalChange, 0)
        XCTAssertEqual(first?.perWeek, 0)
        XCTAssertGreaterThan(first?.days ?? 0, 50, "the days still count")
    }

    func testAWeighInBeyondToleranceIsNotBorrowed() {
        let readings = [(date: day(-30), value: 100.0)]
        XCTAssertNil(MedicationResponse.nearest(to: day(0), in: readings))
        XCTAssertEqual(MedicationResponse.nearest(to: day(-25), in: readings), 100)
    }

    func testInferredDosesStillDefineTheStep() {
        // The titration engine's proposal is what says the reader was on 2.5
        // before they started logging. Excluding it would credit the whole
        // period to the first hand-logged dose.
        let doses = [dose(2.5, -14, inferred: true), dose(5, -7)]
        let weights = [weight(100, -14), weight(99, -7), weight(97, 0)]
        let analysis = MedicationResponse.analyze(doses: doses, weights: weights, now: now)
        XCTAssertEqual(analysis.byDose.map(\.milligrams), [2.5, 5])
    }

    // MARK: - Sites

    func testSitesAreTalliedSeparatelyFromDoses() {
        let doses = [dose(5, -21, site: "Stomach upper left"),
                     dose(5, -14, site: "Stomach lower right"),
                     dose(5, -7, site: "Stomach upper left")]
        let weights = (0...21).map { weight(100 - Double($0) * 0.1, -Double(21 - $0)) }
        let analysis = MedicationResponse.analyze(doses: doses, weights: weights, now: now)

        XCTAssertEqual(analysis.byDose.count, 1, "one dose step")
        XCTAssertEqual(Set(analysis.bySite.map(\.label)),
                       ["Stomach upper left", "Stomach lower right"])
        let left = analysis.bySite.first { $0.label == "Stomach upper left" }
        XCTAssertEqual(left?.doseCount, 2)
    }

    func testDosesWithNoSiteDoNotBecomeABlankRow() {
        let analysis = MedicationResponse.analyze(
            doses: [dose(5, -14), dose(5, -7)],
            weights: [weight(100, -14), weight(98, 0)], now: now)
        XCTAssertTrue(analysis.bySite.isEmpty)
    }

    // MARK: - Overall

    func testOverallIsMeasuredFromTheFirstDoseNotTheFirstEverWeighIn() {
        // A year of weight history before the medication started must not be
        // counted as the medication's doing.
        let old = [weight(130, -400), weight(125, -300)]
        let recent = [weight(110, -70), weight(100, 0)]
        let analysis = MedicationResponse.analyze(
            doses: [dose(2.5, -70)], weights: old + recent, now: now)

        let overall = analysis.overall
        XCTAssertEqual(overall?.startWeight, 110)
        XCTAssertEqual(overall?.totalChange ?? 0, -10, accuracy: 0.001)
        XCTAssertEqual(overall?.percentChange ?? 0, -9.09, accuracy: 0.05)
        XCTAssertEqual(overall?.weeks ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(overall?.perWeek ?? 0, -1, accuracy: 0.01)
    }

    func testNoDosesMeansNoAnalysis() {
        let analysis = MedicationResponse.analyze(
            doses: [], weights: [weight(100, -7), weight(99, 0)], now: now)
        XCTAssertTrue(analysis.isEmpty)
        XCTAssertNil(analysis.overall)
    }

    // MARK: - The overlay

    func testOverlayStandardisesEachSeriesAgainstItsOwnSpread() {
        let curve = (0...30).map {
            ActiveCompoundPoint(date: day(Double($0) - 30),
                                level: 5 + Double($0) * 0.1,
                                restsOnInferredDose: false)
        }
        let weights = (0...30).map { weight(100 - Double($0) * 0.2, Double($0) - 30) }
        let fat = (0...30).map {
            HealthMetricSample(type: .bodyFatPercentage, value: 33 - Double($0) * 0.05,
                               start: day(Double($0) - 30), source: .manual)
        }
        let series = MedicationResponse.overlay(curve: curve, weights: weights + fat,
                                                range: day(-30)...now)

        XCTAssertEqual(series.map(\.kind), [.onBoard, .weight, .bodyFat])
        for one in series {
            let zs = one.points.map(\.z)
            // Standardised: mean ~0, and the ends are the extremes.
            XCTAssertEqual(zs.reduce(0, +) / Double(zs.count), 0, accuracy: 0.001)
            XCTAssertGreaterThan(abs(zs.first ?? 0), 1.5)
        }
    }

    /// Three lines, three hues, decided in InsightKit rather than by eye — the
    /// rule the `add-chart` skill exists to enforce.
    func testEverySeriesTakesADistinctPaletteSlot() {
        let slots = MedicationResponse.ResponseSeries.Kind.allCases.map(\.paletteSlot)
        XCTAssertEqual(Set(slots).count, slots.count)
    }

    /// The dash rule survives normalisation. A curve resting on doses the app
    /// worked out has to stay drawn as an estimate once it is standardised —
    /// losing the flag in the normaliser would put a guess on the chart as a
    /// solid line.
    func testInferredStretchesSurviveStandardisation() {
        let curve = (0...30).map {
            ActiveCompoundPoint(date: day(Double($0) - 30),
                                level: 5 + Double($0) * 0.1,
                                restsOnInferredDose: $0 < 15)
        }
        let series = MedicationResponse.overlay(curve: curve, weights: [],
                                                range: day(-30)...now)
        let onBoard = series.first { $0.kind == .onBoard }
        XCTAssertEqual(onBoard?.points.filter(\.isInferred).count, 15)
        XCTAssertEqual(onBoard?.points.last?.isInferred, false)
        // And the real milligrams are still there for the read-out.
        XCTAssertEqual(onBoard?.points.last?.raw ?? 0, 8, accuracy: 0.001)
    }

    func testAConstantSeriesIsDroppedRatherThanDrawnFlat() {
        let curve = (0...10).map {
            ActiveCompoundPoint(date: day(Double($0) - 10), level: 5,
                                restsOnInferredDose: false)
        }
        let series = MedicationResponse.overlay(curve: curve, weights: [],
                                                range: day(-10)...now)
        XCTAssertTrue(series.isEmpty)
    }

    func testOverlayHonoursTheVisibleRange() {
        let curve = (0...60).map {
            ActiveCompoundPoint(date: day(Double($0) - 60), level: Double($0),
                                restsOnInferredDose: false)
        }
        let series = MedicationResponse.overlay(curve: curve, weights: [],
                                                range: day(-7)...now)
        XCTAssertEqual(series.first?.points.count, 8)
    }

    // MARK: - Side effects

    func testSideEffectsAreRankedBySeverityNotFrequency() {
        let effects: [(name: String, severity: Int, date: Date)] = [
            ("Nausea", 2, day(-5)), ("Nausea", 2, day(-4)), ("Nausea", 2, day(-3)),
            ("Nausea", 2, day(-2)), ("Nausea", 2, day(-1)),
            ("Vomiting", 9, day(-6)), ("Vomiting", 9, day(-2))
        ]
        let tally = MedicationResponse.sideEffectTally(effects)
        XCTAssertEqual(tally.first?.name, "Vomiting")
        XCTAssertEqual(tally.first?.occurrences, 2)
        XCTAssertEqual(tally.first?.averageSeverity ?? 0, 9, accuracy: 0.001)
        XCTAssertEqual(tally.last?.name, "Nausea")
        XCTAssertEqual(tally.last?.occurrences, 5)
    }
}
