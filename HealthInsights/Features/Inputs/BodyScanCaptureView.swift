import SwiftUI
import InsightKit
#if canImport(ARKit)
import ARKit
#endif

/// The guided body scan, on screen.
///
/// ## What this screen is for
///
/// Not "point the camera at yourself". Every consumer scanner does that and
/// every one of them is reviewed as *inconsistent*, because the numbers move
/// with clothing, distance, camera height and light and nobody records any of
/// it. `ScanSetupTarget` is the answer — **aim the reader at their own previous
/// setup** rather than at a nominal one — and this screen is where that
/// happens: one instruction at a time, a hold that resets the moment the pose
/// breaks, and conditions written from what was observed rather than from what
/// was asked for.
///
/// ## What of it can be trusted today
///
/// The stages, the refusals, the consent brief, the pose rules and every string
/// on this screen come from `BodyScanCaptureFlow`, which is tested in InsightKit
/// on any machine. **The camera half has never been run**: it needs a phone with
/// a LiDAR sensor and a person standing two metres in front of it. See
/// `ARBodyScanCaptureDriver` for the three things only the device can falsify.
///
/// **Walked on the simulator 2026-08-08** with `ScriptedBodyScanCaptureDriver`
/// (screenshots in `build/simulator-shots/wf_3f11b9f1-d1f-7-d3f8f5f-*.png`):
/// consent brief → setup form (clothing picker, placement, accuracy caveat) →
/// live capture (station header, hold countdown) → all four stations →
/// processing → the `.measurementFailed` ending, with no retry offered, which
/// is `CaptureFailure.isRetryable` rendering correctly. Not yet seen on a
/// screen: the pose-problem instruction card, an `OutcomeView` *with* a
/// Try-again button, the `blocked` variants, the two-station camera path and
/// the 90-second station timeout — their copy is pinned by the InsightKit
/// tests, but their rendering has only been reasoned about, not looked at.
///
/// It is reachable from the tape sheet rather than being its own `InputKind`,
/// and that is `InputKind.bodyMeasurements`' own reasoning: a tape and a scan
/// produce the same thing and answer the same question, so the choice between
/// them belongs inside the sheet, not as two near-identical rows on every
/// surface.
struct BodyScanCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var capture: BodyScanCaptureModel?

    var body: some View {
        Group {
            if let capture {
                content(capture)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Body scan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if capture == nil {
                capture = BodyScanCaptureModel(
                    policy: model.bodyScanPolicy,
                    previousScans: model.bodyScans,
                    // Nil on every normal launch. A DEBUG build launched with
                    // `-BodyScanScriptedCapture` gets the scripted sensor, so a
                    // simulator session can walk the states past the honest
                    // `.blocked(.simulator)` refusal — see
                    // `ScriptedBodyScanCaptureDriver`.
                    driver: ScriptedBodyScanCapture.driverIfRequested())
            }
        }
        .onDisappear { capture?.tearDown() }
    }

    @ViewBuilder private func content(_ capture: BodyScanCaptureModel) -> some View {
        switch capture.flow.stage {
        case let .explaining(brief):
            ConsentBriefView(brief: brief, target: capture.flow.target) {
                Task { await capture.consentAndPrompt() }
            }
        case .awaitingPermission:
            waiting("Waiting for you to answer iOS…")
        case .settingUp:
            SetUpView(capture: capture)
        case .placing, .holding:
            LiveCaptureView(capture: capture)
        case .processing:
            waiting("Working out your measurements…")
        case let .finished(scan):
            FinishedView(scan: scan, caveat: capture.flow.accuracyCaveat) {
                model.saveBodyScan(scan)
                dismiss()
            }
        case let .failed(failure):
            OutcomeView(title: failure.title, explanation: failure.explanation,
                        whatNow: failure.whatNow, symbol: "exclamationmark.triangle",
                        retry: failure.isRetryable ? { capture.restart() } : nil,
                        dismiss: { dismiss() })
        case let .blocked(block):
            OutcomeView(title: block.title, explanation: block.explanation,
                        whatNow: block.whatNow, symbol: "camera.badge.ellipsis",
                        retry: nil, dismiss: { dismiss() })
        }
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - The model

/// The flow, the driver, and the clock that joins them.
///
/// The polling loop is here rather than in the driver because the *rules* about
/// what a good frame means live in `PoseCheck`, and a driver that decided them
/// would put a second copy of them behind a sensor no test can reach.
@MainActor
@Observable
final class BodyScanCaptureModel {
    private(set) var flow: BodyScanCaptureFlow
    private(set) var problem: PoseProblem?
    private(set) var holdProgress: Double = 0

    private let driver: any BodyScanCaptureDriver
    private let policy: BodyScanPolicy
    private let previousScans: [BodyScan]
    private var hold = HoldTimer()
    private var loop: Task<Void, Never>?
    /// When the station now on screen was opened, for the deadline below.
    private var stationOpenedAt: Date?
    private var openStation: CaptureStation?

    /// Ten a second. Fast enough that the countdown ring moves smoothly, slow
    /// enough that it is not doing trigonometry on every ARKit frame.
    private static let tickSeconds = 0.1
    /// How long one station may go without a clean hold before the flow gives
    /// up and says so. ⚠️ **Only the phone can tell whether this is right** —
    /// it is a guess at how long somebody can keep trying before the screen
    /// owes them an explanation.
    private static let stationDeadlineSeconds = 90.0

    init(policy: BodyScanPolicy, previousScans: [BodyScan],
         driver: (any BodyScanCaptureDriver)? = nil) {
        let resolved = driver ?? BodyScanCapture.makeDriver()
        self.driver = resolved
        self.policy = policy
        self.previousScans = previousScans
        self.flow = BodyScanCaptureFlow(
            availability: .decide(capability: resolved.capability,
                                  authorization: resolved.authorization,
                                  policy: policy),
            policy: policy,
            target: ScanSetupTarget.matching(previousScans))
    }

    // MARK: Transitions the screen drives

    func consentAndPrompt() async {
        flow.consentGiven()
        flow.permissionResolved(await driver.requestCameraAccess())
    }

    func setClothing(_ clothing: ScanConditions.Clothing) {
        flow.setClothing(clothing)
    }

    var clothing: ScanConditions.Clothing { flow.clothing }

    /// Open the camera and start guiding.
    func begin() {
        let mode = flow.mode
        flow.beginPlacing()
        guard flow.stage.needsCamera else { return }
        driver.start(mode: mode)
        startLoop()
    }

    func cancel() {
        tearDown()
        flow.fail(.cancelled)
    }

    func restart() {
        tearDown()
        hold = HoldTimer()
        problem = nil
        holdProgress = 0
        stationOpenedAt = nil
        openStation = nil
        flow = BodyScanCaptureFlow(
            availability: .decide(capability: driver.capability,
                                  authorization: driver.authorization,
                                  policy: policy),
            policy: policy,
            target: ScanSetupTarget.matching(previousScans))
    }

    func tearDown() {
        loop?.cancel()
        loop = nil
        driver.stop()
    }

    // MARK: The loop

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
                guard let self else { return }
                self.tick(now: Date())
                if self.flow.stage.isTerminal || !self.flow.stage.needsCamera { return }
            }
        }
    }

    private func tick(now: Date) {
        // A session-level failure wins over anything the pose is doing: there
        // is no point telling somebody to hold still when the camera has gone.
        if let failure = driver.sessionFailure {
            tearDown()
            flow.fail(failure)
            return
        }

        let reading = driver.latestReading ?? CaptureReading()
        let problems = PoseCheck.problems(reading, target: flow.target)
        problem = problems.first

        switch flow.stage {
        case .placing:
            // The first station opens only once the setup is right. Starting a
            // hold while the reader is still walking backwards would burn the
            // first station on a frame nobody meant to give.
            holdProgress = 0
            stationOpenedAt = nil
            if problems.isEmpty { flow.advanceToNextStation() }

        case let .holding(current):
            // **The station has a deadline, and it is the whole reason
            // `CaptureFailure.timedOut` exists.** Without one, a reader
            // standing in a dim room with the phone on a wobbling shelf gets a
            // countdown that resets forever and a screen that never says why —
            // which is the same shape as a card that renders nothing, and just
            // as unreadable. Ninety seconds is generous for a two-second hold;
            // anything that cannot be done in forty-five attempts is not going
            // to be done on the forty-sixth.
            let opened = stationOpenedAt ?? now
            if stationOpenedAt == nil || openStation != current {
                stationOpenedAt = now
                openStation = current
            } else if now.timeIntervalSince(opened) > Self.stationDeadlineSeconds {
                tearDown()
                flow.fail(.timedOut(current))
                return
            }
            holdProgress = hold.update(isAcceptable: problems.isEmpty, now: now)
            guard hold.isComplete(now: now) else { return }
            if case let .holding(station) = flow.stage {
                driver.captureStation(station)
            }
            hold.reset()
            holdProgress = 0
            flow.stationHeld()
            if case .processing = flow.stage { finish(now: now, observed: reading) }

        default:
            return
        }
    }

    private func finish(now: Date, observed: CaptureReading) {
        tearDown()
        Task { [weak self] in
            guard let self else { return }
            let measured = await self.driver.measure()
            _ = self.flow.finish(capturedAt: now,
                                 parserVersion: BodyScanParserVersion.current,
                                 measurements: measured ?? .empty,
                                 observed: observed,
                                 availableAssets: self.driver.availableAssets)
        }
    }

    /// Exposed so the live view can show the camera feed from the same session
    /// the readings come from — two sessions would fight over the camera.
    var arDriver: AnyObject { driver }
}

// MARK: - Before the prompt

/// What the scan does and keeps, before iOS asks anything.
///
/// The rule the location work set and this inherits: **explain before
/// prompting.** Every line here comes out of `BodyScanConsentBrief`, which is
/// generated from the reader's own retention policy — so the screen cannot
/// promise to keep less than it keeps.
private struct ConsentBriefView: View {
    let brief: BodyScanConsentBrief
    let target: ScanSetupTarget
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(brief.title).font(.title2.weight(.semibold))
                Text(brief.why).fixedSize(horizontal: false, vertical: true)

                labelled("What it uses", brief.whatIsUsed)
                labelled("What it keeps", brief.whatIsKept)
                labelled("How it works", target.placementInstruction)

                Text(brief.beforeYouTap)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onContinue) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding()
        }
    }

    private func labelled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Setting up

private struct SetUpView: View {
    let capture: BodyScanCaptureModel

    var body: some View {
        Form {
            Section {
                Picker("Wearing", selection: Binding(
                    get: { capture.clothing },
                    set: { capture.setClothing($0) })) {
                    ForEach([ScanConditions.Clothing.minimal, .formFitting,
                             .looseFitting], id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            } header: {
                Text("What you're wearing")
            } footer: {
                Text(capture.flow.target.matchesPreviousScan
                     ? "Pre-set to what you wore last time. Clothing is the single biggest reason two scans disagree, so change it only if you really are dressed differently — recording the difference is better than hiding it."
                     : "Clothing is the single biggest reason two scans disagree. Whatever you pick, the app will aim you at the same choice next time.")
            }

            Section {
                Text(capture.flow.target.placementInstruction)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Where to put the phone")
            } footer: {
                Text("It'll tell you when you're in the right place — one thing at a time — then count down while you hold each position. \(stationSummary)")
            }

            Section {
                Text(capture.flow.accuracyCaveat)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("How much to believe it")
            }

            Section {
                Button("Start the scan") { capture.begin() }
            }
        }
    }

    private var stationSummary: String {
        let count = capture.flow.stations.count
        return count == 2
            ? "Two positions: facing the phone, then a quarter turn."
            : "\(count) positions, a quarter turn apart."
    }
}

// MARK: - Live

/// The camera, one instruction, and a countdown.
private struct LiveCaptureView: View {
    let capture: BodyScanCaptureModel

    var body: some View {
        ZStack {
            CameraPreview(capture: capture)
                .ignoresSafeArea()
            VStack {
                header
                Spacer()
                instructionCard
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Stop") { capture.cancel() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            if let label = capture.flow.stationCountLabel {
                Text(label).font(.caption.weight(.semibold))
            }
            if case let .holding(station) = capture.flow.stage {
                Text(station.displayName).font(.headline)
            } else {
                Text("Getting into position").font(.headline)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// **One instruction, never a list.** A reader standing two metres away
    /// cannot read six lines, and five of the six would be consequences of the
    /// first — fix the framing and "no body found" goes with it.
    private var instructionCard: some View {
        VStack(spacing: 8) {
            if let problem = capture.problem {
                Text(problem.instruction).font(.title3.weight(.semibold))
                Text(problem.reason)
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case let .holding(station) = capture.flow.stage {
                Text(station.instruction)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                ProgressView(value: capture.holdProgress)
                    .tint(Theme.accent)
                Text("Hold it").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Looking good — starting").font(.title3.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The AR session's own camera feed.
///
/// It shows the **same** `ARSession` the readings come from. A second session
/// for the preview would fight the first one for the camera and the reader
/// would see a frozen image while the flow insisted they were out of frame.
private struct CameraPreview: View {
    let capture: BodyScanCaptureModel

    var body: some View {
        #if canImport(ARKit) && !targetEnvironment(simulator)
        if let driver = capture.arDriver as? ARBodyScanCaptureDriver {
            ARSessionPreview(session: driver.previewSession)
        } else {
            Color.black
        }
        #else
        Color.black
        #endif
    }
}

#if canImport(ARKit) && !targetEnvironment(simulator)
private struct ARSessionPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        // Nothing is drawn into the scene — this is a viewfinder, not an AR
        // experience. Statistics and automatic lighting would only cost frames.
        view.automaticallyUpdatesLighting = false
        view.rendersContinuously = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}
#endif

// MARK: - Endings

private struct FinishedView: View {
    let scan: BodyScan
    let caveat: String
    let onSave: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(scan.measurements.sites, id: \.self) { site in
                    LabeledContent(site.displayName) {
                        Text(String(format: "%.1f cm", scan.measurements.mean(site) ?? 0))
                            .monospacedDigit()
                    }
                }
            } header: {
                Text(scan.mode.displayName)
            } footer: {
                // ⚠️ The standing rule, on the screen the numbers first appear
                // on: a circumference off a mesh has no validated accuracy
                // claim, so the band is stated before the reader has had a
                // chance to believe the decimal point.
                Text(caveat)
            }
            Section {
                Button("Save this scan", action: onSave)
            } footer: {
                Text(scan.isReparseable
                     ? "The raw capture is kept, so a later version of the app can re-measure this scan instead of asking you to take it again."
                     : "Only the numbers are kept — you chose that in Settings ▸ Body scans. This scan can never be re-measured.")
            }
        }
    }
}

private struct OutcomeView: View {
    let title: String
    let explanation: String
    let whatNow: String
    let symbol: String
    let retry: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(explanation)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(whatNow)
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            Button("Use a tape measure instead", action: dismiss)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
