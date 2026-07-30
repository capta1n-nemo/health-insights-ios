import Foundation

/// Which of an insight's signals an overlay chart draws, and in what order the
/// legend offers them.
///
/// Lives here rather than in the chart for the same reason `colourSlot` does:
/// it decides whether two lines can end up looking alike, and that has to be
/// testable without a running view. The first version shipped from the view
/// layer and put two identical reds on one chart.
public enum OverlaySelection {

    /// A departure this large is worth drawing, and earns a point marker on the
    /// day it happened. One threshold, one meaning.
    public static let notableZ = 1.5

    /// Days at the end of the window that count as "recent".
    public static let recentDays = 7

    /// How much this series is actually *doing something* over the window.
    ///
    /// Not "did it ever depart". That is what the first version asked, and a
    /// flat line with one blip three weeks ago ranked alongside a signal that
    /// had been elevated all fortnight — which is how body temperature and skin
    /// temperature came to be drawn on a chart whose own legend called them
    /// "steady". A card that contradicts itself in two places at once is worse
    /// than one that says less.
    ///
    /// Two things count and the larger wins:
    ///
    /// - **Recent**: the furthest it got in the last week. Yesterday's fever is
    ///   a finding even if the rest of the month was flat, so a peak still gets
    ///   a signal onto the chart — while it is still current.
    /// - **Sustained**: the RMS departure across the whole window. A signal
    ///   sitting a full SD off baseline every single day is doing something that
    ///   one spike is not, and RMS says so without a spike being able to fake
    ///   it — one |z| = 4 day among thirty flat ones comes to about 0.8.
    ///
    /// Measured against the newest reading rather than the clock, so a series
    /// that stopped reporting doesn't become "recent" again as time passes.
    public static func anomaly(_ one: NormalizedSeries) -> Double {
        guard let last = one.points.last?.date, !one.points.isEmpty else { return 0 }
        let cutoff = last.addingTimeInterval(-Double(recentDays) * 86_400)
        let recent = one.points.filter { $0.date >= cutoff }.map { abs($0.z) }.max() ?? 0
        let meanSquare = one.points.reduce(0) { $0 + $1.z * $1.z } / Double(one.points.count)
        return Swift.max(recent, meanSquare.squareRoot())
    }

    public static func isNotable(_ one: NormalizedSeries) -> Bool {
        anomaly(one) >= notableZ
    }

    /// Most-departed first, so the legend reads as a ranking and picking the
    /// interesting signals out of thirteen is a matter of reading from the top.
    ///
    /// Ties break on the style index rather than on sort order, which Swift does
    /// not guarantee to be stable — otherwise a quiet week would reshuffle the
    /// list between renders.
    public static func ranked(_ series: [NormalizedSeries]) -> [NormalizedSeries] {
        series.sorted { a, b in
            anomaly(a) == anomaly(b)
                ? a.metric.chartStyleIndex < b.metric.chartStyleIndex
                : anomaly(a) > anomaly(b)
        }
    }

    /// Whether the chart is showing a subset rather than everything.
    public static func filters(_ series: [NormalizedSeries], showingAll: Bool) -> Bool {
        !showingAll && series.count > MetricPalette.comfortableSeriesCount
    }

    /// What the chart draws before the reader has said otherwise.
    ///
    /// Three rules, in order:
    ///
    /// 1. At or below `comfortableSeriesCount` there are more hues than series,
    ///    so everything is drawn — including the quiet ones, because on a small
    ///    card "nothing happened here" is itself worth seeing.
    /// 2. Above it, only the signals doing something.
    /// 3. **Capped at the palette size**, because "only the anomalous ones" is
    ///    not by itself a small number — thirteen vitals with nine departing is
    ///    an ordinary week, and the ninth line had nowhere to go but onto a hue
    ///    already in use.
    ///
    /// This is a starting point, not a restriction: every series can be switched
    /// on or off individually from the legend.
    public static func defaultSelection(_ series: [NormalizedSeries]) -> Set<MetricType> {
        guard filters(series, showingAll: false) else {
            return Set(series.map(\.metric))
        }
        return Set(ranked(series)
            .filter { isNotable($0) }
            .prefix(MetricPalette.hueCount)
            .map(\.metric))
    }

    /// The series to draw, given what's selected.
    ///
    /// Filtered from the original list rather than rebuilt from the set, so the
    /// drawing order — and therefore the hue each series is assigned — doesn't
    /// depend on the order the reader happened to tick things.
    public static func visible(_ series: [NormalizedSeries],
                               selected: Set<MetricType>) -> [NormalizedSeries] {
        series.filter { selected.contains($0.metric) }
    }
}
