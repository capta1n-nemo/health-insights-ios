import SwiftUI
import Charts
import InsightKit

/// Owns pan, zoom, scrub and the axis scales for every metric chart in the app.
///
/// Extracted so the strategy-specific charts (trend line, range band, blood
/// pressure) don't each re-implement scrolling and selection — the blood-pressure
/// screen previously carried a second copy of all of it.
///
/// Marks come from the caller, which is handed the padded date range it should
/// plot so it can slice and thin its own data.
struct ScrollableMetricChart<Marks: ChartContent>: View {
    /// Optional so a chart rendered outside the app's own hierarchy — a
    /// preview, a snapshot harness — draws without one rather than trapping.
    @Environment(AppModel.self) private var model: AppModel?

    /// Extent of the whole history; the scroll domain derives from it.
    let dataSpan: ClosedRange<Date>?
    /// How much time fills the chart's width — the zoom level.
    let window: TimeInterval
    /// Scrub position, owned by the caller so it can render its read-out above
    /// the chart. In-chart annotations are avoided: on the iOS 26 SDK a
    /// `RuleMark` chain resolves to `Chart3DContent`, which has no `annotation`.
    @Binding var selection: Date?

    var logarithmic: Bool = false
    var height: CGFloat = 170
    var emptyMessage: String = "No readings in this window"
    /// Whether the visible range has anything to show, asked of the caller since
    /// only it knows how its data is shaped.
    var isEmpty: (ClosedRange<Date>) -> Bool = { _ in false }
    /// Y-range for the visible slice, so panning rescales rather than flattening
    /// everything against an outlier elsewhere in the history.
    var yDomain: (ClosedRange<Date>) -> ClosedRange<Double>? = { _ in nil }
    var onVisibleRangeChange: ((ClosedRange<Date>) -> Void)?
    @ChartContentBuilder var marks: (ClosedRange<Date>) -> Marks

    /// Leading edge of the visible window; nil until the user pans.
    @State private var scrollX: Date?

    /// Anchor the initial view on the newest reading rather than on "now", so a
    /// metric that last reported a while ago still opens showing its data.
    private var defaultStart: Date {
        (dataSpan?.upperBound ?? Date()).addingTimeInterval(-window)
    }

    private var visibleStart: Date { scrollX ?? defaultStart }

    private var visibleRange: ClosedRange<Date> {
        visibleStart...visibleStart.addingTimeInterval(window)
    }

    /// A window either side of what's on screen, so a pan doesn't reveal an
    /// empty chart before the next redraw.
    private var plotRange: ClosedRange<Date> {
        let lower = visibleStart.addingTimeInterval(-window)
        let upper = visibleStart.addingTimeInterval(window * 2)
        return lower...upper
    }

    /// The scrollable extent.
    ///
    /// The visible length must never exceed this or Charts squashes the data
    /// into a sliver at the leading edge — the bug behind "All shows a thin
    /// strip". Extending leftwards keeps the newest reading pinned right.
    private var scrollDomain: ClosedRange<Date> {
        guard let dataSpan else {
            let now = Date()
            return now.addingTimeInterval(-window)...now
        }
        let start = min(dataSpan.lowerBound,
                        dataSpan.upperBound.addingTimeInterval(-window))
        return start...dataSpan.upperBound
    }

    private var scrollBinding: Binding<Date> {
        Binding(get: { visibleStart }, set: { scrollX = $0 })
    }

    // MARK: - Jump to the nearest data
    //
    // **The reader, 2026-08-07:** *"when no data is visible, show a `<` on the
    // left edge to auto-pan to the nearest data point to the left, and a `>` on
    // the right edge for the nearest to the right."*
    //
    // It lives here rather than in a caller because this is the app's **only**
    // pannable chart — `chartScrollableAxes` appears exactly once in the whole
    // target, on the `Chart` below — so all thirteen wrappers inherit the
    // affordance without a line of their own. The search asks the caller's own
    // `isEmpty` predicate, which every wrapper already supplies for the empty
    // overlay, so there is no second definition of "there is data here" to keep
    // in step and no call-site change.

    /// The earliest window start the scroll domain allows.
    private var earliestStart: Date { scrollDomain.lowerBound }

    /// The latest window start the scroll domain allows. `scrollDomain` is never
    /// shorter than one window (see above), so this cannot precede the earliest.
    private var latestStart: Date {
        max(scrollDomain.lowerBound, scrollDomain.upperBound.addingTimeInterval(-window))
    }

    /// Whether any reading lies before / after what is on screen.
    ///
    /// Answered from `dataSpan` rather than by scanning: its bounds *are*
    /// readings, so the test is O(1) and safe to ask on every redraw. The scan
    /// only runs when the chevron is actually tapped.
    private var hasDataBefore: Bool {
        guard let dataSpan else { return false }
        return dataSpan.lowerBound < visibleRange.lowerBound && visibleStart > earliestStart
    }

    private var hasDataAfter: Bool {
        guard let dataSpan else { return false }
        return dataSpan.upperBound > visibleRange.upperBound && visibleStart < latestStart
    }

    /// Nearest window start in the given direction that the caller calls
    /// non-empty.
    ///
    /// **Contiguous whole-window probes, not a widening gallop.** Stepping one
    /// window at a time tiles the history end to end with no gaps, so the first
    /// hit really is the nearest window holding data rather than whichever one a
    /// doubling stride happened to land on. Capped, because `isEmpty` is the
    /// caller's predicate and a two-day window over a decade of history would
    /// ask it thousands of times; on the cap it falls back to the far edge of
    /// the scroll domain, where `dataSpan` guarantees a reading.
    private func nearestPopulatedStart(before: Bool) -> Date {
        let edge = before ? earliestStart : latestStart
        var start = visibleStart
        for _ in 0..<400 {
            let next = start.addingTimeInterval(before ? -window : window)
            start = before ? max(next, edge) : min(next, edge)
            if !isEmpty(start...start.addingTimeInterval(window)) { return start }
            if start == edge { return edge }
        }
        return edge
    }

    private var tickGranularity: AxisTickGranularity {
        Timeframe.tickGranularity(forSpan: window)
    }

    var body: some View {
        let range = visibleRange
        Chart {
            // **First, so it sits behind the data** — and here rather than in
            // each caller, which is what makes "on every chart" a property of
            // the code instead of a thing each author has to remember. See
            // `SubstanceShading` for the user's rule and what the shading is
            // allowed to claim.
            SubstanceShading.marks(model?.allSubstanceWindows ?? [], in: plotRange)
            marks(plotRange)
            // Drawn here rather than by each caller, so every chart that wraps
            // this one — score history, multi-source, blood pressure, the
            // overlay, the age charts, substance load — gets the same scrub line
            // without seven copies of it. Last, so it sits over the data.
            ScrubIndicator.at(selection)
        }
        .modifier(MetricYScale(domain: yDomain(range), log: logarithmic))
        .chartLegend(.hidden)
        .chartScrollableAxes(.horizontal)
        .chartXScale(domain: scrollDomain)
        .chartXVisibleDomain(length: window)
        .chartScrollPosition(x: scrollBinding)
        .chartXSelection(value: $selection)
        .chartXAxis { axisMarks }
        .frame(height: height)
        .overlay { emptyOverlay(range) }
        .onAppear { onVisibleRangeChange?(visibleRange) }
        .onChange(of: scrollX) { onVisibleRangeChange?(visibleRange) }
        .onChange(of: window) {
            // A new zoom level re-anchors on the newest reading.
            scrollX = nil
            onVisibleRangeChange?(visibleRange)
        }
    }

    /// What an empty window says, and the two ways out of it.
    ///
    /// The message stays centred and the chevrons sit on the edges they point
    /// at, so the affordance reads as "your data is that way" rather than as a
    /// pair of unexplained buttons. Each is shown only when there is something
    /// that way to reach.
    @ViewBuilder private func emptyOverlay(_ range: ClosedRange<Date>) -> some View {
        if isEmpty(range) {
            ZStack {
                Text(emptyMessage)
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    // Wider than the plain `.horizontal` it replaced, so the
                    // text cannot run under the chevrons.
                    .padding(.horizontal, 48)
                HStack {
                    if hasDataBefore { jumpButton(before: true) }
                    Spacer(minLength: 0)
                    if hasDataAfter { jumpButton(before: false) }
                }
            }
        }
    }

    private func jumpButton(before: Bool) -> some View {
        Button {
            let target = nearestPopulatedStart(before: before)
            // Animated, because an instant teleport across a year of history
            // gives no sense of which way you just moved.
            withAnimation(.easeInOut(duration: 0.35)) { scrollX = target }
        } label: {
            Image(systemName: before ? "chevron.left" : "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(8)
                .background(.thinMaterial, in: Circle())
                // The material circle is the hit area; without this the tap
                // target is the glyph's own bounding box, which is tiny.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel(before ? "Jump to the nearest earlier readings"
                                   : "Jump to the nearest later readings")
    }

    /// Labels sized to the span on screen, so an all-time chart reads
    /// "2024 · 2025 · 2026" instead of repeating a day-level format.
    private var axisMarks: AxisMarks<some AxisMark> {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisTick()
            if let date = value.as(Date.self) {
                AxisValueLabel { Text(dateLabel(date)) }
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        switch tickGranularity {
        case .hour: return date.formatted(.dateTime.hour())
        case .day: return date.formatted(.dateTime.day().month(.abbreviated))
        case .month: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        case .year: return date.formatted(.dateTime.year())
        }
    }
}

/// Applies the optional padded Y domain, in linear or logarithmic mode.
///
/// A modifier rather than an inline conditional because `chartYScale` returns a
/// different type in each branch.
struct MetricYScale: ViewModifier {
    let domain: ClosedRange<Double>?
    let log: Bool

    func body(content: Content) -> some View {
        if let domain, domain.lowerBound < domain.upperBound {
            if log, domain.lowerBound > 0 {
                content.chartYScale(domain: domain, type: .log)
            } else {
                content.chartYScale(domain: domain)
            }
        } else {
            content
        }
    }
}

// `paddedYDomain` moved to InsightKit (`Presentation/MetricReferenceRange.swift`).
// It decides what a chart's axis claims about the spread of the data — a
// correctness question — and here nothing could test it. Every call site already
// imports InsightKit, so the name still resolves.
