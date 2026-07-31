import SwiftUI
import InsightKit

/// The universal per-metric screen. For any metric it overlays every source on
/// one chart and shows the honest "Apple Watch: X · Oura: Y · Average: Z"
/// breakdown. Every card links here so multi-source data is treated the same way
/// everywhere.
struct MetricDetailView: View {
    /// What this screen is about. Blood pressure is a systolic/diastolic pair,
    /// so it can't be addressed by a single metric.
    let subject: MetricSubject

    init(subject: MetricSubject) { self.subject = subject }
    /// Source-compatible with every existing call site. Normalising means either
    /// half of a cuff reading opens the paired screen rather than a
    /// systolic-only chart.
    init(metric: MetricType) { self.subject = MetricSubject(metric: metric) }

    private var metric: MetricType { subject.primaryMetric }

    @Environment(AppModel.self) private var model
    @State private var logScale = false
    @State private var timeframe: Timeframe = .month
    /// The span the chart is currently showing; changes as the user pans.
    @State private var visibleRange: ClosedRange<Date>?
    /// Where the finger is while scrubbing, so the read-outs can follow it.
    @State private var scrubbed: Date?

    /// The whole history, handed to the chart so it has something to scroll
    /// through. The timeframe acts as the zoom level, not as a filter here.
    private var allData: MultiSourceBreakdown { model.breakdown(metric) }

    /// Restricted to what's on screen, so the per-source read-outs and averages
    /// describe the visible window rather than stale latest values.
    private var breakdown: MultiSourceBreakdown {
        if let visibleRange { return model.breakdown(metric, in: visibleRange) }
        return model.breakdown(metric, within: timeframe)
    }
    /// Seconds of history one chart-width shows. `.all` resolves against the
    /// data rather than a fixed constant, which is what stopped a short history
    /// being squashed into a sliver.
    private var window: TimeInterval {
        let span = allData.dateSpan.map { $0.upperBound.timeIntervalSince($0.lowerBound) }
        return timeframe.chartWindow(spanning: span)
    }

    /// Whether the metric has any data at all (across all time) — used so the
    /// timeframe picker stays available even when the chosen window is empty.
    private var hasAnyData: Bool { !allData.sources.isEmpty }

    /// Whether a dashed connector can appear at this zoom at all, so the key is
    /// only shown when the encoding is actually in play. O(1) — no history scan.
    /// The after-windows to shade behind this metric's chart, if it is one the
    /// substance analyzer compares at all.
    private var substanceWindows: [SubstanceWindow] {
        model.substanceWindows(for: metric)
    }

    private var canBridge: Bool {
        let bucket = BucketSize.forWindow(window)
        return SeriesBridging.maxBridgeableGap(for: allData.type, bucket: bucket, window: window)
            > allData.type.maxPlottableGap(bucket: bucket)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                switch subject.presentation {
                case .staticAttribute:
                    // A standing fact: no chart, no timeframe, no log toggle.
                    StaticAttributeCard(metric: metric)
                case .discreteBivariate:
                    BloodPressureSections(timeframe: $timeframe)
                default:
                    standardSections
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(subject.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The chart-based layout every metric except blood pressure and the static
    /// attributes uses, with a presentation-specific summary card on top.
    @ViewBuilder private var standardSections: some View {
        Group {
                if !hasAnyData {
                    ContentUnavailableView(
                        "No \(metric.displayName.lowercased()) yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Connect a device or Apple Health, then pull to refresh."))
                        .padding(.top, 40)
                } else {
                    MetricViewStrategy.summary(for: MetricDetailContext(
                        subject: subject,
                        timeframe: timeframe,
                        visibleRange: visibleRange))
                    overlayCard
                    if breakdown.sources.isEmpty {
                        Card {
                            Text("No \(metric.displayName.lowercased()) in the window shown. Swipe the chart sideways, or pick a longer timeframe.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Card {
                            SourceBreakdown(breakdown: breakdown,
                                            timeframe: timeframe,
                                            visibleRange: visibleRange,
                                            scrubbed: scrubbed)
                        }
                        if breakdown.hasMultipleSources { statsCard }
                    }
                }
        }
    }

    /// Names the span on screen: the timeframe's own label until the user pans
    /// away from the present, then the actual dates being shown.
    private var visibleLabel: String {
        guard let visibleRange, visibleRange.upperBound < Date().addingTimeInterval(-window / 20) else {
            return timeframe.longLabel
        }
        let from = visibleRange.lowerBound.formatted(date: .abbreviated, time: .omitted)
        let to = visibleRange.upperBound.formatted(date: .abbreviated, time: .omitted)
        return "\(from) – \(to)"
    }

    private var overlayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(visibleLabel).font(.headline)
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                if breakdown.hasMultipleSources {
                    Text("Each device is a separate colour, so you can spot where they disagree.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                MultiSourceChart(breakdown: allData,
                                 window: window,
                                 logarithmic: logScale,
                                 onVisibleRangeChange: { visibleRange = $0 },
                                 selection: $scrubbed,
                                 substanceWindows: substanceWindows)
                Text("Drag across the chart to read individual points; swipe it sideways to move back through your history.")
                    .font(.caption2).foregroundStyle(.tertiary)
                if canBridge {
                    Text("A dashed stretch joins two readings across a gap — nothing was measured along it.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                // The window was stated on the Substance Impact card and drawn
                // nowhere, so seeing which readings it covered meant doing date
                // arithmetic in your head against a chart.
                if !substanceWindows.isEmpty {
                    Text("The shaded columns are the \(Int(SubstanceResponseAnalyzer.afterWindow / 3600)) hours after something you logged — the readings Substance Impact compares against your unlogged days. It marks when, not whether anything happened.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A shaded band with no words is a coloured rectangle. The range
                // carries its own sentence and its own attribution, so a number
                // can't reach the screen without saying where it came from.
                if let reference = allData.type.referenceRange {
                    Text(reference.caption)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reference.provenance)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if subject.presentation.allowsLogScale {
                HStack {
                    Picker("Scale", selection: $logScale) {
                        Text("Linear").tag(false)
                        Text("Log").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    Spacer()
                }
                }
                if logScale {
                    Text("Logarithmic scale — useful when your sources differ by a wide margin.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var statsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Per-source averages").font(.headline)
                ForEach(Array(breakdown.sources.enumerated()), id: \.element.id) { index, series in
                    HStack(spacing: 9) {
                        Circle().fill(Theme.sourceColor(index)).frame(width: 9, height: 9)
                        Text(series.displayName)
                        Spacer()
                        if let mean = series.mean {
                            Text("\(formatMetric(mean, metric)) \(metric.unit)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text("· \(series.samples.count) readings")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}
