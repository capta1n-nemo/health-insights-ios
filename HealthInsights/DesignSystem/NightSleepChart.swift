import SwiftUI
import Charts
import InsightKit

/// One night, one lane per source: stage bands where a source recorded them,
/// a single stageless block where it only knows its window — and the gaps left
/// as gaps.
///
/// Built at the user's request off the night of 2026-07-29, which Oura filed as
/// 4.3 h and Apple Health as 8.5 h. Drawn on one axis, that night stops being a
/// contradiction: a block of sleep, a wake, and a morning re-sleep that one
/// source typed as a nap. The gaps are the finding, so nothing here bridges —
/// an absence of colour means "this source recorded nothing there", which is
/// the one thing an aggregate number can never say.
///
/// A plain `Chart`, not `ScrollableMetricChart`: the same exemption as
/// `EnergyCurveChart`, and for the same reason — a single night is never longer
/// than the screen, and a pannable axis would let the reader drag it off the
/// edge and find nothing on either side.
struct NightSleepChart: View {
    /// Optional for the same reason the wrapper's is.
    @Environment(AppModel.self) private var model: AppModel?
    let detail: NightSleepDetail
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    /// Fixed semantic colours — stages are categories, not series, so the
    /// palette machinery for keeping metrics apart does not apply. Awake is the
    /// warm one on purpose: inside a night it is the interruption.
    ///
    /// Not `private`: `SleepStageAverageChart` draws the same four stages over a
    /// window and has to agree with this one bar for bar. A second copy of four
    /// colours is a copy that drifts, and the two charts sit on the same card.
    static func color(for stage: NightSleepDetail.Stage?) -> Color {
        switch stage {
        case .deep: return .indigo
        case .light: return .teal
        case .rem: return .purple
        case .awake: return .orange
        case nil: return .gray.opacity(0.5)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            key
            caption
        }
    }

    /// Above the chart, never a mark annotation — 3D chart content has none.
    @ViewBuilder private var readout: some View {
        if let selected {
            HStack(spacing: 8) {
                Text(selected.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                ForEach(detail.lanes) { lane in
                    if let band = lane.bands.first(where: {
                        $0.start <= selected && selected < $0.end
                    }) {
                        Text("\(lane.source): \(band.stage?.label ?? "asleep")")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            // The night's identity when nothing is scrubbed, so a stale night
            // can never pose as last night.
            Text(detail.night.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart {
            // Same reason as `EnergyCurveChart`: one night is never longer than
            // the screen, so this does not wrap `ScrollableMetricChart` and does
            // not inherit its shading. A drink before bed lands squarely here.
            SubstanceShading.marks(model?.allSubstanceWindows ?? [], in: domain)
            marks
        }
        .chartXScale(domain: domain.lowerBound...domain.upperBound)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXSelection(value: selectionBinding)
        .frame(height: CGFloat(detail.lanes.count) * 46 + 24)
    }

    private var domain: ClosedRange<Date> {
        detail.window ?? detail.night...detail.night.addingTimeInterval(86_400)
    }

    /// Explicit `some ChartContent` — without it this chain can resolve to 3D
    /// content on this SDK and silently drop `.foregroundStyle`.
    @ChartContentBuilder
    private var marks: some ChartContent {
        ForEach(detail.lanes) { lane in
            ForEach(lane.bands) { band in
                RectangleMark(
                    xStart: .value("From", band.start),
                    xEnd: .value("To", band.end),
                    y: .value("Source", lane.source),
                    height: .ratio(0.58)
                )
                .foregroundStyle(Self.color(for: band.stage))
            }
        }
        ScrubIndicator.at(selected)
    }

    /// Plain, opaque swatches: a key answers "which stage is this", nothing
    /// about what it sits beside.
    private var key: some View {
        HStack(spacing: 10) {
            ForEach(NightSleepDetail.Stage.allCases, id: \.self) { stage in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(for: stage))
                        .frame(width: 8, height: 8)
                    Text(stage.label)
                }
            }
            if detail.lanes.contains(where: { !$0.hasStageDetail }) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(for: nil))
                        .frame(width: 8, height: 8)
                    Text("No stage detail")
                }
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var caption: some View {
        Text("Each row is one source's own account of the night, gaps included — a blank stretch means that source recorded nothing there. A grey block is a source that reports only when it thinks you slept, drawn from its onset and total without stage detail.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
