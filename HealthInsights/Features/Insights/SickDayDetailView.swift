import SwiftUI
import Charts
import InsightKit

/// **One day, in full** — backlog `B11-2`, reached from either half of the
/// sick-days section (`SickDaysCalendarSection`, shipped as `B11-1`).
///
/// The reader asked for four things and they are the four sections below:
///
/// 1. **The radar for that day** — `SymptomRadarWebCard`, the same drawing the
///    card shows for today, handed that day's snapshot instead of this
///    morning's.
/// 2. **An AI summary for that day** — phrased on-device from a fact sheet
///    InsightKit builds, with a deterministic sentence underneath it wherever no
///    model exists.
/// 3. **The graph of all contributing data sources** — every watched signal's
///    lean, and every figure any other card worked out that day.
/// 4. **An estimated sickness they can correct** — *"similar to how you can
///    correct a work or travel event (same concept - then we can learn from
///    it)"*.
///
/// ## ⚠️ The estimate is a prompt and the screen says so twice
///
/// `docs/illness-detection-evidence-2026-08-07.md`: prospective positive
/// predictive value for this class of detector is **4–12%**, roughly two-thirds
/// of genuine infections produce no clear physiological signal, and what these
/// systems detect is non-specific systemic strain rather than any illness. So
/// the estimate is rendered as a question with its uncertainty attached — the
/// sentence comes from `IllnessEstimate.uncertainty`, which is a non-optional
/// field precisely so a view cannot forget it — and the correction control sits
/// directly under it rather than behind a disclosure.
///
/// **Nothing on this page scores the reader against the radar in either
/// direction.** A quiet card over a day they were ill is the *ordinary* case,
/// and the fake-sick-day inversion is not computed here or anywhere.
///
/// ## Why the model call cannot block anything
///
/// The summary is produced in a `.task` and rendered when it lands, never
/// awaited on a path that reports work finished — repo rule 11, the defect that
/// cost the reader every card on 2026-08-07. The page is fully usable with the
/// template sentence while the model is thinking.
struct SickDayDetailView: View {
    let day: Date
    /// The replay the caller already holds. Passed in rather than recomputed:
    /// six months of `SymptomRadarModel.history` is one pass, and rebuilding it
    /// per opened day would multiply it by the number of days the reader taps.
    let history: [SymptomRadarModel.DayHistory]

    @Environment(AppModel.self) private var model
    @State private var summary: String?
    @State private var correcting = false

    private var calendar: Calendar { .current }

    private var report: SickDayReport {
        SickDayReport.build(day: day, history: history,
                            derived: model.derivedSeries,
                            symptoms: model.symptoms,
                            sickDays: model.sickDayLedger,
                            sideEffects: model.reportedSideEffects,
                            calendar: calendar)
    }

    private var judgement: IllnessJudgement? {
        model.illnessJudgement(on: day, calendar: calendar)
    }

    var body: some View {
        let report = self.report
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                headline(report)
                summarySection(report)
                radarSection(report)
                contributionsSection(report)
                derivedSection(report)
                reportedSection(report)
                estimateSection(report)
            }
            .padding()
        }
        .navigationTitle(day.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: day) {
            // ⚠️ Never awaited by anything that reports a sync complete — see
            // the type note. The page has already rendered `templateSummary` by
            // the time this starts.
            summary = await DaySummarizer.shared.summarize(report: report)
        }
        .sheet(isPresented: $correcting) {
            IllnessCorrectionSheet(day: day, estimate: report.estimate,
                                   existing: judgement)
        }
    }

    // MARK: - The day, in one line

    @ViewBuilder private func headline(_ report: SickDayReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(phrase(report.status))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    // The day's own score. `—` where nothing was judged, never a
                    // zero and never a green: an unworn night is missing
                    // evidence, not a good morning.
                    Text(report.score.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(report.score.map { Theme.color(forScore: $0) }
                                         ?? Color.secondary)
                }
                if report.history.accumulation.daysRunning > 1 {
                    Text("Day \(report.history.accumulation.daysRunning) of a stretch "
                         + "away from your usual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func phrase(_ status: SymptomRadarStatus?) -> String {
        switch status {
        case .quiet: return "Nothing stirring"
        case .someSigns: return "Some signs"
        case .strongSigns: return "Strong signs"
        case nil: return "Not judged"
        }
    }

    // MARK: - 2. The summary

    @ViewBuilder private func summarySection(_ report: SickDayReport) -> some View {
        InsightSection(
            title: "What this day looked like",
            caveat: .computed(.replayed,
                              "Judged the way this morning was — against the three "
                              + "weeks before it, ending four days before the window "
                              + "it judges. Every number in this sentence comes from "
                              + "that calculation; the phrasing is written on this "
                              + "device and invents nothing.")
        ) {
            // The template is rendered immediately and replaced when the model
            // lands. Never a spinner: a page whose first paragraph is a
            // placeholder is a page that reads as broken while it works.
            Text(summary ?? report.templateSummary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 1. The radar

    @ViewBuilder private func radarSection(_ report: SickDayReport) -> some View {
        InsightSection(
            title: "The radar that day",
            caveat: .computed(.replayed,
                              "The same drawing the card shows for today, handed "
                              + "this day's readings. Movement in the healthy "
                              + "direction sits at the centre, because \"not "
                              + "leaning\" is the claim.")
        ) {
            if let output = report.history.output {
                SymptomRadarWebCard(output: output,
                                    tint: Theme.insightTint(.symptomRadar))
            } else {
                Text("Nothing was judged on this day — either nothing was worn, or "
                     + "there was not enough history behind it to compare against. "
                     + "That is missing evidence, not a quiet day.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 3a. The signals that fed it

    /// **How far each watched signal leaned, and what share of the vote it
    /// carried** — the first half of *"the graph of all contributing data
    /// sources, so they can see how each contributed"*.
    ///
    /// A bar per signal, drawn against `strongZ`, because that is the axis the
    /// radar's own rings use — two drawings of one quantity on one page must not
    /// use two scales. A signal moving the *welcome* way sits at zero rather
    /// than negative: `HealthWatchModel.concern` is one-sided, and a bar chart
    /// showing a credit the score never gave would be drawing a different model.
    @ViewBuilder private func contributionsSection(_ report: SickDayReport) -> some View {
        InsightSection(
            title: "What fed it",
            trailing: report.signals.isEmpty ? nil : "\(report.signals.count) signals",
            caveat: .computed(.estimated,
                              "Each bar is how far that signal sat from your own "
                              + "three-week baseline, in standard deviations, and "
                              + "only in the direction illness pushes it. The share "
                              + "beside it is the weight its vote carried — a signal "
                              + "counted once with its twin carries none.")
        ) {
            if report.signals.isEmpty {
                // A threshold, not a collection size:
                // `HealthWatchModel.output(fromEvaluated:)` returns nil below
                // two surviving channels, because agreement between channels is
                // this card's whole finding and one channel cannot agree with
                // itself. There is no collection here to derive it from.
                // count-in-copy: exempt — structural threshold, see above.
                Text("No signal could be judged on this day. The radar needs at least two channels with three weeks behind them.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                signalChart(report)
                ForEach(report.signals) { row in
                    signalRow(row)
                }
            }
        }
    }

    // substance-shading: exempt — no time axis; one day's departures against
    // that day's own baseline, which is the same exemption
    // `SymptomRadarWebCard` carries for the same drawing.
    private func signalChart(_ report: SickDayReport) -> some View {
        Chart(report.signals) { row in
            BarMark(x: .value("Lean", min(row.lean, HealthWatchModel.strongZ)),
                    y: .value("Signal", row.metric.displayName))
                // ⚠️ **Opacity, never a second hue.** This is one series drawn
                // in the card's own resolved tint (`add-chart`'s per-chart
                // resolution rule); a discounted row is the *same* quantity
                // counted once with its twin, and giving it a colour of its own
                // would read as a different kind of thing.
                .foregroundStyle(Theme.insightTint(.symptomRadar)
                    .opacity(row.isDiscounted ? 0.35 : 0.85))
                .annotation(position: .trailing, alignment: .leading) {
                    Text(String(format: "%.1f", row.lean))
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 0...HealthWatchModel.strongZ)
        .chartXAxis {
            AxisMarks(values: [0, HealthWatchModel.leaningZ, HealthWatchModel.strongZ]) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(report.signals.count) * 26 + 30)
        .accessibilityLabel("How far each watched signal leaned on this day")
    }

    private func signalRow(_ row: SickDayReport.SignalRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.metric.displayName).font(.caption)
                Text("\(MetricValueFormatter.string(row.recent, row.metric)) against "
                     + "\(MetricValueFormatter.string(row.reference, row.metric)) usual")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // "Counted once" must never render as "not looked at" — the same
            // statement the radar's open dot makes.
            Text(row.isDiscounted ? "counted with its twin"
                 : String(format: "%.0f%% of the vote", row.weight * 100))
                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
        }
    }

    // MARK: - 3b. Everything else the app worked out that day

    /// **Every other card's figure, on that day** — the second half of the
    /// contributing-sources ask, and a straight read of
    /// `DerivedSeriesStore.value(_:on:)`, which is specifically the lookup a
    /// consumer must use rather than `latest`.
    @ViewBuilder private func derivedSection(_ report: SickDayReport) -> some View {
        InsightSection(
            title: "What the rest of the app worked out",
            trailing: report.derived.isEmpty ? nil : "\(report.derived.count) figures",
            caveat: .computed(.replayed,
                              "Each of these was computed by another card for this "
                              + "day, and read back for this day rather than taken "
                              + "from the latest one. Nothing here was sensed."),
            expansion: .collapsed(preview: report.derived.isEmpty
                                  ? "Nothing computed for this day"
                                  : "\(report.derived.count) figures from "
                                    + "\(Set(report.derived.map(\.producedBy)).count) cards")
        ) {
            if report.derived.isEmpty {
                Text("No card had worked anything out for this day. Derived figures "
                     + "are filled in by replay, so days before the app was "
                     + "installed can be sparse.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(report.derived) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.spec.displayName).font(.caption)
                            Text(row.producedBy.rawValue)
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(row.spec.string(row.value))
                            .font(.caption.weight(.medium)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - What you recorded

    /// The reader's own records for that day, and the one place on this page
    /// where the app is reading something they said rather than something it
    /// measured. Kept in its own section rather than merged into the bars above
    /// for exactly that reason — a chart drawing both on one axis would assert
    /// they are the same kind of quantity.
    @ViewBuilder private func reportedSection(_ report: SickDayReport) -> some View {
        InsightSection(
            title: "What you recorded",
            caveat: .computed(.none,
                              "Your own records for this day, exactly as you left "
                              + "them. Nothing here was worked out.")
        ) {
            if report.reported.isSpeaking {
                ForEach(report.reported.components) { component in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(component.source.displayName)
                            .font(.caption.weight(.medium))
                        Text(component.detail)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("What you record counts for more here than any of the readings "
                     + "do — they are a proxy for it, and a poor one.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You recorded nothing about this day — no symptom tag, no sick "
                     + "day, nothing beside a dose. That is not evidence you were "
                     + "well; it is the absence of evidence either way.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 4. The estimate, and correcting it

    @ViewBuilder private func estimateSection(_ report: SickDayReport) -> some View {
        let answered = judgement
        InsightSection(
            title: "Were you ill?",
            trailing: answered?.isAnswered == true ? "answered" : nil,
            caveat: .computed(.estimated,
                              "A guess, and a poor one by design. Correcting it is "
                              + "the point: your answer is stored beside the guess "
                              + "rather than over it, so the app can show you how "
                              + "often it was right.")
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(answered?.isAnswered == true ? "You said" : "The app's guess")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text((answered?.effective ?? report.estimate.assessment).summary)
                        .font(.callout.weight(.medium))
                }
                // The app's own guess stays visible after a correction — the
                // reader asked to be able to see the pair, and hiding the guess
                // is how a learning loop stops being auditable.
                if let answered, answered.wasCorrected {
                    HStack {
                        Text("It had guessed").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text(answered.estimate.assessment.summary)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                ForEach(report.estimate.basis, id: \.self) { line in
                    Text("• " + line)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // ⚠️ Never optional and never behind a disclosure — the estimate
                // carries its own uncertainty and this is where it is read.
                Text(report.estimate.uncertainty)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    correcting = true
                } label: {
                    Label(answered?.isAnswered == true ? "Change your answer"
                          : "Tell it what this day was",
                          systemImage: "square.and.pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
