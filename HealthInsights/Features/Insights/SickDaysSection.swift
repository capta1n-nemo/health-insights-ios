import SwiftUI
import Charts
import InsightKit

/// **When this card spoke, how a finding builds, and how many days you actually
/// recorded being ill** — the symptom radar's §B11 section, carrying backlog
/// `S4` (flagged days over time) and `S3` (the "nights to flag" sheet).
///
/// ## Why the three sit together
///
/// The radar's own report card already prints *how often* it spoke. What it has
/// never shown is **when**, and the reader asked for exactly that: *"flagged
/// days over time — when sickness was flagged and how it builds"*. "How it
/// builds" is the second line on the chart — the accumulation, which is what
/// answers their earlier complaint that a correct flag evaporated overnight —
/// and the sheet answers the obvious next question, which is how long a
/// departure has to last before this card says anything at all.
///
/// ## ⚠️ The comparison this section deliberately does not make
///
/// It shows the reader's recorded sick days as a **count**, next to a chart of
/// the radar's flags, and it does **not** draw them on the same axis or score
/// the agreement between them. That restraint is the whole point, and
/// `docs/illness-detection-evidence-2026-08-07.md` is why: prospective positive
/// predictive value for this class of detector is **4–12%**, and roughly
/// **two-thirds of genuine infections produce no clear physiological signal at
/// all**. So a quiet radar over a day the reader was ill is the *ordinary* case,
/// not a discrepancy — and rendering the two series against each other invites a
/// reading the evidence does not support, in the one direction this app must
/// never err. The copy under the count says so in the reader's own terms rather
/// than leaving them to infer it.
///
/// (§B11's fake-sick-day inversion — flagging recorded sick days that the radar
/// did not corroborate — is gated on a decision the reader has not made, and
/// nothing here computes it.)
struct SickDaysSection: View {
    @Environment(AppModel.self) private var model
    @State private var showingLatency = false
    @State private var scrubbed: Date?

    private var history: [SymptomRadarModel.DayHistory] {
        model.memoized("radarHistory") {
            SymptomRadarModel.history(over: SymptomRadarModel.timeline(
                samples: model.samples, days: SymptomRadarModel.historyDays,
                endingAt: Date(), calendar: .current))
        }
    }

    var body: some View {
        InsightSection(
            title: "When it has spoken",
            trailing: flaggedCount.map { "\($0) days" },
            caveat: .computed(.estimated,
                              "Every day here was judged the same way this morning was — "
                              + "against the three weeks before it, ending four days "
                              + "before the window it is judging. Days nothing was worn "
                              + "are gaps, not quiet days."),
            // Closed on arrival — the radar web above it is the card's picture,
            // and six months of history is a thing you go looking for. The
            // preview is required rather than optional for a collapsed section:
            // a closed section showing only its title is a locked door.
            expansion: .collapsed(preview: previewLine)
        ) {
            RadarHistoryChart(history: history, selection: $scrubbed)
            legend
            Divider()
            sickDayCount
            Button {
                showingLatency = true
            } label: {
                Label("How long before it notices", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .sheet(isPresented: $showingLatency) {
            NightsToFlagDetail()
        }
    }

    /// What the closed section says about itself.
    ///
    /// ⚠️ Never gated on the history being non-empty — the section, its title
    /// and its preview are unconditional, and only the figures inside are
    /// optional (`add-chart` §9b). A card whose sections appear and disappear as
    /// data arrives changes height under the reader's finger.
    private var previewLine: String {
        let judged = history.filter { $0.output != nil }.count
        guard judged > 0 else { return "Nothing judged yet" }
        let flagged = flaggedCount ?? 0
        return "\(flagged) of \(judged) days judged"
    }

    /// Judged days on which the card was not quiet, over the chart's span.
    private var flaggedCount: Int? {
        let judged = history.filter { $0.output != nil }
        guard !judged.isEmpty else { return nil }
        return judged.filter(\.isFlagged).count
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendSwatch(Theme.accent, "That morning")
            legendSwatch(Color.secondary, "With memory")
            Spacer()
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func legendSwatch(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(colour).frame(width: 12, height: 3)
            Text(label)
        }
    }

    /// The reader's own record, as a number and nothing more — see the type note
    /// on why it is not drawn against the chart above it.
    @ViewBuilder private var sickDayCount: some View {
        let ledger = model.sickDayLedger
        let end = Date()
        let start = Calendar.current.date(byAdding: .year, value: -1, to: end) ?? end
        let days = ledger.dayCount(in: DateInterval(start: start, end: end))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Days you recorded being ill").font(.caption)
                Spacer()
                Text(days == 0 ? "none in the last year" : "\(days) in the last year")
                    .font(.caption.weight(.medium)).monospacedDigit()
            }
            Text("This card does not check itself against those days, in either "
                 + "direction. About two-thirds of real infections never produce a "
                 + "clear change in overnight vitals, so a quiet card on a day you "
                 + "were genuinely ill is the ordinary case — and it is not evidence "
                 + "of anything about you.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - R28: the two symptom records, side by side

/// **What you logged by hand, against what Health already knew** — backlog
/// `R28`, on the symptom radar's card because that is the card the gap is about.
///
/// The radar grades itself against Apple Health tags and nothing else. A reader
/// who types their side effects into a medication tracker instead has a second
/// record the ledger has never been able to see — so a hit rate built from one
/// of two logs has been quietly reading half the evidence. This section is the
/// other half made visible.
///
/// Every figure comes from `SymptomReconciliation` in InsightKit, where the
/// join, the grade mapping and the dispute threshold are tested. **The section
/// never picks a winner**: two records made by the same person on the same day
/// for different purposes do not have one true value between them, and the note
/// on a disputed row says so in as many words.
struct SymptomReconciliationSection: View {
    @Environment(AppModel.self) private var model

    private var logged: [SymptomReconciliation.LoggedEffect] {
        model.sideEffects.map {
            .init(name: $0.name, severity: $0.severity, date: $0.date)
        }
    }

    private var summary: SymptomReconciliation.Summary {
        SymptomReconciliation.summary(symptoms: model.symptoms, sideEffects: logged)
    }

    var body: some View {
        // Nothing to reconcile with one empty side: this is a comparison, and a
        // comparison against nothing is not an empty state, it is a section that
        // does not apply yet.
        if !logged.isEmpty || !model.symptoms.isEmpty {
            let counts = summary
            InsightSection(
                title: "Your two symptom records",
                trailing: counts.alsoInHealth.map { String(format: "%.0f%% in both", $0 * 100) },
                caveat: .computed(.estimated,
                                  "Matched by day and by name. A 1–10 severity is read "
                                  + "as mild, moderate or severe in thirds — a stated "
                                  + "assumption, not a validated scale — so only grades "
                                  + "more than one step apart are called a disagreement."),
                expansion: .collapsed(preview: preview(counts))
            ) {
                row("Recorded in both", counts.both,
                    "The strongest record you have.")
                row("Only with your medication", counts.handOnly,
                    "Nothing on this card reads these — its ledger looks at Health tags alone.")
                row("Only in Health", counts.healthOnly,
                    "Usually the ones you did not read as a dose reaction.")
                if counts.disputed > 0 {
                    row("Graded differently", counts.disputed,
                        "Both are yours. This app cannot tell which you meant, and does not guess.")
                }
                if counts.unmatchedNames > 0 {
                    row("Names it could not match", counts.unmatchedNames,
                        "Written in words this app has no symptom for, so nothing here reads them. They are still in your data.")
                }
            }
        }
    }

    private func preview(_ counts: SymptomReconciliation.Summary) -> String {
        let hand = counts.both + counts.handOnly
        guard hand > 0 else { return "\(counts.healthOnly) tagged in Health only" }
        return "\(counts.both) of \(hand) also tagged in Health"
    }

    private func row(_ label: String, _ value: Int, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text("\(value)").font(.caption.weight(.medium)).monospacedDigit()
            }
            Text(detail)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - S4: the chart

/// **Flagged days over time, and the accumulation building behind them.**
///
/// Wraps `ScrollableMetricChart`, so pan, zoom, scrub, the substance shading and
/// the jump-to-nearest-data chevrons all arrive without a line here — the rule
/// in `add-chart` §1, §9a and §9b.
///
/// Two series on one 0–100 axis, which is honest only because the model puts
/// them there itself: `SymptomRadarModel.Accumulation.excess` exists precisely so
/// the accumulated statistic can be rendered by the same score curve as a single
/// day's, and the card already reports whichever of the two says more. Both are
/// **solid** — each is computed from measurements rather than inferred, and dash
/// in this app means "not measured" and nothing else.
private struct RadarHistoryChart: View {
    let history: [SymptomRadarModel.DayHistory]
    @Binding var selection: Date?

    /// One drawable point. Flattened out of `DayHistory` so the chart's `ForEach`
    /// runs over a plain `Identifiable` — the construction this repo has verified
    /// against the `Chart3DContent` overload.
    private struct Point: Identifiable {
        let id: String
        let day: Date
        /// What the card said that morning on the day alone.
        let daily: Double
        /// What the accumulation alone was worth on the same curve.
        let memory: Double
        let run: Int
        let isFlagged: Bool
    }

    private var points: [Point] {
        // Runs of consecutive judged days, so no line crosses a stretch nothing
        // was worn. The split is `SymptomRadarModel.runs`, in InsightKit, where
        // it is tested — not a loop in a view.
        SymptomRadarModel.runs(of: history).enumerated().flatMap { index, run in
            run.map { row in
                Point(id: "\(index)-\(row.day.timeIntervalSince1970)",
                      day: row.day,
                      daily: row.output?.score ?? 100,
                      memory: HealthWatchModel.score(excess: row.accumulation.excess),
                      run: index,
                      isFlagged: row.isFlagged)
            }
        }
    }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.day, let last = points.last?.day,
              first <= last else { return nil }
        return first...last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            ScrollableMetricChart(
                dataSpan: span,
                // Six weeks on screen out of six months of history: a day is
                // the unit here, and a year squeezed into a phone's width makes
                // every episode one pixel wide.
                window: 42 * 86_400,
                selection: $selection,
                height: 150,
                emptyMessage: "Nothing judged in the period on screen. Swipe sideways, or tap the arrows at the edges to jump to the nearest days this card could read.",
                isEmpty: { range in !points.contains { range.contains($0.day) } },
                // Fixed 0–100, never fitted: a score is a score, and rescaling
                // per window would make a two-point wobble look like an
                // illness.
                yDomain: { _ in 0...100 }
            ) { range in
                marks(points.filter { range.contains($0.day) })
            }
        }
    }

    @ViewBuilder private var readout: some View {
        if let selection, let hit = nearest(to: selection) {
            HStack(spacing: 8) {
                Circle().fill(Theme.color(forScore: hit.daily)).frame(width: 7, height: 7)
                Text("\(Int(hit.daily.rounded()))")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.day.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                if hit.memory < 99.5 {
                    Text("· carried \(Int(hit.memory.rounded()))")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            // A blank line of the same height, so scrubbing cannot change the
            // content height under the finger — `add-chart` §9b.
            Text(" ").font(.caption2)
        }
    }

    private func nearest(to date: Date) -> Point? {
        points.min {
            abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date))
        }
    }

    /// Explicit `some ChartContent`, as every mark builder in this app must
    /// have: without it the chain can resolve to 3D chart content on this SDK
    /// and silently drop `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private func marks(_ visible: [Point]) -> some ChartContent {
        areaMarks(visible)
        bandMarks
        memoryMarks(visible)
        dailyMarks(visible)
    }

    /// The band-coloured fill under the day's own score.
    ///
    /// Anchored to the highest score on screen rather than to 100, because a
    /// gradient resolves against the filled shape's own bounding box — passing
    /// 100 squeezes the whole ramp into whatever height the data reaches. See
    /// `Theme.scoreFill` and `add-chart` §7.
    @ChartContentBuilder
    private func areaMarks(_ visible: [Point]) -> some ChartContent {
        let peak = visible.map(\.daily).max() ?? 100
        ForEach(visible) { point in
            AreaMark(x: .value("Day", point.day), y: .value("Score", point.daily),
                     series: .value("Run", point.run))
                .foregroundStyle(Theme.scoreFill(peak: peak))
                .interpolationMethod(.linear)
        }
    }

    /// The card's own band edges, so 85 on the chart means the same thing as
    /// "nothing stirring" on the card.
    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        ForEach([50.0, 85.0], id: \.self) { level in
            RuleMark(y: .value("Band", level))
                .foregroundStyle(Color.secondary.opacity(0.18))
                .lineStyle(Theme.referenceStroke)
        }
    }

    /// What the accumulation alone was worth — the "how it builds" half.
    @ChartContentBuilder
    private func memoryMarks(_ visible: [Point]) -> some ChartContent {
        ForEach(visible) { point in
            LineMark(x: .value("Day", point.day), y: .value("Carried", point.memory),
                     series: .value("Carried run", "m\(point.run)"))
                .foregroundStyle(Color.secondary.opacity(0.55))
                .interpolationMethod(.linear)
        }
    }

    /// The day's own verdict, and a dot on the days the card was not quiet.
    @ChartContentBuilder
    private func dailyMarks(_ visible: [Point]) -> some ChartContent {
        ForEach(visible) { point in
            LineMark(x: .value("Day", point.day), y: .value("Score", point.daily),
                     series: .value("Run", point.run))
                .foregroundStyle(Theme.accent)
                // Straight segments: a curve would invent scores for mornings
                // that were never judged.
                .interpolationMethod(.linear)
        }
        ForEach(visible.filter(\.isFlagged)) { point in
            PointMark(x: .value("Day", point.day), y: .value("Score", point.daily))
                .foregroundStyle(Theme.color(forScore: point.daily))
                .symbolSize(26)
        }
    }
}

// MARK: - S3: nights to flag

/// **How long a departure has to last before this card says anything** — backlog
/// `S3`, *"slides up, slides back down"*.
///
/// Every figure is `SymptomRadarModel.nightsToFlag(atDailyExcess:)`, which is the
/// accumulation's own arithmetic and nothing else: while the body sits a given
/// distance past ordinary, each night adds that distance minus the daily
/// allowance, and the accumulation is a finding when it reaches the decision
/// interval. Nothing here is a constant somebody typed — change the allowance or
/// the interval and this sheet changes with them.
///
/// ⚠️ **Latency is not accuracy, and the sheet has to say so.** How quickly this
/// card notices a departure is a different question from how often a departure
/// means illness, and the second is the one the literature answers badly:
/// prospective positive predictive value of 4–12%
/// (`docs/illness-detection-evidence-2026-08-07.md`). A sheet of small numbers
/// reads as precision, so the closing paragraph is not optional decoration.
/// ⚠️ **Named `…Detail`, never `…Sheet`, and that is a rule rather than taste.**
/// `verify.sh` requires every view under `Features/` whose name ends in `Sheet`
/// to be openable from `AddDataView`'s master input list, because the defect
/// that rule closed was an *input* surface no list knew about. This takes
/// nothing from the reader — it is a read-only explanation — so it must not
/// claim a name reserved for things that do.
private struct NightsToFlagDetail: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SymptomRadarModel.flagLatencyExcesses, id: \.self) { excess in
                        HStack {
                            Text(String(format: "%.1f SD past your normal", excess))
                            Spacer()
                            Text(SymptomRadarModel.nightsToFlag(atDailyExcess: excess)
                                    .map { "about \($0) night\($0 == 1 ? "" : "s")" }
                                 ?? "never")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("If it stayed there every night")
                } footer: {
                    Text("The card keeps a running total of how far past ordinary each night sits, minus an allowance of \(SymptomRadarModel.Memory.allowance, format: .number) so ordinary nights pull it back down. It becomes a finding at \(SymptomRadarModel.Memory.decisionInterval, format: .number). That is all these numbers are — the arithmetic, not a promise about your body.")
                }

                Section {
                    Text("A departure at or under the allowance never accumulates at all, however long it lasts. That is deliberate: a detector that eventually flags everything has stopped saying anything.")
                    Text("Real nights vary, so treat these as the middle of a spread rather than a countdown. A simulation of the same arithmetic with ordinary night-to-night noise lands within a night of each figure.")
                } header: {
                    Text("What these numbers are not")
                }

                Section {
                    Text("How quickly this card notices something is a different question from how often what it notices is an illness — and the published evidence on the second is not encouraging. In studies that ran detectors like this one forward in real time against a real test, between 4 and 12 in every 100 alerts were confirmed infections.")
                    Text("It also cuts the other way: about two-thirds of genuine infections never produce a clear change in these signals at all. A quiet card is not an all-clear, and a fast one is not a diagnosis.")
                } footer: {
                    Text("Sources are summarised in this project's illness-detection evidence note.")
                }
            }
            .navigationTitle("Nights to flag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // "Slides up, slides back down" — a detent sheet rather than a push, so
        // it leaves the card exactly where the reader left it.
        .presentationDetents([.medium, .large])
    }
}
