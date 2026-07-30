import Foundation

/// Which of an insight's signals an overlay chart actually draws.
///
/// Lives here rather than in the chart for the same reason `colourSlot` does:
/// it is the rule that decides whether two lines can end up looking alike, and
/// that has to be testable without a running view. The first version of this
/// shipped from the view layer and put two identical reds on one chart.
public enum OverlaySelection {

    /// A departure this large earns a point marker, and is what "away from
    /// baseline" means everywhere on the chart. One threshold, one meaning.
    public static let notableZ = 1.5

    /// The furthest a series got from its own baseline over the window.
    public static func peakZ(_ one: NormalizedSeries) -> Double {
        one.points.map { abs($0.z) }.max() ?? 0
    }

    public static func isNotable(_ one: NormalizedSeries) -> Bool {
        peakZ(one) >= notableZ
    }

    /// Whether the chart is showing a subset rather than everything.
    public static func filters(_ series: [NormalizedSeries], showingAll: Bool) -> Bool {
        !showingAll && series.count > MetricPalette.comfortableSeriesCount
    }

    /// The series to draw.
    ///
    /// Three rules, in order:
    ///
    /// 1. At or below `comfortableSeriesCount` there are more hues than series,
    ///    so everything is drawn.
    /// 2. Above it, only the series away from baseline — the same principle the
    ///    drivers card uses, leading with what departed and folding the routine
    ///    majority away.
    /// 3. **Capped at the palette size**, because "only the anomalous ones" is
    ///    not by itself a small number. Thirteen vitals with nine away from
    ///    baseline is an ordinary week, and the ninth line had nowhere to go but
    ///    onto a hue already in use. The most-departed win the colours and the
    ///    rest fold into the legend's list, which is a better answer than two
    ///    series that look identical.
    ///
    /// The cap does not apply when `showingAll` is set: that is an explicit ask
    /// for every signal, and past the palette a repeat is unavoidable.
    public static func visible(_ series: [NormalizedSeries],
                               showingAll: Bool) -> [NormalizedSeries] {
        guard filters(series, showingAll: showingAll) else { return series }
        let notable = series.filter { isNotable($0) }
        guard notable.count > MetricPalette.hueCount else { return notable }
        // Ranked by departure, tie-broken on the style index so the same week
        // always yields the same set rather than shuffling between renders.
        let kept = Set(notable
            .sorted { a, b in
                peakZ(a) == peakZ(b)
                    ? a.metric.chartStyleIndex < b.metric.chartStyleIndex
                    : peakZ(a) > peakZ(b)
            }
            .prefix(MetricPalette.hueCount)
            .map(\.metric))
        // Re-filtered in the original order, so a series keeps its hue when a
        // neighbour drops out.
        return notable.filter { kept.contains($0.metric) }
    }
}
