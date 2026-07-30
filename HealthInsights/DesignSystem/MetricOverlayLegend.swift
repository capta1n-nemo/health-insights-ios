import SwiftUI
import InsightKit

/// The legend under the overlay.
///
/// Not optional decoration: four of the eight light-mode hues sit below 3:1
/// against the grouped background, so the palette is only accessible with the
/// names and values written out beside the swatches. It also carries the metrics
/// that have *no* data, which is the difference between "this doesn't affect your
/// score" and "we couldn't measure it".
struct MetricOverlayLegend: View {
    let series: [NormalizedSeries]
    let contributions: [MetricContribution]
    /// Declared inputs with nothing to plot — shown dimmed rather than omitted.
    let missing: [MetricType]
    /// Which series are on the chart. Shared with it, so the key and the plot
    /// can never disagree about what's drawn.
    var selection: Binding<Set<MetricType>>?
    var onSelect: ((MetricType) -> Void)?

    /// Unselected signals stay one tap away rather than filling the card. The
    /// list expands independently of the chart: you can read what a signal did
    /// without adding a line to a busy plot.
    @State private var showsUnselected = false

    private var selected: Set<MetricType> {
        selection?.wrappedValue ?? Set(series.map(\.metric))
    }

    /// Most-departed first, so choosing the interesting signals out of thirteen
    /// is a matter of reading from the top.
    private var ranked: [NormalizedSeries] { OverlaySelection.ranked(series) }
    private var onChart: [NormalizedSeries] { ranked.filter { selected.contains($0.metric) } }
    private var offChart: [NormalizedSeries] { ranked.filter { !selected.contains($0.metric) } }

    /// Hues resolved over the drawn set, in the chart's own drawing order.
    private var slots: [MetricType: Int] {
        MetricPalette.slots(for: OverlaySelection.visible(series, selected: selected).map(\.metric))
    }

    private func contribution(for metric: MetricType) -> MetricContribution? {
        contributions.first { $0.metric == metric }
    }

    private func toggle(_ metric: MetricType) {
        guard let selection else {
            onSelect?(metric)
            return
        }
        var next = selection.wrappedValue
        if next.contains(metric) { next.remove(metric) } else { next.insert(metric) }
        withAnimation(.snappy) { selection.wrappedValue = next }
    }

    /// Unselected signals that are nonetheless doing something — so the
    /// disclosure never calls a departing signal "in your normal range".
    private var departingButOff: Int {
        offChart.filter { OverlaySelection.isNotable($0) }.count
    }

    private var disclosureLabel: String {
        if showsUnselected { return "Hide the rest" }
        if departingButOff > 0 {
            return "Show \(offChart.count) more, \(departingButOff) away from baseline"
        }
        return "Show \(offChart.count) more in your normal range"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(onChart) { one in
                row(one, slot: slots[one.metric], isOn: true)
            }

            // Past the palette the reader has asked for more lines than there
            // are colours. Allowed — it's their chart — but said out loud,
            // because two series in the same red is exactly the confusion the
            // automatic selection exists to avoid.
            if onChart.count > MetricPalette.hueCount {
                Text("\(onChart.count) signals selected. Past \(MetricPalette.hueCount) the colours repeat.")
                    .font(.caption2).foregroundStyle(Theme.warn)
            }

            if !offChart.isEmpty {
                Divider()
                Button {
                    withAnimation(.snappy) { showsUnselected.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(disclosureLabel)
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .rotationEffect(.degrees(showsUnselected ? 180 : 0))
                        Spacer()
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsUnselected {
                    ForEach(offChart) { one in
                        row(one, slot: nil, isOn: false)
                    }
                }
            }

            // Before any controls: these are signals, and a "No data" row under
            // a button reads as belonging to it.
            ForEach(missing, id: \.self) { metric in
                missingRow(metric)
            }

            if let selection, series.count > MetricPalette.comfortableSeriesCount {
                Divider()
                HStack {
                    Text("Tap a signal to put it on the chart or take it off.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(selected.count == series.count ? "Reset" : "All") {
                        withAnimation(.snappy) {
                            selection.wrappedValue = selected.count == series.count
                                ? OverlaySelection.defaultSelection(series)
                                : Set(series.map(\.metric))
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// `slot` is the hue the chart gave this series, or nil when it isn't being
    /// drawn — in which case the swatch is hollow, because there is no line for
    /// it to be the key to.
    private func row(_ one: NormalizedSeries, slot: Int?, isOn: Bool) -> some View {
        let contribution = contribution(for: one.metric)
        return Button {
            toggle(one.metric)
        } label: {
            HStack(spacing: 8) {
                swatch(slot: slot)
                VStack(alignment: .leading, spacing: 1) {
                    Text(one.metric.displayName)
                        .font(.subheadline)
                    if let weight = contribution?.weight, weight > 0 {
                        Text("\(Int((weight * 100).rounded()))% of this score")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if let trend = trendPhrase(one) {
                        Text(trend).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // The model's own formatting when it reported one, otherwise the
                // latest plotted value. Checked for emptiness, not just for nil:
                // a stand-in contribution carries a blank detail, and printing
                // that would leave the row with no number at all.
                if let detail = contribution?.detail, !detail.isEmpty {
                    Text(detail).font(.subheadline.weight(.medium))
                        .monospacedDigit()
                } else if let raw = one.latest?.raw {
                    Text(formatMetric(raw, one.metric))
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isOn ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(isOn ? "Double tap to remove from the chart"
                                : "Double tap to add to the chart")
    }

    /// A short solid stroke in the hue the chart assigned, so the legend and the
    /// chart are unambiguously the same key. Hollow where the series isn't
    /// drawn.
    private func swatch(slot: Int?) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 18, y: 5))
        }
        .stroke(slot.map { Theme.paletteColour(slot: $0) } ?? Color.secondary.opacity(0.25),
                style: StrokeStyle(lineWidth: 2))
        .frame(width: 18, height: 10)
    }

    private func missingRow(_ metric: MetricType) -> some View {
        HStack(spacing: 8) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 18, y: 5))
            }
            // Hollow rather than dashed. Dash now means "inferred, not
            // measured" everywhere in the app, and a metric with no data at all
            // has nothing inferred either.
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 2))
            .frame(width: 18, height: 10)
            Text(metric.displayName).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("No data").font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// Direction over the window, in plain words, and whether that direction is
    /// the good one for this particular signal — rising HRV and rising resting
    /// heart rate mean opposite things, and a bare arrow would imply otherwise.
    /// Silent about good-or-bad where neither direction is (temperature
    /// deviation is best near zero).
    private func trendPhrase(_ one: NormalizedSeries) -> String? {
        guard let slope = one.trendPerWeek, abs(slope) >= PatternFinder.minimumSlope else {
            return "steady"
        }
        let rising = slope > 0
        let direction = rising ? "trending up" : "trending down"
        guard let higherIsBetter = one.higherIsBetter else { return direction }
        return direction + (rising == higherIsBetter ? " (good)" : " (worth watching)")
    }
}
