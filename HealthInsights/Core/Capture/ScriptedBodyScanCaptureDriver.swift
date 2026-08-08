import Foundation
import InsightKit

/// A scripted sensor, so the simulator can walk the capture screens.
///
/// ## Why this exists
///
/// The guided flow shipped with every decision in InsightKit and the sensors
/// behind `BodyScanCaptureDriver` — and the session that built it could verify
/// neither the screens nor the copy, because the simulator honestly reports
/// itself as `.simulator` and the flow (correctly) refuses to run. So every
/// stage past the refusal screen had never been *seen*: the consent brief, the
/// setup form, the live instructions, the hold countdown, and every failure
/// ending. This repo has shipped two invisible cards on exactly that kind of
/// "compiles, therefore renders" reasoning.
///
/// This driver feeds the flow a scripted timeline of `CaptureReading`s instead
/// of ARKit frames, so a simulator session can drive the real state machine
/// through the real screens and read the real copy.
///
/// ## What it can never do
///
/// **It cannot produce a saved scan.** `measure()` returns nil — the same
/// honest answer the real driver gives while the depth-to-circumference step
/// (`BodyScanMeasuring`) is unbuilt — so every script ends at a terminal
/// failure screen and nothing reaches `saveBodyScan`. A scripted capture that
/// minted circumferences would be the modelled-dressed-as-measured failure
/// with a debug flag on it; when `BodyScanMeasuring` lands, this driver must
/// *still* return nil, because a number it produced would carry a real
/// `MetricSource` while measuring nothing.
///
/// ## What it does not verify
///
/// The scripted readings bypass `ARFrameReader` entirely, so nothing here says
/// anything about the ARKit geometry — device height, distance, tilt, framing —
/// nor about whether a two-second hold is achievable by a human, nor whether
/// body tracking and scene depth co-exist on a real device. Those remain the
/// Pro-phone-only claims named in `ARBodyScanCaptureDriver`.
///
/// ## Enabling it
///
/// DEBUG builds only, and only when launched with the argument
/// `-BodyScanScriptedCapture`, optionally with `-BodyScanScript <name>`:
///
/// ```
/// xcrun simctl launch <udid> <bundle> -BodyScanScriptedCapture \
///     -BodyScanScript camera
/// ```
///
/// A normal launch — every launch the reader ever performs — never passes the
/// argument, so the release path is untouched and the debug path is inert.
@MainActor
enum ScriptedBodyScanCapture {

    /// The scripted driver the launch arguments asked for, or nil for every
    /// normal launch. `BodyScanCaptureModel` treats nil as "use the real one".
    static func driverIfRequested() -> (any BodyScanCaptureDriver)? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-BodyScanScriptedCapture")
        else { return nil }
        let name = UserDefaults.standard.string(forKey: "BodyScanScript")
        let script = ScriptedBodyScanCaptureDriver.Script(rawValue: name ?? "")
            ?? .measurementFailed
        return ScriptedBodyScanCaptureDriver(script: script)
        #else
        return nil
        #endif
    }
}

#if DEBUG

@MainActor
final class ScriptedBodyScanCaptureDriver: BodyScanCaptureDriver {

    /// Each script walks the flow to a different ending, so each terminal
    /// screen can be read rather than inferred from its source.
    enum Script: String {
        /// The longest walkable path: consent → setup → placing (three staged
        /// pose problems, so the one-instruction-at-a-time card can be read) →
        /// four LiDAR holds → processing → `.measurementFailed`. The furthest
        /// any capture can go while `BodyScanMeasuring` is unbuilt.
        case measurementFailed
        /// A phone with no depth sensor: the camera-mode consent copy and the
        /// two-station path, same ending.
        case camera
        /// The AR session is torn from under the flow mid-capture.
        case interrupted
        /// A pose that never settles: "Hold still" forever, then the station
        /// deadline. ⚠️ Takes the real 90 s — the deadline is the thing under
        /// test, so the script must not shortcut it.
        case timeout
        /// The reader declines the system prompt: `.blocked(.permissionDenied)`.
        case denied
    }

    private let script: Script
    /// Set when `start` is called; the readings are a pure function of the
    /// elapsed time since, so no timer runs and nothing races the poll loop.
    private var startedAt: Date?
    private var capturedStations: [CaptureStation] = []

    init(script: Script) {
        self.script = script
    }

    /// A capable phone, *scripted*. `isSimulator: false` is deliberately untrue
    /// on the machine this runs on: the honest capability produces the
    /// `.blocked(.simulator)` refusal — already verifiable without this driver —
    /// and the whole point here is the states behind it.
    var capability: BodyScanDeviceCapability {
        BodyScanDeviceCapability(hasCamera: true,
                                 hasSceneDepth: script != .camera,
                                 supportsBodyTracking: true,
                                 isSimulator: false)
    }

    /// Never asked, so the flow starts on the consent brief — the screen the
    /// permission rule exists for.
    var authorization: CameraAuthorization { .notDetermined }

    func requestCameraAccess() async -> CameraAuthorization {
        script == .denied ? .denied : .authorized
    }

    func start(mode: BodyScan.CaptureMode) {
        startedAt = Date()
        capturedStations = []
    }

    func stop() {}

    var sessionFailure: CaptureFailure? {
        guard script == .interrupted, let startedAt,
              Date().timeIntervalSince(startedAt) >= 6 else { return nil }
        return .interrupted
    }

    /// The scripted timeline. Three staged problems first — orderable only
    /// because `PoseCheck` shows one instruction at a time, which is the
    /// behaviour being demonstrated — then a clean pose that lets every hold
    /// complete.
    var latestReading: CaptureReading? {
        guard let startedAt else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)

        // The pose that matches a first scan's default target exactly
        // (`ScanSetupTarget.defaultDistanceMetres` / `defaultDeviceHeightMetres`).
        // Scripted, so it aims at the defaults; on a store that already holds a
        // scan the target moves and the script may show extra instructions —
        // harmless, but worth knowing when reading the screen.
        func reading(distance: Double = ScanSetupTarget.defaultDistanceMetres,
                     height: Double = ScanSetupTarget.defaultDeviceHeightMetres,
                     body: Bool = true, still: Bool = true) -> CaptureReading {
            CaptureReading(subjectDistanceMetres: distance,
                           deviceHeightMetres: height,
                           deviceTiltDegrees: 2, ambientLux: 800,
                           isBodyTracked: body, isFullBodyInFrame: body,
                           isStill: still)
        }

        if script == .timeout {
            // Tracked, framed, lit — and never still. The only instruction the
            // card can show is "Hold still", until the deadline says why that
            // was never going to work.
            return reading(still: false)
        }

        switch elapsed {
        case ..<1.5: return reading(body: false)               // step into view
        case ..<3.0: return reading(distance: ScanSetupTarget.defaultDistanceMetres + 0.5)
                                                               // come closer
        case ..<4.5: return reading(height: ScanSetupTarget.defaultDeviceHeightMetres - 0.3)
                                                               // raise the phone
        default: return reading()
        }
    }

    func captureStation(_ station: CaptureStation) {
        guard !capturedStations.contains(station) else { return }
        capturedStations.append(station)
    }

    var availableAssets: Set<BodyScanAsset> {
        script == .camera
            ? [.personMask, .skeleton, .colourFrames]
            : [.personMask, .skeleton, .colourFrames, .depthMap]
    }

    /// Nil, always — including after `BodyScanMeasuring` ships. See the type
    /// comment: a scripted capture must never mint a figure.
    func measure() async -> BodyMeasurements? { nil }
}

#endif
