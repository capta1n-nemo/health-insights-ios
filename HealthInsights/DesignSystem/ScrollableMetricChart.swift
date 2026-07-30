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

    private var tickGranularity: AxisTickGranularity {
        Timeframe.tickGranularity(forSpan: window)
    }

    var body: some View {
        let range = visibleRange
        Chart {
            marks(plotRange)
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
        .overlay {
            if isEmpty(range) {
                Text(emptyMessage)
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .onAppear { onVisibleRangeChange?(visibleRange) }
        .onChange(of: scrollX) { onVisibleRangeChange?(visibleRange) }
        .onChange(of: window) {
            // A new zoom level re-anchors on the newest reading.
            scrollX = nil
            onVisibleRangeChange?(visibleRange)
        }
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

/// A padded Y-range so a single point or a flat line isn't glued to an edge.
func paddedYDomain(_ values: [Double], logarithmic: Bool = false) -> ClosedRange<Double>? {
    guard let lo = values.min(), let hi = values.max() else { return nil }
    let useLog = logarithmic && values.allSatisfy { $0 > 0 }
    if lo == hi {
        let pad = Swift.max(abs(lo) * 0.05, 1)
        let lower = useLog ? Swift.max(lo * 0.9, 0.0001) : lo - pad
        return lower...(hi + pad)
    }
    let span = hi - lo
    let lower = useLog ? Swift.max(lo * 0.7, 0.0001) : lo - span * 0.1
    return lower...(hi + span * 0.1)
}
