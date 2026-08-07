import Foundation

/// The guided body-scan capture, as a state machine with no sensors in it.
///
/// ## Why this is here and not in the app target
///
/// **The guided flow is the hard part, not the mesh.** Every consumer body
/// scanner is reviewed the same way — *inconsistent* — and `ScanComparability`
/// already says why: the numbers move with clothing, posture, camera height and
/// lighting. That diagnosis is worth nothing unless something *makes the reader
/// stand in the same place twice*, and that is what this type is.
///
/// The capture itself needs ARKit, a LiDAR sensor and a real body in front of
/// the phone, none of which exists in a simulator or on Linux. So everything
/// that is not the sensor lives here, in a target whose tests run on every
/// machine: which mode the phone can offer, what the reader is told before any
/// permission dialog appears, what the setup has to match, what is wrong with
/// the current pose, when a hold counts, what each failure says, and what a
/// finished capture is allowed to keep.
///
/// The state machine is `BodyScanCaptureFlow` at the foot of this file;
/// everything above it is the vocabulary that machine is written in.

// MARK: - What the phone can do

/// The device facts the flow needs, gathered once by the app target.
///
/// A plain struct rather than a call into ARKit, so every decision below is
/// exercisable from a test with no device attached.
public struct BodyScanDeviceCapability: Sendable, Equatable {
    /// A rear camera exists and is usable.
    public let hasCamera: Bool
    /// The LiDAR sensor reports per-pixel metric depth.
    ///
    /// **Pro and Pro Max only.** This is the whole of the "Pro-models-only"
    /// caveat: without it a scan is silhouette widths scaled by the skeleton,
    /// which is a real scan with twice the error, not a refusal.
    public let hasSceneDepth: Bool
    /// ARKit will track a body skeleton on this chip.
    public let supportsBodyTracking: Bool
    /// Running in a simulator, where the camera is a still image and the
    /// skeleton is nothing at all.
    public let isSimulator: Bool

    public init(hasCamera: Bool, hasSceneDepth: Bool,
                supportsBodyTracking: Bool, isSimulator: Bool) {
        self.hasCamera = hasCamera
        self.hasSceneDepth = hasSceneDepth
        self.supportsBodyTracking = supportsBodyTracking
        self.isSimulator = isSimulator
    }

    /// Nothing works. The value a non-iOS build and a test both start from.
    public static let none = BodyScanDeviceCapability(
        hasCamera: false, hasSceneDepth: false,
        supportsBodyTracking: false, isSimulator: false)
}

/// The camera permission, as the flow needs to reason about it.
///
/// Mirrors `AVAuthorizationStatus` rather than importing it, because importing
/// AVFoundation here would make this file unbuildable on Linux and take the
/// tests with it.
public enum CameraAuthorization: String, Sendable, Equatable, CaseIterable {
    /// Never asked. **The only state in which a prompt may be raised**, and the
    /// state the explanation screen exists for.
    case notDetermined
    case authorized
    /// The reader said no. Recoverable only in Settings.
    case denied
    /// Screen Time or an MDM profile said no. Not the reader's to change.
    case restricted
}

/// Why a scan cannot be offered, in the reader's terms.
///
/// A refusal is a screen with three sentences on it, not a greyed-out button:
/// **an input that vanishes is indistinguishable from one that was never
/// built**, which is the confusion `InputKind` exists to end. Every case
/// therefore carries what is wrong, why, and what to do instead — and "what to
/// do instead" is always the tape, which needs no sensor and beats every
/// optical method anyway (`BodyMeasurementProvenance.tape`).
public enum BodyScanCaptureBlock: String, Sendable, Equatable, CaseIterable {
    case noCamera
    case bodyTrackingUnsupported
    case simulator
    case permissionDenied
    case permissionRestricted
    /// Settings ▸ Body scans has the silhouette switched off, and every width
    /// the app derives is a width of the silhouette (`BodyScanAsset.personMask`
    /// is the one asset `isRequiredToMeasure`).
    case silhouetteTurnedOff

    public var title: String {
        switch self {
        case .noCamera: return "No camera available"
        case .bodyTrackingUnsupported: return "This phone can't run a body scan"
        case .simulator: return "Not available in the simulator"
        case .permissionDenied: return "Camera access is off"
        case .permissionRestricted: return "Camera access is restricted"
        case .silhouetteTurnedOff: return "Scanning is switched off"
        }
    }

    public var explanation: String {
        switch self {
        case .noCamera:
            return "A scan needs the rear camera, and this device doesn't have one available."
        case .bodyTrackingUnsupported:
            return "A scan needs ARKit's body tracking, which this phone's chip doesn't support."
        case .simulator:
            return "A body scan needs a real camera and a real body in front of it. The simulator has neither, so this screen can show you the steps but can't take a scan."
        case .permissionDenied:
            return "You turned the camera off for this app, so it can't see you to scan."
        case .permissionRestricted:
            return "Something else on this phone — Screen Time, or a profile your organisation installed — is blocking camera access. It isn't a setting this app can change."
        case .silhouetteTurnedOff:
            return "Settings ▸ Body scans has the silhouette turned off. Every width a scan takes is a width of the silhouette, so with it off there's nothing to measure."
        }
    }

    /// What the reader can do about it, right now.
    public var whatNow: String {
        switch self {
        case .permissionDenied:
            return "Settings ▸ Health Insights ▸ Camera turns it back on. Or skip the scan entirely — a tape measure is more accurate than any scan, and the app ranks it higher."
        case .permissionRestricted, .noCamera, .bodyTrackingUnsupported, .simulator:
            return "Enter your measurements with a tape instead. That's not a downgrade: a tape is the most accurate circumference this app will ever hold, and it outranks both scan modes."
        case .silhouetteTurnedOff:
            return "Turn the silhouette back on in Settings ▸ Body scans, or use a tape measure."
        }
    }

    /// Whether raising the system permission prompt could clear this.
    ///
    /// Only `.permissionDenied` is *about* permission and cannot be cleared by
    /// asking again — iOS shows the dialog once. Nothing here is promptable,
    /// which is the point: the flow prompts from `.notDetermined`, and by the
    /// time a block exists the prompting moment has passed.
    public var isClearedBySettings: Bool {
        self == .permissionDenied || self == .permissionRestricted
            || self == .silhouetteTurnedOff
    }
}

/// Whether a scan can be offered, and in which mode.
public enum BodyScanCaptureAvailability: Sendable, Equatable {
    /// Ready to start, in this mode.
    case ready(BodyScan.CaptureMode)
    /// Would be ready, but the camera has never been asked for. The
    /// explanation screen comes first — see `BodyScanConsentBrief`.
    case needsPermission(BodyScan.CaptureMode)
    case unavailable(BodyScanCaptureBlock)

    /// The mode a scan would run in, where there is one.
    public var mode: BodyScan.CaptureMode? {
        switch self {
        case let .ready(mode), let .needsPermission(mode): return mode
        case .unavailable: return nil
        }
    }

    public var block: BodyScanCaptureBlock? {
        if case let .unavailable(block) = self { return block }
        return nil
    }

    /// Decide, in one place, from the three things that can each veto a scan:
    /// the hardware, the permission, and the reader's own retention policy.
    ///
    /// Order matters and is deliberate. Hardware is checked before permission
    /// because prompting for a camera on a phone that cannot run the scan
    /// anyway is asking for something and then not using it — the single
    /// rudest thing a permission flow can do. Policy is checked before
    /// permission for the same reason.
    public static func decide(capability: BodyScanDeviceCapability,
                              authorization: CameraAuthorization,
                              policy: BodyScanPolicy) -> BodyScanCaptureAvailability {
        if capability.isSimulator { return .unavailable(.simulator) }
        guard capability.hasCamera else { return .unavailable(.noCamera) }
        guard capability.supportsBodyTracking else {
            return .unavailable(.bodyTrackingUnsupported)
        }
        guard policy.canMeasure else { return .unavailable(.silhouetteTurnedOff) }

        // The mode is a *policy* decision as much as a hardware one: a Pro
        // phone whose owner switched depth off in Settings takes a camera scan,
        // and `BodyScan.mode` records which so a chart mixing the two can say
        // so. This is exactly the case `CaptureMode`'s doc comment describes.
        let mode: BodyScan.CaptureMode =
            (capability.hasSceneDepth && policy.captured.contains(.depthMap))
                ? .lidarDepth : .cameraSegmentation

        switch authorization {
        case .authorized: return .ready(mode)
        case .notDetermined: return .needsPermission(mode)
        case .denied: return .unavailable(.permissionDenied)
        case .restricted: return .unavailable(.permissionRestricted)
        }
    }
}

// MARK: - What the reader is told before the prompt

/// What a scan will use and what it will keep, said **before** iOS asks.
///
/// The standing rule, carried over from the location work: *camera and LiDAR
/// are new permission surfaces; explain before prompting.* A system dialog is
/// eleven words chosen by Apple's template and gives the reader no way to find
/// out what "uses the camera" means here — whether a photograph of them is
/// about to be written to disk, and whether they can decline just that part.
///
/// This is generated from the reader's own `BodyScanPolicy` rather than being
/// a paragraph typed into a view, so it cannot claim to keep less than it
/// keeps. If a later build adds an asset, the brief gains a line for free; a
/// hand-written string would have gone stale silently, which is the whole
/// reason `InputKind` and `DataDomain` exist.
public struct BodyScanConsentBrief: Sendable, Equatable {
    public let mode: BodyScan.CaptureMode
    /// What the capture collects, in the order `BodyScanAsset` declares.
    public let used: [BodyScanAsset]
    /// What survives the capture.
    public let kept: [BodyScanAsset]

    public init(policy: BodyScanPolicy, mode: BodyScan.CaptureMode) {
        self.mode = mode
        // A camera scan never touches depth even on a phone that has it, so
        // the brief must not promise otherwise.
        let usable = BodyScanAsset.allCases.filter { asset in
            guard policy.captured.contains(asset) else { return false }
            if mode != .lidarDepth, asset == .depthMap || asset == .sceneMesh {
                return false
            }
            return true
        }
        self.used = usable
        self.kept = BodyScanAsset.allCases.filter {
            usable.contains($0) && policy.retained.contains($0)
        }
    }

    public var title: String { "Before the camera opens" }

    /// Why it needs the camera at all — one sentence, in the reader's terms.
    public var why: String {
        switch mode {
        case .lidarDepth:
            return "The scan uses the camera and the LiDAR sensor to measure how far away each part of you is, and turns that into circumferences."
        case .cameraSegmentation:
            return "This phone has no depth sensor, so the scan works from your outline in the camera image, scaled by where your joints are. It is less precise than a LiDAR scan and the app records which kind each scan was."
        case .tape:
            // Not reachable — a tape entry never opens a camera. Stated rather
            // than crashed, because an unreachable branch that traps is a crash
            // waiting for a refactor.
            return "A tape measurement needs no camera."
        }
    }

    public var whatIsUsed: String {
        guard !used.isEmpty else { return "Nothing — the scan has nothing to work with." }
        return used.map(\.displayName).formattedList()
    }

    /// What is written to disk afterwards — the sentence the system dialog
    /// cannot say and the one the reader actually wants.
    public var whatIsKept: String {
        guard !kept.isEmpty else {
            return "Nothing. The measurements are saved; every raw frame is discarded the moment the scan finishes."
        }
        let names = kept.map(\.displayName).formattedList()
        if kept.contains(where: \.isIdentifiable) {
            return "\(names) — and photographs are among them, so this scan will leave pictures of you on this phone. You turned that on in Settings ▸ Body scans and can turn it off there."
        }
        return "\(names). None of it is recognisable as you, and it is what lets a later version of the app re-measure this scan instead of asking you to take it again."
    }

    /// The closing line before the button that raises the system prompt.
    public var beforeYouTap: String {
        "Nothing is uploaded. Tapping below asks iOS for camera access — you can say no, and the tape-measure route still works."
    }
}

private extension Array where Element == String {
    /// "a, b and c" — an Oxford-comma-free list, because these are read aloud
    /// in a sentence rather than parsed.
    func formattedList() -> String {
        switch count {
        case 0: return ""
        case 1: return self[0]
        default: return dropLast().joined(separator: ", ") + " and " + self[count - 1]
        }
    }
}

// MARK: - Standing in the same place twice

/// The setup this scan is aiming at.
///
/// **This is the differentiator, and it is the whole reason `ScanConditions` is
/// stored.** Every scanner tells the reader to stand "about two metres back".
/// Two metres one month and two-and-a-half the next is a different
/// pixels-per-centimetre, and `ScanComparability` will correctly refuse to
/// compare them — which is honest but useless. The fix is to aim the reader at
/// *their previous setup* rather than at a nominal one, so the two scans are
/// comparable by construction instead of being judged afterwards.
///
/// The tolerances are `ScanComparability`'s own, unchanged, because a flow that
/// accepted a looser setup than the comparison accepts would wave through scans
/// it then refuses to plot together.
public struct ScanSetupTarget: Sendable, Equatable {
    public let distanceMetres: Double
    public let deviceHeightMetres: Double
    /// Pre-selected, not enforced — the reader may genuinely be dressed
    /// differently, and lying about it is worse than recording the difference.
    public let clothing: ScanConditions.Clothing
    /// True when these came from a real previous scan, so the flow can say
    /// "the same spot as last time" instead of inventing a claim.
    public let matchesPreviousScan: Bool

    public var distanceTolerance: Double { ScanComparability.distanceToleranceMetres }
    public var heightTolerance: Double { ScanComparability.deviceHeightToleranceMetres }

    /// Two metres: far enough that a whole adult fits in a portrait frame with
    /// room at the feet, near enough that LiDAR is still dense. It is a
    /// starting point for the first scan and is never used again once one
    /// exists.
    public static let defaultDistanceMetres = 2.0
    /// A metre up — a table, a shelf, a chair-back. Roughly mid-body, which is
    /// the height that foreshortens the least at both ends.
    public static let defaultDeviceHeightMetres = 1.0

    public init(distanceMetres: Double, deviceHeightMetres: Double,
                clothing: ScanConditions.Clothing, matchesPreviousScan: Bool) {
        self.distanceMetres = distanceMetres
        self.deviceHeightMetres = deviceHeightMetres
        self.clothing = clothing
        self.matchesPreviousScan = matchesPreviousScan
    }

    /// Aim at the last scan the app can honestly reproduce.
    ///
    /// A tape entry is skipped: it has no distance and no camera height, so
    /// "match your last measurement" would mean matching nothing. So is a scan
    /// that recorded neither — an imported one, or one from a build before the
    /// conditions were captured.
    public static func matching(_ previousScans: [BodyScan]) -> ScanSetupTarget {
        let reproducible = previousScans
            .filter { $0.mode != .tape }
            .sorted { $0.capturedAt > $1.capturedAt }
            .first { $0.conditions.subjectDistanceMetres != nil
                  || $0.conditions.deviceHeightMetres != nil }

        guard let previous = reproducible else {
            return ScanSetupTarget(distanceMetres: defaultDistanceMetres,
                                   deviceHeightMetres: defaultDeviceHeightMetres,
                                   clothing: .minimal, matchesPreviousScan: false)
        }
        return ScanSetupTarget(
            distanceMetres: previous.conditions.subjectDistanceMetres ?? defaultDistanceMetres,
            deviceHeightMetres: previous.conditions.deviceHeightMetres ?? defaultDeviceHeightMetres,
            clothing: previous.conditions.clothing == .unknown
                ? .minimal : previous.conditions.clothing,
            matchesPreviousScan: true)
    }

    /// The one line at the top of the placement screen.
    public var placementInstruction: String {
        let distance = String(format: "%.1f m", distanceMetres)
        let height = String(format: "%.0f cm", deviceHeightMetres * 100)
        guard matchesPreviousScan else {
            return "Stand about \(distance) from the phone, with the phone propped up around \(height) off the floor. Whatever you pick, the app will aim you at the same spot next time."
        }
        return "Same as last time: \(distance) back, phone \(height) off the floor. Matching your last setup is what makes the two scans comparable — a different distance changes the numbers more than your body does."
    }
}

// MARK: - The stations

/// One position the reader holds while the phone records.
///
/// Quarter turns rather than a continuous spin: a spin has no moment the app
/// can call "now", so it cannot tell the reader they moved too soon, and it
/// cannot recover a single bad view without redoing the lot.
public enum CaptureStation: String, Sendable, Equatable, CaseIterable, Codable {
    case front
    case rightSide
    case back
    case leftSide

    public var displayName: String {
        switch self {
        case .front: return "Facing the phone"
        case .rightSide: return "Right shoulder to the phone"
        case .back: return "Back to the phone"
        case .leftSide: return "Left shoulder to the phone"
        }
    }

    public var instruction: String {
        switch self {
        case .front:
            return "Face the phone. Arms slightly away from your sides, feet about hip-width apart."
        case .rightSide:
            return "Turn a quarter to your left, so your right shoulder points at the phone. Keep your arms where they are."
        case .back:
            return "Another quarter turn. Back to the phone now."
        case .leftSide:
            return "Last quarter turn — left shoulder to the phone."
        }
    }

    /// Which stations a mode asks for.
    ///
    /// A camera scan takes two, a depth scan takes four, and that is not
    /// arbitrary: with no depth, a circumference is fitted from a width and a
    /// depth read off two silhouettes, so front-and-side is the minimum that
    /// says anything at all. Depth measures the surface directly and gains from
    /// seeing round the back, where a silhouette cannot help. Asking a
    /// camera-only phone for four turns would cost the reader two more holds
    /// for information the method cannot use.
    public static func stations(for mode: BodyScan.CaptureMode) -> [CaptureStation] {
        switch mode {
        case .lidarDepth: return allCases
        case .cameraSegmentation: return [.front, .rightSide]
        case .tape: return []
        }
    }
}

// MARK: - What is wrong right now

/// One live reading from the sensors, as the flow needs it.
///
/// Every field is optional because every field can genuinely be unknown for a
/// frame or two — tracking drops, the light meter has not settled — and a flow
/// that treated "not yet known" as "wrong" would fire an instruction at the
/// reader for something that was about to resolve itself.
public struct CaptureReading: Sendable, Equatable {
    public let subjectDistanceMetres: Double?
    public let deviceHeightMetres: Double?
    /// How far off vertical the phone is, degrees. A phone leaning back on a
    /// sofa cushion looks up at the ceiling and foreshortens everything.
    public let deviceTiltDegrees: Double?
    public let ambientLux: Double?
    /// ARKit has a body skeleton this frame.
    public let isBodyTracked: Bool
    /// Head and both feet are inside the frame.
    public let isFullBodyInFrame: Bool
    /// Neither the phone nor the reader moved appreciably this frame.
    public let isStill: Bool

    public init(subjectDistanceMetres: Double? = nil, deviceHeightMetres: Double? = nil,
                deviceTiltDegrees: Double? = nil, ambientLux: Double? = nil,
                isBodyTracked: Bool = false, isFullBodyInFrame: Bool = false,
                isStill: Bool = false) {
        self.subjectDistanceMetres = subjectDistanceMetres
        self.deviceHeightMetres = deviceHeightMetres
        self.deviceTiltDegrees = deviceTiltDegrees
        self.ambientLux = ambientLux
        self.isBodyTracked = isBodyTracked
        self.isFullBodyInFrame = isFullBodyInFrame
        self.isStill = isStill
    }
}

/// What is stopping the capture, most urgent first.
///
/// Declaration order **is** the priority order — `PoseCheck` returns the first
/// one as the instruction to show. One instruction at a time is not a
/// simplification: a reader standing two metres away, squinting, cannot read
/// six lines, and the six would in any case mostly be consequences of the
/// first. Fix the framing and "no body found" goes with it.
public enum PoseProblem: String, Sendable, Equatable, CaseIterable {
    case noBodyFound
    case tooFar
    case tooClose
    case notFullyInFrame
    case phoneTooLow
    case phoneTooHigh
    case phoneNotLevel
    case tooDark
    case moving

    /// What to do about it — imperative, second person, one action.
    public var instruction: String {
        switch self {
        case .noBodyFound: return "Step into view of the phone"
        case .tooFar: return "Come a little closer"
        case .tooClose: return "Take a step back"
        case .notFullyInFrame: return "Move back until your head and feet both fit"
        case .phoneTooLow: return "Raise the phone a little"
        case .phoneTooHigh: return "Lower the phone a little"
        case .phoneNotLevel: return "Stand the phone upright — it's leaning"
        case .tooDark: return "Turn a light on"
        case .moving: return "Hold still"
        }
    }

    /// Why it matters, for the reader who wants to know rather than obey.
    public var reason: String {
        switch self {
        case .noBodyFound:
            return "The phone can't see anyone, so there is nothing to measure."
        case .tooFar, .tooClose:
            return "Standing a different distance than last time changes the scale everything is measured against — it is the second-largest reason two scans disagree."
        case .notFullyInFrame:
            return "A measurement needs your whole height in the frame to scale from."
        case .phoneTooLow, .phoneTooHigh:
            return "A phone at a different height looks at you from a different angle, which squashes whatever is furthest from the middle of the frame."
        case .phoneNotLevel:
            return "A leaning phone tilts the whole scene, and every height the scan measures from is tilted with it."
        case .tooDark:
            return "In poor light the edge of your outline lands in the wrong place, and every width is a width of that outline."
        case .moving:
            return "A frame taken mid-movement blurs the outline."
        }
    }
}

/// Judging the live reading against the setup the scan is aiming at.
public enum PoseCheck {

    /// Below this, edge detection on the silhouette starts to wander. 50 lux is
    /// a dim room; a lit room is several hundred. There is deliberately no
    /// upper bound — a bright room is not a problem, and the *ratio* between
    /// two scans is what `ScanComparability` judges afterwards.
    public static let minimumLux = 50.0
    /// Degrees off vertical before the tilt matters. Ten is about the most a
    /// phone leans against something and still looks upright.
    public static let tiltToleranceDegrees = 10.0

    /// Everything wrong with this frame, in priority order.
    ///
    /// Distance and height are judged against `ScanComparability`'s own
    /// tolerances via the target, so a pose this accepts produces a scan that
    /// comparison will accept. An unknown field is never a problem: see
    /// `CaptureReading`.
    public static func problems(_ reading: CaptureReading,
                                target: ScanSetupTarget) -> [PoseProblem] {
        var found: [PoseProblem] = []

        if !reading.isBodyTracked { found.append(.noBodyFound) }

        if let distance = reading.subjectDistanceMetres {
            let delta = distance - target.distanceMetres
            if delta > target.distanceTolerance { found.append(.tooFar) }
            if delta < -target.distanceTolerance { found.append(.tooClose) }
        }
        // Only worth saying once the body is tracked — "your feet are cut off"
        // about an empty room is nonsense.
        if reading.isBodyTracked && !reading.isFullBodyInFrame {
            found.append(.notFullyInFrame)
        }
        if let height = reading.deviceHeightMetres {
            let delta = height - target.deviceHeightMetres
            if delta < -target.heightTolerance { found.append(.phoneTooLow) }
            if delta > target.heightTolerance { found.append(.phoneTooHigh) }
        }
        if let tilt = reading.deviceTiltDegrees, abs(tilt) > tiltToleranceDegrees {
            found.append(.phoneNotLevel)
        }
        if let lux = reading.ambientLux, lux < minimumLux { found.append(.tooDark) }
        if !reading.isStill { found.append(.moving) }

        return PoseProblem.allCases.filter(found.contains)
    }

    /// The one thing to say, or nil when the pose is good.
    public static func instruction(_ reading: CaptureReading,
                                   target: ScanSetupTarget) -> PoseProblem? {
        problems(reading, target: target).first
    }

    public static func isAcceptable(_ reading: CaptureReading,
                                    target: ScanSetupTarget) -> Bool {
        problems(reading, target: target).isEmpty
    }
}

// MARK: - Holding a station

/// How long a good pose has been held, and whether that is enough.
///
/// Separated from `PoseCheck` because the two answer different questions and
/// only one of them needs a clock. **A single good frame is not a hold**: the
/// pose has to survive long enough for the sensors to average, and the reader
/// has to be given a countdown they can act on rather than a shutter that fires
/// while they are still turning.
public struct HoldTimer: Sendable, Equatable {
    /// Two seconds. Long enough that a frame caught mid-turn cannot satisfy it,
    /// short enough that four of them is under a minute of standing still.
    public static let requiredSeconds = 2.0

    private var startedAt: Date?

    public init() {}

    /// Feed a judged frame. Returns how far through the hold the reader is,
    /// 0 to 1.
    ///
    /// A bad frame resets to zero rather than pausing. Pausing would let a hold
    /// be assembled out of two separate seconds either side of a stumble, which
    /// is exactly the frame set the hold exists to exclude.
    @discardableResult
    public mutating func update(isAcceptable: Bool, now: Date) -> Double {
        guard isAcceptable else {
            startedAt = nil
            return 0
        }
        guard let startedAt else {
            self.startedAt = now
            return 0
        }
        let elapsed = now.timeIntervalSince(startedAt)
        return min(max(elapsed / Self.requiredSeconds, 0), 1)
    }

    public func progress(now: Date) -> Double {
        guard let startedAt else { return 0 }
        return min(max(now.timeIntervalSince(startedAt) / Self.requiredSeconds, 0), 1)
    }

    public func isComplete(now: Date) -> Bool { progress(now: now) >= 1 }

    public mutating func reset() { startedAt = nil }
}

// MARK: - Failing

/// Everything a capture can fail with, and what each one says.
///
/// **No failure keeps a partial scan.** Three stations out of four is not a
/// scan with a bit missing, it is a set of measurements taken from angles that
/// no longer agree — and saving it would put a number on the reader's chart
/// that nothing downstream could tell apart from a good one. `BodyScan` has no
/// "partial" flag on purpose.
public enum CaptureFailure: Sendable, Equatable {
    /// ARKit lost the world or the body and did not get it back.
    case trackingLost
    /// The reader backed out.
    case cancelled
    /// A station never got a clean hold inside the time allowed.
    case timedOut(CaptureStation)
    /// A phone call, a notification tap, the app going to the background.
    case interrupted
    /// The sensor stopped mid-capture.
    case sensorUnavailable
    /// Frames were captured but no measurement could be derived from them.
    ///
    /// **This is the honest state of the depth-to-circumference step in this
    /// build** — see `BodyScanMeasuring` in the app target. The flow reaches
    /// here and says so rather than inventing circumferences, which is the
    /// standing rule: a modelled figure is never dressed as a measured one, and
    /// a figure with no method behind it is not modelled either.
    case measurementFailed

    public var title: String {
        switch self {
        case .trackingLost: return "Lost track of you"
        case .cancelled: return "Scan cancelled"
        case .timedOut: return "Couldn't get a clean hold"
        case .interrupted: return "Scan interrupted"
        case .sensorUnavailable: return "The camera stopped"
        case .measurementFailed: return "Couldn't measure that scan"
        }
    }

    public var explanation: String {
        switch self {
        case .trackingLost:
            return "The phone stopped being able to tell where you were. It usually means the light changed, or there wasn't enough in the room for it to hold on to."
        case .cancelled:
            return "Nothing was saved."
        case let .timedOut(station):
            return "\(station.displayName.lowercased()) never held steady for long enough. Nothing from this scan was saved."
        case .interrupted:
            return "Something took over the screen part-way through. A scan has to run start to finish, so this one was discarded."
        case .sensorUnavailable:
            return "The camera became unavailable part-way through — usually another app taking it."
        case .measurementFailed:
            return "The capture worked, but this version of the app can't yet turn depth frames into circumferences. Nothing was recorded, because a measurement it can't take is not a measurement it should guess at."
        }
    }

    /// What the reader does next. Every one of them ends somewhere real.
    public var whatNow: String {
        switch self {
        case .trackingLost, .sensorUnavailable:
            return "Try again in a brighter room with a bit more furniture in shot. If it keeps happening, a tape measure needs no sensors at all."
        case .cancelled:
            return "Start again whenever you like, or enter your measurements with a tape."
        case .timedOut:
            return "Prop the phone against something solid and try again — the countdown restarts whenever you move, so a wobbling phone can hold it off indefinitely."
        case .interrupted:
            return "Turn on Do Not Disturb and try again."
        case .measurementFailed:
            return "Use a tape measure for now. A tape is more accurate than either scan mode anyway, and the app ranks it above both."
        }
    }

    /// Whether offering "try again" makes sense.
    ///
    /// `.measurementFailed` is the one that does not: retrying runs the same
    /// unimplemented step and fails identically, and a retry button that cannot
    /// succeed is a lie with a tap target.
    public var isRetryable: Bool {
        self != .measurementFailed
    }
}

// MARK: - The flow itself

/// The guided capture, stage by stage.
///
/// Held as a value so a view model can own one and a test can drive one, and
/// mutated only through the named transitions below — the stage is
/// `private(set)` precisely so no view can put the flow somewhere the sensors
/// are not.
public struct BodyScanCaptureFlow: Sendable, Equatable {

    public enum Stage: Sendable, Equatable {
        /// What the scan does, what it keeps, before any system dialog.
        case explaining(BodyScanConsentBrief)
        /// The system prompt is up.
        case awaitingPermission
        /// Clothing, and anything else the reader chooses about the setup.
        case settingUp
        /// Live, getting the phone and the reader into position.
        case placing
        /// Live, holding one station.
        case holding(CaptureStation)
        /// Every station captured; deriving measurements.
        case processing
        case finished(BodyScan)
        case failed(CaptureFailure)
        case blocked(BodyScanCaptureBlock)

        /// Whether the camera has to be running for this stage.
        ///
        /// Read by the view so the AR session starts and stops with the stage
        /// rather than with a `.onAppear` somebody has to remember to pair.
        public var needsCamera: Bool {
            switch self {
            case .placing, .holding: return true
            case .explaining, .awaitingPermission, .settingUp, .processing,
                 .finished, .failed, .blocked:
                return false
            }
        }

        public var isTerminal: Bool {
            switch self {
            case .finished, .failed, .blocked: return true
            case .explaining, .awaitingPermission, .settingUp, .placing,
                 .holding, .processing:
                return false
            }
        }
    }

    public private(set) var stage: Stage
    public let mode: BodyScan.CaptureMode
    public let target: ScanSetupTarget
    public let policy: BodyScanPolicy
    /// The stations this mode asks for, in order.
    public let stations: [CaptureStation]
    /// Stations already held. Order-preserving and duplicate-free.
    public private(set) var captured: [CaptureStation] = []
    /// What the reader says they are wearing. Starts at the target's value —
    /// the clothing they wore last time — because the commonest true answer is
    /// "the same as before" and a picker that starts on the right answer is the
    /// difference between a recorded condition and `.unknown`.
    public private(set) var clothing: ScanConditions.Clothing

    /// Start a flow, or refuse to.
    ///
    /// The availability decision is taken here rather than by the caller so
    /// there is no way to construct a flow that runs on a phone which cannot
    /// run it — `blocked` is a stage, so the refusal is a screen with an
    /// explanation on it rather than a nil the view has to invent copy for.
    public init(availability: BodyScanCaptureAvailability,
                policy: BodyScanPolicy,
                target: ScanSetupTarget) {
        self.policy = policy
        self.target = target
        self.clothing = target.clothing

        switch availability {
        case let .ready(mode):
            self.mode = mode
            self.stations = CaptureStation.stations(for: mode)
            self.stage = .settingUp
        case let .needsPermission(mode):
            self.mode = mode
            self.stations = CaptureStation.stations(for: mode)
            self.stage = .explaining(BodyScanConsentBrief(policy: policy, mode: mode))
        case let .unavailable(block):
            // A blocked flow still needs a mode to be a value; the stations are
            // empty and nothing reads the mode before `stage` is inspected.
            self.mode = .cameraSegmentation
            self.stations = []
            self.stage = .blocked(block)
        }
    }

    // MARK: Transitions

    /// The reader has read the brief and tapped through. **The only place a
    /// system permission prompt may be raised from.**
    public mutating func consentGiven() {
        guard case .explaining = stage else { return }
        stage = .awaitingPermission
    }

    /// iOS answered.
    public mutating func permissionResolved(_ authorization: CameraAuthorization) {
        guard case .awaitingPermission = stage else { return }
        switch authorization {
        case .authorized: stage = .settingUp
        case .denied: stage = .blocked(.permissionDenied)
        case .restricted: stage = .blocked(.permissionRestricted)
        // iOS does not return here after a prompt; treat it as a decline
        // rather than looping the reader back through the brief they just
        // agreed to.
        case .notDetermined: stage = .blocked(.permissionDenied)
        }
    }

    public mutating func setClothing(_ value: ScanConditions.Clothing) {
        clothing = value
    }

    /// Setup done — open the camera and start guiding.
    public mutating func beginPlacing() {
        guard case .settingUp = stage else { return }
        stage = .placing
    }

    /// The pose is good and steady; start the first, or next, station.
    ///
    /// Returns false when there is nothing left to capture, which is the
    /// caller's cue to `finishCapturing`.
    @discardableResult
    public mutating func advanceToNextStation() -> Bool {
        guard let next = stations.first(where: { !captured.contains($0) }) else {
            return false
        }
        stage = .holding(next)
        return true
    }

    /// The current station held for long enough.
    public mutating func stationHeld() {
        guard case let .holding(station) = stage else { return }
        if !captured.contains(station) { captured.append(station) }
        if !advanceToNextStation() { stage = .processing }
    }

    /// Something went wrong. Terminal, and it keeps nothing.
    public mutating func fail(_ failure: CaptureFailure) {
        stage = .failed(failure)
    }

    /// Turn a completed capture into a stored scan.
    ///
    /// Three things are enforced here rather than at the call site:
    ///
    /// 1. **Every station must have been held.** A short capture is a failure,
    ///    not a scan with a caveat.
    /// 2. **Retention runs through `BodyScanPolicy`**, so what is written is
    ///    what the reader chose in Settings — the policy has existed since the
    ///    scan engine landed with nothing at capture time reading it.
    /// 3. **The conditions are recorded from what was actually observed**, not
    ///    from the target that was aimed at. Storing the intention rather than
    ///    the measurement would make `ScanComparability` compare two plans.
    public mutating func finish(id: UUID = UUID(), capturedAt: Date,
                                parserVersion: Int,
                                measurements: BodyMeasurements,
                                observed: CaptureReading,
                                availableAssets: Set<BodyScanAsset>,
                                calendar: Calendar = .current) -> BodyScan? {
        guard case .processing = stage else { return nil }
        guard Set(captured) == Set(stations), !stations.isEmpty else {
            stage = .failed(.trackingLost)
            return nil
        }
        guard !measurements.values.isEmpty else {
            stage = .failed(.measurementFailed)
            return nil
        }

        let scan = BodyScan(
            id: id, capturedAt: capturedAt, mode: mode,
            parserVersion: parserVersion, measurements: measurements,
            conditions: ScanConditions(
                deviceHeightMetres: observed.deviceHeightMetres,
                subjectDistanceMetres: observed.subjectDistanceMetres,
                ambientLux: observed.ambientLux,
                clothing: clothing,
                hourOfDay: calendar.component(.hour, from: capturedAt)),
            retainedAssets: policy.assetsToWrite(from: availableAssets))
        stage = .finished(scan)
        return scan
    }

    // MARK: Reading the flow

    /// How far through the stations, 0 to 1. Nil where there are none to do.
    public var stationProgress: Double? {
        guard !stations.isEmpty else { return nil }
        return Double(captured.count) / Double(stations.count)
    }

    /// "2 of 4" for the header.
    public var stationCountLabel: String? {
        guard !stations.isEmpty else { return nil }
        let current = min(captured.count + 1, stations.count)
        return "\(current) of \(stations.count)"
    }

    /// The error the finished scan carries, stated wherever its numbers are.
    ///
    /// ⚠️ **There is no validated accuracy claim behind a scanned
    /// circumference**, and this is the sentence that says so. It is the
    /// method's *repeatability* — the band inside which a difference is not a
    /// difference — which is the only figure this app can honestly quote, and
    /// `ScanComparability` owns it so the flow and the comparison cannot
    /// disagree.
    public var statedErrorCentimetres: Double {
        ScanComparability.repeatabilityBandCentimetres(mode)
    }

    public var accuracyCaveat: String {
        let band = String(format: "±%.0f cm", statedErrorCentimetres)
        switch mode {
        case .lidarDepth:
            return "A scanned circumference is an ellipse fitted to depth at one height, not a tape around you. Treat it as \(band): a change smaller than that is the method, not your body. A tape measurement always wins over this one and is never overwritten by it."
        case .cameraSegmentation:
            return "With no depth sensor this is your outline, scaled — the weakest of the three methods the app holds. Treat it as \(band), and note that an entry from Apple Health outranks it, because a silhouette is a guess about a shape. A tape beats everything."
        case .tape:
            return "Entered by hand, and the most accurate figure this app holds."
        }
    }
}
