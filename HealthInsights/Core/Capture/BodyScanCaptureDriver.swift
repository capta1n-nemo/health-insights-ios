import Foundation
import AVFoundation
import InsightKit
#if canImport(ARKit)
import ARKit
#endif

/// The sensor half of the guided body scan.
///
/// ## Why there is a protocol here at all
///
/// **A body scan cannot be exercised anywhere except a real phone**, and only a
/// Pro one for the depth half. No simulator has a camera that sees a body, no CI
/// runner has a LiDAR sensor, and no test can stand two metres back and turn
/// round. If the flow talked to ARKit directly, then *nothing* about the scan
/// would be checkable — not the pose rules, not the failure copy, not what the
/// reader is told before the permission dialog.
///
/// So the split is deliberate: `BodyScanCaptureFlow` in InsightKit holds every
/// decision and is fully tested on any machine, and this protocol is the narrow
/// seam where the unfalsifiable part lives. Everything below the protocol is
/// **device-only and unverified** — it compiles, and that is the whole of what
/// this session can claim about it.
@MainActor
protocol BodyScanCaptureDriver: AnyObject {
    /// What this phone can do. Read once, before anything is offered.
    var capability: BodyScanDeviceCapability { get }
    /// The camera permission as it stands, without prompting.
    var authorization: CameraAuthorization { get }

    /// Raise the system prompt. **Only ever called after the reader has read
    /// `BodyScanConsentBrief` and tapped through it** — the flow enforces that
    /// by making `.awaitingPermission` reachable from `.explaining` alone.
    func requestCameraAccess() async -> CameraAuthorization

    /// Open the camera for a scan in this mode.
    func start(mode: BodyScan.CaptureMode)
    /// Close it. Idempotent, because a view can be torn down twice.
    func stop()

    /// The most recent judged frame. `nil` until the session produces one.
    var latestReading: CaptureReading? { get }
    /// Set when the session itself fails — tracking lost, camera taken by
    /// another app — so the flow can end honestly rather than waiting forever.
    var sessionFailure: CaptureFailure? { get }

    /// Record whatever this station needs. Called once per station, on the
    /// frame that completed the hold.
    func captureStation(_ station: CaptureStation)

    /// Which raw assets the completed capture actually has to offer, so
    /// `BodyScanPolicy` decides what of it survives.
    var availableAssets: Set<BodyScanAsset> { get }

    /// Turn the captured stations into circumferences.
    ///
    /// ⚠️ **Returns nil in this build, and that is the honest answer** — see
    /// `BodyScanMeasuring`. The flow turns a nil into
    /// `CaptureFailure.measurementFailed`, which says so on screen and offers
    /// the tape instead.
    func measure() async -> BodyMeasurements?
}

/// The depth-frames-to-circumferences step. **Declared, not implemented.**
///
/// This is the one piece of the body scanner that is genuinely missing, and it
/// is named here rather than left as a gap so that nobody has to rediscover
/// which half is done. What exists: the guided capture (this file and
/// `BodyScanCaptureFlow`), the comparability rules (`ScanComparability`), the
/// retention policy (`BodyScanPolicy`), the reconciliation against a tape or
/// Apple Health (`BodyMeasurementReconciliation`), the mesh renderer
/// (`BodyMeshBuilder`) and the tape entry sheet. What does not: fitting an
/// ellipse to depth at a height station and calling the perimeter a waist.
///
/// It is deliberately not stubbed with a plausible number. A circumference with
/// no method behind it would flow straight into `BuildAssessmentModel`, the
/// Body Composition dial and the export, and nothing downstream could tell it
/// apart from a real one. **A measurement this app cannot take is not one it
/// should guess at** — the reader's standing instruction is the honest version,
/// always.
///
/// When it is built it must also state its own error rather than inheriting
/// `ScanComparability`'s placeholder: there is no validated accuracy claim for a
/// circumference off a mesh, so the number quoted has to be repeatability
/// measured on this reader, against their own tape.
protocol BodyScanMeasuring: Sendable {
    func measurements(from stations: [CaptureStation]) async -> BodyMeasurements?
}

// MARK: - Reading the permission without asking for it

enum CameraPermission {
    /// The current status, translated into the flow's vocabulary.
    static var current: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Raise the prompt and translate the answer.
    ///
    /// iOS shows this dialog **once, ever**. That is the entire reason
    /// `BodyScanConsentBrief` exists: eleven words of Apple's template is not
    /// enough for the reader to know whether a photograph of them is about to
    /// be written to disk, and there is no second chance to explain.
    static func request() async -> CameraAuthorization {
        guard current == .notDetermined else { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}

// MARK: - The ARKit driver

#if canImport(ARKit)

/// The real thing: ARKit body tracking, with the phone propped up.
///
/// ⚠️ **Nothing in this class has been run.** It compiles against the iOS SDK
/// and its geometry is written from ARKit's documented frames of reference, but
/// a body scan needs a device with a LiDAR sensor and a person standing in
/// front of it, and this session had neither. The three things only the phone
/// can falsify:
///
/// 1. **Whether the derived readings are right** — device height off the floor,
///    subject distance, tilt and framing are all computed here from the camera
///    transform and the body anchor, and a sign error in any of them would show
///    up as the flow calmly telling the reader to do the opposite of the right
///    thing.
/// 2. **Whether a two-second hold is achievable** while standing two metres
///    from a phone you cannot read. It may need to be longer, or the tolerances
///    looser; both are single named constants for that reason.
/// 3. **Whether `ARBodyTrackingConfiguration` and scene depth can run together**
///    at all on the target device, and what the frame rate does when they do.
@MainActor
final class ARBodyScanCaptureDriver: BodyScanCaptureDriver {

    private let session = ARSession()
    private let reader = ARFrameReader()

    private(set) var latestReading: CaptureReading?
    private(set) var sessionFailure: CaptureFailure?
    private(set) var availableAssets: Set<BodyScanAsset> = []
    private var capturedStations: [CaptureStation] = []
    private var runningMode: BodyScan.CaptureMode?

    /// Exposed so the preview view can show the same session the readings come
    /// from. Two sessions would fight over the camera.
    var previewSession: ARSession { session }

    /// One place, so the row in the tape sheet and the flow behind it cannot
    /// disagree about what this phone can do.
    var capability: BodyScanDeviceCapability { BodyScanCapture.currentCapability }

    var authorization: CameraAuthorization { CameraPermission.current }

    func requestCameraAccess() async -> CameraAuthorization {
        await CameraPermission.request()
    }

    func start(mode: BodyScan.CaptureMode) {
        guard ARBodyTrackingConfiguration.isSupported else {
            sessionFailure = .sensorUnavailable
            return
        }
        sessionFailure = nil
        latestReading = nil
        capturedStations = []
        runningMode = mode

        let configuration = ARBodyTrackingConfiguration()
        // Gravity-aligned so "how far off vertical is the phone" and "how high
        // above the floor" both mean something. Without it the world's Y axis
        // is wherever the phone happened to be pointing when the session
        // started, and every height below is nonsense.
        configuration.worldAlignment = .gravity

        var assets: Set<BodyScanAsset> = [.personMask, .skeleton, .colourFrames]
        if mode == .lidarDepth,
           ARBodyTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            assets.insert(.depthMap)
        }
        availableAssets = assets

        reader.reset()
        reader.onReading = { [weak self] reading in
            Task { @MainActor in self?.latestReading = reading }
        }
        reader.onFailure = { [weak self] failure in
            Task { @MainActor in self?.sessionFailure = failure }
        }
        session.delegate = reader
        // Main queue, so the reader's own frame-to-frame state is serialised
        // by the run loop rather than by a lock.
        session.delegateQueue = .main
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        session.delegate = nil
        reader.onReading = nil
        reader.onFailure = nil
        runningMode = nil
    }

    /// Record the station.
    ///
    /// **Nothing is written to disk.** The depth and colour buffers are not
    /// retained, because the only thing that would consume them is the
    /// measurement step, and that step does not exist yet — so keeping them
    /// would mean writing frames of the reader to storage for no purpose, which
    /// is the opposite of what `BodyScanPolicy` is for. When
    /// `BodyScanMeasuring` lands, this is where the retained assets are written
    /// under `policy.assetsToWrite(from: availableAssets)`.
    func captureStation(_ station: CaptureStation) {
        guard !capturedStations.contains(station) else { return }
        capturedStations.append(station)
    }

    /// See `BodyScanMeasuring`. Nil, deliberately and visibly.
    func measure() async -> BodyMeasurements? { nil }
}

/// Turns ARKit frames into `CaptureReading`s, off the flow's back.
///
/// Deliberately not `@MainActor`: `ARSessionDelegate` is a plain delegate, and
/// the values it hands on are scalars in a `Sendable` struct rather than the
/// frame itself. `ARFrame` must not escape this class — holding one starves the
/// capture pipeline of buffers.
private final class ARFrameReader: NSObject, ARSessionDelegate, @unchecked Sendable {

    /// How far the body root may move between frames and still count as still,
    /// metres. About the width of a breath.
    static let stillnessToleranceMetres = 0.02

    var onReading: (@Sendable (CaptureReading) -> Void)?
    var onFailure: (@Sendable (CaptureFailure) -> Void)?

    /// Frame-to-frame state. Only ever touched on the session's delegate queue,
    /// which the driver pins to main — hence `@unchecked`.
    private var previousRoot: SIMD3<Float>?

    func reset() { previousRoot = nil }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onReading?(reading(from: frame))
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onFailure?(.sensorUnavailable)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onFailure?(.interrupted)
    }

    private func reading(from frame: ARFrame) -> CaptureReading {
        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                          cameraTransform.columns.3.y,
                                          cameraTransform.columns.3.z)

        // How far off vertical the phone is. Column 1 of the camera transform
        // is its up axis; the angle between that and world up is the lean.
        let up = SIMD3<Float>(cameraTransform.columns.1.x,
                              cameraTransform.columns.1.y,
                              cameraTransform.columns.1.z)
        let tilt = Double(acos(min(max(simd_dot(simd_normalize(up),
                                                SIMD3<Float>(0, 1, 0)), -1), 1)))
            * 180 / .pi

        // ARKit reports ambient intensity in lumens on a scale where 1000 is a
        // neutrally-lit room. It is not lux and does not pretend to be, but it
        // is the only light figure available and is used consistently on both
        // sides of a comparison — which is what `ScanComparability` needs, since
        // it judges a *ratio* rather than an absolute.
        let lux = frame.lightEstimate.map { Double($0.ambientIntensity) }

        guard let body = frame.anchors.compactMap({ $0 as? ARBodyAnchor }).first else {
            previousRoot = nil
            return CaptureReading(deviceHeightMetres: nil, deviceTiltDegrees: tilt,
                                  ambientLux: lux, isBodyTracked: false,
                                  isFullBodyInFrame: false, isStill: false)
        }

        let root = SIMD3<Float>(body.transform.columns.3.x,
                                body.transform.columns.3.y,
                                body.transform.columns.3.z)

        // Distance on the floor plane, not through the air: a phone on a high
        // shelf is not further away from the reader in the sense that matters
        // for scale, and mixing the two would make the height and the distance
        // checks fight each other.
        let planar = SIMD2<Float>(root.x - cameraPosition.x, root.z - cameraPosition.z)
        let distance = Double(simd_length(planar))

        // Height above the floor, taken from the reader's own feet rather than
        // from the world origin — ARKit's origin is wherever the phone was when
        // the session started, which for a propped phone is the shelf, not the
        // floor.
        let floorY = footY(of: body) ?? root.y
        let deviceHeight = Double(cameraPosition.y - floorY)

        let inFrame = isWholeBodyInFrame(body, frame: frame)

        let moved = previousRoot.map { simd_distance($0, root) } ?? .greatestFiniteMagnitude
        previousRoot = root
        let isStill = Double(moved) <= Self.stillnessToleranceMetres

        return CaptureReading(subjectDistanceMetres: distance,
                              deviceHeightMetres: deviceHeight,
                              deviceTiltDegrees: tilt, ambientLux: lux,
                              isBodyTracked: true, isFullBodyInFrame: inFrame,
                              isStill: isStill)
    }

    /// World-space Y of the lower of the two feet.
    private func footY(of body: ARBodyAnchor) -> Float? {
        let names: [ARSkeleton.JointName] = [.leftFoot, .rightFoot]
        let feet = names.compactMap { name -> Float? in
            guard let local = body.skeleton.modelTransform(for: name) else { return nil }
            let world = body.transform * local
            return world.columns.3.y
        }
        return feet.min()
    }

    /// Head and both feet inside the image.
    ///
    /// A measurement needs the reader's whole height in shot to scale from, and
    /// the commonest way a first scan fails is feet cropped off the bottom.
    private func isWholeBodyInFrame(_ body: ARBodyAnchor, frame: ARFrame) -> Bool {
        let names: [ARSkeleton.JointName] = [.head, .leftFoot, .rightFoot]
        let size = frame.camera.imageResolution
        for name in names {
            guard let local = body.skeleton.modelTransform(for: name) else { return false }
            let world = body.transform * local
            let point = SIMD3<Float>(world.columns.3.x, world.columns.3.y,
                                     world.columns.3.z)
            // Projected into the *image*, not a view: `viewportSize` is the
            // camera's own resolution, so the inset below is a fraction of the
            // frame rather than of whatever the phone happens to be showing.
            let projected = frame.camera.projectPoint(point, orientation: .portrait,
                                                      viewportSize: size)
            // A small inset rather than the exact edge: a joint one pixel
            // inside the frame is a joint about to leave it.
            let inset = 0.04
            if projected.x < size.width * inset || projected.x > size.width * (1 - inset)
                || projected.y < size.height * inset
                || projected.y > size.height * (1 - inset) {
                return false
            }
        }
        return true
    }
}

#endif

// MARK: - The driver a machine with no sensors gets

/// Used wherever ARKit is unavailable — and on a simulator, where ARKit exists
/// but sees nothing.
///
/// It is a real driver rather than an optional, so every screen below it has one
/// code path. It reports the block honestly and the flow turns that into a
/// screen that says why, which is the rule: **an input that vanishes is
/// indistinguishable from one that was never built.**
@MainActor
final class UnavailableBodyScanCaptureDriver: BodyScanCaptureDriver {
    let capability: BodyScanDeviceCapability
    var authorization: CameraAuthorization { CameraPermission.current }
    private(set) var latestReading: CaptureReading?
    private(set) var sessionFailure: CaptureFailure?
    let availableAssets: Set<BodyScanAsset> = []

    init(capability: BodyScanDeviceCapability = BodyScanDeviceCapability(
        hasCamera: false, hasSceneDepth: false,
        supportsBodyTracking: false, isSimulator: false)) {
        self.capability = capability
    }

    func requestCameraAccess() async -> CameraAuthorization { .denied }
    func start(mode: BodyScan.CaptureMode) { sessionFailure = .sensorUnavailable }
    func stop() {}
    func captureStation(_ station: CaptureStation) {}
    func measure() async -> BodyMeasurements? { nil }
}

/// The driver this build actually uses.
@MainActor
enum BodyScanCapture {

    /// What this phone can do, without starting a session or prompting for
    /// anything.
    ///
    /// Cheap enough for a row in a form to ask on every redraw, which is the
    /// point: the scan row is offered on every phone and says which of the
    /// reasons applies, rather than vanishing on the ones that cannot run it.
    static var currentCapability: BodyScanDeviceCapability {
        #if canImport(ARKit) && !targetEnvironment(simulator)
        return BodyScanDeviceCapability(
            hasCamera: true,
            hasSceneDepth: ARWorldTrackingConfiguration
                .supportsFrameSemantics(.sceneDepth),
            supportsBodyTracking: ARBodyTrackingConfiguration.isSupported,
            isSimulator: false)
        #elseif canImport(ARKit)
        return BodyScanDeviceCapability(hasCamera: false, hasSceneDepth: false,
                                        supportsBodyTracking: false,
                                        isSimulator: true)
        #else
        return .none
        #endif
    }

    static func makeDriver() -> any BodyScanCaptureDriver {
        #if canImport(ARKit) && !targetEnvironment(simulator)
        return ARBodyScanCaptureDriver()
        #elseif canImport(ARKit)
        // A simulator has ARKit and no camera. Reporting the capability
        // honestly is what makes `BodyScanCaptureAvailability` produce the
        // `.simulator` block, which the guided screen explains rather than
        // hiding behind a disabled button.
        return UnavailableBodyScanCaptureDriver(
            capability: BodyScanDeviceCapability(hasCamera: false,
                                                 hasSceneDepth: false,
                                                 supportsBodyTracking: false,
                                                 isSimulator: true))
        #else
        return UnavailableBodyScanCaptureDriver()
        #endif
    }
}
