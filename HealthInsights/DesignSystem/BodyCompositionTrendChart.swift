import SwiftUI
import Charts
import InsightKit

/// How the body's composition has changed, as bands that thicken and thin.
///
/// ## Why a stacked area and not the extruded bar
///
/// The obvious build is the "what you're made of" bar repeated down the screen,
/// one row per weigh-in, time running vertically. That is the right *substance*
/// — same quantities, same colours, one axis added — and two changes make it
/// read better. Time runs left-to-right, which is the convention every other
/// chart in this app follows and which fits a year of weigh-ins where stacked
/// rows fit about twenty. And the bands are continuous rather than discrete, so
/// a band narrowing over months is one visible taper instead of a difference the
/// reader has to measure between rows.
///
/// ## Kilograms, not percentages
///
/// A 100%-normalised stack answers "what proportion of me is fat" and hides the
/// total. This user's weight has moved from a median of 124 kg to 110.7, and the
/// interesting question — did the loss come off fat, or did muscle go with it —
/// is exactly the one normalising destroys. In kilograms the top edge of the
/// stack *is* body weight, so both readings are in one picture.
///
/// ## The bands do not all start together, and that is real
///
/// Body fat reaches back to 2020; muscle, bone and water begin when the Body
/// Smart scale arrived. `BodyCompositionSplit.series` gives each day the finest
/// split its own readings support, so the lean band visibly subdivides rather
/// than the older history being fabricated to match the newer.
struct BodyCompositionTrendChart: View {

    let points: [BodyCompositionSplit.Dated]
    /// The day the lean band subdivides, when the window spans both resolutions.
    let finerSplitBegins: Date?
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    /// One band's value on one day, flattened for `Chart`.
    private struct Row: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let metric: MetricType
        let kilograms: Double
    }

    /// Where the water line reaches on one day. A named type, not a tuple:
    /// `ForEach(_, id: \.date)` over a tuple is a compile error.
    private struct WaterPoint: Identifiable {
        let date: Date
        let kilograms: Double
        var id: Date { date }
    }

    /// Bottom of the stack first. Fat leads deliberately: it sits on the flat
    /// zero baseline, which is the only band whose thickness can be read without
    /// discounting the wobble of everything under it — and it is the band the
    /// question is usually about.
    private static let order = ["Fat", "Muscle", "Bone", "Other lean", "Lean"]

    private var rows: [Row] {
        points.flatMap { point in
            point.split.parts.map {
                Row(date: point.date, label: $0.label,
                    metric: $0.metric, kilograms: $0.kilograms)
            }
        }
    }

    /// Labels present, in stacking order — not every split has every band.
    private var labels: [String] {
        let present = Set(rows.map(\.label))
        return Self.order.filter(present.contains)
    }

    /// Hues resolved once over every metric that can appear, water included, so
    /// no two bands can share one and the colours match the "now" bar.
    private var slots: [MetricType: Int] {
        MetricPalette.slots(for: [.bodyFatPercentage, .muscleMass, .boneMass,
                                  .leanBodyMass, .bodyWaterPercentage])
    }

    private func colour(_ label: String) -> Color {
        let metric = rows.first { $0.label == label }?.metric ?? .leanBodyMass
        return Theme.metricColor(metric, slots: slots)
    }

    /// Where body water reaches inside the band hosting it, as a cumulative
    /// height from the baseline: everything below the host, plus the water.
    ///
    /// Drawn as a solid hairline, never dashed — a dash means *inferred* in this
    /// app, and this is a measurement. It is a line rather than a fifth band
    /// because water is held *within* lean tissue; a band of its own would count
    /// the same kilograms twice.
    private var waterLine: [WaterPoint] {
        points.compactMap { point in
            guard let water = point.split.water else { return nil }
            var below: Double = 0
            for part in point.split.parts {
                if part.metric == water.host { break }
                below += part.kilograms
            }
            // The clamped figure, so the line can never escape its host band.
            let host = point.split.parts.first { $0.metric == water.host }?.kilograms ?? 0
            return WaterPoint(date: point.date,
                              kilograms: below + Swift.min(water.kilograms, host))
        }
    }

    /// The weigh-in nearest the finger, ignoring anything more than a fortnight
    /// away — past that there is no reading under the touch to report.
    private func point(at date: Date) -> BodyCompositionSplit.Dated? {
        points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }.flatMap { abs($0.date.timeIntervalSince(date)) <= 14 * 86_400 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
        }
    }

    /// Above the chart, not as an annotation — a `RuleMark` chain resolves to
    /// `Chart3DContent` on this SDK and that has no `annotation`. The blank line
    /// reserves the height so nothing jumps on first touch.
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f kg", hit.split.total))
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                ForEach(hit.split.parts, id: \.metric) { part in
                    HStack(spacing: 3) {
                        Circle().fill(Theme.metricColor(part.metric, slots: slots))
                            .frame(width: 5, height: 5)
                        Text(String(format: "%.1f", part.kilograms)).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        Chart {
            bands
            waterMarks
            ScrubIndicator(date: selected)
        }
        .chartXSelection(value: selectionBinding)
        .chartForegroundStyleScale(domain: labels, range: labels.map(colour))
        .chartLegend(.hidden)   // the card draws its own, with the water sub-dot
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text("\(Int(kg))")
                    }
                }
            }
        }
        .frame(height: 190)
    }

    // Explicit `some ChartContent` on both: without it a mark chain on the
    // current SDK can silently resolve to `Chart3DContent` and drop its
    // modifiers. This has cost this repo two CI failures — it is a known trap,
    // not a precaution.
    @ChartContentBuilder private var bands: some ChartContent {
        ForEach(rows) { row in
            AreaMark(x: .value("Date", row.date),
                     y: .value("Mass", row.kilograms),
                     stacking: .standard)
                .foregroundStyle(by: .value("Part", row.label))
        }
    }

    @ChartContentBuilder private var waterMarks: some ChartContent {
        ForEach(waterLine) { entry in
            LineMark(x: .value("Date", entry.date),
                     y: .value("Water", entry.kilograms),
                     series: .value("Series", "water"))
                .foregroundStyle(Theme.metricColor(.bodyWaterPercentage, slots: slots))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
    }
}
