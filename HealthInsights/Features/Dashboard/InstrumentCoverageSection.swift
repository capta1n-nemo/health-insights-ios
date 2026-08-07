import SwiftUI
import InsightKit

/// **"What I could see last night."** Backlog B3-19.
///
/// ## The ambiguity it removes
///
/// A quiet symptom radar means one of two completely different things: nothing
/// stirred, or the ring spent the night on the charger. Until this card, the app
/// rendered both as the same green — and that is the worst failure available to
/// a card whose entire value is that it stays quiet, because a reader who cannot
/// tell the two apart learns that the quiet means nothing, and then the one
/// night it speaks means nothing either.
///
/// Every card here already refuses to score on data it does not have. What none
/// of them did was say what they *had*. This is the denominator, on the tab
/// where the reader looks first.
///
/// ## What it never claims
///
/// Not *why* an instrument was silent. Charging, flat, unworn and unsynced are
/// indistinguishable from this phone, so the copy stops at "reported nothing" —
/// see `InstrumentCoverage`, which enforces the same restraint in its own
/// sentences.
///
/// ## Why the abstaining cards are listed but not attributed
///
/// The card names which daily insights are waiting on today's data
/// (`InsightResult.isAwaitingTodaysData` — the flag that already exists for
/// exactly this state) and stops there. Drawing a line from *this silent
/// instrument* to *that abstaining card* would need a per-card map of which
/// device feeds it, and the honest version of that map does not exist: several
/// cards read a metric that three devices can all supply. A guessed
/// attribution is worse than an unattributed fact, so the two lists sit next to
/// each other and the reader joins them.
///
/// ## And why the learning gates are on the same card
///
/// "Why is this card not telling me something" has two answers, and they arrive
/// at the reader identically: the instruments were quiet, or the history is
/// still too short. Only the second is a reason to keep going. Splitting them
/// across two surfaces would leave a reader who found one assuming there was no
/// other, so both live here — see `CoverageGateNotice`, which this is the only
/// caller of, and backlog D46.
struct InstrumentCoverageSection: View {
    @Environment(AppModel.self) private var model
    @State private var isExpanded = false

    /// Memoised for the same reason every other model pass on this tab is: the
    /// tab re-evaluates `body` on every scroll, and this walks the whole sample
    /// set once.
    private var coverage: InstrumentCoverage {
        model.memoized("instrumentCoverageNight") {
            InstrumentCoverage.night(samples: model.samples)
        }
    }

    /// Daily cards with real history that have no number for today. The flag is
    /// the app's own, set by the engine, so this list cannot disagree with what
    /// the cards below are actually doing.
    private var abstaining: [InsightResult] {
        model.results.filter { $0.id.cadence == .daily && $0.score == nil
            && $0.isAwaitingTodaysData }
    }

    /// Daily cards that *have* a number but cannot yet say which way it is
    /// going, with the gate saying how much more they need.
    ///
    /// The second half of the same question. "Why is this card not telling me
    /// something" has two answers — the instruments were quiet, or the history
    /// is still too short — and a reader who can only see the first will read
    /// the second as the app having nothing to say. Backlog D46; this is the
    /// only place in the app that renders a `CoverageGate` in full.
    private var learning: [(result: InsightResult, gate: CoverageGate)] {
        model.results.compactMap { result in
            guard result.id.cadence == .daily,
                  let gate = model.scoreChangeState(for: result.id)?.gate else { return nil }
            return (result, gate)
        }
    }

    var body: some View {
        if !coverage.isEmpty || !learning.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if !coverage.isEmpty {
                        header
                        if let caveat = coverage.caveat {
                            Text(caveat)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !abstaining.isEmpty {
                            abstainingLine
                        }
                        disclosure
                    }
                    if !learning.isEmpty {
                        learningBlock
                    }
                }
            }
        }
    }

    private var learningBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Still learning your usual")
                .font(.subheadline.weight(.medium))
            ForEach(learning, id: \.result.id) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.result.title)
                        .font(.caption.weight(.medium))
                    CoverageGateNotice(gate: entry.gate)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("What I could see last night", systemImage: "sensor.tag.radiowaves.forward")
                .font(.headline)
            Text(coverage.headline)
                .font(.subheadline)
                .foregroundStyle(coverage.silent.isEmpty ? Theme.good : .primary)
        }
    }

    private var abstainingLine: some View {
        // The count is derived from the list beside it, never written — a
        // sentence that states a size the code owns is the defect D19 pins.
        Text("\(abstaining.count) "
             + (abstaining.count == 1 ? "card is" : "cards are")
             + " waiting rather than scoring: "
             + abstaining.map(\.title).joined(separator: ", ") + ".")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Closed by default. On a normal night the headline is the whole answer,
    /// and a permanently open list of every instrument would be a status panel
    /// on a tab that is meant to be a glance.
    private var disclosure: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(coverage.instruments) { instrument in
                    row(instrument)
                }
            }
            .padding(.top, 6)
        } label: {
            Text(isExpanded ? "Hide instruments" : "Show each instrument")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
        }
        .tint(Theme.accent)
    }

    private func row(_ instrument: InstrumentReport) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // A filled dot for heard-from, a hollow one for silent. Not a tick
            // and a cross: a silent instrument is not a failure, and a cross
            // would say the reader did something wrong.
            Image(systemName: instrument.reported ? "circle.fill" : "circle")
                .font(.system(size: 8))
                .foregroundStyle(instrument.reported ? Theme.good : .secondary)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(instrument.displayName)
                    .font(.subheadline.weight(.medium))
                Text(instrument.statusSentence)
                    .font(.caption).foregroundStyle(.secondary)
                Text(instrument.coverageSentence)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(instrument.displayName). \(instrument.statusSentence) "
                            + instrument.coverageSentence)
    }
}
