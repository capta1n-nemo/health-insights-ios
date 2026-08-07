import SwiftUI
import InsightKit

/// **"Which instrument to believe" — the index.** Every signal the reader's
/// devices disagree about, in one place, ranked by how much.
///
/// Backlog `B3-23`. The ruling on 2026-08-07 was that this ask is *both* a
/// per-card section and a card: the section
/// (`InstrumentAgreementSection`) puts the disagreement where the decision is
/// made, and this makes it findable when the reader is not already looking at a
/// score. Roughly double the work, chosen deliberately.
///
/// ## Why this is a `Card` on the Insights tab rather than an `InsightID`
///
/// It is not a scored insight and must not be dressed as one. Everything in
/// `InsightDetailView` — a dial, "what's driving this", "how this is weighted",
/// "was this accurate?" — is machinery for a number between 0 and 100, and
/// **there is no such number here**: two instruments disagreeing is not good or
/// bad for the reader, it is a fact about their hardware. An `InsightID` would
/// have bought fifteen sections of which thirteen would render placeholders,
/// and a score dial that had to be left blank or invented.
///
/// The precedent is `suggestionsDrawer` directly above in this same tab: a
/// `Card` that is not an insight, collapsed by default, doing one job. This is
/// that shape.
///
/// ⚠️ **If the reader wanted a scored card here**, this is the decision to
/// revisit — it is recorded rather than assumed so that the next session does
/// not re-argue it silently.
///
/// ## What it costs to draw
///
/// It asks the question of every metric any card reads — the union of the
/// engine's `candidateMetrics`, not `MetricType.allCases`, because the index
/// should index the same signals the sections do. That is still one
/// `MultiSource.breakdown` per metric, which is the exact shape
/// `EvaluationMemo` was written for (45 breakdowns cost 1,548 ms unmemoised and
/// 471 ms with the grouping pass), so the build runs inside
/// `MultiSource.withMemo` and the whole result is held by `AppModel.memoized`
/// until the samples change.
///
/// It is also **last in the tab's `LazyVStack`**, so on a tab that has already
/// been made slow twice by work started from a view body, this one does not run
/// at all until the reader scrolls to it.
struct InstrumentIndexCard: View {
    @Environment(AppModel.self) private var model
    /// Collapsed by default, same as the suggestions drawer above: an appendix
    /// that fills the screen every time the tab opens stops being an appendix.
    @AppStorage("instrumentIndexExpanded") private var isExpanded = false

    /// Every signal any card reads, de-duplicated. Ordered by
    /// `MetricType.allCases` so the panel's own ranking is the only thing that
    /// decides the row order, rather than the registry's iteration order.
    private var watchedMetrics: [MetricType] {
        let declared = Set(model.engine.models.flatMap(\.candidateMetrics))
        return MetricType.allCases.filter { declared.contains($0) }
    }

    private var panel: InstrumentAgreementPanel {
        model.memoized("instrumentIndex") {
            MultiSource.withMemo(for: model.samples) {
                InstrumentAgreementPanel.forCard(metrics: watchedMetrics,
                                                 samples: model.samples,
                                                 windowDays: windowDays)
            }
        }
    }

    /// Ninety days, fixed and stated in the copy.
    ///
    /// The card has no timeframe picker — the tab it lives on has none — and
    /// `dailySeries` genuinely picks the instrument that best covers *the
    /// window being read*, so this number is load-bearing rather than
    /// decoration. Ninety days is long enough that a device swapped out months
    /// ago does not still hold the chart, and short enough that "covers this
    /// window" means something. **A card's own section can and will disagree
    /// with this row** when the reader has the picker on a week — which is not
    /// a bug, and is why both surfaces name the number of days they used.
    private let windowDays = 90

    var body: some View {
        let panel = self.panel
        Card {
            VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
                header(panel)
                if isExpanded { expanded(panel) }
            }
        }
    }

    private func header(_ panel: InstrumentAgreementPanel) -> some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                    Text("Which instrument to believe").font(.headline)
                    Spacer(minLength: 4)
                    Text(panel.rows.isEmpty ? "all agree" : "\(panel.rows.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(panel.rows.isEmpty ? Color.secondary.opacity(0.12)
                                                       : Theme.accent.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(panel.rows.isEmpty ? .secondary : Theme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                if !isExpanded {
                    Text(InstrumentAgreementWording.preview(panel))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
    }

    @ViewBuilder private func expanded(_ panel: InstrumentAgreementPanel) -> some View {
        if panel.rows.isEmpty {
            Text(panel.single.isEmpty
                 ? "Nothing is reporting yet, so there is nothing to compare."
                 : "Every signal your cards read comes from a single instrument. "
                    + "Nothing had to be chosen between, and nothing was discarded.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(Array(panel.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                NavigationLink { MetricDetailView(metric: row.metric) } label: { rowLabel(row) }
                    .buttonStyle(.plain)
            }
            Divider()
            Text("Each of these appears on the cards that read it, under "
                    + "\"Which instrument to believe\", with the reason the app chose "
                    + "the one it chose. Coverage here is counted over the last "
                    + "\(windowDays) days; a card counts it over whatever timeframe you "
                    + "have that card set to, so the two can name different instruments "
                    + "and both be right.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rowLabel(_ row: InstrumentAgreement) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.metric.displayName).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                if let spread = row.spread {
                    Text(formatted(spread, row.metric) + " apart")
                        .font(.caption).monospacedDigit().foregroundStyle(Theme.warn)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            // Every instrument's own number, chosen and discarded alike. This
            // one line is the whole of the reader's ask; the card's own section
            // carries the reasoning behind it.
            Text(row.instruments.map { instrument in
                let value = instrument.latest.map { formatted($0, row.metric) } ?? "—"
                return "\(instrument.name) \(value)"
            }.joined(separator: "  ·  "))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let used = row.readingSource {
                    Text("used: \(used)").font(.caption2).foregroundStyle(Theme.accent)
                }
                if row.rulesDisagree, let chart = row.chartSource {
                    Text("chart: \(chart)").font(.caption2).foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func formatted(_ value: Double, _ metric: MetricType) -> String {
        let text = formatMetric(value, metric)
        guard !formatMetricIncludesUnit(metric), !metric.unit.isEmpty else { return text }
        return "\(text) \(metric.unit)"
    }
}
