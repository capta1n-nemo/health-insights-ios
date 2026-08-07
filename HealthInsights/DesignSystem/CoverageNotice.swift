import SwiftUI
import InsightKit

/// **How much more is needed, rendered.** Backlog D46.
///
/// The reader, 2026-08-06: *"it needs to be mentioned appropriately for
/// transparency, so users know why things are - or are not showing in the app"*.
///
/// `CoverageGate` has existed in InsightKit since that day and **nothing in the
/// app target referenced it**, which is the whole shape of the problem: the
/// vocabulary was written and the delivery mechanism never was, so every gate in
/// the app still reached the reader as an empty space. A withheld figure and an
/// absent one look identical from the outside, and only the first is a reason to
/// keep going.
///
/// This is the delivery mechanism. Anything holding a `CoverageGate` can put its
/// sentence where the figure would have been, in one line.
///
/// ## Silent once met
///
/// `gate.sentence` is `nil` when the requirement is satisfied, and this draws
/// nothing in that case rather than congratulating anyone. A card that keeps
/// naming a threshold it has cleared is nagging — the same rule
/// `SuggestionEngine` follows when it ranks "a feature you haven't tried" below
/// every grounding gap.
struct CoverageGateNotice: View {
    let gate: CoverageGate
    /// Defaults to an hourglass — waiting, not broken. A warning triangle would
    /// say the app is in a bad state, and it is not: it is collecting.
    var icon: String = "hourglass"

    var body: some View {
        if let sentence = gate.sentence {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(sentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Only once there is something to show progress *of*. A bar
                    // pinned at zero reads as a failure state, which is the
                    // opposite of what an empty gate means.
                    if gate.have > 0 {
                        ProgressView(value: gate.progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.accent)
                            .frame(maxWidth: 180)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sentence)
        }
    }
}

/// The grey chip that stands where an arrow would be, when there is no arrow to
/// draw. Backlog B15-2.
///
/// `ScoreChangeChip` renders all three *measured* answers, steady included, so
/// its absence used to mean "not enough history to judge" — and meant it by
/// saying nothing at all, in an `if let` with no `else`. A blank space is not a
/// statement, and the reader read it as one.
///
/// ## Why it is grey and wordy rather than an icon
///
/// The three measured states are arrows with a valence colour. This is not a
/// fourth direction and must not look like one, so it takes no arrow and no
/// valence — a word, in the secondary colour, which is what the rest of the app
/// uses for "this is context, not a finding".
struct PendingChangeChip: View {
    let state: ScoreChangeState

    var body: some View {
        if let label = state.pendingLabel {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .accessibilityLabel(state.explanation ?? label)
        }
    }
}
