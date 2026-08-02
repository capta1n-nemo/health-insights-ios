import SwiftUI
import Charts
import InsightKit

/// **Is it working?** — what's on board, your weight and your body fat, on one
/// axis.
///
/// The user's ask, 2026-08-02: *"I want the medication board graph to be in this
/// new Medication section, and for you to overlay weight, fat, relevant stats
/// onto it.. so I can see how well it's working."*
///
/// ## One axis, standardised — not three axes
///
/// Milligrams, kilograms and percent share no scale. Giving each its own y-axis
/// would let any two of them be slid until they agree, which is the oldest way
/// to draw a relationship that isn't there; `MetricOverlayChart` refuses to do
/// it and so does this. Every line is standard deviations from its own mean over
/// the visible window, computed in `MedicationResponse.overlay` where it is
/// tested. The scrub read-out prints the real numbers, so nothing is hidden —
/// the axis is for shape, the read-out is for value.
///
/// ## What the dashes mean
///
/// The same thing they mean everywhere in this app: **not measured.** The
/// on-board line runs dashed over any stretch held up by doses `TitrationEngine`
/// worked out rather than ones the reader logged. Weight and body fat are
/// measurements, so they are always solid.
struct MedicationResponseChart: View {
    let series: [MedicationResponse.ResponseSeries]
    var window: TimeInterval = 90 * 24 * 3600
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    private func colour(_ kind: MedicationResponse.ResponseSeries.Kind) -> Color {
        Theme.paletteColour(slot: kind.paletteSlot)
    }

    private var span: ClosedRange<Date>? {
        let dates = series.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max(), first <= last else { return nil }
        return first...last
    }

    /// One drawn point, flattened out of the series so the chart builder has a
    /// single `ForEach` to walk. The nested-ForEach shape exceeds what the
    /// builder's type checker accepts — the same conclusion `MultiSourceChart`
    /// and `MetricOverlayChart` both reached.
    private struct Plot: Identifiable {
        let id: String
        let date: Date
        let z: Double
        let kind: MedicationResponse.ResponseSeries.Kind
        /// Which drawn line this belongs to. An inferred stretch is its own
        /// series so it can take its own stroke: a `LineMark` styles per series,
        /// so mixing dashed and solid points inside one draws whichever the last
        /// point asked for.
        let lane: String
        let isInferred: Bool
    }

    private func plots(in range: ClosedRange<Date>) -> [Plot] {
        series.flatMap { one in
            one.points.filter { range.contains($0.date) }.map { point in
                Plot(id: "\(one.kind.rawValue)@\(point.date.timeIntervalSince1970)",
                     date: point.date, z: point.z, kind: one.kind,
                     lane: "\(one.kind.rawValue)#\(point.isInferred ? "est" : "measured")",
                     isInferred: point.isInferred)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            legend
            Text("Each line is measured against its own usual range over this window, so they can share an axis — milligrams, kilograms and percent have no common scale, and giving each its own axis is how any two lines can be made to look like they agree. Scrub for the real numbers.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Above the chart as a plain view, never a mark annotation — 3D chart
    /// content has no `annotation`, and this chain can resolve to it.
    @ViewBuilder private var readout: some View {
        if let selected, case let rows = readings(at: selected), !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rows) { row in
                        HStack(spacing: 5) {
                            Circle().fill(colour(row.kind)).frame(width: 7, height: 7)
                            Text(row.text).monospacedDigit()
                        }
                    }
                    Text(selected.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)
            }
        } else {
            Text(" ").font(.caption2)
        }
    }

    private struct Callout: Identifiable {
        let kind: MedicationResponse.ResponseSeries.Kind
        let text: String
        var id: String { kind.rawValue }
    }

    private func readings(at date: Date) -> [Callout] {
        series.compactMap { one in
            guard let nearest = one.points.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
            let value = one.kind == .onBoard
                ? String(format: "%.2f %@", nearest.raw, one.kind.unit)
                : String(format: "%.1f %@", nearest.raw, one.kind.unit)
            return Callout(kind: one.kind,
                           text: nearest.isInferred ? "\(value) est." : value)
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: selectionBinding,
            height: 180,
            emptyMessage: "No readings in this window",
            isEmpty: { range in plots(in: range).isEmpty },
            yDomain: { range in
                let zs = plots(in: range).map(\.z)
                guard let low = zs.min(), let high = zs.max(), low < high else { return nil }
                let pad = (high - low) * 0.12
                return (low - pad)...(high + pad)
            }
        ) { range in
            responseMarks(plots(in: range))
        }
    }

    /// Explicit `-> some ChartContent`. Without it a `RuleMark` + `LineMark`
    /// chain can resolve to `Chart3DContent` on this SDK and silently drop
    /// `.lineStyle` and `.foregroundStyle` — which here would erase both the
    /// measured/estimated distinction and the only thing telling three lines
    /// apart.
    @ChartContentBuilder
    private func responseMarks(_ points: [Plot]) -> some ChartContent {
        baselineMark
        ForEach(points) { point in
            LineMark(x: .value("Day", point.date),
                     y: .value("Against your usual", point.z),
                     series: .value("Series", point.lane))
                .foregroundStyle(colour(point.kind).opacity(point.isInferred ? 0.6 : 1))
                .lineStyle(point.isInferred ? Theme.projectedStroke
                                            : StrokeStyle(lineWidth: 1.8))
                .interpolationMethod(.linear)
        }
    }

    /// "Your usual" — what zero means. A `ForEach` over a one-element array
    /// rather than a bare mark, keeping to the one construction this app has
    /// verified against the 3D-content overload.
    @ChartContentBuilder
    private var baselineMark: some ChartContent {
        ForEach([0.0], id: \.self) { level in
            RuleMark(y: .value("Your usual", level))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(Theme.referenceStroke)
        }
    }

    /// Drawn plain and opaque, whatever the line does on the chart: a key
    /// answers "which quantity is this", and whether a stretch of it was
    /// estimated is a fact about the data, not about the colour.
    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(series) { one in
                HStack(spacing: 5) {
                    Capsule().fill(colour(one.kind)).frame(width: 12, height: 3)
                    Text(one.kind.title)
                    if let latest = one.latest {
                        Text(one.kind == .onBoard
                             ? String(format: "%.2f", latest.raw)
                             : String(format: "%.1f", latest.raw))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
    }
}
