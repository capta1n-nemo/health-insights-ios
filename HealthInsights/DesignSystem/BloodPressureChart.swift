import SwiftUI
import Charts
import InsightKit

/// Systolic and diastolic drawn together, with the ACC/AHA bands behind them.
///
/// Extracted from `BloodPressureSections` so the insight card and the
/// blood-pressure metric screen draw the *same* chart rather than two that drift.
/// Blood pressure was the one insight whose chart lived on a different screen
/// from the card that talks about it; moving it meant either duplicating this or
/// sharing it, and a chart with this many SDK hazards in it is not one to have
/// two copies of.
///
/// Takes `timeframe` by value, not as a binding: the two callers put their
/// picker in different places — the insight screen hoists one picker above every
/// section, the metric screen keeps its own — and neither needs this view to own
/// the control.
struct BloodPressureChart: View {
    let readings: [BloodPressureEstimator.Reading]
    let timeframe: Timeframe
    /// Whether to draw the legend and category strip beneath the plot. The
    /// insight card wants them; a caller that has already explained the encoding
    /// nearby does not.
    var showsKey: Bool = true

    @State private var selected: Date?

    private var dataSpan: ClosedRange<Date>? {
        let dates = readings.map(\.date)
        guard let lo = dates.min(), let hi = dates.max(), lo <= hi else { return nil }
        return lo...hi
    }

    private var window: TimeInterval {
        timeframe.chartWindow(spanning: dataSpan.map {
            $0.upperBound.timeIntervalSince($0.lowerBound)
        })
    }

    /// The reading nearest the crosshair, when one is close enough to be what
    /// the user is pointing at.
    private func reading(at date: Date) -> BloodPressureEstimator.Reading? {
        guard let nearest = readings.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else { return nil }
        return abs(nearest.date.timeIntervalSince(date)) <= window / 8 ? nearest : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            readout
            chart
            if showsKey {
                legend
                categoryStrip
            }
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: dataSpan,
            window: window,
            selection: $selected,
            height: 180,
            emptyMessage: "No readings in this window — swipe sideways to look further back.",
            isEmpty: { range in !readings.contains { range.contains($0.date) } },
            yDomain: { range in
                let visible = readings.filter { range.contains($0.date) }
                return paddedYDomain(visible.flatMap { [$0.systolic, $0.diastolic] })
            }
        ) { range in
            pairMarks(readings.filter { range.contains($0.date) }, across: range)
        }
    }

    @ChartContentBuilder
    private func pairMarks(_ visible: [BloodPressureEstimator.Reading],
                           across range: ClosedRange<Date>) -> some ChartContent {
        bandMarks(across: range)
        ForEach(visible) { r in
            marks(for: r)
        }
    }

    /// The ACC/AHA bands shaded behind the readings, so a point's category is
    /// legible without consulting the axis.
    ///
    /// **Systolic bands only, deliberately.** The two lines share one mmHg axis
    /// but not one set of thresholds — 85 is stage 1 diastolic and entirely
    /// normal systolic — so a single shaded set cannot be correct for both. The
    /// diastolic thresholds are drawn as thin rules instead, and the caption
    /// says which is which. The alternative, shading one set and letting it read
    /// as applying to both, would be a chart that lies.
    ///
    /// Explicit `-> some ChartContent` on every builder here: horizontal band
    /// marks are exactly the family that resolves to `Chart3DContent` on this
    /// SDK and silently drops `.foregroundStyle`.
    @ChartContentBuilder
    private func bandMarks(across range: ClosedRange<Date>) -> some ChartContent {
        ForEach(BloodPressureEstimator.Category.allCases, id: \.self) { category in
            RectangleMark(
                xStart: .value("From", range.lowerBound),
                xEnd: .value("To", range.upperBound),
                yStart: .value("Low", category.systolicRange.lower),
                // A finite top for the open-ended band: the y-domain is fitted
                // to the readings, so anything past the highest plausible
                // reading is off-screen anyway.
                yEnd: .value("High", category.systolicRange.upper ?? 260))
                .foregroundStyle(Self.color(for: category).opacity(0.10))
        }
        // Dashed, and in a neutral hue. These were solid and in the *same*
        // colour as the measured diastolic line, so a reference level was
        // indistinguishable from a measurement — which is the one thing the
        // app's dash rule exists to prevent.
        ForEach([80.0, 90.0, 120.0], id: \.self) { threshold in
            RuleMark(y: .value("Diastolic threshold", threshold))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(Theme.referenceStroke)
        }
    }

    /// Systolic and diastolic wear their *metric* hues here, resolved against
    /// each other, so they match every overlay chart in the app.
    private var pressureSlots: [MetricType: Int] {
        MetricPalette.slots(for: [.bloodPressureSystolic, .bloodPressureDiastolic])
    }

    /// Kept in its own function with an explicit return type, which pins these
    /// to 2D chart content instead of leaving resolution to inference.
    @ChartContentBuilder
    private func marks(for r: BloodPressureEstimator.Reading) -> some ChartContent {
        LineMark(x: .value("Date", r.date), y: .value("mmHg", r.systolic),
                 series: .value("Reading", "Systolic"))
            .foregroundStyle(Theme.metricColor(.bloodPressureSystolic, slots: pressureSlots))
            .interpolationMethod(.linear)
        PointMark(x: .value("Date", r.date), y: .value("mmHg", r.systolic))
            .foregroundStyle(Theme.metricColor(.bloodPressureSystolic, slots: pressureSlots)).symbolSize(20)
        LineMark(x: .value("Date", r.date), y: .value("mmHg", r.diastolic),
                 series: .value("Reading", "Diastolic"))
            .foregroundStyle(Theme.metricColor(.bloodPressureDiastolic, slots: pressureSlots))
            .interpolationMethod(.linear)
        PointMark(x: .value("Date", r.date), y: .value("mmHg", r.diastolic))
            .foregroundStyle(Theme.metricColor(.bloodPressureDiastolic, slots: pressureSlots)).symbolSize(20)
    }

    /// The reading under the finger, shown above the chart: in-chart annotations
    /// resolve to `Chart3DContent` on this SDK and lose their modifiers.
    @ViewBuilder private var readout: some View {
        if let selected, let r = reading(at: selected) {
            HStack(spacing: 8) {
                Text("\(Int(r.systolic.rounded()))/\(Int(r.diastolic.rounded())) mmHg")
                    .fontWeight(.semibold).monospacedDigit()
                Text(r.category).foregroundStyle(.secondary)
                Text("MAP \(Int(r.meanArterialPressure.rounded()))")
                    .foregroundStyle(.secondary)
                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.caption2)
        } else {
            // Reserve the row so the chart doesn't jump as scrubbing starts.
            Text(" ").font(.caption2)
        }
    }

    /// The legend names the two lines by their own metric hues — the same ones
    /// the marks are drawn in. It used to name them in the *source* palette,
    /// which meant the dots disagreed with the lines above them.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                legendDot("Systolic", Theme.metricColor(.bloodPressureSystolic, slots: pressureSlots))
                legendDot("Diastolic", Theme.metricColor(.bloodPressureDiastolic, slots: pressureSlots))
                Spacer()
            }
            Text("Shaded bands are the systolic categories. The two numbers don't share thresholds — 85 is stage 1 diastolic but normal systolic — so the diastolic limits (80, 90, 120) are the thin dashed lines.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).foregroundStyle(.secondary)
        }
    }

    /// Where the latest reading sits among the ACC/AHA categories.
    @ViewBuilder private var categoryStrip: some View {
        if let latest = readings.first {
            let current = latest.categoryValue
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(BloodPressureEstimator.Category.allCases, id: \.self) { category in
                        Text(Self.shortName(category))
                            .font(.caption2)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(category == current ? Self.color(for: category).opacity(0.85)
                                                            : Self.color(for: category).opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(category == current ? .white : .secondary)
                    }
                }
                Text("Latest reading is \(current.displayName.lowercased()).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    static func shortName(_ category: BloodPressureEstimator.Category) -> String {
        switch category {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .stage1: return "Stage 1"
        case .stage2: return "Stage 2"
        case .crisis: return "Crisis"
        }
    }

    static func color(for category: BloodPressureEstimator.Category) -> Color {
        switch category {
        case .normal: return Theme.good
        case .elevated: return Theme.warn
        case .stage1, .stage2, .crisis: return Theme.bad
        }
    }
}
