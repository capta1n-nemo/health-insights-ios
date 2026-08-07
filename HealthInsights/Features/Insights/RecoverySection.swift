import SwiftUI
import InsightKit

/// **How long you take to come back** — backlog §C S6, the reader's request for
/// a recovery tracker on Readiness.
///
/// The section above this draws the trace; this one reads the shape of it. See
/// `RecoveryTracker` for what counts as a dip, what counts as recovered, and the
/// gap rule that decides which episodes are allowed to reach the median.
///
/// ⚠️ **Deliberately not a `Chart`.** The subject is a handful of episodes and
/// their lengths — a list, with the open one first — and the ninety-day line
/// those episodes were read off is already drawn immediately above by "Score
/// over time". A second date axis here would draw the same data twice and pay
/// the chart hazards for it.
///
/// ⚠️ **It renders whatever it found, including nothing.** A recovery tracker
/// that vanishes on a reader who has not dipped is indistinguishable from one
/// that is broken, and "you have not had a bad enough day to count" is a
/// perfectly good answer.
struct RecoverySection: View {
    /// The replayed score history the card already computed for "Score over
    /// time". Empty while that replay is still running.
    let points: [ScorePoint]
    let now: Date

    private var output: RecoveryTracker.Output? {
        RecoveryTracker.evaluate(points)
    }

    var body: some View {
        InsightSection(
            title: "How long you take to come back",
            trailing: output?.typicalDays.map { days in
                days < 1.5 ? "next day" : String(format: "about %.0f days", days)
            },
            caveat: .computed(.replayed,
                              "Read off your replayed score history, so it moves as that does. A dip is a day more than one of your own standard deviations below your typical score, and it counts as over on the first day back at typical — not on the first day back above the dip line, which would report half the real length."),
            expansion: expansion
        ) {
            if let output {
                VStack(alignment: .leading, spacing: 12) {
                    Text(RecoveryTracker.phrase(output))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let open = output.openEpisode {
                        openRow(open, in: output)
                    }
                    let closed = output.episodes.filter { $0.recovered != nil }
                    if !closed.isEmpty {
                        Divider()
                        ForEach(closed) { episode in
                            episodeRow(episode)
                        }
                    }
                    footnote(output)
                }
            } else {
                // The two ways there is nothing to say are different, and the
                // placeholder names which: too little replayed history, or
                // (below) enough history and no dip in it.
                emptyState
            }
        }
    }

    private var expansion: SectionExpansion {
        guard let output else {
            return .collapsed(preview: "Needs about \(RecoveryTracker.minimumPoints) days of scored history")
        }
        return .collapsed(preview: RecoveryTracker.phrase(output))
    }

    // MARK: - Rows

    /// The dip that has not closed. First, and phrased as a fact rather than a
    /// warning: being three days into a dip is information, not an alarm, and
    /// this card does not nag.
    private func openRow(_ episode: RecoveryTracker.Episode,
                         in output: RecoveryTracker.Output) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.down.right.circle")
                .foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Still below your typical day")
                    .font(.subheadline)
                Text("\(daysSince(episode.start)) since it started, low point \(Int(episode.troughScore.rounded())) on \(episode.trough.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func episodeRow(_ episode: RecoveryTracker.Episode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(episode.start, format: .dateTime.day().month(.abbreviated))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(lengthPhrase(episode))
                    .font(.subheadline).monospacedDigit()
                Text("Low point \(Int(episode.troughScore.rounded()))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            // ⚠️ **An unobserved episode is labelled rather than dropped.** Its
            // number is real arithmetic over days nobody watched, and hiding it
            // would make the list look tidier than the evidence is.
            if !episode.isObserved {
                Text("gap")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lengthPhrase(_ episode: RecoveryTracker.Episode) -> String {
        guard let days = episode.days else { return "Still open" }
        if days <= 1 { return "Back the next day" }
        return "\(days) days to come back"
    }

    private func daysSince(_ date: Date) -> String {
        let days = max(0, Int((now.timeIntervalSince(date) / 86_400).rounded()))
        return days == 1 ? "1 day" : "\(days) days"
    }

    // MARK: - What the figure is missing

    @ViewBuilder private func footnote(_ output: RecoveryTracker.Output) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sentence = output.gate?.sentence {
                Text(sentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if output.unobservedEpisodes > 0 {
                Text("\(output.unobservedEpisodes) \(output.unobservedEpisodes == 1 ? "dip" : "dips") had more than \(RecoveryTracker.maximumGapDays) days with no score inside them, so \(output.unobservedEpisodes == 1 ? "it is" : "they are") shown but left out of the figure above — counting days nobody watched would be inventing a recovery.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(String(format: "Measured against your own typical day of %.0f, from %d scored days. A dip starts below %.0f.",
                        output.typical, output.observedDays, output.dipFloor))
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not enough scored history yet")
                .font(.subheadline)
            Text("This needs about \(RecoveryTracker.minimumPoints) days with a readiness score before your typical day and your own spread mean anything — and it is those two, rather than a fixed number, that decide what counts as a dip for you.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
