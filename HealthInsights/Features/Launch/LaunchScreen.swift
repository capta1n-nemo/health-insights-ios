import Foundation
import SwiftUI
import UIKit
import AVFoundation
import InsightKit

/// What the first seconds of a cold start look like, instead of a blank screen
/// while the cached history is read and the insights are evaluated.
///
/// The heart is a pre-rendered particle animation played by AVFoundation rather
/// than anything drawn here, and that is a performance decision as much as an
/// aesthetic one: video decode is hardware-accelerated and happens off the main
/// thread, so the animation keeps moving even while the main actor is busy. The
/// first version drew the mark in SwiftUI — a `TimelineView(.animation)` with a
/// shadowed symbol and a full-screen gradient, every frame, on the main thread —
/// and froze solid for ten seconds the moment real work started, which is
/// exactly when a loading animation most needs to be moving.
///
/// The decisions that can be wrong — which line, when it changes, when the
/// screen comes down — are in `LaunchNarration`, in InsightKit, where they have
/// tests. This file is the playback and the layout.
struct LaunchScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the status line sits, as a fraction of the video's height. The
    /// source animation was composed with its own caption at this height, so
    /// the ring's gap is already there waiting for it.
    private static let captionHeight: CGFloat = 0.74

    @State private var narration = LaunchNarration()
    @State private var message = LaunchNarration.script[0].text
    @State private var startedAt = Date()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The video's own background, and the same colour the static
                // UILaunchScreen uses, so the handoff from the launch image to
                // this view has nothing to see.
                Color("LaunchBackground").ignoresSafeArea()

                if reduceMotion {
                    // Reduce Motion takes the movement, not the screen: the
                    // poster is frame one of the same animation.
                    Image("LaunchPoster")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                } else {
                    LoopingVideo(resource: "LaunchHeart", extension: "mp4")
                        .ignoresSafeArea()
                }

                status
                    .position(x: geo.size.width / 2,
                              y: geo.size.height * Self.captionHeight)
            }
        }
        .task { await narrate() }
        .task { await releaseOnCeiling() }
        // One element, one label. A rotating string re-announced every 1.25 s
        // would talk over VoiceOver's own reading of it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your health data")
        .accessibilityValue(message)
    }

    // MARK: - The status line

    private var status: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .transition(.opacity)
            .id(message)
            .padding(.horizontal, 40)
    }

    // MARK: - Driving it

    /// Poll rather than react to the phase.
    ///
    /// The narration needs the *clock* as well as the phase — its whole job is
    /// to hold a line long enough to read — so it cannot be driven by phase
    /// changes alone, and `LaunchNarration` is a state machine that has to be
    /// stepped. 100 ms is well under the shortest hold, so no change lands late
    /// enough to see.
    @MainActor private func narrate() async {
        startedAt = Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(startedAt)

            let next = narration.line(at: elapsed, phase: model.launchPhase)
            if next != message {
                withAnimation(.easeInOut(duration: 0.3)) { message = next }
            }

            if LaunchNarration.shouldDismiss(elapsed: elapsed, hasContent: model.isHydrated) {
                dismiss()
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The ceiling, on a timer that cannot be starved by what it protects
    /// against.
    ///
    /// `narrate()` is `@MainActor`, so a long synchronous main-thread call
    /// blocks it — which means the one launch that needs a hard ceiling is the
    /// one launch where a ceiling polled from that loop cannot fire. It shipped
    /// that way and the user sat through twenty-five seconds of a twenty-second
    /// ceiling. **A timeout must not live on the thread it is timing out.**
    ///
    /// This one is deliberately *not* `@MainActor`: a `View`'s own methods are
    /// nonisolated, so the suspension resumes on the cooperative pool and only
    /// the final hop needs the main actor.
    private func releaseOnCeiling() async {
        try? await Task.sleep(for: .seconds(LaunchNarration.hardCeiling))
        guard !Task.isCancelled else { return }
        await dismiss()
    }

    @MainActor private func dismiss() {
        guard model.isLaunching else { return }
        // The cross-dissolve: clearing `isLaunching` fades this screen out and
        // reveals the tabs underneath — see `RootView`.
        withAnimation(.easeInOut(duration: 0.45)) { model.finishLaunch() }
    }
}

/// An `AVPlayerLayer` that loops gaplessly, muted, with no controls.
///
/// `AVKit.VideoPlayer` would bring playback controls and a scrubber to a launch
/// screen, and `AVPlayer.actionAtItemEnd = .none` plus a notification leaves a
/// visible stall at the loop point. `AVPlayerLooper` over an `AVQueuePlayer` is
/// the one that actually loops without a seam.
private struct LoopingVideo: UIViewRepresentable {
    let resource: String
    let `extension`: String

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: resource, withExtension: `extension`) else {
            return view
        }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        // The asset is encoded with no audio track at all, so nothing here can
        // touch the audio session or interrupt what the user is listening to.
        // `isMuted` is belt and braces; the display-sleep opt-out matters more —
        // a launch screen has no business holding the screen awake.
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.looper = AVPlayerLooper(player: queue, templateItem: item)
        view.player = queue
        queue.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        coordinator.looper?.disableLooping()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    /// A `UIView` backed by `AVPlayerLayer`, so the video is composited by the
    /// render server rather than blitted through the view hierarchy.
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        var player: AVPlayer? {
            get { playerLayer.player }
            set {
                playerLayer.player = newValue
                // Fill, matching UILaunchScreen's own scaling of the poster, so
                // the static launch image and the first video frame line up.
                playerLayer.videoGravity = .resizeAspectFill
            }
        }
    }
}
