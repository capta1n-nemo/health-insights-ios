import Foundation
import SwiftUI
import InsightKit

/// What the first two-to-five seconds look like, instead of a blank white screen
/// while the providers answer and the on-device model writes the summary.
///
/// The reference feel is the Apple Watch first-pairing hologram: a luminous
/// centred form with something slowly radiating out of it. Nothing here is a
/// progress bar, deliberately — the launch has no measurable fraction complete,
/// and a bar that fills at a rate unrelated to the work is a lie the user learns
/// to distrust. It says *something is happening*, and the copy says what.
///
/// The decisions that can be wrong — which line, when it changes, when the
/// screen comes down — are all in `LaunchNarration`, in InsightKit, where they
/// have tests. This file is the drawing.
struct LaunchScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One breath, and one full trip outward for a ring. Slow enough to read as
    /// calm — the resting rate this is standing in for is nearer 15 a minute
    /// than 60, and a fast pulse on a health app's launch screen is a mood.
    private static let period: Double = 2.6
    private static let ringCount = 3

    @State private var narration = LaunchNarration()
    @State private var message = LaunchNarration.script[0].text
    @State private var startedAt = Date()

    var body: some View {
        ZStack {
            // The same background every tab uses. The cross-dissolve is only
            // seamless if the two sides sit on one colour — otherwise the fade
            // carries a background change with it, which reads as a flash.
            Color(.systemGroupedBackground).ignoresSafeArea()
            glow
            VStack(spacing: 34) {
                pulse
                status
            }
            .padding(.horizontal, 40)
        }
        .task { await narrate() }
        // One element, one label. A rotating string re-announced every 1.25 s
        // would talk over VoiceOver's own reading of it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your health data")
        .accessibilityValue(message)
    }

    // MARK: - The pulse

    /// A soft accent wash behind the mark, so the rings fade into something
    /// rather than into flat background. Sized past the screen edge on purpose.
    private var glow: some View {
        RadialGradient(colors: [Theme.accent.opacity(0.20),
                                Theme.accent.opacity(0.05),
                                .clear],
                       center: .center, startRadius: 0, endRadius: 300)
            .ignoresSafeArea()
    }

    @ViewBuilder private var pulse: some View {
        if reduceMotion {
            // Reduce Motion takes the movement, not the screen. The rings stay
            // as a static mark so the layout and the glow are unchanged.
            ZStack {
                ring(phase: 0.34)
                ring(phase: 0.68)
                heart(scale: 1)
            }
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(startedAt)
                ZStack {
                    ForEach(0..<Self.ringCount, id: \.self) { index in
                        ring(phase: ringPhase(t, index: index))
                    }
                    heart(scale: 1 + 0.055 * sin(t * 2 * .pi / Self.period))
                }
            }
        }
    }

    /// Where ring `index` is in its trip out, as 0...1. Staggered evenly so one
    /// leaves as the next arrives and the sequence never bunches.
    private func ringPhase(_ t: Double, index: Int) -> Double {
        let raw = t / Self.period + Double(index) / Double(Self.ringCount)
        return raw - raw.rounded(.down)
    }

    /// Fades out as it grows, on a curve rather than linearly — a ring that
    /// dims evenly all the way out reads as a hard-edged circle to the last
    /// frame, which is the difference between a hologram and a loading spinner.
    private func ring(phase: Double) -> some View {
        Circle()
            .stroke(Theme.accent.opacity(pow(1 - phase, 1.7) * 0.5), lineWidth: 1.5)
            .frame(width: 128, height: 128)
            .scaleEffect(0.5 + phase * 1.0)
    }

    private func heart(scale: Double) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 52))
            .foregroundStyle(Theme.accent)
            .shadow(color: Theme.accent.opacity(0.45), radius: 22)
            .scaleEffect(scale)
    }

    // MARK: - The status line

    private var status: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            // Transition inside the identity, frame outside it: the line fades
            // out and the next fades in, while the box they sit in holds still.
            .transition(.opacity)
            .id(message)
            // Two lines' worth, held whatever the copy is: a line that wraps at
            // large Dynamic Type would otherwise shove the pulse up the screen
            // mid-rotation.
            .frame(minHeight: 46, alignment: .top)
    }

    // MARK: - Driving it

    /// Poll rather than react to the phase.
    ///
    /// The narration needs the *clock* as well as the phase — its whole job is
    /// to hold a line long enough to read — so it cannot be driven by phase
    /// changes alone, and `LaunchNarration` is a state machine that has to be
    /// stepped. 80 ms is well under the shortest hold, so no change lands late
    /// enough to see.
    @MainActor private func narrate() async {
        startedAt = Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(startedAt)
            let phase = model.launchPhase

            let next = narration.line(at: elapsed, phase: phase)
            if next != message {
                withAnimation(.easeInOut(duration: 0.3)) { message = next }
            }

            if LaunchNarration.shouldDismiss(elapsed: elapsed, phase: phase) {
                // The cross-dissolve: this clears `isLaunching`, which fades
                // this screen out and the tabs in together — see `RootView`.
                withAnimation(.easeInOut(duration: 0.5)) { model.finishLaunch() }
                return
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }
}
