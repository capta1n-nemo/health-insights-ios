import Foundation

/// A joint's position in the scan's own space, metres.
///
/// Not `simd_float3`: InsightKit builds on Linux, and the whole point of this
/// file is that the judgement is testable without a camera. The capture layer
/// converts ARKit's transforms into these.
///
/// Axes as the capture presents them, facing the phone: **x** to the subject's
/// left as seen by the camera, **y** up, **z** toward the camera.
public struct JointPosition: Sendable, Equatable, Codable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// The joints posture is read from.
///
/// A deliberately small subset of ARKit's ninety-odd: these are the ones the
/// published plumb-line assessments actually use, and carrying the rest would
/// mean storing and versioning a skeleton nobody reads.
public enum PostureJoint: String, Sendable, Codable, CaseIterable {
    case head
    case shoulderLeft, shoulderRight
    case hipLeft, hipRight
    case kneeLeft, kneeRight
    case ankleLeft, ankleRight
}

public typealias PostureSkeleton = [PostureJoint: JointPosition]

/// What a standing scan says about alignment.
///
/// ## What this is, and firmly is not
///
/// Fit3D's posture report is its headline differentiator and sells at
/// gym-installation prices; the inputs are joints this app's capture already
/// needs for its pose check, so the marginal cost here is arithmetic.
///
/// **It is an observation, never a diagnosis and never a correction.** The same
/// discipline the rest of the app applies to a lab value applies harder here:
/// a shoulder sitting a centimetre lower than the other is a fact about how
/// somebody stood for ten seconds, and the honest framing is that a *pattern*
/// across scans is worth mentioning to a professional, not that anything needs
/// fixing.
public enum PostureAssessment {

    public enum Finding: Sendable, Equatable, Identifiable, CaseIterable {
        case shoulderTilt
        case hipTilt
        case headTilt
        case headForward
        case kneeAlignment

        public var id: String { String(describing: self) }

        public var displayName: String {
            switch self {
            case .shoulderTilt: return "Shoulder tilt"
            case .hipTilt: return "Hip tilt"
            case .headTilt: return "Head tilt"
            case .headForward: return "Head forward of the shoulders"
            case .kneeAlignment: return "Knee alignment"
            }
        }
    }

    public struct Observation: Sendable, Equatable, Identifiable {
        public let finding: Finding
        /// How far, in centimetres — a height difference, or a forward offset.
        public let magnitudeCentimetres: Double
        /// Which side is higher or further forward, where the finding has one.
        public let side: BodySide?

        public var id: String { finding.id }

        public var sentence: String {
            let amount = String(format: "%.1f cm", magnitudeCentimetres)
            switch finding {
            case .shoulderTilt:
                return "Your \(side == .right ? "right" : "left") shoulder sat \(amount) higher."
            case .hipTilt:
                return "Your \(side == .right ? "right" : "left") hip sat \(amount) higher."
            case .headTilt:
                return "Your head was tilted \(amount) off centre."
            case .headForward:
                return "Your head sat \(amount) forward of your shoulders."
            case .kneeAlignment:
                return "Your knees sat \(amount) off the line between hip and ankle."
            }
        }
    }

    // MARK: - Thresholds
    //
    // All in centimetres, all chosen to sit above what a ten-second stand can
    // produce by itself. Somebody shifting their weight moves a hip by a
    // centimetre without anything being true about them.

    public static let shoulderTiltCentimetres = 1.5
    public static let hipTiltCentimetres = 1.5
    public static let headTiltCentimetres = 2.0
    public static let headForwardCentimetres = 5.0
    public static let kneeDeviationCentimetres = 3.0

    /// Read a skeleton. Findings only; silence is the common and correct case.
    public static func observations(in skeleton: PostureSkeleton) -> [Observation] {
        var out: [Observation] = []

        if let left = skeleton[.shoulderLeft], let right = skeleton[.shoulderRight] {
            let difference = (right.y - left.y) * 100
            if abs(difference) >= shoulderTiltCentimetres {
                out.append(Observation(finding: .shoulderTilt,
                                       magnitudeCentimetres: abs(difference),
                                       side: difference > 0 ? .right : .left))
            }
        }

        if let left = skeleton[.hipLeft], let right = skeleton[.hipRight] {
            let difference = (right.y - left.y) * 100
            if abs(difference) >= hipTiltCentimetres {
                out.append(Observation(finding: .hipTilt,
                                       magnitudeCentimetres: abs(difference),
                                       side: difference > 0 ? .right : .left))
            }
        }

        // Head sideways of the midpoint between the shoulders.
        if let head = skeleton[.head], let left = skeleton[.shoulderLeft],
           let right = skeleton[.shoulderRight] {
            let midX = (left.x + right.x) / 2
            let offset = abs(head.x - midX) * 100
            if offset >= headTiltCentimetres {
                out.append(Observation(finding: .headTilt,
                                       magnitudeCentimetres: offset, side: nil))
            }
            // And forward of them — the side-view finding, and the one most
            // people recognise.
            let midZ = (left.z + right.z) / 2
            let forward = (head.z - midZ) * 100
            if forward >= headForwardCentimetres {
                out.append(Observation(finding: .headForward,
                                       magnitudeCentimetres: forward, side: nil))
            }
        }

        // Knees off the hip-to-ankle line, taken as the worse of the two.
        var worstKnee: (deviation: Double, side: BodySide)?
        for (hip, knee, ankle, side) in [
            (PostureJoint.hipLeft, PostureJoint.kneeLeft, PostureJoint.ankleLeft, BodySide.left),
            (PostureJoint.hipRight, PostureJoint.kneeRight, PostureJoint.ankleRight, BodySide.right)
        ] {
            guard let hip = skeleton[hip], let knee = skeleton[knee],
                  let ankle = skeleton[ankle] else { continue }
            // Where the knee *would* be if hip, knee and ankle were in line,
            // interpolated by height so a bent leg is judged at its own knee.
            let span = hip.y - ankle.y
            guard abs(span) > 0.01 else { continue }
            let t = (knee.y - ankle.y) / span
            let expectedX = ankle.x + (hip.x - ankle.x) * t
            let deviation = abs(knee.x - expectedX) * 100
            if worstKnee == nil || deviation > worstKnee!.deviation {
                worstKnee = (deviation, side)
            }
        }
        if let worstKnee, worstKnee.deviation >= kneeDeviationCentimetres {
            out.append(Observation(finding: .kneeAlignment,
                                   magnitudeCentimetres: worstKnee.deviation,
                                   side: worstKnee.side))
        }

        return out.sorted { $0.magnitudeCentimetres > $1.magnitudeCentimetres }
    }

    /// The caveat that goes under any list of these, every time.
    public static let caveat =
        "Measured from where your joints were during one scan, not a clinical assessment. "
        + "How you happened to stand moves these. If the same thing shows up across "
        + "several scans, it is worth mentioning to a physio or doctor."

    /// What to say when nothing cleared a threshold.
    public static let alignedSentence =
        "Nothing stood out about your alignment in this scan."
}
