import SwiftUI
import InsightKit

struct InsightDetailView: View {
    let insightID: InsightID
    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?
    @State private var feedbackGiven = false
    @State private var timeframe: Timeframe = .month
    @State private var scale: SeriesScale = .zScore
    @State private var logarithmic = false

    /// Resolved against the data being charted, so `.all` doesn't squash a short
    /// history into a sliver of a decade-wide viewport.
    private func window(spanning span: ClosedRange<Date>?) -> TimeInterval {
        timeframe.chartWindow(spanning: span.map { $0.upperBound.timeIntervalSince($0.lowerBound) })
    }

    private var result: InsightResult? { model.result(for: insightID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let result {
                    headerCard(result)
                    if insightID == .heartAge {
                        ageComparisonCard
                    }
                    if !result.unmetRequirements.isEmpty {
                        requirementsCard(result)
                    }
                    if !result.drivers.isEmpty {
                        driversCard(result)
                    }
                    if insightID == .bloodPressure {
                        bloodPressureLogLink
                    }
                    scoreHistoryCard
                    contributorsCard(result)
                    patternsCard(result)
                    contributorLinksCard(result)
                    feedbackCard(result)
                    disclaimerCard
                } else {
                    ContentUnavailableView("Not available", systemImage: "questionmark")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(result?.title ?? "Insight")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $groundingKind) { GroundingSheet(kind: $0) }
    }

    private func headerCard(_ result: InsightResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let score = result.score {
                        ScoreDial(score: score, label: result.headline, size: 96)
                    } else {
                        VStack(alignment: .leading) {
                            Text(result.headline).font(.largeTitle.weight(.bold))
                        }
                    }
                    Spacer()
                    ConfidenceBadge(confidence: result.confidence)
                }
                Text(result.explanation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requirementsCard(_ result: InsightResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Add these for a better estimate", systemImage: "exclamationmark.circle")
                    .font(.headline)
                ForEach(result.unmetRequirements) { req in
                    Button { groundingKind = req.kind } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(req.kind.displayName).font(.subheadline)
                                Text(req.rationale).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    /// Three ages side by side. The whole point of this insight is the gap
    /// between them, which a number buried in a sentence doesn't convey.
    @ViewBuilder private var ageComparisonCard: some View {
        let analysis = HeartAgeInsight().analyse(samples: model.samples,
                                                 profile: model.profile, now: Date())
        if analysis.heart != nil || analysis.fitness != nil {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How old are you behaving?").font(.headline)
                    HStack(alignment: .top, spacing: 0) {
                        ageColumn("You", value: analysis.chronologicalAge, tint: .primary)
                        if let heart = analysis.heart, let heartAge = heart.heartAge {
                            Divider().frame(height: 44)
                            ageColumn("Heart", value: heartAge,
                                      tint: Self.tint(excessYears: heart.excessYears ?? 0))
                        }
                        if let fitness = analysis.fitness {
                            Divider().frame(height: 44)
                            ageColumn("Fitness", value: fitness.fitnessAge,
                                      tint: Self.tint(excessYears: -(fitness.yearsYounger ?? 0)))
                        }
                    }
                    Text("Heart age comes from the risk equations, fitness age from your VO₂max against age norms. They can disagree — a fit heart can still carry high blood pressure.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func ageColumn(_ label: String, value: Double?, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Years ahead of your real age, coloured the way the rest of the app does:
    /// behind your years is good, well ahead needs attention.
    private static func tint(excessYears: Double) -> Color {
        if excessYears >= 3 { return Theme.bad }
        if excessYears <= -3 { return Theme.good }
        return Theme.warn
    }

    private func driversCard(_ result: InsightResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's driving this").font(.headline)
                ForEach(result.drivers, id: \.self) { d in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 6)
                            .foregroundStyle(Theme.accent)
                        Text(d).font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Score over time

    /// How this insight's own number has moved. Part reconstructed from the raw
    /// samples, part read back from what the app recorded on the day — see
    /// `ScoreHistory`. Absent for insights that don't produce a score (substance
    /// impact reports a load figure, not a 0–100).
    @ViewBuilder private var scoreHistoryCard: some View {
        let history = model.scoreHistory(for: insightID)
        if history.count >= 2 {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Score over time").font(.headline)
                        Spacer()
                        Text(trendPhrase(history)).font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Timeframe", selection: $timeframe) {
                        ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ScoreHistoryChart(points: history, window: window(spanning: scoreSpan(history)))
                    Text("Days before you had at least two signals recording aren't shown — a score resting on one measurement isn't one.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func scoreSpan(_ history: [ScorePoint]) -> ClosedRange<Date>? {
        guard let first = history.first?.date, let last = history.last?.date,
              first <= last else { return nil }
        return first...last
    }

    /// Direction over the window, stated only when the slope is big enough to be
    /// one. A tenth of a point a week is not a trend.
    private func trendPhrase(_ history: [ScorePoint]) -> String {
        guard let perWeek = history.trendPerWeek, abs(perWeek) >= 0.5 else {
            return "Holding steady"
        }
        return String(format: "%@ %.1f a week", perWeek > 0 ? "↑" : "↓", abs(perWeek))
    }

    // MARK: - What goes into it

    /// Every metric behind the score, standardised onto one axis.
    ///
    /// The series come from `result.contributors`, which the scoring code emits
    /// as it builds each component — so adding an input to a score adds a line
    /// here with no edit to this file. Where a model doesn't yet report its
    /// components, its declared `candidateMetrics` stand in.
    @ViewBuilder private func contributorsCard(_ result: InsightResult) -> some View {
        let contributions = resolvedContributions(result)
        let series = model.overlaySeries(for: insightID, contributions: contributions,
                                         timeframe: timeframe)
        if !series.isEmpty {
            let missing = contributions.metrics.filter { metric in
                !series.contains { $0.metric == metric }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What goes into this").font(.headline)
                    Text(scale == .zScore
                         ? "Each signal against its own normal for this period, so they can be read against each other. The dashed line is your average."
                         : "Measured values, in their own units. Signals with very different ranges will look flat next to each other — that's what the compare view is for.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Scale", selection: $scale) {
                        ForEach(SeriesScale.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    MetricOverlayChart(
                        series: series, scale: scale, logarithmic: logarithmic,
                        window: window(spanning: model.overlayRange(for: contributions.metrics,
                                                                    timeframe: timeframe)))

                    if scale == .raw && series.supportsLogScale {
                        Toggle("Logarithmic axis", isOn: $logarithmic)
                            .font(.caption)
                    }

                    Divider()
                    MetricOverlayLegend(series: series, contributions: contributions,
                                        missing: missing)
                }
            }
        }
    }

    /// Contributions to chart: what the model reported, or its declared inputs
    /// where it doesn't report yet. Without the fallback, an insight that hasn't
    /// been migrated would show an empty card rather than a chart.
    private func resolvedContributions(_ result: InsightResult) -> [MetricContribution] {
        if !result.contributors.isEmpty { return result.contributors }
        return candidateMetrics(for: insightID).map {
            MetricContribution(metric: $0, higherIsBetter: nil, weight: 0, detail: "")
        }
    }

    private func candidateMetrics(for id: InsightID) -> [MetricType] {
        // Not named `model` — that's the AppModel in this scope, and shadowing it
        // here has bitten this codebase before.
        if let insight = model.engine.models.first(where: { $0.id == id }) {
            return insight.candidateMetrics
        }
        // Substance impact isn't an engine model — it needs the event log.
        return id == .substanceImpact ? SubstanceResponseAnalyzer.comparedMetrics : []
    }

    // MARK: - Patterns across those metrics

    /// What reading the series against each other turns up: two signals heading
    /// opposite ways, two that move together, or the one that tracks the score.
    /// Silent when nothing clears the sample-count and effect-size floors —
    /// which is most of the time, and correctly so.
    @ViewBuilder private func patternsCard(_ result: InsightResult) -> some View {
        let series = model.overlaySeries(for: insightID,
                                         contributions: resolvedContributions(result),
                                         timeframe: timeframe)
        let patterns = PatternFinder.patterns(in: series,
                                              against: model.scoreHistory(for: insightID))
        if !patterns.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Patterns worth a look", systemImage: "lightbulb")
                        .font(.headline)
                    ForEach(patterns) { pattern in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: pattern.kind))
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(pattern.sentence)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("These are associations found in your own data over this window, not causes, and not medical findings. A short run of days can show a relationship that isn't there.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func icon(for kind: PatternKind) -> String {
        switch kind {
        case .divergence: return "arrow.up.arrow.down"
        case .coMovement: return "arrow.left.arrow.right"
        case .driver: return "target"
        }
    }

    // MARK: - Full history per metric

    /// One link per input, replacing the single "open full history" that only
    /// ever reached the one metric this screen used to chart.
    @ViewBuilder private func contributorLinksCard(_ result: InsightResult) -> some View {
        let metrics = resolvedContributions(result).metrics
        if !metrics.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Full history").font(.headline)
                    ForEach(metrics, id: \.self) { metric in
                        NavigationLink {
                            MetricDetailView(metric: metric)
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Theme.metricColor(metric))
                                    .frame(width: 9, height: 9)
                                Text(metric.displayName).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var bloodPressureLogLink: some View {
        NavigationLink {
            MetricDetailView(subject: .bloodPressure)
        } label: {
            Card {
                HStack {
                    Image(systemName: "list.bullet.rectangle").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("View & add readings").font(.subheadline.weight(.semibold))
                        Text("Log cuff readings with dates — the estimate needs a few")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // Discreet, only-in-detail feedback loop: rate accuracy and (optionally)
    // enter the real value, which trains/refines the model over time.
    @ViewBuilder private func feedbackCard(_ result: InsightResult) -> some View {
        if result.primaryValue != nil {
            Card {
                if feedbackGiven {
                    Label("Thanks — this helps improve the model over time.",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Theme.good)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Was this accurate?").font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            Button {
                                model.recordFeedback(insightID, accurate: true); feedbackGiven = true
                            } label: { Label("Accurate", systemImage: "hand.thumbsup") }
                            Button {
                                model.recordFeedback(insightID, accurate: false); feedbackGiven = true
                            } label: { Label("Not accurate", systemImage: "hand.thumbsdown") }
                        }
                        .font(.caption).buttonStyle(.bordered)

                        if let kind = groundingPromptKind(result) {
                            Button {
                                groundingKind = kind
                            } label: {
                                Text("Have the real number? Enter it →")
                                    .font(.caption).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Which "real value" to invite for this insight (its first unmet input, or a
    /// cuff reading for blood pressure).
    private func groundingPromptKind(_ result: InsightResult) -> GroundingKind? {
        if let first = result.unmetRequirements.first { return first.kind }
        return insightID == .bloodPressure ? .cuffSystolic : nil
    }

    private var disclaimerCard: some View {
        Card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("These insights are for information only and are not a medical diagnosis or advice. Talk to a clinician about any health decisions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

}
