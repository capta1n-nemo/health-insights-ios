import XCTest
@testable import InsightKit

/// The Readiness strip draws what `VitalSignsCheck` already decided. These pin
/// the two places that could still come apart: the threshold rule (now shared,
/// so this is a regression net rather than a binding) and the panel's treatment
/// of readings it cannot plot.
final class VitalDepartureTests: XCTestCase {

    private func spec(_ metric: MetricType) throws -> VitalSignsCheck.Spec {
        try XCTUnwrap(VitalSignsCheck.specs.first { $0.metric == metric })
    }

    private func reading(_ metric: MetricType, z: Double?,
                         status: VitalSignsCheck.Reading.Status,
                         value: Double = 60) -> VitalSignsCheck.Reading {
        VitalSignsCheck.Reading(metric: metric, value: value, baseline: 60, zScore: z,
                                status: status, note: "", normality: 50,
                                measuredAt: Date(), sourceName: "Watch", historyDays: 28)
    }

    // MARK: - The threshold rule

    func testTheBandEdgesAreTheScansOwnConstants() {
        XCTAssertEqual(VitalDeparture.watchZ, VitalSignsCheck.watchZ)
        XCTAssertEqual(VitalDeparture.unusualZ, VitalSignsCheck.unusualZ)
    }

    /// The edges, from both sides. Written as literals on purpose: if somebody
    /// moves a threshold, this should make them say so rather than move with it.
    func testWhereTheBandsChange() {
        XCTAssertEqual(VitalDeparture.band(z: 1.24, concerning: true), .ordinary)
        XCTAssertEqual(VitalDeparture.band(z: 1.25, concerning: true), .watch)
        XCTAssertEqual(VitalDeparture.band(z: 1.99, concerning: true), .watch)
        XCTAssertEqual(VitalDeparture.band(z: 2.0, concerning: true), .unusual)
        XCTAssertEqual(VitalDeparture.band(z: -2.0, concerning: true), .unusual)
    }

    /// A big move towards the harmless side is worth noticing and is never an
    /// alarm. This is the one the naive `abs(z)` implementation gets wrong, and
    /// it would paint the best morning of the month in the same red as the worst.
    func testADepartureTowardsTheHarmlessSideIsNeverUnusual() {
        for tenth in 0...80 {
            let z = Double(tenth) / 10
            XCTAssertNotEqual(VitalDeparture.band(z: z, concerning: false), .unusual)
            XCTAssertNotEqual(VitalDeparture.band(z: -z, concerning: false), .unusual)
        }
        XCTAssertEqual(VitalDeparture.band(z: 3, concerning: false), .watch)
        XCTAssertEqual(VitalDeparture.band(z: 1.5, concerning: false), .ordinary)
    }

    /// Direction comes from the metric's own spec, not from the sign of z.
    func testDirectionIsReadFromTheSpec() throws {
        // A resting heart rate above baseline is the concerning way round.
        let rhr = try spec(.restingHeartRate)
        XCTAssertTrue(VitalDeparture.isConcerning(z: 2, spec: rhr))
        XCTAssertFalse(VitalDeparture.isConcerning(z: -2, spec: rhr))

        // Blood oxygen runs the other way: low is the problem.
        let spo2 = try spec(.oxygenSaturation)
        XCTAssertTrue(VitalDeparture.isConcerning(z: -2, spec: spo2))
        XCTAssertFalse(VitalDeparture.isConcerning(z: 2, spec: spo2))
    }

    // MARK: - What the panel refuses to draw

    /// A reading nobody could judge must leave the axis, not sit at zero. A dot
    /// at the origin says "measured, and ordinary", which is the opposite claim.
    func testAnUnjudgeableReadingBecomesAFootnoteNotAPointAtZero() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.restingHeartRate, z: nil, status: .insufficientHistory)],
            stale: [], events: [], score: nil, coverage: 1)
        let panel = VitalDeparturePanel.from(output)

        XCTAssertTrue(panel.rows.isEmpty)
        XCTAssertEqual(panel.unjudged, [.restingHeartRate])
        XCTAssertEqual(panel.footnote,
                       "Resting Heart Rate has too little history to judge yet.")
    }

    func testStaleVitalsAreNamedRatherThanDrawn() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.restingHeartRate, z: 0.2, status: .normal)],
            stale: [VitalSignsCheck.StaleReading(metric: .oxygenSaturation, value: 97,
                                                 lastMeasured: Date())],
            events: [], score: 90, coverage: 0.5)
        let panel = VitalDeparturePanel.from(output)

        XCTAssertEqual(panel.rows.map(\.metric), [.restingHeartRate])
        XCTAssertEqual(panel.stale, [.oxygenSaturation])
        XCTAssertEqual(panel.footnote,
                       "Blood Oxygen was not measured recently enough to show.")
    }

    func testNothingToApologiseForMeansNoFootnote() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.restingHeartRate, z: 0.2, status: .normal)],
            stale: [], events: [], score: 95, coverage: 1)
        XCTAssertNil(VitalDeparturePanel.from(output).footnote)
    }

    // MARK: - Drawing

    func testTheAxisIsBoundedAndSaysWhenItHadTo() throws {
        let output = VitalSignsCheck.Output(
            readings: [reading(.restingHeartRate, z: 9.4, status: .unusual),
                       reading(.oxygenSaturation, z: -1.4, status: .watch)],
            stale: [], events: [], score: 20, coverage: 1)
        let panel = VitalDeparturePanel.from(output)

        let pinned = try XCTUnwrap(panel.rows.first { $0.metric == .restingHeartRate })
        XCTAssertEqual(pinned.plotted, VitalDeparture.axisLimit)
        XCTAssertEqual(pinned.z, 9.4)
        XCTAssertTrue(pinned.isClamped)

        let ordinary = try XCTUnwrap(panel.rows.first { $0.metric == .oxygenSaturation })
        XCTAssertEqual(ordinary.plotted, -1.4)
        XCTAssertFalse(ordinary.isClamped)
    }

    func testWorstFirst() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.oxygenSaturation, z: -0.1, status: .normal),
                       reading(.restingHeartRate, z: 2.6, status: .unusual),
                       reading(.respiratoryRate, z: 1.4, status: .watch)],
            stale: [], events: [], score: 40, coverage: 1)
        XCTAssertEqual(VitalDeparturePanel.from(output).rows.map(\.metric),
                       [.restingHeartRate, .respiratoryRate, .oxygenSaturation])
    }

    /// A reading pushed to `.unusual` by an absolute clinical bound sits wherever
    /// its z-score puts it, which can be near the middle. The strip has to be
    /// able to say why it is red, or it just looks broken.
    func testAClinicalBoundIsFlaggedSoARedDotNearZeroMakesSense() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.oxygenSaturation, z: 0.3, status: .unusual, value: 88)],
            stale: [], events: [], score: 10, coverage: 1)
        let row = VitalDeparturePanel.from(output).rows.first

        XCTAssertEqual(row?.band, .unusual)
        XCTAssertEqual(row?.isBeyondClinicalBound, true)
        XCTAssertEqual(row?.plotted, 0.3)
    }

    func testAnOrdinaryDepartureIsNotFlaggedAsClinical() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.restingHeartRate, z: 2.4, status: .unusual)],
            stale: [], events: [], score: 30, coverage: 1)
        XCTAssertEqual(VitalDeparturePanel.from(output).rows.first?.isBeyondClinicalBound,
                       false)
    }

    // MARK: - The strip against the scan it draws

    /// End to end over generated data: every row the strip draws carries the
    /// band the scan itself assigned that metric, and nothing the scan judged is
    /// silently missing from the picture.
    func testThePanelNeverDisagreesWithTheScanItDraws() {
        let output = VitalSignsCheck.evaluate(samples: GoldenDataset.samples(),
                                              now: TestClock.now)
        let panel = VitalDeparturePanel.from(output)

        XCTAssertFalse(output.readings.isEmpty, "the fixture stopped producing readings")

        for reading in output.readings {
            if let row = panel.rows.first(where: { $0.metric == reading.metric }) {
                XCTAssertEqual(row.band, VitalDeparture.Band(reading.status),
                               "\(reading.metric) drawn as \(row.band) but scanned as \(reading.status)")
                XCTAssertEqual(row.z, reading.zScore)
            } else {
                XCTAssertNil(VitalDeparture.Band(reading.status),
                             "\(reading.metric) was judged but is not on the strip")
            }
        }
        XCTAssertEqual(panel.rows.count + panel.unjudged.count, output.readings.count)
    }

    // MARK: - Non-clinical metrics reach the strip too

    private func vitalReading(_ metric: MetricType, z: Double?,
                              value: Double = 8000) -> VitalReading {
        VitalReading(metric: metric, value: value, date: Date(),
                     baseline: z.map { _ in value }, zScore: z, history: [],
                     sourceName: "Watch", isFresh: true)
    }

    /// A step count or a VO₂max has no clinical concerning direction, so its
    /// baseline departure is neutral — notable ("watch") at most, never the
    /// clinical red. This is what lets "How far from your normal" list a card's
    /// non-vital signals without dressing a quiet day as an alarm.
    func testANonClinicalMetricGetsANeutralBaselineRow() throws {
        let dep = try XCTUnwrap(VitalDeparture.baseline(vitalReading(.stepCount, z: 2.5)))
        XCTAssertEqual(dep.metric, .stepCount)
        XCTAssertEqual(dep.z, 2.5)
        XCTAssertEqual(dep.band, .watch, "a big move with no concerning side caps at watch")
        XCTAssertFalse(dep.isConcerningDirection)
        XCTAssertFalse(dep.isBeyondClinicalBound)
    }

    func testANonClinicalMetricWithNoBaselineYieldsNoRow() {
        XCTAssertNil(VitalDeparture.baseline(vitalReading(.stepCount, z: nil)))
    }

    /// The fix for the reported gap: a Fitness-shaped card whose scan covers one
    /// of its signals must still draw the rest against their own baseline, so the
    /// section lists what "How you compare" lists rather than two rows out of six.
    func testForCardAddsTheNonScanSignalsBesideTheScanOnes() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.restingHeartRate, z: 0.2, status: .normal)],
            stale: [], events: [], score: 90, coverage: 1)
        let panel = VitalDeparturePanel.forCard(
            output, cardMetrics: [.restingHeartRate, .stepCount, .vo2Max],
            extraReadings: [vitalReading(.stepCount, z: 2.4, value: 3000),
                            vitalReading(.vo2Max, z: -0.5, value: 42)])
        XCTAssertEqual(Set(panel.rows.map(\.metric)),
                       [.restingHeartRate, .stepCount, .vo2Max])
        XCTAssertEqual(panel.rows.first?.metric, .stepCount, "worst departure leads")
    }

    /// A metric the scan already drew must not be added a second time from the
    /// extra readings.
    func testForCardDoesNotDuplicateAScanMetric() {
        let output = VitalSignsCheck.Output(
            readings: [reading(.restingHeartRate, z: 0.2, status: .normal)],
            stale: [], events: [], score: 90, coverage: 1)
        let panel = VitalDeparturePanel.forCard(
            output, cardMetrics: [.restingHeartRate],
            extraReadings: [vitalReading(.restingHeartRate, z: 5)])
        XCTAssertEqual(panel.rows.filter { $0.metric == .restingHeartRate }.count, 1)
    }
}
