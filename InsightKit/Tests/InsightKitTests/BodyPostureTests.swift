import XCTest
@testable import InsightKit

/// Left-against-right, and what a standing scan says about alignment.
///
/// Synthetic skeletons rather than captured ones, for the same reason
/// `ScreenTimeChartGeometry` is tested from synthetic masks: the capture cannot
/// run here, and what needs pinning is the judgement on the other side of it.
/// Each posture test starts from a neutral body, perturbs exactly one joint, and
/// asserts that only the matching finding fires.
final class BodyPostureTests: XCTestCase {

    // MARK: - Symmetry

    private func paired(_ site: BodySite, left: Double, right: Double) -> BodyMeasurements {
        BodyMeasurements([.init(site: site, side: .left, centimetres: left),
                          .init(site: site, side: .right, centimetres: right)])
    }

    /// **Everybody is slightly asymmetric.** A difference inside the method's own
    /// repeatability is not a difference — flagging it would report handedness
    /// as a finding.
    func testADifferenceInsideTheNoiseIsNotReported() {
        let measurements = paired(.upperArm, left: 34.0, right: 34.6)
        XCTAssertTrue(BodySymmetry.findings(in: measurements, mode: .lidarDepth).isEmpty)
    }

    /// The floor comes from `ScanComparability`, so a shakier method needs a
    /// bigger gap — one set of numbers, not two that agree today.
    func testTheFloorFollowsTheCaptureMethod() {
        let measurements = paired(.upperArm, left: 34.0, right: 35.5)
        XCTAssertFalse(BodySymmetry.findings(in: measurements, mode: .lidarDepth).isEmpty,
                       "1.5 cm clears LiDAR's 1.0")
        XCTAssertTrue(BodySymmetry.findings(in: measurements, mode: .cameraSegmentation).isEmpty,
                      "but not the camera's 2.0")
    }

    func testTheLargerSideIsNamedCorrectly() throws {
        let rightBigger = try XCTUnwrap(
            BodySymmetry.findings(in: paired(.thigh, left: 55, right: 58),
                                  mode: .lidarDepth).first)
        XCTAssertEqual(rightBigger.largerSide, .right)
        let leftBigger = try XCTUnwrap(
            BodySymmetry.findings(in: paired(.thigh, left: 58, right: 55),
                                  mode: .lidarDepth).first)
        XCTAssertEqual(leftBigger.largerSide, .left)
    }

    /// An unpaired site has no left and right to compare.
    func testUnpairedSitesAreNeverCompared() {
        let waist = BodyMeasurements([.init(site: .waist, centimetres: 88)])
        XCTAssertTrue(BodySymmetry.findings(in: waist, mode: .tape).isEmpty)
    }

    /// One side measured is not a comparison.
    func testASingleSideYieldsNoFinding() {
        let lonely = BodyMeasurements([.init(site: .calf, side: .left, centimetres: 38)])
        XCTAssertTrue(BodySymmetry.findings(in: lonely, mode: .tape).isEmpty)
    }

    /// Biggest difference first — the reader should not have to scan the list.
    func testFindingsAreOrderedByHowBigTheyAre() {
        let measurements = BodyMeasurements([
            .init(site: .thigh, side: .left, centimetres: 55),
            .init(site: .thigh, side: .right, centimetres: 56.5),
            .init(site: .upperArm, side: .left, centimetres: 34),
            .init(site: .upperArm, side: .right, centimetres: 38)
        ])
        XCTAssertEqual(BodySymmetry.findings(in: measurements, mode: .lidarDepth)
                        .map(\.site), [.upperArm, .thigh])
    }

    /// The second floor: past the noise, but still inside what handedness
    /// explains, is not worth a word.
    func testOrdinaryHandednessClearsTheNoiseButNotTheNotableFloor() {
        // 1.2 cm on a 34 cm arm is 3.5% — above LiDAR's 1.0 cm noise floor,
        // below the 5% that ordinary asymmetry explains.
        let measurements = paired(.upperArm, left: 34.0, right: 35.2)
        XCTAssertFalse(BodySymmetry.findings(in: measurements, mode: .lidarDepth).isEmpty)
        XCTAssertTrue(BodySymmetry.notableFindings(in: measurements, mode: .lidarDepth).isEmpty)
    }

    func testAClearlyNotableDifferenceSurvivesBothFloors() {
        let measurements = paired(.upperArm, left: 32.0, right: 38.0)
        XCTAssertFalse(BodySymmetry.notableFindings(in: measurements, mode: .lidarDepth).isEmpty)
    }

    // MARK: - Posture

    /// A body standing straight, in metres.
    private func neutral() -> PostureSkeleton {
        [.head: JointPosition(x: 0, y: 1.70, z: 0),
         .shoulderLeft: JointPosition(x: -0.20, y: 1.45, z: 0),
         .shoulderRight: JointPosition(x: 0.20, y: 1.45, z: 0),
         .hipLeft: JointPosition(x: -0.12, y: 0.95, z: 0),
         .hipRight: JointPosition(x: 0.12, y: 0.95, z: 0),
         .kneeLeft: JointPosition(x: -0.12, y: 0.50, z: 0),
         .kneeRight: JointPosition(x: 0.12, y: 0.50, z: 0),
         .ankleLeft: JointPosition(x: -0.12, y: 0.08, z: 0),
         .ankleRight: JointPosition(x: 0.12, y: 0.08, z: 0)]
    }

    /// Standing straight says nothing, which is a real answer.
    func testANeutralBodyProducesNoObservations() {
        XCTAssertTrue(PostureAssessment.observations(in: neutral()).isEmpty)
    }

    func testAShoulderTiltIsFoundAndSided() throws {
        var skeleton = neutral()
        skeleton[.shoulderRight] = JointPosition(x: 0.20, y: 1.47, z: 0)   // 2 cm up
        let observations = PostureAssessment.observations(in: skeleton)
        let finding = try XCTUnwrap(observations.first { $0.finding == .shoulderTilt })
        XCTAssertEqual(finding.magnitudeCentimetres, 2.0, accuracy: 0.001)
        XCTAssertEqual(finding.side, .right)
        XCTAssertEqual(observations.count, 1, "perturbing one joint fires one finding")
    }

    func testAHipTiltIsFoundAndSided() throws {
        var skeleton = neutral()
        skeleton[.hipLeft] = JointPosition(x: -0.12, y: 0.97, z: 0)
        let finding = try XCTUnwrap(PostureAssessment.observations(in: skeleton)
                                    .first { $0.finding == .hipTilt })
        XCTAssertEqual(finding.side, .left)
    }

    /// The side-view finding, and the one most readers recognise by name.
    func testForwardHeadIsFound() throws {
        var skeleton = neutral()
        skeleton[.head] = JointPosition(x: 0, y: 1.70, z: 0.08)   // 8 cm forward
        let finding = try XCTUnwrap(PostureAssessment.observations(in: skeleton)
                                    .first { $0.finding == .headForward })
        XCTAssertEqual(finding.magnitudeCentimetres, 8.0, accuracy: 0.001)
    }

    /// Backward is not the same finding — a head behind the shoulders is not
    /// forward-head posture, and reporting it as such would be wrong.
    func testAHeadBehindTheShouldersIsNotForwardHead() {
        var skeleton = neutral()
        skeleton[.head] = JointPosition(x: 0, y: 1.70, z: -0.08)
        XCTAssertTrue(PostureAssessment.observations(in: skeleton)
                        .allSatisfy { $0.finding != .headForward })
    }

    func testHeadTiltIsFound() throws {
        var skeleton = neutral()
        skeleton[.head] = JointPosition(x: 0.04, y: 1.70, z: 0)   // 4 cm sideways
        let finding = try XCTUnwrap(PostureAssessment.observations(in: skeleton)
                                    .first { $0.finding == .headTilt })
        XCTAssertEqual(finding.magnitudeCentimetres, 4.0, accuracy: 0.001)
    }

    /// The knee is judged against the hip-to-ankle line at its own height, so a
    /// leg that is simply shorter is not flagged.
    func testAKneeOffTheHipAnkleLineIsFound() throws {
        var skeleton = neutral()
        skeleton[.kneeLeft] = JointPosition(x: -0.16, y: 0.50, z: 0)   // 4 cm outward
        let finding = try XCTUnwrap(PostureAssessment.observations(in: skeleton)
                                    .first { $0.finding == .kneeAlignment })
        XCTAssertEqual(finding.magnitudeCentimetres, 4.0, accuracy: 0.01)
        XCTAssertEqual(finding.side, .left)
    }

    /// Ten seconds of standing moves a hip a centimetre. The thresholds sit
    /// above that on purpose.
    func testSmallShiftsDoNotFire() {
        var skeleton = neutral()
        skeleton[.shoulderRight] = JointPosition(x: 0.20, y: 1.46, z: 0)   // 1 cm
        skeleton[.hipRight] = JointPosition(x: 0.12, y: 0.96, z: 0)        // 1 cm
        XCTAssertTrue(PostureAssessment.observations(in: skeleton).isEmpty)
    }

    /// A partial skeleton is read for what it has rather than refused.
    func testMissingJointsAreSkippedNotFatal() {
        var skeleton = neutral()
        skeleton[.kneeLeft] = nil
        skeleton[.ankleLeft] = nil
        skeleton[.shoulderRight] = JointPosition(x: 0.20, y: 1.48, z: 0)
        XCTAssertEqual(PostureAssessment.observations(in: skeleton).map(\.finding),
                       [.shoulderTilt])
    }

    func testAnEmptySkeletonSaysNothing() {
        XCTAssertTrue(PostureAssessment.observations(in: [:]).isEmpty)
    }

    /// Biggest first, so the list leads with what stood out.
    func testObservationsAreOrderedByMagnitude() {
        var skeleton = neutral()
        skeleton[.shoulderRight] = JointPosition(x: 0.20, y: 1.47, z: 0)   // 2 cm
        skeleton[.head] = JointPosition(x: 0, y: 1.70, z: 0.09)            // 9 cm
        XCTAssertEqual(PostureAssessment.observations(in: skeleton).first?.finding,
                       .headForward)
    }

    /// The framing is fixed and load-bearing: an observation, never a diagnosis
    /// and never a correction.
    func testTheCaveatRefusesToDiagnose() {
        XCTAssertTrue(PostureAssessment.caveat.contains("not a clinical assessment"))
        XCTAssertTrue(PostureAssessment.caveat.lowercased().contains("physio")
                      || PostureAssessment.caveat.lowercased().contains("doctor"))
    }
}
