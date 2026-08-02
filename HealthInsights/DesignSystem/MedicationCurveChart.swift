import SwiftUI
import Charts
import InsightKit

/// How much of the medication is still in you, day by day.
///
/// The shape is the point. A weekly injectable does not arrive and leave — it
/// accumulates for a month or more before it stops climbing, which is why a
/// dose that has not changed can still feel like it is getting stronger. A list
/// of injection dates cannot show that; this can.
///
/// **Dashed means the line rests on a dose the app guessed.** `TitrationEngine`
/// proposes a titration history from the reader's current dose, and until they
/// confirm it, every part of the curve holding that dose up is drawn as the
/// estimate it is — the same rule every other inferred line in this app follows.
///
/// Wraps `ScrollableMetricChart` like every other historical chart here. The
/// first version did not, and it showed: it drew a fixed ninety days while the
/// card's picker said "M", could not be panned, and had none of the shared
/// scroll behaviour. A curve over months is history, and history in this app
/// pans and obeys the picker.
struct MedicationCurveChart: View {
    let points: [ActiveCompoundPoint]
    let compound: GLPCompound
    /// How much time fills the width — driven by the card's timeframe picker.
    var window: TimeInterval = 90 * 24 * 3600
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }
    private var tint: Color { .teal }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    private func point(at date: Date) -> ActiveCompoundPoint? {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            caption
        }
    }

    /// Above the chart, never a mark annotation — 3D chart content has none.
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(String(format: "%.2f mg", hit.level))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                if hit.restsOnInferredDose {
                    Text("· estimated").foregroundStyle(.tertiary)
                }
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
            selection: selectionBinding,
            height: 150,
            emptyMessage: "No doses in this window",
            isEmpty: { range in !points.contains { range.contains($0.date) } }
        ) { range in
            curveMarks(points.filter { range.contains($0.date) })
        }
    }

    /// Explicit `some ChartContent` — without it this chain can resolve to 3D
    /// content on this SDK and silently drop `.foregroundStyle` and
    /// `.lineStyle`, which here would erase the measured/estimated distinction
    /// entirely.
    @ChartContentBuilder
    private func curveMarks(_ visible: [ActiveCompoundPoint]) -> some ChartContent {
        // Two series rather than one styled per point: a `LineMark` takes its
        // stroke from the series, so mixing dashed and solid points inside one
        // series draws whichever the last point asked for.
        ForEach(visible.filter { !$0.restsOnInferredDose }) { point in
            LineMark(x: .value("Date", point.date), y: .value("In your system", point.level),
                     series: .value("Series", "measured"))
                .foregroundStyle(tint)
                .interpolationMethod(.linear)
        }
        ForEach(visible.filter(\.restsOnInferredDose)) { point in
            LineMark(x: .value("Date", point.date), y: .value("In your system", point.level),
                     series: .value("Series", "estimated"))
                .foregroundStyle(tint.opacity(0.6))
                .lineStyle(Theme.projectedStroke)
                .interpolationMethod(.linear)
        }
    }

    private var caption: some View {
        Text(points.contains(where: \.restsOnInferredDose)
             ? "Dashed where the line rests on doses the app worked out from your current dose rather than ones you logged — confirm or correct them below. Milligram-equivalent from \(compound.displayName)'s published half-life of \(Int(compound.eliminationHalfLifeHours / 24)) days; a model, not a measurement of your blood."
             : "Milligram-equivalent still active, from your logged doses and \(compound.displayName)'s published half-life of \(Int(compound.eliminationHalfLifeHours / 24)) days. A model of the drug's decay, not a measurement of your blood.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
