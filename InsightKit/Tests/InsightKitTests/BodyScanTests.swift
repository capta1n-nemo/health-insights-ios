import XCTest
@testable import InsightKit

/// The body-scan core: what a scan holds, what it may keep, whether two of them
/// can be compared, and when the next one is due.
final class BodyScanTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func scan(waist: Double = 88, thighLeft: Double = 56, thighRight: Double = 58,
                      mode: BodyScan.CaptureMode = .lidarDepth,
                      conditions: ScanConditions = ScanConditions(clothing: .formFitting),
                      at when: Date? = nil) -> BodyScan {
        BodyScan(id: UUID(), capturedAt: when ?? date(2026, 8, 1), mode: mode,
                 parserVersion: 1,
                 measurements: BodyMeasurements([
                     .init(site: .waist, centimetres: waist),
                     .init(site: .hip, centimetres: 100),
                     .init(site: .thigh, side: .left, centimetres: thighLeft),
                     .init(site: .thigh, side: .right, centimetres: thighRight)
                 ]),
                 conditions: conditions, retainedAssets: [.depthMap, .personMask])
    }

    // MARK: - Measurements

    /// A paired site reports the **mean** of the two sides. Two lines a
    /// centimetre apart say less than one line plus a symmetry figure.
    func testAPairedSiteAveragesItsSides() {
        let measurements = scan(thighLeft: 56, thighRight: 58).measurements
        XCTAssertEqual(measurements.mean(.thigh) ?? 0, 57, accuracy: 1e-9)
        XCTAssertEqual(measurements.value(.thigh, .left), 56)
        XCTAssertEqual(measurements.value(.thigh, .right), 58)
    }

    /// Only one side measured is still an answer — it is just that side.
    func testASingleSideIsUsedAlone() {
        let measurements = BodyMeasurements([.init(site: .upperArm, side: .left,
                                                   centimetres: 34)])
        XCTAssertEqual(measurements.mean(.upperArm), 34)
    }

    /// Sites are reported in a stable order, whatever order they were measured.
    func testSitesComeBackInAFixedOrder() {
        let jumbled = BodyMeasurements([
            .init(site: .hip, centimetres: 100),
            .init(site: .neck, centimetres: 38),
            .init(site: .waist, centimetres: 88)
        ])
        XCTAssertEqual(jumbled.sites, [.neck, .waist, .hip])
    }

    /// Only sites that earned a `MetricType` become samples; the rest stay scan
    /// data. Nine exhaustive switches is the price of a chart, and twenty
    /// near-identical lines is not worth it.
    func testOnlyPromotedSitesBecomeSamples() {
        let extras = BodyScan(id: UUID(), capturedAt: date(2026, 8, 1), mode: .tape,
                              parserVersion: 1,
                              measurements: BodyMeasurements([
                                  .init(site: .waist, centimetres: 88),
                                  .init(site: .inseam, centimetres: 80),
                                  .init(site: .underbust, centimetres: 90)
                              ]),
                              conditions: ScanConditions(), retainedAssets: [])
        XCTAssertEqual(extras.samples(source: .manual).map(\.type), [.waistCircumference])
    }

    /// The bridge into the maths that already exists and has never had an input.
    func testAScanProducesTheDimensionsTheAssessmentReads() throws {
        let dimensions = try XCTUnwrap(scan().dimensions(heightMetres: 1.80))
        XCTAssertEqual(dimensions.waistCentimetres, 88)
        XCTAssertEqual(dimensions.hipCentimetres, 100)
        XCTAssertEqual(dimensions.source, .lidar)
        XCTAssertEqual(dimensions.waistToHeight, 88 / 180, accuracy: 1e-9)

        // And that it actually drives the assessment, which is the whole point.
        let build = try XCTUnwrap(BuildAssessmentModel.evaluate(
            dimensions: dimensions, weightKg: 82, sex: .male))
        XCTAssertGreaterThan(build.relativeFatMass, 0)
    }

    /// No waist, no assessment — the one measurement RFM cannot do without.
    func testAScanWithNoWaistYieldsNoDimensions() {
        let noWaist = BodyScan(id: UUID(), capturedAt: date(2026, 8, 1), mode: .tape,
                               parserVersion: 1,
                               measurements: BodyMeasurements([.init(site: .hip, centimetres: 100)]),
                               conditions: ScanConditions(), retainedAssets: [])
        XCTAssertNil(noWaist.dimensions(heightMetres: 1.80))
    }

    /// A scan that kept nothing is still good history, but it can never improve.
    func testOnlyAScanWithAssetsCanBeReparsed() {
        XCTAssertTrue(scan().isReparseable)
        let tape = BodyScan(id: UUID(), capturedAt: date(2026, 8, 1), mode: .tape,
                            parserVersion: 1, measurements: .empty,
                            conditions: ScanConditions(), retainedAssets: [])
        XCTAssertFalse(tape.isReparseable, "a tape measurement has nothing to re-derive")
    }

    // MARK: - The two policy matrices

    /// **The invariant.** Keeping what was never collected is a contradiction,
    /// not a preference, and it is normalised away so no screen can show it.
    func testRetainedIsAlwaysASubsetOfCaptured() {
        let impossible = BodyScanPolicy(captured: [.personMask],
                                        retained: [.personMask, .colourFrames])
        XCTAssertEqual(impossible.retained, [.personMask])
    }

    /// Turning off a capture takes its retention with it, rather than leaving a
    /// switch on for something that will never arrive.
    func testDroppingACaptureDropsItsRetention() {
        let policy = BodyScanPolicy(captured: [.personMask, .colourFrames],
                                    retained: [.personMask, .colourFrames])
            .capturing(.colourFrames, false)
        XCTAssertFalse(policy.captured.contains(.colourFrames))
        XCTAssertFalse(policy.retained.contains(.colourFrames))
    }

    /// The separation that is the whole reason for two matrices: measure *using*
    /// the photographs and never write one to disk.
    func testAnAssetCanBeUsedWithoutBeingKept() {
        let policy = BodyScanPolicy(captured: Set(BodyScanAsset.allCases),
                                    retained: [.depthMap])
        XCTAssertTrue(policy.captured.contains(.colourFrames))
        XCTAssertEqual(policy.assetsToWrite(from: Set(BodyScanAsset.allCases)), [.depthMap])
    }

    /// Photographs are the one thing a reader switches **on**, not off.
    func testTheDefaultKeepsEverythingUnidentifiable() {
        XCTAssertTrue(BodyScanPolicy.standard.captured.contains(.colourFrames))
        XCTAssertFalse(BodyScanPolicy.standard.retained.contains(.colourFrames))
        XCTAssertTrue(BodyScanPolicy.standard.retained.contains(.depthMap))
        XCTAssertTrue(BodyScanPolicy.standard.isReparseable)
    }

    /// Keeping nothing is allowed, and the reader is told what it costs.
    func testKeepingNothingMeansNoReparsing() {
        XCTAssertFalse(BodyScanPolicy.numbersOnly.isReparseable)
        XCTAssertTrue(BodyScanPolicy.numbersOnly.canMeasure,
                      "you can still measure — you just cannot re-measure later")
    }

    /// Without the silhouette there is no width to take.
    func testTheSilhouetteIsTheFloorForMeasuringAtAll() {
        let blind = BodyScanPolicy(captured: [.colourFrames], retained: [])
        XCTAssertFalse(blind.canMeasure)
    }

    // MARK: - Comparability

    private func conditions(clothing: ScanConditions.Clothing = .formFitting,
                            distance: Double? = 3.0, height: Double? = 1.0,
                            lux: Double? = 300, hour: Int? = 8) -> ScanConditions {
        ScanConditions(deviceHeightMetres: height, subjectDistanceMetres: distance,
                       ambientLux: lux, clothing: clothing, hourOfDay: hour)
    }

    func testIdenticalSetupsAreComparable() {
        XCTAssertEqual(ScanComparability.compare(conditions(), conditions(),
                                                 modeFirst: .lidarDepth,
                                                 modeSecond: .lidarDepth),
                       .comparable)
    }

    /// **Clothing is the largest term**, and the reviews of every competitor say
    /// so. Different clothes is not a degraded comparison, it is not one.
    func testDifferentClothingBreaksTheComparison() {
        let verdict = ScanComparability.compare(conditions(clothing: .minimal),
                                                conditions(clothing: .looseFitting),
                                                modeFirst: .lidarDepth,
                                                modeSecond: .lidarDepth)
        XCTAssertFalse(verdict.isPlottableTogether)
        XCTAssertTrue(verdict.reasons.contains(.clothingDiffers))
    }

    /// Not knowing is milder than knowing they differed — it is a warning, not a
    /// disqualification, because the two may well have matched.
    func testUnrecordedClothingOnlyDegrades() {
        let verdict = ScanComparability.compare(conditions(clothing: .unknown),
                                                conditions(clothing: .formFitting),
                                                modeFirst: .tape, modeSecond: .tape)
        XCTAssertTrue(verdict.isPlottableTogether)
        XCTAssertTrue(verdict.reasons.contains(.clothingUnknown))
    }

    /// A camera scan and a LiDAR scan do not carry the same kind of error.
    func testDifferentCaptureModesAreNotComparable() {
        let verdict = ScanComparability.compare(conditions(), conditions(),
                                                modeFirst: .lidarDepth,
                                                modeSecond: .cameraSegmentation)
        XCTAssertFalse(verdict.isPlottableTogether)
        XCTAssertTrue(verdict.reasons.contains(.captureModeDiffers))
    }

    func testStandingSomewhereElseBreaksIt() {
        let verdict = ScanComparability.compare(conditions(distance: 2.0),
                                                conditions(distance: 3.5),
                                                modeFirst: .lidarDepth,
                                                modeSecond: .lidarDepth)
        XCTAssertFalse(verdict.isPlottableTogether)
        XCTAssertTrue(verdict.reasons.contains(.distanceDiffers))
    }

    /// Light is judged as a ratio: 5,000 lux against 5,050 is the same room.
    func testLightingIsJudgedProportionally() {
        XCTAssertEqual(ScanComparability.compare(conditions(lux: 5000), conditions(lux: 5050),
                                                 modeFirst: .lidarDepth,
                                                 modeSecond: .lidarDepth),
                       .comparable)
        let dim = ScanComparability.compare(conditions(lux: 50), conditions(lux: 400),
                                            modeFirst: .lidarDepth, modeSecond: .lidarDepth)
        XCTAssertTrue(dim.reasons.contains(.lightingDiffers))
        XCTAssertTrue(dim.isPlottableTogether, "lighting degrades, it does not disqualify")
    }

    /// Morning against evening is a genuinely different abdomen.
    func testTimeOfDayDegradesTheComparison() {
        let verdict = ScanComparability.compare(conditions(hour: 7), conditions(hour: 21),
                                                modeFirst: .lidarDepth,
                                                modeSecond: .lidarDepth)
        XCTAssertTrue(verdict.reasons.contains(.timeOfDayDiffers))
    }

    /// A missing condition cannot be compared, and is not invented.
    func testAbsentConditionsAreNotHeldAgainstTheScan() {
        let bare = ScanConditions(clothing: .formFitting)
        XCTAssertEqual(ScanComparability.compare(bare, bare, modeFirst: .tape,
                                                 modeSecond: .tape),
                       .comparable)
    }

    /// The order of the two makes no difference — this asks whether they match.
    func testComparisonIsSymmetric() {
        let a = conditions(distance: 2.0), b = conditions(distance: 3.5)
        XCTAssertEqual(ScanComparability.compare(a, b, modeFirst: .tape, modeSecond: .tape),
                       ScanComparability.compare(b, a, modeFirst: .tape, modeSecond: .tape))
    }

    // MARK: - The repeatability band

    /// **This is what stops a scanner announcing ten pounds of muscle
    /// overnight.** A change inside the method's own noise is not a change.
    func testAChangeInsideTheNoiseBandIsNotReported() {
        XCTAssertFalse(ScanComparability.isMeaningfulChange(0.6, from: .lidarDepth,
                                                            to: .lidarDepth))
        XCTAssertTrue(ScanComparability.isMeaningfulChange(1.4, from: .lidarDepth,
                                                           to: .lidarDepth))
    }

    /// A comparison is only as repeatable as its shakier half.
    func testTheWiderBandWins() {
        XCTAssertFalse(ScanComparability.isMeaningfulChange(1.5, from: .lidarDepth,
                                                            to: .cameraSegmentation))
        XCTAssertTrue(ScanComparability.isMeaningfulChange(2.5, from: .lidarDepth,
                                                           to: .cameraSegmentation))
    }

    /// Direction never matters to whether a change is real.
    func testTheBandIsSymmetricAboutZero() {
        XCTAssertEqual(ScanComparability.isMeaningfulChange(-2.5, from: .tape, to: .tape),
                       ScanComparability.isMeaningfulChange(2.5, from: .tape, to: .tape))
    }

    // MARK: - Cadence

    func testCadenceStates() {
        let last = date(2026, 7, 1)
        XCTAssertEqual(BodyScanCadence.state(lastScan: nil, now: last,
                                             calendar: calendar), .missing)
        XCTAssertEqual(BodyScanCadence.state(lastScan: last, now: date(2026, 7, 10),
                                             calendar: calendar), .current)
        XCTAssertEqual(BodyScanCadence.state(lastScan: last, now: date(2026, 7, 26),
                                             calendar: calendar), .expiringSoon)
        XCTAssertEqual(BodyScanCadence.state(lastScan: last, now: date(2026, 7, 31),
                                             calendar: calendar), .overdue)
    }

    /// A reminder that appears every day stops being a reminder.
    func testNothingIsSaidWhileTheScanIsCurrent() {
        XCTAssertNil(BodyScanCadence.prompt(lastScan: date(2026, 7, 1),
                                            now: date(2026, 7, 10), calendar: calendar))
        XCTAssertNotNil(BodyScanCadence.prompt(lastScan: nil, now: date(2026, 7, 10),
                                               calendar: calendar))
        XCTAssertNotNil(BodyScanCadence.prompt(lastScan: date(2026, 7, 1),
                                               now: date(2026, 8, 15), calendar: calendar))
    }

    func testDaysUntilDueGoesNegativeWhenOverdue() {
        XCTAssertEqual(BodyScanCadence.daysUntilDue(lastScan: date(2026, 7, 1),
                                                    now: date(2026, 7, 21),
                                                    calendar: calendar), 10)
        XCTAssertEqual(BodyScanCadence.daysUntilDue(lastScan: date(2026, 7, 1),
                                                    now: date(2026, 8, 5),
                                                    calendar: calendar), -5)
    }

    /// A scan is not a fact that expires, so nothing here calls an old
    /// measurement wrong — the overdue copy is about a gap in the trend.
    func testTheOverduePromptDoesNotCallOldMeasurementsWrong() throws {
        let prompt = try XCTUnwrap(BodyScanCadence.prompt(lastScan: date(2026, 7, 1),
                                                          now: date(2026, 8, 5),
                                                          calendar: calendar))
        XCTAssertTrue(prompt.detail.contains("gap"), prompt.detail)
    }
}
