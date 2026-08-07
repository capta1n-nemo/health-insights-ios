import SwiftUI
import Charts
import InsightKit

/// Every computed age against your real age, over time.
///
/// The card used to show three numbers and a dial — where you are, and nothing
/// about which way it's going. Direction is the actionable part: a heart age of
/// 46 reads one way after a year at 50 and the opposite way after a year at 42.
///
/// Your chronological age is drawn as the reference because it is the only line
/// with a guaranteed slope — one year per year. A heart age climbing more slowly
/// than that is closing the gap even while its own number rises, which no chart
/// of the age alone can show.
struct AgeHistoryChart: View {
    /// The computed ages get hues of their own rather than borrowing slot 0 and
    /// slot 2, which are heart rate's and blood oxygen's preferred ones. Low
    /// severity — none of these is a `MetricType` and they never share a chart
    /// with those two — but "it can't collide today" is the belief that shipped
    /// wrong once already, and the far end of the palette is free.
    ///
    /// Four distinct slots (red, green, violet, orange) plus blue for the
    /// chronological line, so **any** combination of these series stays
    /// separable by hue alone — §3's rule, and the reason the two added on
    /// 2026-08-07 did not simply reuse the two already here.
    static let heartSlot = 7        // red
    static let fitnessSlot = 5      // green
    static let biologicalSlot = 6   // violet
    static let vascularSlot = 1     // orange

    /// One drawable age, in the order `AgePoint.leadingAge` prefers them.
    ///
    /// A table rather than four hand-written blocks: the blocks were duplicated
    /// per series across the marks, the legend and the scrub read-out, so adding
    /// a series meant remembering three places and a series drawn but absent
    /// from the legend is a line with no name on it.
    struct Series: Identifiable {
        let id: String
        /// What the legend calls it; the read-out uses the first word.
        let label: String
        let slot: Int
        let value: (AgePoint) -> Double?

        var tint: Color { Theme.paletteColour(slot: slot) }
        var short: String { String(label.split(separator: " ").first ?? "") }
    }

    static let series: [Series] = [
        .init(id: "heart", label: "Heart age", slot: heartSlot, value: \.heart),
        .init(id: "fitness", label: "Fitness age", slot: fitnessSlot, value: \.fitness),
        .init(id: "biological", label: "Biological age", slot: biologicalSlot,
              value: \.biological),
        .init(id: "vascular", label: "Vascular age", slot: vascularSlot, value: \.vascular),
    ]

    let points: [AgePoint]
    var window: TimeInterval = 365 * 24 * 3600
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    private func point(at date: Date) -> AgePoint? {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            legend
        }
    }

    /// Above the chart rather than as a mark annotation — on this SDK a
    /// `RuleMark` chain resolves to `Chart3DContent`, which has no `annotation`.
    @ViewBuilder private var readout: some View {
        if let selected = selectionBinding.wrappedValue, let hit = point(at: selected) {
            HStack(spacing: 10) {
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                value("You", hit.chronological, Self.chronologicalTint)
                ForEach(drawn) { series in
                    if let years = series.value(hit) {
                        value(series.short, years, series.tint)
                    }
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    /// The series this chart's own data actually contains.
    ///
    /// Every caller blanks the ages that are not its card's, so this is normally
    /// one — see `InsightDetailView.ageHistoryCard`.
    private var drawn: [Series] {
        Self.series.filter { series in points.contains { series.value($0) != nil } }
    }

    /// The one series that gets a filled band to the chronological line.
    ///
    /// ⚠️ **One, never several, and that is `add-chart` §8 rather than taste.**
    /// These bands are translucent, so where two of them cover the same stretch
    /// they *mix* into a third colour that means nothing. It was tolerable while
    /// only ever one could be drawn; with four series available it stops being a
    /// theoretical hazard. The card's own age — the one `AgePoint.leadingAge`
    /// picks, and the one the section's pace figure is about — keeps the band,
    /// and anything drawn beside it is a line only.
    private var banded: Series? { drawn.first }

    private func value(_ label: String, _ years: Double, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text("\(label) \(Int(years.rounded()))")
                .monospacedDigit()
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: selectionBinding,
            height: 170,
            emptyMessage: "No ages computed in this window",
            isEmpty: { range in !points.contains { range.contains($0.date) } },
            // Padded around the ages actually present: a fixed 0–100 domain
            // would compress a decade of movement into a few pixels.
            yDomain: { range in Self.domain(points.filter { range.contains($0.date) }) }
        ) { range in
            ageMarks(points.filter { range.contains($0.date) })
        }
    }

    /// **A whole life, 0 to 100 — deliberately not the visible data.**
    ///
    /// The reader, 2026-08-05: *"its weird that my age is the very bottom of
    /// the graph, its basically along the bottom... it should start with 0 (age
    /// 0) and go up to age 100"*.
    ///
    /// This is a considered exception to `add-chart` §10's "the axis fits the
    /// data in the visible window, not a round number above it", and the reason
    /// it is safe here is that **an age is meaningful on an absolute scale in a
    /// way a heart-rate variability is not**. Fitted to its own data the axis
    /// spanned roughly the low thirties to the low seventies, which made a
    /// four-year gap between two ages look like the whole plot and pinned the
    /// reader's real age to the floor — reading as "you are at the bottom" when
    /// it meant "this is the smallest number here".
    ///
    /// Against a lifespan the same gap is a small distance, which is what it
    /// is. The cost is honest and accepted: a year's change is now barely
    /// visible, and this chart is about *standing*, not about week-to-week
    /// movement.
    ///
    /// `visible` is unused and kept in the signature so the wrapper's
    /// per-window call site is unchanged; a fixed domain is the point.
    static func domain(_ visible: [AgePoint]) -> ClosedRange<Double>? {
        0...100
    }

    /// **Not `Color.secondary`.** It rendered as a pale grey at 0.5 opacity
    /// against a grey plot and the reader could not see it at all — which is
    /// fatal for the one line the other two are read against.
    ///
    /// Its own palette slot rather than a brighter grey: hue is identity in
    /// this app (`add-chart` §3), and the reference deserves one as much as the
    /// two computed ages do. Solid, because a chronological age is measured —
    /// dash means inferred and nothing else.
    static let chronologicalSlot = 0
    static var chronologicalTint: Color { Theme.paletteColour(slot: chronologicalSlot) }

    /// Explicit `some ChartContent`, as every mark builder in this app must
    /// have: without it the chain resolves to 3D chart content on this SDK and
    /// silently drops `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private func ageMarks(_ visible: [AgePoint]) -> some ChartContent {
        // Your real age first, underneath, so the two computed ages read
        // against it rather than the other way round.
        ForEach(visible) { point in
            LineMark(x: .value("Day", point.date),
                     y: .value("Age", point.chronological),
                     series: .value("Series", "You"))
                .foregroundStyle(Self.chronologicalTint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
        }
        // **Filled to your own age, not to the axis.** The reader asked for a
        // fill "similar to the activity graph, where they can overlap", and the
        // quantity this chart is actually about is the *gap* — how much older
        // or younger than you a system reads. An area between the two lines
        // draws exactly that, and shades below your age when the news is good,
        // which a fill to the baseline cannot express at all.
        //
        // `AreaMark(x:yStart:yEnd:)` takes no `stacking:` — an absolute band
        // between two heights is inherently unstacked (`add-chart` §7).
        //
        // ⚠️ **Exactly one band, whatever is drawn** — see `banded` for why
        // several translucent ones is §8's hatch-never-blend in a chart that now
        // has four series to choose from.
        ForEach(banded.map { [$0] } ?? []) { series in
            ForEach(visible.filter { series.value($0) != nil }) { point in
                AreaMark(x: .value("Day", point.date),
                         yStart: .value("Age", point.chronological),
                         yEnd: .value("Age", series.value(point) ?? point.chronological))
                    .foregroundStyle(series.tint.opacity(0.16))
            }
        }
        ForEach(drawn) { series in
            ForEach(visible.filter { series.value($0) != nil }) { point in
                LineMark(x: .value("Day", point.date),
                         y: .value("Age", series.value(point) ?? 0),
                         series: .value("Series", series.label))
                    .foregroundStyle(series.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendKey("Your age", Self.chronologicalTint)
            ForEach(drawn) { series in
                legendKey(series.label, series.tint)
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendKey(_ label: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(tint).frame(width: 12, height: 3)
            Text(label)
        }
    }
}
