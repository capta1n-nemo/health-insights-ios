import XCTest
@testable import InsightKit

/// The guided body-scan capture — everything about it that is not a sensor.
///
/// The capture needs ARKit, a LiDAR sensor and a real body, so nothing here can
/// run on a simulator or in CI. That is exactly why the flow was built as a
/// value type with the sensors on the outside: the availability gate, the
/// consent brief, the setup target, the pose rules, the hold timing, the
/// failure copy and the retention rule are all falsifiable here, and only the
/// readings feeding them are not.
final class BodyScanCaptureFlowTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour))!
    }

    private let proPhone = BodyScanDeviceCapability(
        hasCamera: true, hasSceneDepth: true,
        supportsBodyTracking: true, isSimulator: false)
    private let nonProPhone = BodyScanDeviceCapability(
        hasCamera: true, hasSceneDepth: false,
        supportsBodyTracking: true, isSimulator: false)

    // MARK: - Availability

    func testProPhoneWithPermissionIsReadyForLiDAR() {
        let availability = BodyScanCaptureAvailability.decide(
            capability: proPhone, authorization: .authorized, policy: .standard)
        XCTAssertEqual(availability, .ready(.lidarDepth))
    }

    func testNonProPhoneFallsBackToCameraRatherThanRefusing() {
        let availability = BodyScanCaptureAvailability.decide(
            capability: nonProPhone, authorization: .authorized, policy: .standard)
        XCTAssertEqual(availability, .ready(.cameraSegmentation),
                       "No depth sensor is a less precise scan, not a blocked one.")
    }

    /// The reader's Settings choice changes the *mode*, not just what is kept —
    /// a Pro phone with depth switched off takes a camera scan and says so.
    func testDepthTurnedOffInSettingsDowngradesAProPhoneToACameraScan() {
        let policy = BodyScanPolicy.standard.capturing(.depthMap, false)
        let availability = BodyScanCaptureAvailability.decide(
            capability: proPhone, authorization: .authorized, policy: policy)
        XCTAssertEqual(availability, .ready(.cameraSegmentation))
    }

    func testSilhouetteTurnedOffBlocksTheScanEntirely() {
        let policy = BodyScanPolicy.standard.capturing(.personMask, false)
        let availability = BodyScanCaptureAvailability.decide(
            capability: proPhone, authorization: .authorized, policy: policy)
        XCTAssertEqual(availability, .unavailable(.silhouetteTurnedOff))
    }

    /// Hardware and policy are checked *before* permission, so a phone that
    /// could never run the scan is never asked for camera access.
    func testUnsupportedHardwareIsRefusedWithoutEverPromptingForCamera() {
        let old = BodyScanDeviceCapability(hasCamera: true, hasSceneDepth: false,
                                           supportsBodyTracking: false,
                                           isSimulator: false)
        let availability = BodyScanCaptureAvailability.decide(
            capability: old, authorization: .notDetermined, policy: .standard)
        XCTAssertEqual(availability, .unavailable(.bodyTrackingUnsupported))
        XCTAssertNil(availability.mode)
    }

    func testSimulatorIsBlockedAndSaysSo() {
        let simulator = BodyScanDeviceCapability(hasCamera: true, hasSceneDepth: false,
                                                 supportsBodyTracking: true,
                                                 isSimulator: true)
        let availability = BodyScanCaptureAvailability.decide(
            capability: simulator, authorization: .authorized, policy: .standard)
        XCTAssertEqual(availability.block, .simulator)
    }

    func testEveryBlockOffersARouteThatStillWorks() {
        for block in BodyScanCaptureBlock.allCases {
            XCTAssertFalse(block.title.isEmpty)
            XCTAssertFalse(block.explanation.isEmpty)
            XCTAssertTrue(block.whatNow.lowercased().contains("tape"),
                          "\(block) leaves the reader with nowhere to go.")
        }
    }

    // MARK: - What is said before the prompt

    /// The brief is generated from the policy, so it cannot claim to keep less
    /// than it keeps.
    func testConsentBriefNamesPhotographsWhenThePolicyKeepsThem() {
        let policy = BodyScanPolicy.standard.retaining(.colourFrames, true)
        let brief = BodyScanConsentBrief(policy: policy, mode: .lidarDepth)
        XCTAssertTrue(brief.kept.contains(.colourFrames))
        XCTAssertTrue(brief.whatIsKept.lowercased().contains("photograph"))
    }

    func testConsentBriefSaysNothingIsKeptUnderTheNumbersOnlyPolicy() {
        let brief = BodyScanConsentBrief(policy: .numbersOnly, mode: .lidarDepth)
        XCTAssertTrue(brief.kept.isEmpty)
        XCTAssertTrue(brief.whatIsKept.lowercased().contains("discarded"))
    }

    /// A camera scan must not promise depth on a phone that has the sensor but
    /// is not using it for this capture.
    func testCameraScanBriefDoesNotClaimToUseDepth() {
        let brief = BodyScanConsentBrief(policy: .standard, mode: .cameraSegmentation)
        XCTAssertFalse(brief.used.contains(.depthMap))
        XCTAssertFalse(brief.used.contains(.sceneMesh))
        XCTAssertFalse(brief.whatIsUsed.lowercased().contains("depth"))
    }

    // MARK: - Standing in the same place twice

    func testFirstEverScanAimsAtTheDefaultSetup() {
        let target = ScanSetupTarget.matching([])
        XCTAssertFalse(target.matchesPreviousScan)
        XCTAssertEqual(target.distanceMetres, ScanSetupTarget.defaultDistanceMetres)
    }

    /// The point of the whole type: the second scan is aimed at the first one's
    /// setup, so the two are comparable by construction rather than judged
    /// afterwards.
    func testSecondScanAimsAtTheFirstScansOwnConditions() {
        let first = scan(distance: 2.4, height: 1.15, clothing: .formFitting,
                         at: date(2026, 7, 1))
        let target = ScanSetupTarget.matching([first])
        XCTAssertTrue(target.matchesPreviousScan)
        XCTAssertEqual(target.distanceMetres, 2.4, accuracy: 0.001)
        XCTAssertEqual(target.deviceHeightMetres, 1.15, accuracy: 0.001)
        XCTAssertEqual(target.clothing, .formFitting)
    }

    /// A tape entry has no distance and no camera height, so "match your last
    /// measurement" would mean matching nothing.
    func testATapeEntryIsNeverTheSetupToMatch() {
        let tape = BodyScan(id: UUID(), capturedAt: date(2026, 8, 1), mode: .tape,
                            parserVersion: 1,
                            measurements: BodyMeasurements([.init(site: .waist,
                                                                  centimetres: 88)]),
                            conditions: ScanConditions(clothing: .minimal),
                            retainedAssets: [])
        let older = scan(distance: 2.4, height: 1.15, clothing: .minimal,
                         at: date(2026, 7, 1))
        let target = ScanSetupTarget.matching([tape, older])
        XCTAssertEqual(target.distanceMetres, 2.4, accuracy: 0.001,
                       "The tape entry should have been skipped for the older scan.")
    }

    /// The flow accepts exactly what the comparison accepts. A looser flow
    /// would wave through scans it then refuses to plot together.
    func testThePoseToleranceIsTheComparisonTolerance() {
        let target = ScanSetupTarget.matching([])
        XCTAssertEqual(target.distanceTolerance,
                       ScanComparability.distanceToleranceMetres)
        XCTAssertEqual(target.heightTolerance,
                       ScanComparability.deviceHeightToleranceMetres)
    }

    func testAPoseInsideToleranceProducesAScanThatComparesAsComparable() {
        let previous = scan(distance: 2.0, height: 1.0, clothing: .minimal,
                            at: date(2026, 7, 1))
        let target = ScanSetupTarget.matching([previous])
        // Sitting right on the edge of what the pose check allows.
        let reading = goodReading(distance: target.distanceMetres
                                    + target.distanceTolerance - 0.001,
                                  height: target.deviceHeightMetres
                                    + target.heightTolerance - 0.001)
        XCTAssertTrue(PoseCheck.isAcceptable(reading, target: target))

        let taken = ScanConditions(deviceHeightMetres: reading.deviceHeightMetres,
                                   subjectDistanceMetres: reading.subjectDistanceMetres,
                                   ambientLux: reading.ambientLux,
                                   clothing: .minimal, hourOfDay: 9)
        let verdict = ScanComparability.compare(previous.conditions, taken,
                                                modeFirst: .lidarDepth,
                                                modeSecond: .lidarDepth)
        XCTAssertEqual(verdict, .comparable)
    }

    // MARK: - Pose

    func testAGoodPoseHasNothingToSay() {
        let target = ScanSetupTarget.matching([])
        XCTAssertNil(PoseCheck.instruction(goodReading(), target: target))
    }

    func testOnlyTheMostImportantProblemIsShown() {
        let target = ScanSetupTarget.matching([])
        // Standing far too far back, in the dark, wobbling.
        let reading = CaptureReading(subjectDistanceMetres: 4.0,
                                     deviceHeightMetres: 1.0,
                                     deviceTiltDegrees: 0, ambientLux: 5,
                                     isBodyTracked: true, isFullBodyInFrame: true,
                                     isStill: false)
        XCTAssertEqual(PoseCheck.problems(reading, target: target),
                       [.tooFar, .tooDark, .moving])
        XCTAssertEqual(PoseCheck.instruction(reading, target: target), .tooFar,
                       "One instruction at a time, and distance outranks the rest.")
    }

    /// "Your feet are cut off" about an empty room is nonsense.
    func testFramingIsNotComplainedAboutBeforeAnyoneIsInShot() {
        let target = ScanSetupTarget.matching([])
        let empty = CaptureReading(subjectDistanceMetres: 2.0, deviceHeightMetres: 1.0,
                                   deviceTiltDegrees: 0, ambientLux: 300,
                                   isBodyTracked: false, isFullBodyInFrame: false,
                                   isStill: true)
        XCTAssertEqual(PoseCheck.problems(empty, target: target), [.noBodyFound])
    }

    /// An unknown reading is not a wrong one — a flow that fired an instruction
    /// at every unsettled field would never stop talking.
    func testUnknownFieldsAreNeverProblems() {
        let target = ScanSetupTarget.matching([])
        let sparse = CaptureReading(isBodyTracked: true, isFullBodyInFrame: true,
                                    isStill: true)
        XCTAssertTrue(PoseCheck.problems(sparse, target: target).isEmpty)
    }

    func testEveryPoseProblemSaysWhatToDoAndWhy() {
        for problem in PoseProblem.allCases {
            XCTAssertFalse(problem.instruction.isEmpty)
            XCTAssertFalse(problem.reason.isEmpty)
        }
    }

    // MARK: - Holding

    func testHoldNeedsTheFullDurationOfGoodFrames() {
        let start = date(2026, 8, 7)
        var timer = HoldTimer()
        XCTAssertEqual(timer.update(isAcceptable: true, now: start), 0)
        XCTAssertEqual(timer.update(isAcceptable: true,
                                    now: start.addingTimeInterval(1)), 0.5,
                       accuracy: 0.001)
        XCTAssertTrue(timer.isComplete(
            now: start.addingTimeInterval(HoldTimer.requiredSeconds)))
    }

    /// A hold must not be assembled out of two good seconds either side of a
    /// stumble — those are exactly the frames it exists to exclude.
    func testABadFrameResetsTheHoldRatherThanPausingIt() {
        let start = date(2026, 8, 7)
        var timer = HoldTimer()
        timer.update(isAcceptable: true, now: start)
        timer.update(isAcceptable: true, now: start.addingTimeInterval(1.5))
        timer.update(isAcceptable: false, now: start.addingTimeInterval(1.6))
        timer.update(isAcceptable: true, now: start.addingTimeInterval(1.7))
        XCTAssertFalse(timer.isComplete(now: start.addingTimeInterval(2.1)),
                       "1.5s + 0.4s must not add up to a 2s hold.")
    }

    // MARK: - The flow

    private func readyFlow(mode: BodyScan.CaptureMode = .lidarDepth,
                           policy: BodyScanPolicy = .standard) -> BodyScanCaptureFlow {
        BodyScanCaptureFlow(availability: .ready(mode), policy: policy,
                            target: ScanSetupTarget.matching([]))
    }

    func testAFlowThatNeedsPermissionStartsOnTheExplanationNotTheCamera() {
        let flow = BodyScanCaptureFlow(availability: .needsPermission(.lidarDepth),
                                       policy: .standard,
                                       target: ScanSetupTarget.matching([]))
        guard case .explaining = flow.stage else {
            return XCTFail("Expected the brief first, got \(flow.stage)")
        }
        XCTAssertFalse(flow.stage.needsCamera,
                       "The camera must not be running while the brief is on screen.")
    }

    func testAFlowCannotRaiseThePromptWithoutTheBriefBeingAcknowledged() {
        var flow = readyFlow()   // already authorised, so it starts at set-up
        flow.permissionResolved(.denied)
        guard case .settingUp = flow.stage else {
            return XCTFail("A stray permission result moved an authorised flow.")
        }
    }

    func testDecliningTheSystemPromptEndsInAnExplainedBlock() {
        var flow = BodyScanCaptureFlow(availability: .needsPermission(.lidarDepth),
                                       policy: .standard,
                                       target: ScanSetupTarget.matching([]))
        flow.consentGiven()
        flow.permissionResolved(.denied)
        XCTAssertEqual(flow.stage, .blocked(.permissionDenied))
    }

    func testABlockedFlowIsTerminalAndNeverOpensTheCamera() {
        let flow = BodyScanCaptureFlow(availability: .unavailable(.simulator),
                                       policy: .standard,
                                       target: ScanSetupTarget.matching([]))
        XCTAssertTrue(flow.stage.isTerminal)
        XCTAssertFalse(flow.stage.needsCamera)
        XCTAssertTrue(flow.stations.isEmpty)
    }

    func testALiDARScanAsksForFourStationsAndACameraScanForTwo() {
        XCTAssertEqual(readyFlow(mode: .lidarDepth).stations.count, 4)
        XCTAssertEqual(readyFlow(mode: .cameraSegmentation).stations,
                       [.front, .rightSide])
    }

    func testStationsAreWalkedInOrderAndEndInProcessing() {
        var flow = readyFlow()
        flow.beginPlacing()
        XCTAssertTrue(flow.advanceToNextStation())
        XCTAssertEqual(flow.stage, .holding(.front))
        XCTAssertEqual(flow.stationCountLabel, "1 of 4")

        for _ in flow.stations { flow.stationHeld() }
        XCTAssertEqual(flow.stage, .processing)
        XCTAssertEqual(flow.captured, CaptureStation.allCases)
        XCTAssertEqual(flow.stationProgress, 1)
    }

    /// Three stations of four is not a scan with a bit missing — it is
    /// measurements from angles that no longer agree.
    func testAShortCaptureCannotBeFinished() {
        var flow = readyFlow()
        flow.beginPlacing()
        flow.advanceToNextStation()
        flow.stationHeld()
        flow.stationHeld()
        // Force the stage without holding the rest.
        flow.fail(.trackingLost)
        XCTAssertEqual(flow.stage, .failed(.trackingLost))
        XCTAssertNil(flow.finish(capturedAt: date(2026, 8, 7), parserVersion: 1,
                                 measurements: BodyMeasurements([
                                     .init(site: .waist, centimetres: 88)]),
                                 observed: goodReading(),
                                 availableAssets: Set(BodyScanAsset.allCases),
                                 calendar: calendar))
    }

    /// A capture that produced no numbers fails loudly rather than storing an
    /// empty scan that would read on a chart like any other.
    func testACaptureWithNoMeasurementsFailsRatherThanSavingNothingQuietly() {
        var flow = readyFlow()
        flow.beginPlacing()
        flow.advanceToNextStation()
        for _ in flow.stations { flow.stationHeld() }
        XCTAssertNil(flow.finish(capturedAt: date(2026, 8, 7), parserVersion: 1,
                                 measurements: .empty, observed: goodReading(),
                                 availableAssets: Set(BodyScanAsset.allCases),
                                 calendar: calendar))
        XCTAssertEqual(flow.stage, .failed(.measurementFailed))
    }

    /// The conditions stored are the ones observed, not the ones aimed at.
    /// Storing the intention would make `ScanComparability` compare two plans.
    func testTheFinishedScanRecordsWhatWasObservedNotWhatWasAimedAt() {
        var flow = readyFlow()
        flow.setClothing(.formFitting)
        flow.beginPlacing()
        flow.advanceToNextStation()
        for _ in flow.stations { flow.stationHeld() }

        let observed = goodReading(distance: 2.13, height: 1.07)
        let scan = flow.finish(capturedAt: date(2026, 8, 7, 18), parserVersion: 3,
                               measurements: BodyMeasurements([
                                   .init(site: .waist, centimetres: 88)]),
                               observed: observed,
                               availableAssets: Set(BodyScanAsset.allCases),
                               calendar: calendar)
        let unwrapped = try? XCTUnwrap(scan)
        guard let unwrapped else { return XCTFail("Expected a scan") }
        XCTAssertEqual(unwrapped.conditions.subjectDistanceMetres, 2.13)
        XCTAssertEqual(unwrapped.conditions.deviceHeightMetres, 1.07)
        XCTAssertEqual(unwrapped.conditions.clothing, .formFitting)
        XCTAssertEqual(unwrapped.conditions.hourOfDay, 18)
        XCTAssertEqual(unwrapped.mode, .lidarDepth)
        XCTAssertEqual(unwrapped.parserVersion, 3)
    }

    /// Retention at capture time runs through `BodyScanPolicy` — which had
    /// existed since the scan engine landed with nothing at capture reading it.
    func testWhatIsKeptIsWhatTheReaderChoseInSettings() {
        var flow = readyFlow(policy: .numbersOnly)
        flow.beginPlacing()
        flow.advanceToNextStation()
        for _ in flow.stations { flow.stationHeld() }
        let scan = flow.finish(capturedAt: date(2026, 8, 7), parserVersion: 1,
                               measurements: BodyMeasurements([
                                   .init(site: .waist, centimetres: 88)]),
                               observed: goodReading(),
                               availableAssets: Set(BodyScanAsset.allCases),
                               calendar: calendar)
        XCTAssertEqual(scan?.retainedAssets, [])
        XCTAssertEqual(scan?.isReparseable, false)
    }

    // MARK: - The honesty rules

    /// ⚠️ Standing rule: a circumference from a mesh has no validated accuracy
    /// claim. The only number the app may quote is the method's repeatability,
    /// and it must come from the same place the comparison uses.
    func testTheStatedErrorIsTheComparisonsOwnRepeatabilityBand() {
        for mode in [BodyScan.CaptureMode.lidarDepth, .cameraSegmentation] {
            let flow = readyFlow(mode: mode)
            XCTAssertEqual(flow.statedErrorCentimetres,
                           ScanComparability.repeatabilityBandCentimetres(mode))
            XCTAssertTrue(flow.accuracyCaveat.lowercased().contains("tape"),
                          "\(mode) must say a tape beats it.")
        }
    }

    func testACameraScanNeverClaimsToBeatAnExternalMeasurement() {
        let flow = readyFlow(mode: .cameraSegmentation)
        XCTAssertGreaterThan(flow.statedErrorCentimetres,
                             readyFlow(mode: .lidarDepth).statedErrorCentimetres)
        XCTAssertLessThan(BodyMeasurementProvenance.cameraScan.authority,
                          BodyMeasurementProvenance.externalHealthApp.authority)
    }

    /// A retry button that cannot succeed is a lie with a tap target.
    func testTheUnimplementedMeasurementStepIsNotOfferedARetry() {
        XCTAssertFalse(CaptureFailure.measurementFailed.isRetryable)
        XCTAssertTrue(CaptureFailure.trackingLost.isRetryable)
    }

    func testEveryFailureExplainsItselfAndPointsSomewhere() {
        let failures: [CaptureFailure] = [.trackingLost, .cancelled,
                                          .timedOut(.front), .interrupted,
                                          .sensorUnavailable, .measurementFailed]
        for failure in failures {
            XCTAssertFalse(failure.title.isEmpty)
            XCTAssertFalse(failure.explanation.isEmpty)
            XCTAssertFalse(failure.whatNow.isEmpty)
        }
    }

    // MARK: - Fixtures

    private func goodReading(distance: Double = ScanSetupTarget.defaultDistanceMetres,
                             height: Double = ScanSetupTarget.defaultDeviceHeightMetres)
        -> CaptureReading {
        CaptureReading(subjectDistanceMetres: distance, deviceHeightMetres: height,
                       deviceTiltDegrees: 1, ambientLux: 320,
                       isBodyTracked: true, isFullBodyInFrame: true, isStill: true)
    }

    private func scan(distance: Double, height: Double,
                      clothing: ScanConditions.Clothing, at when: Date) -> BodyScan {
        BodyScan(id: UUID(), capturedAt: when, mode: .lidarDepth, parserVersion: 1,
                 measurements: BodyMeasurements([.init(site: .waist, centimetres: 88)]),
                 conditions: ScanConditions(deviceHeightMetres: height,
                                            subjectDistanceMetres: distance,
                                            ambientLux: 300, clothing: clothing,
                                            hourOfDay: calendar.component(.hour, from: when)),
                 retainedAssets: [.personMask])
    }
}
