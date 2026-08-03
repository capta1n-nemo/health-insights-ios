import XCTest
@testable import InsightKit

/// Choosing between sources that measured the same part of the same body.
///
/// The reader's rule, in their words: a scan taken in this app overrides,
/// *"unless we see an issue with the measurements in Apple Health being more
/// accurate than ours"*. Both halves are pinned here.
final class BodyMeasurementSourceTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var now: Date { date(2026, 8, 3) }

    private func measurement(_ provenance: BodyMeasurementProvenance, _ cm: Double,
                             site: BodySite = .waist,
                             on when: Date? = nil) -> SourcedMeasurement {
        SourcedMeasurement(site: site, centimetres: cm, provenance: provenance,
                           measuredAt: when ?? date(2026, 8, 1))
    }

    private func resolve(_ candidates: [SourcedMeasurement])
        -> BodyMeasurementReconciliation.Outcome? {
        BodyMeasurementReconciliation.resolve(candidates, now: now, calendar: calendar)
    }

    // MARK: - The reader's rule

    /// **The first half.** A LiDAR scan taken here beats a Health entry of
    /// unknown provenance — it is an actual, and the other is not known to be
    /// better.
    func testOurLidarScanOverridesAppleHealth() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.externalHealthApp, 92),
            measurement(.lidarScan, 88)
        ]))
        XCTAssertEqual(outcome.chosen.provenance, .lidarScan)
    }

    /// **The second half — the escape hatch.** A camera silhouette is the
    /// weakest method here, so preferring it over somebody's actual measurement
    /// would be the app trusting its own guess above a reading.
    func testAppleHealthOverridesOurCameraScan() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.cameraScan, 88),
            measurement(.externalHealthApp, 92)
        ]))
        XCTAssertEqual(outcome.chosen.provenance, .externalHealthApp)
    }

    /// **A tape beats everything**, including our own LiDAR. It measures the
    /// quantity directly rather than inferring it from pixels, and ranking by
    /// whose app it came from rather than by method would throw that away.
    func testATapeBeatsEveryOpticalMethod() throws {
        for optical in [BodyMeasurementProvenance.lidarScan, .cameraScan] {
            let outcome = try XCTUnwrap(resolve([
                measurement(optical, 88), measurement(.tape, 91)
            ]))
            XCTAssertEqual(outcome.chosen.provenance, .tape, "\(optical) should defer to a tape")
        }
    }

    /// Same method twice: the newer one is the reader's body today.
    func testTheFresherReadingWinsWithinAMethod() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.lidarScan, 92, on: date(2026, 6, 1)),
            measurement(.lidarScan, 88, on: date(2026, 8, 1))
        ]))
        XCTAssertEqual(outcome.chosen.centimetres, 88)
    }

    /// **Authority does not last forever.** Without this a single tape reading
    /// would describe a body it no longer matches, outranking every scan since.
    func testAStaleAuthoritativeReadingLosesToAFreshOne() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.tape, 100, on: date(2026, 1, 1)),      // long stale
            measurement(.cameraScan, 88, on: date(2026, 8, 1))
        ]))
        XCTAssertEqual(outcome.chosen.provenance, .cameraScan)
    }

    /// But it holds inside the window — one scan cycle should not displace a
    /// better method.
    func testAuthorityHoldsInsideTheWindow() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.tape, 91, on: date(2026, 7, 20)),
            measurement(.cameraScan, 88, on: date(2026, 8, 1))
        ]))
        XCTAssertEqual(outcome.chosen.provenance, .tape)
    }

    // MARK: - Disagreement is information

    /// Two methods within their combined noise are two methods agreeing.
    func testCloseReadingsAreNotADispute() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.lidarScan, 88), measurement(.externalHealthApp, 89)
        ]))
        XCTAssertFalse(outcome.isDisputed)
        XCTAssertNil(outcome.note)
    }

    /// **Beyond the noise, one of them is wrong and the app cannot tell which**
    /// — so it says so rather than hiding the loser.
    func testAWideDisagreementIsFlaggedRatherThanHidden() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.lidarScan, 88), measurement(.externalHealthApp, 97)
        ]))
        XCTAssertTrue(outcome.isDisputed)
        let note = try XCTUnwrap(outcome.note)
        XCTAssertTrue(note.contains("88"), note)
        XCTAssertTrue(note.contains("97"), note)
    }

    /// The losing sources stay available — the card can show what else was read.
    func testAlternativesAreKept() throws {
        let outcome = try XCTUnwrap(resolve([
            measurement(.lidarScan, 88),
            measurement(.externalHealthApp, 97),
            measurement(.cameraScan, 90)
        ]))
        XCTAssertEqual(outcome.alternatives.count, 2)
    }

    /// The dispute band widens with the shakier method: a camera scan is allowed
    /// to differ further before it counts as a real disagreement.
    func testTheBandWidensForTheWeakerMethod() throws {
        let tight = try XCTUnwrap(resolve([
            measurement(.tape, 88), measurement(.lidarScan, 90.5)
        ]))
        XCTAssertTrue(tight.isDisputed, "2.5 cm exceeds tape+LiDAR's 2.0")

        let loose = try XCTUnwrap(resolve([
            measurement(.externalHealthApp, 88), measurement(.cameraScan, 90.5)
        ]))
        XCTAssertFalse(loose.isDisputed, "2.5 cm is inside Health+camera's 3.5")
    }

    // MARK: - Merging

    /// The whole point: a reader with Apple Health well populated gets a body
    /// model **without ever opening the scanner**.
    func testAppleHealthAloneProducesUsableMeasurements() {
        let merged = BodyMeasurementReconciliation.merge([
            measurement(.externalHealthApp, 92, site: .waist),
            measurement(.externalHealthApp, 101, site: .hip)
        ], now: now, calendar: calendar)
        XCTAssertEqual(merged.mean(.waist), 92)
        XCTAssertEqual(merged.mean(.hip), 101)
    }

    /// A scan improves the sites it measured and leaves the others alone, rather
    /// than replacing the whole set.
    func testAScanUpgradesOnlyTheSitesItMeasured() {
        let merged = BodyMeasurementReconciliation.merge([
            measurement(.externalHealthApp, 92, site: .waist),
            measurement(.externalHealthApp, 101, site: .hip),
            measurement(.lidarScan, 88, site: .waist)
        ], now: now, calendar: calendar)
        XCTAssertEqual(merged.mean(.waist), 88, "the scan wins where it measured")
        XCTAssertEqual(merged.mean(.hip), 101, "and leaves what it didn't alone")
    }

    /// Merged measurements feed the assessment that has never had an input.
    func testMergedMeasurementsReachTheBuildAssessment() throws {
        let merged = BodyMeasurementReconciliation.merge([
            measurement(.externalHealthApp, 92, site: .waist)
        ], now: now, calendar: calendar)
        let scan = BodyScan(id: UUID(), capturedAt: now, mode: .tape, parserVersion: 1,
                            measurements: merged, conditions: ScanConditions(),
                            retainedAssets: [])
        let dimensions = try XCTUnwrap(scan.dimensions(heightMetres: 1.80))
        XCTAssertNotNil(BuildAssessmentModel.evaluate(dimensions: dimensions,
                                                      weightKg: 82, sex: .male))
    }

    func testDisputesAreListedPerSite() {
        let disputes = BodyMeasurementReconciliation.disputes([
            measurement(.lidarScan, 88, site: .waist),
            measurement(.externalHealthApp, 97, site: .waist),
            measurement(.lidarScan, 100, site: .hip),
            measurement(.externalHealthApp, 100.5, site: .hip)
        ], now: now, calendar: calendar)
        XCTAssertEqual(disputes.count, 1)
        XCTAssertEqual(disputes.first?.chosen.site, .waist)
    }

    func testNothingInNothingOut() {
        XCTAssertNil(resolve([]))
        XCTAssertTrue(BodyMeasurementReconciliation.merge([], now: now,
                                                          calendar: calendar).values.isEmpty)
    }
}
