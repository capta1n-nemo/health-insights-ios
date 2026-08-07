import SwiftUI
import InsightKit

/// **Substance Impact's three honest sections** — backlog `S7` and `P16`.
///
/// ## What the reader asked for, and what they got instead
///
/// `P16` asked for three things: score everything currently charted-but-not-
/// scored, a recovery-time section, and a per-substance good-versus-bad
/// section. The middle and last are built here. **The first is deliberately not
/// built**, and that is the reader's own decision rather than a shortfall.
///
/// Independent statistical review of their record refuted the premise the
/// scoring ask rested on: `heartRate`'s apparent stimulant effect fell from
/// 0.91 SD to **0.03** once same-day step count entered the model; three of the
/// four "confirmed" effects were in the welcome direction and two were the same
/// measurement twice (r = 0.912); the permutation null was about twice
/// anti-conservative; Benjamini-Hochberg is invalid under the measured negative
/// dependence (r = −0.795); and the whole finding set flipped on the day
/// boundary — three confirmations at UTC+8, one at UTC, **zero** at UTC−5.
///
/// Shown that, the reader ruled, verbatim and standing: **"Honest version,
/// always!"** So these sections carry per-episode deltas, the named alternative
/// explanation beside every row, **no score**, and the sentence
/// `SubstanceEpisodeReport.ordinaryRun`.
///
/// ## Why there is no chart here
///
/// Not an oversight and not a shading exemption dodge. The reader's real log is
/// 16 events in ~25 days — **four exposure occasions** — and four points drawn
/// as a line is the single most persuasive way to present the thing the review
/// just refuted. Rows carry the readings behind them; a chart would not.
///
/// ⚠️ The per-substance panel **near-duplicates the pooled card** for the reader's
/// stimulant rows, because 15 of their 16 events are stimulants and the pooled
/// card is mostly that same pool. `duplicationNote` says so out loud rather than
/// letting a second look read as a second piece of evidence. Cannabis at n = 1
/// is unattributable by construction and gets the honest empty state.
struct SubstanceEpisodesSection: View {
    @Environment(AppModel.self) private var model

    private var report: SubstanceEpisodeReport.Report {
        SubstanceEpisodeReport.report(events: model.substanceEvents, samples: model.samples)
    }

    var body: some View {
        // Built once per body evaluation and handed down, rather than read from
        // the computed property in each of the three sections — it walks the
        // sample history, and three walks a frame is three times the cost of one.
        let built = report
        if built.substances.isEmpty {
            InsightSection(title: "Occasions", trailing: nil, caveat: .none,
                           expansion: .collapsed(preview: "Nothing logged yet.")) {
                Text("Log something and this shows each occasion on its own — what your readings did around it, what else could explain that, and how long anything took to look ordinary again.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            occasionsSection(built)
            Divider()
            recoverySection(built)
            Divider()
            perSubstanceSection(built)
        }
    }

    // MARK: - S7: the occasion is the unit of evidence

    /// `S7`: *"the logic exists and is tested; nothing shows it to you."* This
    /// is the showing.
    private func occasionsSection(_ report: SubstanceEpisodeReport.Report) -> some View {
        InsightSection(
            title: "Occasions",
            trailing: "\(report.totalOccasions) "
                + SectionCaveat.plural(report.totalOccasions, "occasion"),
            caveat: .computed(.partial, SubstanceEpisodeReport.ordinaryRun
                              + " Each row below is one occasion, not one entry."),
            expansion: .init(startsExpanded: false, preview: occasionPreview(report))
        ) {
            // count-in-copy: exempt — "two exposures of two different things" is
            // the rule being stated (substances never merge), not a count of
            // anything on screen. count-in-copy: exempt
            Text("Three drinks in one evening is **one** occasion. A fortnight later is another. Substances never merge — a stimulant night and an alcohol night are two exposures of two different things, and pooling them would credit one with the other's response.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(report.substances) { substance in
                Divider()
                Text(substance.substance.displayName)
                    .font(.caption.weight(.semibold))
                ForEach(substance.episodes) { episode in
                    occasionRow(episode)
                }
            }
        }
    }

    private func occasionPreview(_ report: SubstanceEpisodeReport.Report) -> String {
        let n = report.totalOccasions
        return "\(n) \(SectionCaveat.plural(n, "occasion")) across "
            + "\(report.substances.count) "
            + SectionCaveat.plural(report.substances.count, "substance")
            + ". The occasion is the unit, not the entry."
    }

    private func occasionRow(_ episode: SubstanceEpisodeReport.Episode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(episode.episode.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                Spacer(minLength: 8)
                Text("\(episode.episode.eventCount) "
                     + SectionCaveat.plural(episode.episode.eventCount, "entry", plural: "entries"))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(episode.shape.displayName)
                .font(.caption2.weight(.medium)).foregroundStyle(Theme.accent)
            Text(episode.shape.explanation)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if episode.deltas.isEmpty {
                Text("No signal had readings both inside and outside this occasion's window, so there is nothing to compare.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(episode.deltas.prefix(4)) { delta in
                    deltaRow(delta)
                }
            }
        }
    }

    /// **One difference, and the thing that would also produce it.**
    ///
    /// The alternative is on the row rather than in a footnote on purpose: a
    /// reader who sees "heart rate up" and has to scroll for "could also be how
    /// much you moved that day" has already believed the first one.
    private func deltaRow(_ delta: SubstanceEpisodeReport.MetricDelta) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(delta.metric.displayName).font(.caption2)
                Spacer(minLength: 8)
                Text(SubstanceResponseAnalyzer.format(delta: delta.delta,
                                                      baseline: delta.cleanMean,
                                                      of: delta.metric))
                    .font(.caption2.weight(.medium)).monospacedDigit()
                Text("· \(delta.duringReadings) vs \(delta.cleanReadings)")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
            if let alternative = delta.alternative {
                Text("could also be \(alternative)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - P16: how long it took to look ordinary again

    /// The reader's recovery question, answered only where it can be.
    ///
    /// A departure of less than one baseline SD is not timed at all — timing a
    /// return from a sub-SD wobble is timing noise — and an occasion whose
    /// readings never came back inside the horizon reports *that*, not a bigger
    /// number.
    private func recoverySection(_ report: SubstanceEpisodeReport.Report) -> some View {
        let timed = report.substances.flatMap { $0.episodes }
            .filter { !$0.recoveries.isEmpty }
        return InsightSection(
            title: "How long it took to settle",
            trailing: timed.compactMap { $0.slowestRecovery?.hoursToBaseline }.max()
                .map { String(format: "up to %.0f h", $0) },
            caveat: .computed(.fitted,
                              "\"Settled\" means a day whose average is back inside one of your own baseline spreads. It is a description of your readings, not a claim about how long anything stays in you."),
            expansion: .collapsed(preview: timed.isEmpty
                ? "Nothing moved far enough from your baseline to time a return from."
                : "\(timed.count) \(SectionCaveat.plural(timed.count, "occasion")) had something to time.")
        ) {
            if timed.isEmpty {
                Text("Nothing has moved more than one of your own baseline spreads around a logged occasion, so there is no departure to time a return from. That is a real answer, not a missing one — a recovery time measured off a smaller wobble would be timing noise.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(timed) { episode in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(episode.episode.substance.displayName
                                 + " · " + episode.shape.displayName)
                                .font(.caption.weight(.medium))
                            Spacer(minLength: 8)
                            Text(episode.episode.start.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(episode.recoveries) { recovery in
                            recoveryRow(recovery)
                        }
                    }
                    Divider()
                }
                Text("A single occasion, several entries close together and a longer stretch are different questions, and they are labelled rather than averaged — a mean recovery time across four occasions of three different shapes would describe none of them.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func recoveryRow(_ recovery: SubstanceEpisodeReport.Recovery) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(recovery.metric.displayName).font(.caption2)
            Spacer(minLength: 8)
            if let hours = recovery.hoursToBaseline {
                Text(String(format: "%.0f h", hours))
                    .font(.caption2.weight(.medium)).monospacedDigit()
            } else {
                Text(String(format: "not back within %.0f h", recovery.observedHours))
                    .font(.caption2).foregroundStyle(Theme.warn)
            }
            Text(String(format: "· from %+.1f SD", recovery.departureZ))
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
    }

    // MARK: - P16: per substance, good and bad

    /// The direction split, per substance — and mostly "not enough to say".
    private func perSubstanceSection(_ report: SubstanceEpisodeReport.Report) -> some View {
        InsightSection(
            title: "Each substance, good and bad",
            trailing: nil,
            caveat: .computed(.partial,
                              "Direction only, and from the most recent occasion that measured each signal rather than an average over occasions — averaging four occasions would manufacture a precision none of them has."),
            expansion: .collapsed(preview: report.isEmptyOfEvidence
                ? SubstanceEpisodeReport.ordinaryRun
                : "What moved which way, per substance.")
        ) {
            ForEach(report.substances) { substance in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(substance.substance.displayName).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text("\(substance.occasions) "
                             + SectionCaveat.plural(substance.occasions, "occasion"))
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(substance.verdict)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if substance.welcome.isEmpty && substance.unwelcome.isEmpty
                        && substance.noBetterEnd.isEmpty {
                        Text(emptyLine(for: substance))
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        directionList("Moved the way you'd want", substance.welcome)
                        directionList("Moved the other way", substance.unwelcome)
                        directionList("No better end either way", substance.noBetterEnd)
                    }
                    if substance.occasions >= 3 {
                        Text(duplicationNote)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
            }
        }
    }

    /// The honest empty state for a substance with an occasion but no paired
    /// readings — the reader's cannabis row, at n = 1.
    private func emptyLine(for substance: SubstanceEpisodeReport.SubstanceReport) -> String {
        substance.occasions == 1
            ? "One occasion, and nothing measured both inside and outside it. There is nothing here to attribute — not a small effect, and not no effect. \(SubstanceEpisodeReport.ordinaryRun)"
            : "Nothing had readings both inside and outside these occasions, so there is nothing to compare yet."
    }

    /// ⚠️ Standing copy. The panel is a second *view* of the pooled card's own
    /// pool, not a second piece of evidence, and a reader seeing the same
    /// direction twice will otherwise count it twice.
    private let duplicationNote =
        "These rows come from the same readings as the card's own comparison above — a second view of one pool, not a second piece of evidence. Seeing a direction here and there is one observation."

    @ViewBuilder
    private func directionList(_ title: String,
                               _ deltas: [SubstanceEpisodeReport.MetricDelta]) -> some View {
        if !deltas.isEmpty {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            ForEach(deltas.prefix(5)) { delta in
                deltaRow(delta)
            }
        }
    }
}
