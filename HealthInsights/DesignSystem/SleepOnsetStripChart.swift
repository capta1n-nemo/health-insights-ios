import SwiftUI
import Charts
import InsightKit

/// A fortnight of bedtimes against the middle they are measured from.
///
/// Sleep Regularity scores the *spread* of sleep onset about its own centre, and
/// until this existed the detail screen drew the score history like every other
/// card — a month of numbers, which answers "has my regularity been improving"
/// and not "what does my regularity look like". Those are different questions
/// and only the second one is what the card is about. A regular sleeper is a
/// tight column here; an irregular one is scatter. That picture is the finding,
/// and no summary statistic renders it.
///
/// ## The nights come from the model, not from this file
///
/// `CircadianConsistencyModel.Output.nights` carries each night *with the centre
/// it was actually judged against*, because the weekday/weekend split is not a
/// presentation detail — it is the thing that separates a recurring lie-in from
/// randomness. A chart that re-derived the split would be a second
/// implementation, free to disagree with the score sitting above it. Same
/// reasoning as `InsightResult.contributors`: the series a picture draws are
/// emitted by the code that did the scoring.
///
/// ## Encodings, and what each is spoken for
///
/// - **Dash means inferred**, here as everywhere. The centre lines and the
///   spread band are fitted quantities, not measurements, so they are dashed and
///   the points are not.
/// - **Hue is identity** and is therefore not free to mean weekday-versus-
///   weekend. That distinction rides on *symbol shape*, which nothing else in
///   this app uses.
/// - **The y axis is clock times**, never the raw stored value.
///   `.sleepOnset` is signed hours from midnight with the branch cut at midday —
///   the encoding that lets the linear baseline machinery treat a bedtime like
///   any other metric — and an axis reading "−1.5" would leak it at the one
///   place a reader is looking.
struct SleepOnsetStripChart: View {
    /// The card's own fit, over the nights it scored. The fallback whenever a
    /// visible window cannot be fitted, and what the strip shows before it has
    /// been scrolled.
    let output: CircadianConsistencyModel.Output
    /// Every night read, not just the scored fortnight — the strip re-fits over
    /// whatever stretch is on screen, so it needs something to scroll to.
    let allNights: [VitalReader.DailyValue]
    /// How much time fills the width, from the card's timeframe picker.
    let window: TimeInterval
    var selection: Binding<Date?>?

    @State private var localSelection: Date?
    @State private var visibleRange: ClosedRange<Date>?

    /// **Re-fitted over whatever is on screen**, falling back to the card's own
    /// fit before the chart has reported a range and wherever a window holds
    /// too few nights to fit anything.
    ///
    /// The centre, the band and the weekend shift are all measured over the
    /// nights they are drawn against — scroll to last spring and the middle
    /// drawn is last spring's middle. Drawing older nights against this
    /// fortnight's centre would show a departure the model never computed,
    /// which is the exact thing `Night.centre` exists to prevent.
    ///
    /// Cheap enough for a drag: the nights are read once by the card, and this
    /// is a mean, a split and a standard deviation over a few dozen of them.
    /// `CircadianConsistencyModel.nights(from:)` is the expensive half and is
    /// not on this path.
    private var fitted: CircadianConsistencyModel.Output {
        guard let visibleRange else { return output }
        let inWindow = allNights.filter { visibleRange.contains($0.date) }
        return CircadianConsistencyModel.evaluate(nights: inWindow) ?? output
    }

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    private var tint: Color { Theme.insightTint(.sleep) }

    /// The night nearest the scrubbed instant, ignoring anything further than
    /// half a day away — past that the finger is between nights, not on one.
    private func night(at date: Date) -> CircadianConsistencyModel.Output.Night? {
        guard let nearest = fitted.nights.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= 12 * 3600 else { return nil }
        return nearest
    }

    /// The two block centres actually in play. One entry when no weekday/weekend
    /// shift was measurable, which is also when both centres are the same number
    /// — drawing it twice would double the line's opacity for no reason.
    private var centres: [Double] {
        Array(Set(fitted.nights.map(\.centre))).sorted()
    }

    /// The **whole** history, not the fitted window — this is the scroll domain,
    /// and deriving it from `fitted` would shrink to whatever is on screen and
    /// leave nothing to scroll to. That circularity is the bug this comment is
    /// here to stop somebody reintroducing.
    private var span: ClosedRange<Date>? {
        guard let first = allNights.first?.date, let last = allNights.last?.date,
              first < last else { return nil }
        // Half a day of margin either side, so the first and last points aren't
        // drawn hard against the plot edge.
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
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
    /// The blank line holds the height so the chart doesn't jump on first touch.
    @ViewBuilder private var readout: some View {
        if let selected, let hit = night(at: selected) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(MetricValueFormatter.string(hit.onset, .sleepOnset))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .foregroundStyle(.secondary)
                if abs(hit.departure) >= 0.25 {
                    Text(String(format: "· %.1f h %@ than usual", abs(hit.departure),
                                hit.departure > 0 ? "later" : "earlier"))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    /// Wraps `ScrollableMetricChart`, like every other history chart here.
    ///
    /// It used to be a plain `Chart` with a fixed fourteen-night domain, and the
    /// argument for that was sound while it was true: the window was never wider
    /// than the screen, so there was nothing to scroll to. What made it pannable
    /// was not the chart — it was splitting `CircadianConsistencyModel` so the
    /// fit could be recomputed over whatever comes into view. See `fitted`.
    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: selectionBinding,
            height: 170,
            emptyMessage: "No bedtimes recorded in this window",
            isEmpty: { range in !allNights.contains { range.contains($0.date) } },
            onVisibleRangeChange: { visibleRange = $0 }
        ) { _ in
            marks
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        // The stored value is signed hours from midnight; a
                        // reader wants a clock.
                        Text(MetricValueFormatter.string(hours, .sleepOnset))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    /// Explicit `some ChartContent` on every builder here, as this app requires:
    /// without it a `RuleMark` / `RectangleMark` chain can resolve to
    /// `Chart3DContent` on this SDK and silently drop `.foregroundStyle` and
    /// `.lineStyle`. It compiles; it just renders wrong.
    @ChartContentBuilder
    private var marks: some ChartContent {
        spreadBand
        centreMarks
        nightMarks
    }

    /// One standard deviation either side of each centre — the quantity the
    /// score is computed from, drawn rather than only stated.
    ///
    /// A `RectangleMark`, not a filled `AreaMark`: two-series filled bands are a
    /// live Swift Charts hazard in this app and are still on the roadmap as
    /// needing a dedicated compile spike. This is the construction
    /// `MultiSourceChart.bandMarks` already uses safely.
    @ChartContentBuilder
    private var spreadBand: some ChartContent {
        ForEach(span.map { range in centres.map { (centre: $0, range: range) } } ?? [],
                id: \.centre) { band in
            RectangleMark(xStart: .value("From", band.range.lowerBound),
                          xEnd: .value("To", band.range.upperBound),
                          yStart: .value("Low", band.centre - fitted.spreadHours),
                          yEnd: .value("High", band.centre + fitted.spreadHours))
                .foregroundStyle(tint.opacity(0.10))
        }
    }

    /// The middle each night is measured against. Dashed because a fitted centre
    /// is not a time anybody went to bed.
    @ChartContentBuilder
    private var centreMarks: some ChartContent {
        ForEach(centres, id: \.self) { centre in
            RuleMark(y: .value("Usual", centre))
                .foregroundStyle(tint.opacity(0.55))
                .lineStyle(Theme.projectedStroke)
        }
    }

    /// The measured bedtimes. Solid, filled, and the only thing on this chart
    /// that anybody observed.
    @ChartContentBuilder
    private var nightMarks: some ChartContent {
        ForEach(fitted.nights) { night in
            PointMark(x: .value("Night", night.date),
                      y: .value("Asleep", night.onset))
                // Shape, not hue and not dash: both of those already mean
                // something else here.
                .symbol(night.isWeekend ? .square : .circle)
                .symbolSize(isFurthestOut(night) ? 90 : 45)
                .foregroundStyle(tint.opacity(isFurthestOut(night) ? 1 : 0.75))
        }
    }

    /// The card names one night as furthest out in its driver lines; this is the
    /// same night, emphasised. Two surfaces naming different nights would be a
    /// defect the reader can see.
    private func isFurthestOut(_ night: CircadianConsistencyModel.Output.Night) -> Bool {
        fitted.mostIrregular?.date == night.date
    }

    private var caption: some View {
        Text(captionText)
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captionText: String {
        let base = "Each point is the night's sleep time. The dashed line is your usual one and the band is how far either side of it you typically fall — the narrower that band, the more regular."
        guard fitted.socialJetlagHours != nil, centres.count > 1 else { return base }
        return base + " Weekends (squares) are measured against their own line, so a consistent lie-in reads as regular rather than as drift."
    }
}
