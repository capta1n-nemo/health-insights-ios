import SwiftUI
import InsightKit

/// **The app grading itself.** Backlog P24, asked for by name.
///
/// ## Why this screen is the feature, not a footnote
///
/// Every card in this app states a number about the reader's body. Almost no
/// consumer health product publishes how often its numbers are right — not
/// because it would be difficult, but because the answer is usually
/// unflattering and nobody makes them. A screen that prints its own error, and
/// prints *"not enough yet"* where that is the true answer, is a thing the
/// reader can check. That is the differentiator, and it only works if it is
/// never quietly improved.
///
/// ## What it refuses to do
///
/// - **No accuracy percentage.** One number cannot separate *precise but
///   useless* from *confident but wrong*, and those are the two failures worth
///   knowing about. See `ModelAccuracy`.
/// - **No figure without its `n`.** An error figure at n = 3 is theatre; the
///   count travels with every sentence.
/// - ⚠️ **No card graded against its own output.** Most rows on this screen say
///   there is nothing to check them against, and that is the honest answer
///   rather than a gap — see `circularity`.
///
/// ## What it does instead of an empty screen
///
/// A permanent null is the useless option, not the safe one. With nothing
/// graded yet the screen still shows a **worked example on invented numbers**,
/// built by the same code that would render the real thing
/// (`ModelAccuracy.workedExample`), so the reader can see what arriving looks
/// like — the device `TelemetryOutboxView` already uses for the sharing
/// payloads.
struct ModelAccuracyView: View {
    @Environment(AppModel.self) private var model

    /// Built once in `.task` rather than in `body`.
    ///
    /// The ledger reads SwiftData for every card's stored score history, and a
    /// `List` body is re-evaluated on every scroll tick — computing it there
    /// would fetch the whole score store dozens of times a second.
    @State private var entries: [ModelAccuracyEntry] = []
    @State private var withheldPairs = 0
    @State private var hasLoaded = false

    var body: some View {
        List {
            premise
            ForEach(AccuracyEvidence.allCases, id: \.self) { group(for: $0) }
            circularity
            workedExample
        }
        .navigationTitle("How right has it been?")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let outcomes = model.dataStore.loadPredictionOutcomes()
        let verdicts = model.dataStore.loadFeedback().map { (insight: $0.insight, rating: $0.rating) }
        var titles: [InsightID: String] = [:]
        for insight in model.engine.models { titles[insight.id] = insight.title }
        var scored: [InsightID: Int] = [:]
        // `storedScoreHistory`, never `scoreHistory(for:)` — the latter is a
        // lazy view cache that answers `[]` until a card's chart has been drawn,
        // which would report every card as never scored. Same trap the export
        // fell into on 2026-08-07.
        for id in InsightID.allCases { scored[id] = model.storedScoreHistory(for: id).count }
        entries = ModelAccuracy.ledger(outcomes: outcomes, verdicts: verdicts,
                                       scoredDays: scored, titles: titles)
        withheldPairs = outcomes.filter { !ModelAccuracy.admits($0) }.count
    }

    // MARK: - The premise

    private var premise: some View {
        Section {
            Text("Most health apps tell you what they think and never tell you how often they were right. This one checks itself — against measurements it did not produce — and says **not enough yet** wherever that is the true answer.")
                .font(.subheadline)
            Text("No single accuracy percentage appears anywhere here. A model can be precise and useless, or confident and wrong, and one number cannot tell those apart. Every figure below carries the number of checks it rests on.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - The three kinds of evidence

    @ViewBuilder
    private func group(for evidence: AccuracyEvidence) -> some View {
        let rows = entries.filter { $0.evidence == evidence }
        Section {
            if rows.isEmpty {
                emptyRow(for: evidence)
            } else {
                ForEach(rows) { row(for: $0) }
            }
        } header: {
            Text(evidence.heading)
        } footer: {
            Text(footer(for: evidence)).font(.caption)
        }
    }

    /// ⚠️ **A section with nothing in it still appears and still says what it is
    /// waiting for.** The reader's rule from 2026-08-07 is that no card is
    /// hidden for want of data and the obligation moves to the empty state; the
    /// same reasoning applies to a whole section, which is more likely to be
    /// mistaken for "this app has nothing like that" if it simply vanishes.
    @ViewBuilder
    private func emptyRow(for evidence: AccuracyEvidence) -> some View {
        switch evidence {
        case .externalTruth:
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing checked yet.").font(.subheadline)
                Text("One card here can be checked today: the blood-pressure estimate. Log a cuff reading after the app has estimated one and the pair is recorded automatically — the app's guess, your measurement, and the date. Five pairs and this can say how far out it typically is.")
                    .font(.caption).foregroundStyle(.secondary)
                CoverageGateNotice(gate: CoverageGate(
                    need: CalibrationReport.minimumForTypicalError, have: 0,
                    unit: "cuff reading logged after an estimate",
                    unlocks: "this can say how far out the estimate typically is"))
            }
        case .readerVerdict:
            Text("You have not rated any card yet. The thumbs on a card's detail screen collect here — that is your verdict on it, which is a different thing from its accuracy and is labelled as such.")
                .font(.subheadline).foregroundStyle(.secondary)
        case .selfDefined:
            Text("Every card has something checking it. That is not a state this app expects to reach.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func footer(for evidence: AccuracyEvidence) -> String {
        switch evidence {
        case .externalTruth:
            return "Each of these was checked against a measurement this app did not produce — a cuff, a scale, a tape. That is the only kind of check that can support an error figure."
        case .readerVerdict:
            return "Your thumbs are evidence about whether a card is useful. They are not evidence about whether it is right: you are more likely to tap when something surprises you, so this is a self-selected sample of your own impressions. It is never called a hit rate."
        case .selfDefined:
            return "These cards score you, and nothing outside the app measures the same thing, so there is no honest error figure to print. They may still be good — there is simply nothing here that could tell you, and inventing a check would be worse than saying so."
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for entry: ModelAccuracyEntry) -> some View {
        switch entry.evidence {
        case .externalTruth:
            ForEach(entry.reports) { report in
                NavigationLink {
                    ModelAccuracyReportView(title: entry.title, report: report)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(entry.title) · \(report.metric.displayName)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("n = \(report.n)").font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(report.sentence)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .readerVerdict:
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.subheadline.weight(.medium))
                if let agreement = entry.verdicts.agreement {
                    Text(String(format: "You called it accurate %.0f%% of the time, over %d ratings. Your verdict, not its accuracy.",
                                agreement * 100, entry.verdicts.total))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(entry.verdicts.accurate) accurate · \(entry.verdicts.inaccurate) not")
                        .font(.caption).foregroundStyle(.secondary)
                    CoverageGateNotice(gate: entry.verdicts.gate)
                }
            }
        case .selfDefined:
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(.subheadline)
                Spacer()
                // The count is context and is labelled as context. A card can be
                // scored every day for a year with nothing checking any of it,
                // and that is exactly what this row says.
                Text(entry.scoredDays > 0
                     ? "\(entry.scoredDays) days scored, none checked"
                     : "not scored yet")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - ⚠️ Marking its own homework

    /// The hazard, named on the screen and not only in the code.
    ///
    /// The reader is entitled to ask why eighteen of twenty rows say "nothing to
    /// check it against" when the app clearly stores a score for every card
    /// every day. The answer is that grading those scores against each other
    /// would produce a number and the number would be worthless, and saying so
    /// is more trustworthy than quietly not doing it.
    private var circularity: some View {
        Section {
            Text("This app stores a score for each card every day, so it would be easy to \"grade\" Monday's prediction against Thursday's score and print a confident figure. It would mean nothing: the model would be marking its own homework.")
                .font(.subheadline)
            Text("So a check only counts when the truth came from an instrument this app does not own — a blood-pressure cuff, a scale, a tape measure. Another company's estimate does not count either: comparing this model against their model is a comparison, not a measurement.")
                .font(.caption).foregroundStyle(.secondary)
            if withheldPairs > 0 {
                Label("\(withheldPairs) recorded pair\(withheldPairs == 1 ? " is" : "s are") being held back for that reason, and \(withheldPairs == 1 ? "is" : "are") not counted in anything above.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Why most of this list says \"nothing to check it against\"")
        }
    }

    // MARK: - What arriving looks like

    /// ⚠️ **Invented numbers, and it says so three times** — here, in the row's
    /// own subtitle, and in a banner at the top of the screen it opens.
    private var workedExample: some View {
        Section {
            NavigationLink {
                ModelAccuracyReportView(title: "A worked example",
                                        report: ModelAccuracy.workedExample(),
                                        isWorkedExample: true)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label("How to read these numbers", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.medium))
                    Text("A made-up card with twelve checks behind it — small errors, an obvious lean, and barely better than assuming nothing changed. Not your data.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            Text("The example is drawn by the same code that draws the real thing, so what this screen promises cannot drift from what it would actually print.")
                .font(.caption)
        }
    }
}

// MARK: - One card's record, in full

/// **Prediction against truth, over time, with every figure's `n` beside it.**
///
/// The layering is deliberate and is the honest part: the individual pairs are
/// facts and are always shown; the summaries are withheld until there are enough
/// of them, and each withheld figure is replaced by a `CoverageGate` sentence
/// saying how many more are needed and what they buy — never by a blank.
struct ModelAccuracyReportView: View {
    let title: String
    let report: CalibrationReport
    var isWorkedExample: Bool = false

    var body: some View {
        List {
            if isWorkedExample { inventedBanner }
            headline
            chartSection
            figures
            pairsSection
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inventedBanner: some View {
        Section {
            Label("Every number on this screen is invented. It is not your data and never will be — it is here so you can see what this looks like once there is something to show.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: some View {
        Section {
            Text(report.sentence)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let warning = report.comparabilityWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(report.metric.displayName)
        }
    }

    private var chartSection: some View {
        Section {
            PredictionVersusActualChart(report: report)
                .padding(.vertical, 4)
            Text(SubstanceShading.caption)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            Text("The dashed line is what the app said; the solid line is what was measured. The grey rule between them is the miss. There is no trend line: \"is it getting better?\" cannot be answered honestly from this many checks, so nothing here implies an answer.")
                .font(.caption)
        }
    }

    // MARK: The three separable questions

    private var figures: some View {
        Section {
            figureRow("Checks behind this", "\(report.n)")
            if let window = windowLabel { figureRow("Over", window) }

            if let typical = report.typicalError {
                figureRow("Typically out by", String(format: "%.1f %@", typical, report.unit))
                if let worst = report.worstError {
                    figureRow("Worst miss", String(format: "%.1f %@", worst, report.unit))
                }
            } else {
                CoverageGateNotice(gate: report.typicalErrorGate)
            }

            if let bias = report.bias, report.biasIsBeyondChance {
                figureRow("Leans", String(format: "%.1f %@ too %@", abs(bias), report.unit,
                                          bias > 0 ? "high" : "low"))
                if let scatter = report.scatterAroundBias {
                    figureRow("Scatter around that", String(format: "±%.1f %@", scatter, report.unit))
                }
            } else if report.n >= CalibrationReport.minimumForBias {
                figureRow("Leans", "no detectable lean")
            } else {
                CoverageGateNotice(gate: report.biasGate)
            }

            if let skill = report.persistenceSkill, let baseline = report.persistenceBaselineError {
                figureRow("Versus assuming no change",
                          String(format: "%@%.0f%%", skill > 0 ? "+" : "", skill * 100))
                figureRow("(your readings move)", String(format: "%.1f %@ between checks",
                                                         baseline, report.unit))
            } else {
                CoverageGateNotice(gate: report.skillGate)
            }
        } header: {
            Text("How far out, which way, and does it beat doing nothing")
        } footer: {
            Text("These are three different questions and one percentage cannot answer them. A model can be out by very little on a quantity that barely moves — precise, and no better than assuming you are the same as last time. A model that misses in the same direction every time is not noisy, it is off by a fixed amount, and that is something somebody can go and fix.")
                .font(.caption)
        }
    }

    private var windowLabel: String? {
        guard let first = report.firstAt, let last = report.lastAt else { return nil }
        return "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    private func figureRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    /// **The facts, always.** Three pairs support no summary at all, but they are
    /// still three things that happened, and showing them is what makes every
    /// figure above checkable by hand.
    private var pairsSection: some View {
        Section {
            ForEach(report.pairs.reversed()) { pair in
                HStack(alignment: .firstTextBaseline) {
                    Text(pair.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "said %.0f · was %.0f", pair.predicted, pair.actual))
                        .font(.caption.monospacedDigit())
                    Text(String(format: "%+.0f", pair.signedError))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(abs(pair.signedError) > (report.typicalError ?? .infinity)
                                         ? Theme.warn : .secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        } header: {
            Text("Every check, newest first")
        } footer: {
            Text("Each row is one thing that happened: what the app said, what was then measured, and the difference. Every figure on this screen is computed from these and nothing else.")
                .font(.caption)
        }
    }
}
