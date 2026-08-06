import SwiftUI
import Charts
import InsightKit

/// One derived series over time — the shared chart the Generated-insights data
/// pages draw, so no data page hand-rolls a `Chart {}`.
///
/// Wraps `ScrollableMetricChart` (add-chart §1), so pan, scrub, the y-scale and
/// the substance shading all arrive from the wrapper rather than being
/// re-implemented here.
///
/// **Solid line, deliberately** — the dash grammar (§3) means *not measured*,
/// and it is tempting to read "computed" as that. Wrong reading: a dash marks a
/// value the app inferred *between* real ones — a gap bridge, a projection.
/// Each point here is a real computed value for that day, the same standing
/// `activeMedicationLevel` has, and what carries the "computed, never measured"
/// caveat is the page around this chart, not the stroke. What a dash would say
/// is that the *line between* two computed days was itself invented, which is
/// true of every chart in the app and is exactly why gaps break instead.
struct DerivedSeriesChart: View {
    let spec: DerivedSeriesSpec
    let points: [DerivedPoint]
    var window: TimeInterval = 90 * 24 * 3600

    @State private var selection: Date?

    /// One figure a day, so two days apart is a gap like any other daily
    /// series — the same rule `maxValidInterval` states for screen time.
    static let maxJoin: TimeInterval = 2 * 24 * 3600

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.day, let last = points.last?.day,
              first <= last else { return nil }
        return first...last
    }

    /// Runs of consecutive days, split wherever the gap rule says the line may
    /// not bridge. Plotted as separate series so Charts breaks the stroke.
    private var segments: [[DerivedPoint]] {
        var out: [[DerivedPoint]] = []
        var current: [DerivedPoint] = []
        for point in points {
            if let last = current.last,
               point.day.timeIntervalSince(last.day) > Self.maxJoin {
                out.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private func point(at date: Date) -> DerivedPoint? {
        guard let nearest = points.min(by: {
            abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date))
        }), abs(nearest.day.timeIntervalSince(date)) <= window / 8 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
        }
    }

    /// Above the chart, never a mark annotation (add-chart §2).
    @ViewBuilder private var readout: some View {
        if let selected = selection, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Text(hit.day.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                Text(spec.string(hit.value)).monospacedDigit()
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: $selection,
            height: 150,
            emptyMessage: "Nothing computed in this window",
            isEmpty: { range in !points.contains { range.contains($0.day) } },
            yDomain: { range in Self.domain(points.filter { range.contains($0.day) }) }
        ) { range in
            marks(points.filter { range.contains($0.day) })
        }
    }

    /// Explicit return type, or a mark chain can resolve to `Chart3DContent`
    /// on this SDK and silently drop its modifiers (add-chart §2).
    @ChartContentBuilder
    private func marks(_ visible: [DerivedPoint]) -> some ChartContent {
        let visibleSegments = segments
            .map { segment in segment.filter { visible.contains($0) } }
            .filter { !$0.isEmpty }
        ForEach(Array(visibleSegments.enumerated()), id: \.offset) { index, segment in
            ForEach(segment) { point in
                LineMark(x: .value("Day", point.day),
                         y: .value(spec.displayName, point.value),
                         series: .value("Segment", index))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.linear)
            }
        }
        ForEach(visible) { point in
            PointMark(x: .value("Day", point.day),
                      y: .value(spec.displayName, point.value))
                .foregroundStyle(Theme.accent)
                .symbolSize(12)
        }
    }

    /// Fitted to the visible slice with a little headroom — the default rule
    /// (add-chart §10), since none of these quantities has an absolute scale
    /// the way an age does.
    static func domain(_ visible: [DerivedPoint]) -> ClosedRange<Double>? {
        guard let low = visible.map(\.value).min(),
              let high = visible.map(\.value).max() else { return nil }
        let pad = Swift.max((high - low) * 0.15, Swift.max(abs(high) * 0.05, 0.5))
        return (low - pad)...(high + pad)
    }
}
