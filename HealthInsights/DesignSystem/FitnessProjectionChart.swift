import SwiftUI
import Charts
import InsightKit

/// Today's VO₂max, extended twelve months on the trajectory's own slope, with
/// the fit's residual spread as a band.
///
/// `VO2Trajectory` has computed `projectedIn12Months` and `residualSD` — its own
/// doc comment calls the latter "the honest ± on the forecast" — since the card
/// shipped, and nothing outside `CardioTrajectory.swift` ever read either. The
/// card said "you are gaining 0.4 a year" and left the reader to do the
/// arithmetic and to guess at the uncertainty.
///
/// ## The encoding
///
/// **Everything drawn here is dashed**, because none of it was measured: the
/// line is a projection and the band is a residual spread. Dash means "not
/// measured" and nothing else in this app, so the whole chart being dashed is
/// the correct reading rather than a decoration. The only solid mark is the
/// single point at today, which *is* a measurement — the EWMA-smoothed current
/// value the projection starts from.
///
/// **The band is `AreaMark(x:yStart:yEnd:)`**, which takes no `stacking:`
/// argument. An absolute band between two heights is inherently unstacked, and
/// passing one is a compile error rather than a silent mis-render.
// substance-shading: exempt — the x axis is months ahead of today, not a date.
// A window that happened yesterday has nowhere to land on a chart whose zero is
// now and whose extent is the future. See `SubstanceShading` for the rule.
struct FitnessProjectionChart: View {
    let trajectory: VO2Trajectory.Output

    /// Months ahead, not a date: this chart's x-axis is the only numeric one in
    /// the app. It was also the only chart with no scrub at all — you could see
    /// the line rise and not read a value off it anywhere but the two ends.
    @State private var selectedMonths: Double?

    private struct Point: Identifiable {
        let id: Int
        let monthsFromNow: Double
        let value: Double
        let low: Double
        let high: Double
    }

    /// Two points is all the geometry needs — the projection is a straight line
    /// by construction, and the band opens linearly with it. Drawing more would
    /// imply the model has an opinion about the months in between.
    private var points: [Point] {
        let start = trajectory.smoothed
        let end = trajectory.projectedIn12Months
        let spread = trajectory.residualSD
        return [
            // No uncertainty at the point the projection leaves from.
            Point(id: 0, monthsFromNow: 0, value: start, low: start, high: start),
            Point(id: 1, monthsFromNow: 12, value: end,
                  low: end - spread, high: end + spread)
        ]
    }

    /// Fitted to what is drawn, including the band, rather than to a round
    /// number above it.
    private var range: ClosedRange<Double> {
        let lows = points.map(\.low)
        let highs = points.map(\.high)
        let low = (lows.min() ?? 0) - 1
        let high = (highs.max() ?? 1) + 1
        return low...Swift.max(high, low + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Above the chart, never as a mark annotation: a `RuleMark` chain
            // can resolve to `Chart3DContent` on this SDK and that has no
            // `annotation`. The blank line reserves the height so nothing jumps
            // on first touch.
            readout
            Chart {
                marks
                ScrubIndicator.at(selectedMonths)
            }
            .chartXSelection(value: $selectedMonths)
            .chartYScale(domain: range)
            // Doubles, not integer literals: the marks plot `Double` months and
            // a `ClosedRange<Int>` domain will not type-check against them.
            .chartXScale(domain: 0.0...12.0)
            .chartXAxis {
                AxisMarks(values: [0.0, 6.0, 12.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let months = value.as(Double.self) {
                            Text(months == 0 ? "now" : "\(Int(months))m")
                        }
                    }
                }
            }
            .frame(height: 130)

            key
        }
    }

    /// What the projection says at the month under the finger, with the band as
    /// a ± rather than as two numbers. Interpolated along the same straight
    /// line the marks draw — the model has no opinion about the months between
    /// its two endpoints, and this states the line's value there rather than
    /// inventing a reading.
    @ViewBuilder private var readout: some View {
        if let months = selectedMonths, (0...12).contains(months) {
            let fraction = months / 12
            let value = trajectory.smoothed
                + (trajectory.projectedIn12Months - trajectory.smoothed) * fraction
            let spread = trajectory.residualSD * fraction
            HStack(spacing: 8) {
                Text(months < 0.5 ? "now" : String(format: "%.0f months", months))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", value))
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                if spread >= 0.05 {
                    Text(String(format: "± %.1f", spread))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    /// Explicit `-> some ChartContent`. Without it a `RuleMark`/`AreaMark` chain
    /// can resolve to `Chart3DContent` on this SDK and silently drop
    /// `.lineStyle` and `.foregroundStyle` — which would render this chart
    /// solid, i.e. claiming the projection was measured.
    @ChartContentBuilder private var marks: some ChartContent {
        ForEach(points) { point in
            AreaMark(x: .value("Months", point.monthsFromNow),
                     yStart: .value("Low", point.low),
                     yEnd: .value("High", point.high))
                .foregroundStyle(Theme.accent.opacity(0.12))
        }
        ForEach(points) { point in
            LineMark(x: .value("Months", point.monthsFromNow),
                     y: .value("VO₂max", point.value))
                .interpolationMethod(.linear)
                .lineStyle(Theme.projectedStroke)
                .foregroundStyle(Theme.accent)
        }
        ForEach(points.prefix(1)) { point in
            PointMark(x: .value("Months", point.monthsFromNow),
                      y: .value("VO₂max", point.value))
                .foregroundStyle(Theme.accent)
        }
    }

    private var key: some View {
        Text(String(format: "Dashed because none of it is measured. The shaded band is ±%.1f, the spread of your own readings about the fitted line.",
                    trajectory.residualSD))
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One projected risk, as a proportion of the largest projected risk on screen.
///
/// A bar rather than a chart: four numbers with a shared maximum is a comparison
/// between four things, not a series over anything. Outlined rather than filled,
/// for the same reason the line above is dashed — nobody measured it.
struct RiskProjectionBar: View {
    let percent: Double
    /// Scaled against the largest bar drawn, not against 100%: at realistic
    /// ten-year risks every bar would otherwise be a sliver.
    let peak: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(Theme.accent.opacity(0.35))
                    .frame(width: max(2, geometry.size.width
                                         * min(1, percent / max(peak, 0.001))))
                    .overlay(
                        Capsule().strokeBorder(Theme.accent, style: Theme.projectedStroke)
                            .frame(width: max(2, geometry.size.width
                                                 * min(1, percent / max(peak, 0.001))))
                    )
            }
        }
        .frame(height: 10)
    }
}
