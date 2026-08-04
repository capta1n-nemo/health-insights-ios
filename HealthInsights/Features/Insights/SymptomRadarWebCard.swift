import SwiftUI
import InsightKit

// substance-shading: exempt — no time axis; a single morning's deviations
// against baseline.

/// The radar itself: seven watched signals on a polar layout, each spoke
/// showing how far the signal is leaning the way illness pushes it.
///
/// ## Why this is not `ScrollableMetricChart`, and not Swift Charts at all
///
/// The same reasoning as `ScoreBalanceWeb`, which this is modelled on: there is
/// no time axis, Swift Charts has no polar mark, and `Path` sidesteps the
/// `Chart3DContent` overload hazard entirely. The geometry is
/// `BalanceWebGeometry` — pure, public, Linux-tested — with **no new geometry
/// type**; only the ring fractions differ, because here the rings are the two
/// thresholds the model actually uses rather than score quarters.
///
/// ## The encoding
///
/// - **Radius is the directional z-score**: `|z| / strongZ` when the movement
///   is in the illness direction, clamped to the outer ring, and **0 when the
///   movement is the healthy way** — the honest read, because the healthy
///   direction is not "more healthy", it is "not leaning".
/// - **Rings at 0.5 and 1.0** are `leaningZ` and `strongZ`: past the inner ring
///   a signal is voting, at the outer it votes with full weight.
/// - **Dots**: filled at its radius for a voting signal (larger when leaning);
///   an **open** dot for a signal folded into a same-basis twin's vote
///   (`Output.discounted`) — "counted once" must not render as "not looked
///   at"; a greyed axis with no dot for a watched metric with too little data.
/// - **One hue** — the card's own resolved insight tint, exactly as
///   `ScoreBalanceWeb` colours spokes: a single-series bespoke drawing claims
///   no per-metric hues (`add-chart`'s per-chart resolution rule; this is not
///   a multi-series chart).
struct SymptomRadarWebCard: View {
    let output: HealthWatchModel.Output
    /// The card's resolved hue — passed in so this view holds no palette
    /// opinion of its own.
    let tint: Color

    /// Radius as a fraction of the square's side; the rest is the label ring.
    private static let plotRadiusRatio: CGFloat = 0.30
    /// Where a label's centre sits, as a multiple of the plot radius.
    private static let labelRadiusRatio: CGFloat = 1.32
    /// The rings are the model's two thresholds, not score quarters.
    private static let ringFractions: [Double] = [0.5, 1.0]

    /// The fixed axis order — `HealthWatchModel.watchedMetrics`, index 0 at
    /// twelve o'clock, so the shape a reader learns is always the same shape.
    private var axes: [MetricType] { HealthWatchModel.watchedMetrics }

    /// What one axis shows.
    private struct Axis: Identifiable {
        let metric: MetricType
        let signal: HealthWatchModel.Signal?
        /// True when the signal was folded into a same-basis twin's vote.
        let isDiscounted: Bool
        var id: MetricType { metric }

        /// Distance from centre: leaning z against `strongZ`, floor 0 for a
        /// move in the healthy direction.
        var fraction: Double {
            guard let signal else { return 0 }
            let directional = signal.isConcerning ? abs(signal.zScore) : 0
            return min(max(directional / HealthWatchModel.strongZ, 0), 1)
        }
    }

    private var resolvedAxes: [Axis] {
        axes.map { metric in
            if let voting = output.signals.first(where: { $0.metric == metric }) {
                return Axis(metric: metric, signal: voting, isDiscounted: false)
            }
            if let folded = output.discounted.first(where: { $0.metric == metric }) {
                return Axis(metric: metric, signal: folded, isDiscounted: true)
            }
            return Axis(metric: metric, signal: nil, isDiscounted: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            web
                .frame(height: 250)
                .frame(maxWidth: .infinity)
            Text("Dots past the inner ring are leaning; the outer ring is a "
                 + "strong lean. The two HRV measures and the two temperatures "
                 + "each count once.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var web: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side * Self.plotRadiusRatio
            let axes = resolvedAxes

            ZStack {
                grid(axes: axes, centre: centre, radius: radius)
                dots(axes: axes, centre: centre, radius: radius)
                labels(axes: axes, centre: centre, radius: radius)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Radar of your watched signals")
    }

    // MARK: - Grid

    /// Threshold rings plus one line per axis. A greyed spoke is the "not
    /// enough data" state — the axis is still drawn, because a watched signal
    /// the app cannot currently judge is different from one it never watches.
    private func grid(axes: [Axis], centre: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            ForEach(Self.ringFractions, id: \.self) { ring in
                RadarRingShape(fraction: ring, count: axes.count,
                               radiusRatio: Self.plotRadiusRatio)
                    .stroke(Color.primary.opacity(ring == 1 ? 0.16 : 0.10),
                            style: StrokeStyle(lineWidth: ring == 1 ? 1 : 0.5))
            }
            ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                RadarSpokeShape(index: index, count: axes.count,
                                radiusRatio: Self.plotRadiusRatio)
                    .stroke(Color.primary.opacity(axis.signal == nil ? 0.04 : 0.10),
                            lineWidth: 0.5)
            }
        }
    }

    // MARK: - Dots

    @ViewBuilder private func dots(axes: [Axis], centre: CGPoint,
                                   radius: CGFloat) -> some View {
        ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
            if let signal = axis.signal {
                dot(for: axis, signal: signal)
                    .position(position(index: index, count: axes.count,
                                       fraction: axis.fraction,
                                       centre: centre, radius: radius))
                    .accessibilityLabel(speech(for: axis))
            }
        }
    }

    @ViewBuilder private func dot(for axis: Axis,
                                  signal: HealthWatchModel.Signal) -> some View {
        if axis.isDiscounted {
            // Leaned or not, the twin carried the vote: an open dot says
            // "looked at, counted once" without claiming a second vote.
            Circle()
                .stroke(tint.opacity(0.8), lineWidth: 1.5)
                .frame(width: 8, height: 8)
        } else if signal.isLeaning {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
        } else {
            Circle()
                .fill(tint.opacity(0.45))
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Labels

    /// View-local short names — a rendering choice about seven fixed axes on a
    /// phone-width circle, deliberately not a new InsightKit switch.
    private func shortName(_ metric: MetricType) -> String {
        switch metric {
        case .skinTemperatureDeviation: return "Temp dev"
        case .skinTemperature: return "Skin temp"
        case .restingHeartRate: return "RHR"
        case .heartRateVariabilityRMSSD: return "HRV rMSSD"
        case .heartRateVariabilitySDNN: return "HRV SDNN"
        case .respiratoryRate: return "Resp rate"
        case .oxygenSaturation: return "SpO₂"
        default: return metric.displayName
        }
    }

    private func labels(axes: [Axis], centre: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
            Text(shortName(axis.metric))
                .font(.caption2.weight(.medium))
                .foregroundStyle(axis.signal == nil ? .tertiary : .secondary)
                .fixedSize()
                .position(labelPosition(index: index, count: axes.count,
                                        centre: centre, radius: radius))
                .accessibilityHidden(true)   // the dot already speaks it
        }
    }

    // MARK: - Geometry (all through BalanceWebGeometry — no new maths)

    private func position(index: Int, count: Int, fraction: Double,
                          centre: CGPoint, radius: CGFloat) -> CGPoint {
        let point = BalanceWebGeometry.point(index: index, count: count,
                                             radiusFraction: fraction)
        return CGPoint(x: centre.x + CGFloat(point.x) * radius,
                       y: centre.y + CGFloat(point.y) * radius)
    }

    /// Outside the outer ring — a label is not a reading, so it must not go
    /// through the clamping `point` function (`ScoreBalanceWeb` documents the
    /// pile-up that produced).
    private func labelPosition(index: Int, count: Int,
                               centre: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = BalanceWebGeometry.angle(index: index, count: count)
        let distance = radius * Self.labelRadiusRatio
        return CGPoint(x: centre.x + CGFloat(cos(angle)) * distance,
                       y: centre.y + CGFloat(sin(angle)) * distance)
    }

    // MARK: - Accessibility

    private func speech(for axis: Axis) -> String {
        guard let signal = axis.signal else {
            return "\(axis.metric.displayName): not enough data"
        }
        let state: String
        if axis.isDiscounted {
            state = "counted once with its twin"
        } else if signal.isLeaning {
            state = abs(signal.zScore) >= HealthWatchModel.strongZ
                ? "leaning hard" : "leaning"
        } else {
            state = "inside your usual range"
        }
        return "\(axis.metric.displayName): \(state), "
            + "\(MetricValueFormatter.string(signal.recent, signal.metric)) against "
            + "\(MetricValueFormatter.string(signal.reference, signal.metric)) usual"
    }
}

// MARK: - Shapes

/// A closed polygonal ring at one fraction — polygonal rather than circular for
/// the same reason `ScoreBalanceWeb`'s grid is: a circle invites reading the
/// chord between adjacent vertices as though it meant something.
private struct RadarRingShape: Shape {
    let fraction: Double
    let count: Int
    let radiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count >= 2 else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusRatio
        for index in 0..<count {
            let point = BalanceWebGeometry.point(index: index, count: count,
                                                 radiusFraction: fraction)
            let screen = CGPoint(x: centre.x + CGFloat(point.x) * radius,
                                 y: centre.y + CGFloat(point.y) * radius)
            if index == 0 { path.move(to: screen) } else { path.addLine(to: screen) }
        }
        path.closeSubpath()
        return path
    }
}

/// One centre-to-rim line. Per-axis rather than one shape for all spokes
/// (`ScoreBalanceWeb`'s `WebSpokesShape`) because each spoke here carries its
/// own opacity — a greyed axis is the "not enough data" state.
private struct RadarSpokeShape: Shape {
    let index: Int
    let count: Int
    let radiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count >= 2 else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusRatio
        let point = BalanceWebGeometry.point(index: index, count: count,
                                             radiusFraction: 1)
        path.move(to: centre)
        path.addLine(to: CGPoint(x: centre.x + CGFloat(point.x) * radius,
                                 y: centre.y + CGFloat(point.y) * radius))
        return path
    }
}
