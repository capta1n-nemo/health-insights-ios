import SwiftUI
import Charts
import InsightKit

/// How the body's composition has changed, as bands that thicken and thin.
///
/// ## Why a stacked area and not the extruded bar
///
/// The brief was the "what you're made of" bar repeated down the screen, one row
/// per weigh-in, time running vertically. That is the right *substance* — same
/// quantities, same colours, one axis added — and two changes make it read
/// better. Time runs left-to-right, this app's convention, and it fits a year of
/// weigh-ins where stacked rows fit about twenty. And the bands are continuous,
/// so a band narrowing over months is one visible taper rather than a difference
/// measured between rows.
///
/// ## Kilograms, not percentages
///
/// A 100%-normalised stack answers "what proportion of me is fat" and hides the
/// total. This user's weight has moved from a median of 124 kg to 110.7, and the
/// interesting question — did the loss come off fat, or did muscle go with it —
/// is the one normalising destroys. In kilograms the top edge of the stack *is*
/// body weight, so both readings are in one picture.
///
/// ## Water is a band, not a line
///
/// It was a hairline over the muscle band, which read as an axis annotation
/// rather than as part of the muscle. It is now the lower share of the muscle
/// band in its own cooled-red tone: still inside muscle, visibly distinct,
/// summing to exactly the same total because `BodyCompositionSplit.bands` cuts
/// the host block in two rather than adding one.
struct BodyCompositionTrendChart: View {

    let points: [BodyCompositionSplit.Dated]
    /// The day the lean band subdivides, when the window spans both resolutions.
    let finerSplitBegins: Date?
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    /// One band's value on one day, flattened for `Chart`.
    private struct Row: Identifiable {
        let id = UUID()
        let date: Date
        let kind: BodyCompositionSplit.Band.Kind
        let label: String
        let kilograms: Double
    }

    /// A stretch of chart whose muscle/bone division was borrowed rather than
    /// measured, so it can be drawn as the inference it is.
    private struct EstimatedSpan: Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }

        /// A run of estimated points, widened to the measured weigh-ins either
        /// side so the shading covers the whole stretch the inference carries.
        init(points: [BodyCompositionSplit.Dated], from: Int, to: Int) {
            self.start = points[Swift.max(0, from - 1)].date
            self.end = points[Swift.min(points.count - 1, to)].date
        }
    }

    /// Bottom of the stack first. Fat leads deliberately: it sits on the flat
    /// zero baseline, the only band whose thickness can be read without
    /// discounting the wobble of everything under it — and it is the band the
    /// question is usually about. Water sits directly above it, inside muscle.
    private static let order: [BodyCompositionSplit.Band.Kind] =
        [.fat, .muscleWater, .muscle, .otherLean, .lean, .bone]

    private var rows: [Row] {
        points.flatMap { point in
            point.split.bands.map {
                Row(date: point.date, kind: $0.kind,
                    label: $0.label, kilograms: $0.kilograms)
            }
        }
    }

    /// Labels present, in stacking order — not every split has every band.
    private var labels: [String] {
        var seen: [BodyCompositionSplit.Band.Kind: String] = [:]
        for row in rows where seen[row.kind] == nil { seen[row.kind] = row.label }
        return Self.order.compactMap { seen[$0] }
    }

    private func colour(_ label: String) -> Color {
        Theme.compositionColour(rows.first { $0.label == label }?.kind ?? .lean)
    }

    /// The top of the y axis: the heaviest weigh-in **in this window**, not a
    /// round number above it.
    ///
    /// Swift Charts' automatic domain rounded up to 150 against a history topping
    /// out near 124, which spent a third of the height on weights that never
    /// happened and squashed the bands the chart exists to compare. Anchoring to
    /// the window's own peak also means the picture re-scales as the timeframe
    /// changes, which is the point: a month whose peak is 115 should use the
    /// whole frame for the range 0–115.
    ///
    /// The baseline stays at zero and is not negotiable — these are stacked
    /// shares of a mass, so a cropped bottom would make the bands lie about
    /// their own size.
    private var peak: Double {
        max(points.map(\.split.total).max() ?? 1, 1)
    }

    /// First weigh-in of the window against the last.
    private var change: BodyCompositionSplit.Change? {
        BodyCompositionSplit.change(over: points)
    }

    /// Consecutive runs of estimated weigh-ins, extended to their measured
    /// neighbours so the shading covers the span the inference actually spans
    /// rather than stopping at the last estimated point.
    private var estimatedSpans: [EstimatedSpan] {
        var spans: [EstimatedSpan] = []
        var runStart: Int?
        for (index, point) in points.enumerated() {
            if point.isEstimated, runStart == nil { runStart = index }
            if !point.isEstimated, let start = runStart {
                spans.append(EstimatedSpan(points: points, from: start, to: index))
                runStart = nil
            }
        }
        if let start = runStart {
            spans.append(EstimatedSpan(points: points, from: start, to: points.count - 1))
        }
        return spans
    }

    /// The weigh-in nearest the finger, ignoring anything more than a fortnight
    /// away — past that there is no reading under the touch to report.
    private func point(at date: Date) -> BodyCompositionSplit.Dated? {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= 14 * 86_400 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            changeRow
        }
    }

    /// What the window actually did, by band.
    ///
    /// The chart says what the body *is* at every point and never said what it
    /// had *done* — and a bare total would not be enough either, because two
    /// kilograms off is a different event depending on which band it left. That
    /// is the whole reason this chart has bands rather than one weight line, so
    /// it is worth stating in numbers under it.
    ///
    /// Coloured per band, never by the total: fat down is welcome, muscle down
    /// is not, and water is neither — it tracks hydration and the hour of the
    /// weigh-in more than anything worth congratulating. `BandChange`
    /// `higherIsBetter` owns that judgement so this only renders it.
    @ViewBuilder private var changeRow: some View {
        if let change {
            VStack(alignment: .leading, spacing: 3) {
                Divider()
                HStack(spacing: 10) {
                    ForEach(change.bands) { band in
                        if abs(band.delta) >= 0.05 {
                            HStack(spacing: 3) {
                                Circle().fill(Theme.compositionColour(band.kind))
                                    .frame(width: 5, height: 5)
                                Text(band.label).foregroundStyle(.secondary)
                                Text(signed(band.delta))
                                    .monospacedDigit()
                                    .foregroundStyle(tint(for: band))
                            }
                        }
                    }
                    Spacer()
                }
                .font(.caption2)
            }
        }
    }

    private func signed(_ kilograms: Double) -> String {
        String(format: "%@%.1f", kilograms > 0 ? "+" : "−", abs(kilograms))
    }

    private func tint(for band: BodyCompositionSplit.BandChange) -> Color {
        guard let higherIsBetter = band.higherIsBetter, abs(band.delta) >= 0.05 else {
            return .secondary
        }
        return (band.delta > 0) == higherIsBetter ? Theme.good : Theme.bad
    }

    /// Above the chart, not as an annotation — a `RuleMark` chain resolves to
    /// `Chart3DContent` on this SDK and that has no `annotation`. The blank line
    /// reserves the height so nothing jumps on first touch.
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f kg", hit.split.total))
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                ForEach(hit.split.bands) { band in
                    HStack(spacing: 3) {
                        Circle().fill(Theme.compositionColour(band.kind))
                            .frame(width: 5, height: 5)
                        Text(String(format: "%.1f", band.kilograms)).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
                if hit.isEstimated {
                    Image(systemName: "questionmark.circle")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        Chart {
            bands
            estimatedScrim
            ScrubIndicator.at(selected)
        }
        .chartXSelection(value: selectionBinding)
        .chartForegroundStyleScale(domain: labels, range: labels.map(colour))
        .chartLegend(.hidden)   // the card draws its own, with the water sub-dot
        .chartYScale(domain: 0...peak)
        .chartYAxis {
            AxisMarks(values: [0, (peak / 2).rounded(), peak]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        // The top label is the actual peak, so the number the
                        // axis tops out at is a weight that was really recorded.
                        Text(kg == peak ? String(format: "%.1f", kg) : "\(Int(kg))")
                    }
                }
            }
        }
        .frame(height: 190)
    }

    // Explicit `some ChartContent` on every builder: without it a mark chain on
    // the current SDK can silently resolve to `Chart3DContent` and drop its
    // modifiers. This has cost this repo two CI failures — a known trap.
    @ChartContentBuilder private var bands: some ChartContent {
        ForEach(rows) { row in
            AreaMark(x: .value("Date", row.date),
                     y: .value("Mass", row.kilograms),
                     stacking: .standard)
                .foregroundStyle(by: .value("Part", row.label))
        }
    }

    /// Where the muscle/bone division was borrowed from a neighbouring weigh-in,
    /// washed out so it reads as less certain than the measured stretches.
    ///
    /// A scrim over the bands rather than a second set of bands drawn at lower
    /// opacity: a stacked area cannot vary opacity along its own length, and the
    /// alternative — `AreaMark(x:yStart:yEnd:)` — is the filled-band construction
    /// this repo still carries as an unverified SDK hazard. `RectangleMark` with
    /// an x-range is what `SleepOnsetStripChart` already uses safely.
    @ChartContentBuilder private var estimatedScrim: some ChartContent {
        ForEach(estimatedSpans) { span in
            RectangleMark(xStart: .value("From", span.start),
                          xEnd: .value("To", span.end))
                .foregroundStyle(Theme.cardScrim.opacity(0.55))
        }
    }
}
