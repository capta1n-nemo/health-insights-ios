import Foundation
import SwiftUI
import UIKit
import InsightKit

/// What the first seconds of a cold start look like, instead of a blank screen
/// while the cached history is read and the insights are evaluated.
///
/// The heart is a particle cloud drawn by Metal — see `LaunchParticleView`.
///
/// It has been three things. Drawn in SwiftUI first (a `TimelineView` with a
/// shadowed symbol, every frame, on the main thread), which froze solid the
/// moment real work started — precisely when a loading animation most needs to
/// move. Then a pre-rendered video, which fixed that by being hardware-decoded
/// off the main thread, but was 608×1078 on a screen that upscales it 2.4×, with
/// its dot density and its speed baked into the file. Now generated live, where
/// resolution is the drawable's own, density is an integer, and speed is a
/// constant.
///
/// The decisions that can be wrong — which line, when it changes, when the
/// screen comes down — are in `LaunchNarration`, in InsightKit, where they have
/// tests. This file is the playback and the layout.
struct LaunchScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the status line sits, as a fraction of the screen's height.
    ///
    /// Measured, not chosen. Sweeping the rendered frame in 5% bands over the
    /// middle 70% of its width, ink coverage runs: 0.58–0.63 → **1.6%**,
    /// 0.66–0.71 → 13%, 0.74–0.79 → 37%. This used to sit at 0.74, which is the
    /// densest part of the lower ring, and the copy was simply lost in it.
    /// 0.605 is the centre of the one genuinely clear band — under the heart's
    /// point, above the ring's lower lobe.
    private static let captionHeight: CGFloat = 0.605

    @State private var narration = LaunchNarration()
    @State private var message = LaunchNarration.script[0].text
    @State private var startedAt = Date()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The same colour the static UILaunchScreen uses and the same
                // one the renderer clears to, so the handoff from launch image
                // to live view has nothing to see.
                Color("LaunchBackground").ignoresSafeArea()

                if reduceMotion || !LaunchParticleView.isAvailable {
                    // Reduce Motion takes the movement, not the screen: the
                    // poster is the same cloud, at rest. It is also the fallback
                    // for a device with no Metal — a launch screen that renders
                    // nothing would be worse than the one it replaced.
                    Image("LaunchPoster")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                } else {
                    LaunchParticleView()
                        .ignoresSafeArea()
                }

                status(width: geo.size.width, height: geo.size.height)
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

    private func status(width: CGFloat, height: CGFloat) -> some View {
        Text(message)
            // Sized off the screen rather than off a text style. The reference
            // animation set its caption at roughly 2.4% of frame height, which
            // `.callout`'s fixed 16 pt was nowhere near on a modern phone — it
            // read as a footnote under a full-screen mark. Clamped so it stays
            // sane on a small device and on an iPad.
            .font(.system(size: min(max(height * 0.025, 16), 24), weight: .medium))
            // An explicit colour, not `.secondary`. This screen commits to a
            // light background whatever the system appearance is, and
            // `.secondary` does not — on a phone in dark mode it resolves to a
            // *light* grey and the copy vanished entirely. A semantic colour is
            // only semantic if the surface under it is semantic too.
            //
            // ~10:1 against the launch background, which it needs to be: it sits
            // over mist, not over flat colour.
            .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.14))
            .multilineTextAlignment(.center)
            // The clear band is about 45 pt tall and the longest line here is
            // 44 characters, so let a long one shrink rather than grow a third
            // row down into the ring.
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .transition(.opacity)
            .id(message)
            .frame(maxWidth: width * 0.84)
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
