import SwiftUI
import Charts
import InsightKit

/// The consolidated blood-pressure screen: systolic and diastolic together,
/// calibration progress, and the full dated history merged from everywhere
/// (in-app, Apple Health, Withings).
///
/// Migrated out of the standalone `BloodPressureLogView` so blood pressure uses
/// the same chart plumbing as every other metric. **The grounding rules are
/// unchanged**: five readings to ground, only the last 30 days count, older
/// readings are listed but don't contribute.
struct BloodPressureSections: View {
    @Environment(AppModel.self) private var model
    @Binding var timeframe: Timeframe
    @State private var showingAdd = false
    @State private var selected: Date?
    @State private var showAllEarlier = false

    private var readings: [BloodPressureEstimator.Reading] { model.bloodPressureReadings }
    private var status: BloodPressureEstimator.CalibrationStatus { model.bloodPressureCalibration }

    private var split: (recent: [BloodPressureEstimator.Reading],
                        earlier: [BloodPressureEstimator.Reading]) {
        BloodPressureEstimator.split(readings)
    }

    private var dataSpan: ClosedRange<Date>? {
        let dates = readings.map(\.date)
        guard let lo = dates.min(), let hi = dates.max(), lo <= hi else { return nil }
        return lo...hi
    }

    private var window: TimeInterval {
        timeframe.chartWindow(spanning: dataSpan.map { $0.upperBound.timeIntervalSince($0.lowerBound) })
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
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if !readings.isEmpty { chartCard }
            calibrationCard
            if readings.isEmpty { emptyCard } else { historyCard }
        }
        .sheet(isPresented: $showingAdd) {
            AddBloodPressureView { systolic, diastolic, date in
                model.logBloodPressure(systolic: systolic, diastolic: diastolic, at: date)
            }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                readout
                chart
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
    /// diastolic thresholds are drawn as thin rules instead, in the diastolic
    /// line's own colour, and the caption says which is which. The alternative,
    /// shading one set and letting it read as applying to both, would be a chart
    /// that lies.
    ///
    /// Explicit `-> some ChartContent` on every builder here: horizontal band
    /// marks are exactly the family that resolves to `Chart3DContent` on this
    /// SDK and silently drops `.foregroundStyle`. That hazard is why this screen
    /// previously had a strip under the chart instead of bands behind it.
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
                .foregroundStyle(color(for: category).opacity(0.10))
        }
        ForEach([80.0, 90.0, 120.0], id: \.self) { threshold in
            RuleMark(y: .value("Diastolic threshold", threshold))
                .foregroundStyle(Theme.sourceColor(1).opacity(0.30))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    /// Kept in its own function with an explicit return type, which pins these
    /// to 2D chart content instead of leaving resolution to inference.
    @ChartContentBuilder
    private func marks(for r: BloodPressureEstimator.Reading) -> some ChartContent {
        LineMark(x: .value("Date", r.date), y: .value("mmHg", r.systolic),
                 series: .value("Reading", "Systolic"))
            .foregroundStyle(Theme.sourceColor(0))
            .interpolationMethod(.linear)
        PointMark(x: .value("Date", r.date), y: .value("mmHg", r.systolic))
            .foregroundStyle(Theme.sourceColor(0)).symbolSize(20)
        LineMark(x: .value("Date", r.date), y: .value("mmHg", r.diastolic),
                 series: .value("Reading", "Diastolic"))
            .foregroundStyle(Theme.sourceColor(1))
            .interpolationMethod(.linear)
        PointMark(x: .value("Date", r.date), y: .value("mmHg", r.diastolic))
            .foregroundStyle(Theme.sourceColor(1)).symbolSize(20)
    }

    /// The reading under the finger, shown above the chart: in-chart annotations
    /// resolve to Chart3DContent on this SDK and lose their modifiers.
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

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                legendDot("Systolic", Theme.sourceColor(0))
                legendDot("Diastolic", Theme.sourceColor(1))
                Spacer()
            }
            Text("Shaded bands are the systolic categories. The two numbers don't share thresholds — 85 is stage 1 diastolic but normal systolic — so the diastolic limits (80, 90, 120) are the thin lines in its own colour.")
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

    /// The ACC/AHA bands as a strip beneath the chart rather than shading behind
    /// it: horizontal band marks are the API family that breaks on this SDK, and
    /// a labelled strip reads more clearly anyway.
    @ViewBuilder private var categoryStrip: some View {
        if let latest = readings.first {
            let current = latest.categoryValue
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(BloodPressureEstimator.Category.allCases, id: \.self) { category in
                        Text(shortName(category))
                            .font(.caption2)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(category == current ? color(for: category).opacity(0.85)
                                                            : color(for: category).opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(category == current ? .white : .secondary)
                    }
                }
                Text("Latest reading is \(current.displayName.lowercased()).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func shortName(_ category: BloodPressureEstimator.Category) -> String {
        switch category {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .stage1: return "Stage 1"
        case .stage2: return "Stage 2"
        case .crisis: return "Crisis"
        }
    }

    private func color(for category: BloodPressureEstimator.Category) -> Color {
        switch category {
        case .normal: return Theme.good
        case .elevated: return Theme.warn
        case .stage1, .stage2, .crisis: return Theme.bad
        }
    }

    // MARK: Calibration

    private var calibrationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calibration").font(.headline)
                Button {
                    showingAdd = true
                } label: {
                    Label("Add a reading", systemImage: "plus.circle.fill")
                }
                CalibrationProgress(status: status)
                Text("Grounding uses only readings from the last 30 days: log \(BloodPressureEstimator.initialCalibrationReadings) to ground the estimate, and because readings stop counting after 30 days you'll need to add fresh ones over time. Readings already in Apple Health count automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var emptyCard: some View {
        Card {
            Text("No readings yet. Add one from a cuff, or log some in Apple Health — they'll show here automatically with their dates.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: History

    /// A lazy stack rather than a List, because this screen is a ScrollView of
    /// cards and a List cannot nest inside one. Older readings are paged so a
    /// long history doesn't build hundreds of rows at once.
    private var historyCard: some View {
        let parts = split
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                if !parts.recent.isEmpty {
                    Text("Last 30 days · \(parts.recent.count)").font(.headline)
                    LazyVStack(spacing: 8) {
                        ForEach(parts.recent) { readingRow($0) }
                    }
                }
                if !parts.earlier.isEmpty {
                    Divider()
                    Text("Earlier · \(parts.earlier.count)")
                        .font(.subheadline.weight(.semibold))
                    Text("Listed for reference — these no longer count towards grounding.")
                        .font(.caption2).foregroundStyle(.tertiary)
                    LazyVStack(spacing: 8) {
                        ForEach(showAllEarlier ? parts.earlier : Array(parts.earlier.prefix(20))) {
                            readingRow($0)
                        }
                    }
                    if !showAllEarlier, parts.earlier.count > 20 {
                        Button("Show all \(parts.earlier.count)") { showAllEarlier = true }
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private func readingRow(_ r: BloodPressureEstimator.Reading) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(r.systolic.rounded()))/\(Int(r.diastolic.rounded())) mmHg")
                    .font(.body.weight(.semibold))
                Text(r.category)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                Text(r.source).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
