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
    /// Only for the caption below — the shading itself is drawn by
    /// `ScrollableMetricChart` on every chart in the app now.
    private var substanceWindows: [SubstanceWindow] { model.allSubstanceWindows }

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
                // **Outside the switch, deliberately.** It sat inside
                // `standardSections` until 2026-08-06, which meant three whole
                // classes of page never showed it: height (a static attribute),
                // blood pressure (the bivariate branch — it had an explanation
                // written and rendered nowhere), and any metric whose window is
                // empty, which is the moment "what even is this" is asked most.
                // The reader's rule is every data entry, so it is drawn for
                // every one of them.
                explainerCard
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
                    // **One card either way, and it is always here.** This used
                    // to be an if/else between two different cards and a
                    // `breakdown.hasMultipleSources` gate on the stats card
                    // below — both keyed off the *visible* window, so panning
                    // into a stretch a device did not cover removed whole cards
                    // from a `ScrollView` mid-drag. `SourceBreakdown` already
                    // carries its own honest empty state ("No source reported
                    // in this window."), so the branch only adds the way out.
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SourceBreakdown(breakdown: breakdown,
                                            timeframe: timeframe,
                                            visibleRange: visibleRange,
                                            scrubbed: scrubbed)
                            if breakdown.sources.isEmpty {
                                Text("No \(metric.displayName.lowercased()) in the window shown. Swipe the chart sideways, tap the arrows on its edges to jump to your nearest readings, or pick a longer timeframe.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    // Gated on the whole history, not the window — see
                    // `statsCard`.
                    if allData.hasMultipleSources { statsCard }
                }
        }
    }

    /// **"What even is HRV… am I about to die?"** — the reader, 2026-08-05.
    ///
    /// Three parts, in the order someone actually asks them: what the term is,
    /// what *theirs* is, and why it is worth knowing. The middle one is built
    /// from their own history rather than a population table, because for
    /// several of these the spread between healthy people is wider than the
    /// spread within one — see `MetricExplainer.yours`.
    ///
    /// **Never absent now.** It used to be skipped for the thirty-six metrics
    /// `MetricExplainer` returned nil for; the reader overruled that on
    /// 2026-08-06 — *"I want that kind of description on EVERY data entry"* —
    /// and `explanation(for:)` is non-optional, so there is nothing left to
    /// branch on.
    private var explainerCard: some View {
        let explanation = MetricExplainer.explanation(for: metric)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                // **Not `.lowercased()`.** Several of these display names
                // are acronyms or carry internal capitals — it rendered as
                // "What hrv (rmssd) is" and "What vo₂max is", which reads
                // as a typo in a card whose whole job is to sound like a
                // person explaining something.
                //
                // The **subject's** name, not the metric's: a blood-pressure
                // page's primary metric is systolic, and the heading read
                // "What Systolic BP is" over prose about both numbers.
                Text("What \(subject.displayName) is")
                    .font(.headline)
                Text(explanation.whatItIs)
                    .font(.subheadline)
                if let yours = personalReading {
                    Text(yours)
                        .font(.subheadline.weight(.medium))
                }
                Text(explanation.soWhat)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The reader's own latest value against their own spread. `nil` — and so
    /// the row is absent rather than hedged — until there is enough history for
    /// "your usual" to mean anything.
    /// **One instrument, not a pool.** Taking "your usual range" across every
    /// source would put the watch and the ring in one distribution, and on this
    /// reader's own record those differ by about 13 bpm on resting heart rate —
    /// far more than illness moves it. A pooled p10–p90 would be the gap
    /// between two devices dressed as the reader's own variability, and today's
    /// value would sit "in the middle" of a range it is nowhere near. The
    /// densest source is the one the reader actually wears.
    /// ⚠️ **Memoized, because this is a computed property read from a `body`
    /// and it touches every reading of the densest source** — tens of thousands
    /// for heart rate. Unmemoized it allocated that array and sorted it on
    /// every body evaluation, which is the exact shape that made the Insights
    /// hero laggy in 2026-08-02 (`InsightsListView.comparisonSeries`). The key
    /// carries the metric so two detail pages cannot share an answer.
    /// **Single-metric pages only.** Blood pressure's primary metric is
    /// systolic, so on that page this would print a bare "Yours is 122 mmHg"
    /// under a heading about two numbers, with nothing saying which one it is.
    /// `BloodPressureSections` reads the pair properly; this stays quiet there.
    private var personalReading: String? {
        guard case .single = subject else { return nil }
        return model.memoized("explainer.\(metric.rawValue)") {
            guard let series = allData.sources.max(by: { $0.samples.count < $1.samples.count }),
                  let latest = series.samples.last else { return String?.none }
            return MetricExplainer.yours(metric, value: latest.value,
                                         history: series.samples.map(\.value))
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
                                 selection: $scrubbed)
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
                    Text(SubstanceShading.caption)
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

    /// **Rows come from the whole history; only the figures come from the
    /// window.** Two defects, one change:
    ///
    ///  * it was gated on `breakdown.hasMultipleSources` and iterated the
    ///    *visible* breakdown, so panning into a stretch only one device covered
    ///    deleted the card — a sibling of the chart in one `ScrollView`, so the
    ///    page shortened under the finger and the chart jumped. Fixed by gating
    ///    on `allData` and keeping the row count constant for the page's life.
    ///  * `Theme.sourceColor(index)` is positional and
    ///    `MultiSourceBreakdown.sources` is ordered *most-data-first*, so
    ///    restricting to a window could **reorder** it and give a device a
    ///    different swatch from the one the chart drew it in. The chart indexes
    ///    `allData` (`MultiSourceChart.range`); so does this now.
    private var statsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Per-source averages").font(.headline)
                ForEach(Array(allData.sources.enumerated()), id: \.element.id) { index, series in
                    let visible = breakdown.sources.first { $0.id == series.id }
                    HStack(spacing: 9) {
                        Circle().fill(Theme.sourceColor(index)).frame(width: 9, height: 9)
                        Text(series.displayName)
                        Spacer()
                        if let visible, let mean = visible.mean {
                            Text(MetricValueFormatter.detailedString(mean, metric))
                                .foregroundStyle(.secondary).monospacedDigit()
                            Text("· \(visible.samples.count) readings")
                                .font(.caption).foregroundStyle(.tertiary)
                        } else {
                            // Named and present, saying nothing it cannot back
                            // up — rather than silently absent, which reads as
                            // "this device is gone".
                            Text("nothing in this period")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}
