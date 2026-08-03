import Foundation

/// A kind of raw data a scan can collect.
///
/// Each one is separately choosable twice over — see `BodyScanPolicy`.
public enum BodyScanAsset: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Per-pixel metric depth from the LiDAR sensor.
    case depthMap
    /// The silhouette: which pixels are the person.
    case personMask
    /// ARKit's 3D joint positions.
    case skeleton
    /// The colour frames themselves.
    case colourFrames
    /// The LiDAR reconstruction of the surface.
    case sceneMesh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .depthMap: return "Depth"
        case .personMask: return "Silhouette"
        case .skeleton: return "Skeleton"
        case .colourFrames: return "Photos"
        case .sceneMesh: return "3D surface"
        }
    }

    /// What it is for, in one line, so a settings row is a decision rather than
    /// a word with a switch next to it.
    public var purpose: String {
        switch self {
        case .depthMap:
            return "Per-pixel distance from the LiDAR sensor. This is what makes a circumference a measurement rather than an estimate."
        case .personMask:
            return "Which pixels are you and which are the room. Needed for every width the scan takes."
        case .skeleton:
            return "Where your joints are. Drives the pose check during capture, and posture and left-right symmetry afterwards."
        case .colourFrames:
            return "The photographs themselves. Not needed for any measurement the app takes today — kept only so future versions can look again."
        case .sceneMesh:
            return "The reconstructed surface of your body, as a 3D shape."
        }
    }

    /// Whether a measurement can be taken at all without it.
    ///
    /// The silhouette is the floor: every width the app derives is a width of
    /// the mask. Everything else refines or enriches.
    public var isRequiredToMeasure: Bool { self == .personMask }

    /// Whether keeping this on disk stores something recognisable as the reader.
    ///
    /// Only the colour frames do. Named rather than implied so the Settings
    /// screen can mark them without a second list to keep in step.
    public var isIdentifiable: Bool { self == .colourFrames }
}

/// What a scan may **use**, and — separately — what it may **keep**.
///
/// ## Two matrices, because they are two different questions
///
/// The reader's requirement, in their words: *"make it configurable in the
/// settings, for both 'what is used' and 'what is saved' … allow them to
/// granularly select what they want to be used, and separately what they want
/// to be saved."*
///
/// They come apart in a way that matters. A scan can **use** the colour frames
/// to find the silhouette and then never write them to disk — the measurement is
/// as good either way, and nothing recognisable survives the capture. Collapsing
/// the two into one switch would force a choice between a worse scan and a
/// photo archive, and neither is the answer.
///
/// The one rule tying them together: **`retained ⊆ captured`.** Keeping what was
/// never collected is not a preference, it is a contradiction, and it is
/// normalised away rather than trapped — a Settings screen that can express an
/// impossible state will eventually be in one.
public struct BodyScanPolicy: Sendable, Equatable, Codable {

    public private(set) var captured: Set<BodyScanAsset>
    public private(set) var retained: Set<BodyScanAsset>

    public init(captured: Set<BodyScanAsset>, retained: Set<BodyScanAsset>) {
        self.captured = captured
        // Normalise on the way in, so no caller can construct the impossible
        // state and no reader can be shown it.
        self.retained = retained.intersection(captured)
    }

    /// Capture everything, keep everything that cannot identify the reader.
    ///
    /// The default is deliberately not "keep everything": re-parsing later needs
    /// depth, mask, skeleton and mesh, and none of those is recognisable as a
    /// person. Photographs add nothing the app measures today, so they are the
    /// one thing a reader has to switch **on** rather than remember to switch
    /// off. That is the only asymmetry in here and it is on purpose.
    public static let standard = BodyScanPolicy(
        captured: Set(BodyScanAsset.allCases),
        retained: Set(BodyScanAsset.allCases.filter { !$0.isIdentifiable }))

    /// Measure and keep nothing but the numbers.
    public static let numbersOnly = BodyScanPolicy(
        captured: Set(BodyScanAsset.allCases), retained: [])

    public func capturing(_ asset: BodyScanAsset, _ on: Bool) -> BodyScanPolicy {
        var captured = self.captured
        if on { captured.insert(asset) } else { captured.remove(asset) }
        // Dropping a capture drops its retention with it — the initialiser's
        // normalisation is what makes that automatic rather than remembered.
        return BodyScanPolicy(captured: captured, retained: retained)
    }

    public func retaining(_ asset: BodyScanAsset, _ on: Bool) -> BodyScanPolicy {
        var retained = self.retained
        if on { retained.insert(asset) } else { retained.remove(asset) }
        return BodyScanPolicy(captured: captured, retained: retained)
    }

    /// Whether retention of this asset is even offerable.
    public func canRetain(_ asset: BodyScanAsset) -> Bool { captured.contains(asset) }

    /// Whether a scan can be taken at all under this policy.
    public var canMeasure: Bool {
        BodyScanAsset.allCases.filter(\.isRequiredToMeasure).allSatisfy(captured.contains)
    }

    /// Whether a scan taken under this policy could ever be re-derived.
    ///
    /// The reader is told this in Settings rather than discovering it years
    /// later, when a better parser arrives and half their history cannot use it.
    public var isReparseable: Bool { !retained.isEmpty }

    /// The assets to write for a completed capture.
    public func assetsToWrite(from available: Set<BodyScanAsset>) -> Set<BodyScanAsset> {
        available.intersection(retained)
    }
}
