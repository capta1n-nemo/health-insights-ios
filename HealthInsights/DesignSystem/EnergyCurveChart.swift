import SwiftUI
import Charts
import InsightKit

/// Where today's energy went, hour by hour.
///
/// `EnergyModel` has always computed this curve and nothing drew it — the detail
/// screen showed the score history like every other card, which answers "how have
/// my mornings been this month" and not the question the card is for. Energy is
/// the one insight in this app whose subject is *within* a day: a reservoir that
/// filled overnight and has been draining since, and the shape of that drain is
/// the whole finding. A person who is at 40 because of one hard hour at noon and
/// a person who is at 40 because of a steady leak since breakfast are in
/// different states, and only this chart can tell them apart.
///
/// ## Why an area and not a line
///
/// Every other chart in this app is a line, because every other chart plots a
/// measurement against time and a filled region under a measurement means
/// nothing. Here the quantity genuinely *is* a volume — what is left in the tank
/// — so the fill is the reading rather than decoration. It is also the one place
/// the reader needs to see remaining-versus-spent at a glance rather than read a
/// value off an axis.
///
/// ## The morning charge is drawn, and drawn as inferred
///
/// The reference line is where the day started, so every point can be read as a
/// distance below it. It is dashed because a morning charge is a modelled
/// quantity, not a measurement — the same rule that governs every other dash in
/// this app.
struct EnergyCurveChart: View {
    /// Optional for the same reason the wrapper's is — a chart rendered outside
    /// the app hierarchy draws without shading rather than trapping.
    @Environment(AppModel.self) private var model: AppModel?
    let curve: [EnergyModel.Point]
    /// Where the day started, drawn as the reference the drain is read against.
    let morningCharge: Double
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }
    private var tint: Color { Theme.insightTint(.energy) }

    private var span: ClosedRange<Date>? {
        guard let first = curve.first?.date, let last = curve.last?.date,
              first < last else { return nil }
        return first...last
    }

    private func point(at date: Date) -> EnergyModel.Point? {
        curve.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            caption
        }
    }

    /// Above the chart rather than as a mark annotation: on this SDK a
    /// `RuleMark` chain resolves to `Chart3DContent`, which has no `annotation`.
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("\(Int(hit.level.rounded()))")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.date.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                if hit.drained >= 1 {
                    Text(String(format: "· %.0f spent by then", hit.drained))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    /// A plain `Chart` rather than `ScrollableMetricChart`, which is the wrapper
    /// every other chart here uses.
    ///
    /// That wrapper exists to pan and zoom a history longer than the screen. A
    /// day is never longer than the screen — at most twenty-four points — so
    /// there is nothing to scroll to, and a pannable axis would let the reader
    /// drag today's curve off the edge and find nothing on either side of it.
    private var chart: some View {
        Chart {
            // Drawn here because this chart deliberately does not wrap
            // `ScrollableMetricChart` — see above — so it does not inherit the
            // shading that wrapper applies. A coffee at three shades the rest
            // of today's curve, which is exactly the stretch worth seeing.
            SubstanceShading.marks(model?.allSubstanceWindows ?? [], in: span ?? Date()...Date())
            marks
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartXSelection(value: selectionBinding)
        .frame(height: 160)
        .overlay {
            if span == nil {
                Text("Not enough of the day yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Explicit `some ChartContent`, as every mark builder in this app must
    /// have: without it the chain can resolve to 3D chart content on this SDK
    /// and silently drop `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private var marks: some ChartContent {
        morningMark
        ForEach(curve) { point in
            AreaMark(x: .value("Time", point.date), y: .value("Left", point.level))
                .foregroundStyle(LinearGradient(
                    colors: [tint.opacity(0.42), tint.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.linear)
        }
        ForEach(curve) { point in
            LineMark(x: .value("Time", point.date), y: .value("Left", point.level))
                .foregroundStyle(tint)
                // Straight, like every other series here: the model computes one
                // value an hour, and a curve would invent the minutes between.
                .interpolationMethod(.linear)
        }
        selectionMark
    }

    /// Where the day started. A `ForEach` over one value rather than a bare
    /// `RuleMark`, which is the construction this app has verified against the
    /// 3D-content overload hazard.
    @ChartContentBuilder
    private var morningMark: some ChartContent {
        ForEach([morningCharge], id: \.self) { level in
            RuleMark(y: .value("Morning charge", level))
                .foregroundStyle(tint.opacity(0.55))
                // Modelled, not measured — the one meaning a dash carries here.
                .lineStyle(Theme.projectedStroke)
        }
    }

    /// The shared one. This chart had the app's first scrub line and kept its
    /// own copy — identical colour, stroke and `ForEach`-over-one construction —
    /// after `ScrubIndicator` was extracted from it for the other seven charts.
    /// Identical is exactly how a duplicate stays invisible until the day one
    /// copy is changed.
    @ChartContentBuilder
    private var selectionMark: some ChartContent {
        ScrubIndicator.at(selected)
    }

    private var caption: some View {
        Text("The dashed line is where the day started. Everything below it has been spent — on work done, and on time with your heart rate above resting. A model of a reservoir, not a measurement of one.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
