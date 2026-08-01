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
/// ## Water is a translucent film over the muscle band
///
/// Three attempts got this wrong the same way. A hairline, then a slice carved
/// out of the muscle band and given a colour *blended* to imitate blue over red.
/// The blend was the mistake: carving the slice out means the muscle band stops
/// being red across that stretch, so nothing reads as sitting underneath the
/// water and no choice of hue can put it back. The problem was geometry, not
/// colour.
///
/// The muscle band is now drawn whole, in muscle red, and a genuinely
/// translucent blue is painted over its lower portion — real alpha, real
/// compositing, red showing through. `BodyCompositionSplit.waterSpan` gives the
/// rectangle. Water is not in the stack and adds no mass, so the total is
/// untouched.
struct BodyCompositionTrendChart: View {

    let points: [BodyCompositionSplit.Dated]
    /// The day the lean band subdivides, when the window spans both resolutions.
    let finerSplitBegins: Date?
    var selection: Binding<Date?>?
    /// How much time fills the width — the card's timeframe picker. Defaulted
    /// only so previews stay one-liners; every real call site passes one.
    var window: TimeInterval = 365 * 24 * 3600

    /// What is on screen after panning. Drives the y-axis peak, the change row
    /// and the read-out, so all three describe the stretch being looked at
    /// rather than the stretch that was loaded.
    @State private var visibleRange: ClosedRange<Date>?

    @Environment(\.colorScheme) private var colorScheme

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
        [.fat, .muscle, .otherLean, .lean, .bone]

    /// The label each band kind goes by, for every kind appearing anywhere in
    /// the window.
    private var labelByKind: [BodyCompositionSplit.Band.Kind: String] {
        var out: [BodyCompositionSplit.Band.Kind: String] = [:]
        for point in points {
            for band in point.split.bands where out[band.kind] == nil {
                out[band.kind] = band.label
            }
        }
        return out
    }

    /// Band kinds present anywhere in the window, in stacking order.
    private var presentKinds: [BodyCompositionSplit.Band.Kind] {
        let known = labelByKind
        return Self.order.filter { known[$0] != nil }
    }

    /// One row per band **per point, including the bands that point doesn't
    /// have**, at zero.
    ///
    /// The zeros are load-bearing and were the second half of "missing data
    /// breaks the graph". Water only exists from the day the Body Smart arrived,
    /// so before that the water series had no points at all — and a stacked area
    /// whose series is absent over a stretch still reserves a stacked offset for
    /// it, interpolated from its first real value, while its polygon starts only
    /// where its data does. The two disagree, and the disagreement is drawn: a
    /// white wedge opening between fat and muscle, widening across two years to
    /// exactly the size of the first water reading.
    ///
    /// Giving every series a value at every x makes the offset and the polygon
    /// agree by construction. A zero-height band draws nothing, so this costs an
    /// invisible mark per absent band and removes a whole class of artefact.
    private var rows: [Row] {
        let known = labelByKind
        let kinds = presentKinds
        return points.flatMap { point -> [Row] in
            let have = Dictionary(point.split.bands.map { ($0.kind, $0.kilograms) },
                                  uniquingKeysWith: { a, _ in a })
            return kinds.map { kind in
                Row(date: point.date, kind: kind, label: known[kind] ?? "",
                    kilograms: have[kind] ?? 0)
            }
        }
    }

    /// Labels present, in stacking order — not every split has every band.
    private var labels: [String] {
        let known = labelByKind
        return presentKinds.compactMap { known[$0] }
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
    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    /// The points inside `range`, or all of them before the chart has reported
    /// one. Falls back to the whole series when a range holds nothing, so an
    /// empty stretch does not collapse the axis to 0...1.
    private func points(in range: ClosedRange<Date>?) -> [BodyCompositionSplit.Dated] {
        guard let range else { return points }
        let inside = points.filter { range.contains($0.date) }
        return inside.isEmpty ? points : inside
    }

    private var visiblePoints: [BodyCompositionSplit.Dated] { points(in: visibleRange) }

    /// The axis tops out at the heaviest reading **on screen**, which is what
    /// the caveat claims and what panning has to keep true.
    private func peak(in range: ClosedRange<Date>?) -> Double {
        max(points(in: range).map(\.split.total).max() ?? 1, 1)
    }

    private var peak: Double { peak(in: visibleRange) }

    /// First weigh-in of the window against the last.
    /// Over what is on screen, not over everything loaded. Scrolling to last
    /// spring and reading a change computed across the whole two years is the
    /// disagreement between a picture and the numbers under it that this chart
    /// exists to avoid.
    private var change: BodyCompositionSplit.Change? {
        BodyCompositionSplit.change(over: visiblePoints)
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
                                Circle().fill(Theme.compositionLegendColour(band.kind))
                                    .frame(width: 5, height: 5)
                                Text(band.label).foregroundStyle(.secondary)
                                Text(signed(band.delta))
                                    .monospacedDigit()
                                    .foregroundStyle(tint(for: band))
                            }
                        }
                    }
                    if let water = change.waterDelta, abs(water) >= 0.05 {
                        HStack(spacing: 3) {
                            Circle().fill(Theme.compositionWater)
                                .frame(width: 5, height: 5)
                            Text("water").foregroundStyle(.secondary)
                            Text(signed(water)).monospacedDigit()
                                .foregroundStyle(.secondary)
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
                        Circle().fill(Theme.compositionLegendColour(band.kind))
                            .frame(width: 5, height: 5)
                        Text(String(format: "%.1f", band.kilograms)).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
                if let water = hit.split.water {
                    HStack(spacing: 3) {
                        Circle().fill(Theme.compositionWater)
                            .frame(width: 5, height: 5)
                        Text(String(format: "%.1f", water.kilograms)).monospacedDigit()
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

    /// Wraps `ScrollableMetricChart` like every other time series here.
    ///
    /// It grew its own `Chart` because it started as a fixed picture of a
    /// timeframe-filtered slice, and that made it one of two charts in the app
    /// you could not pan — on a year of weigh-ins the only way to see further
    /// back was the picker. The scroll domain, the zoom, the scrub line and the
    /// per-window y-scale all come from the shared component now; the marks,
    /// the hatch and the axis labels are still this file's.
    ///
    /// `chartForegroundStyleScale` and `chartYAxis` are applied outside it:
    /// both write to the chart environment and reach the `Chart` inside.
    /// `chartYScale` is *not* — that one belongs to the wrapper, which rescales
    /// per visible window through `yDomain`.
    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: selectionBinding,
            height: 190,
            emptyMessage: "No weigh-ins in this window",
            isEmpty: { range in !points.contains { range.contains($0.date) } },
            // Always from zero: this is a stacked share of body mass, and a
            // stack that starts anywhere else misreads every band's thickness.
            yDomain: { range in 0...self.peak(in: range) },
            onVisibleRangeChange: { visibleRange = $0 }
        ) { _ in
            bands
            waterFilm
            estimatedScrim
        }
        .chartForegroundStyleScale(domain: labels, range: labels.map(colour))
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

    /// The water, painted **over** the muscle band rather than carved out of it.
    ///
    /// The `yStart`/`yEnd` form, which takes no `stacking:` argument because an
    /// absolute band between two heights is inherently unstacked — it is not
    /// another share to pile on.
    ///
    /// Filled with a tiled diagonal hatch rather than a translucent colour. A
    /// wash mixes with the muscle red and blue mixed into red is purple however
    /// it is tuned; stripes never mix, so the blue stays blue and the red stays
    /// red between them. See `Theme.waterHatch`.
    @ChartContentBuilder private var waterFilm: some ChartContent {
        ForEach(waterPoints) { point in
            AreaMark(x: .value("Date", point.date),
                     yStart: .value("From", point.from),
                     yEnd: .value("To", point.to))
                .foregroundStyle(Theme.waterHatch(colorScheme))
                .interpolationMethod(.linear)
        }
    }

    /// The film's rectangle per weigh-in. A named type, not a tuple: a key path
    /// into a tuple element is a compile error.
    private struct WaterPoint: Identifiable {
        let date: Date
        let from: Double
        let to: Double
        var id: Date { date }
    }

    private var waterPoints: [WaterPoint] {
        points.compactMap { point in
            point.split.waterSpan.map {
                WaterPoint(date: point.date, from: $0.from, to: $0.to)
            }
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
