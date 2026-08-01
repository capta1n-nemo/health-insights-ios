import SwiftUI
import InsightKit

/// Where your numbers sit against other people your age and sex — as positions,
/// not sentences.
///
/// Heart Health absorbed "Where You Stand" in the consolidation and kept the
/// arithmetic: `PeerStandingModel` computes a centile for resting heart rate,
/// HRV and VO₂max. What survived onto the card was one driver line apiece
/// ("HRV 48 ms — top 25% for your age and sex"), so the number the model
/// actually produced never reached the screen. Three centiles read as three
/// sentences take a paragraph to compare; as three dots on one axis they take a
/// glance, which is the entire reason this section exists.
///
/// ## Two decisions worth keeping
///
/// **Not a distribution curve.** The obvious drawing is a bell with a marker on
/// it, and it would be a lie: `PeerStandingModel` says in its own doc comment
/// that these are normal approximations to *published summary statistics* — the
/// sources give means and spreads, not curves. Drawing the curve claims a
/// distribution nobody has. A position on a plain axis claims exactly what is
/// known.
///
/// **Higher is always to the right**, whichever way the underlying metric runs.
/// A resting heart rate of 48 is a *high* centile, and `percentile` is already
/// oriented that way — the axis just has to not undo it. Labelled at both ends
/// so the orientation is stated rather than assumed.
struct PeerStandingStrip: View {
    let standings: [PeerStandingModel.Standing]

    /// Resolved across the whole list. Without `slots:` a metric falls back to
    /// its *preferred* hue, and this app has already shipped two identical dots
    /// in one list that way.
    private var slots: [MetricType: Int] {
        MetricPalette.slots(for: standings.map(\.metric))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(standings) { standing in
                row(standing)
            }
            scaleKey
        }
    }

    private func row(_ standing: PeerStandingModel.Standing) -> some View {
        let tint = Theme.metricColor(standing.metric, slots: slots)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(standing.metric.displayName).font(.subheadline)
                Spacer(minLength: 4)
                Text(MetricValueFormatter.string(standing.value, standing.metric))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(standing.phrase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            track(standing, tint: tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(standing.metric.displayName), "
            + "\(Int(standing.percentile.rounded()))th centile, \(standing.phrase)")
    }

    /// The axis: a full-width track, the middle band picked out, one dot.
    private func track(_ standing: PeerStandingModel.Standing, tint: Color) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let typical = PeerStandingModel.Band.aroundAverage.bounds
            let dot: CGFloat = 11

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))

                // "Around average", taken from the band table the phrase beside
                // the dot is chosen from — so the shading and the words cannot
                // disagree. `PeerStandingBandTests` binds them.
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: width * (typical.upperBound - typical.lowerBound) / 100)
                    .offset(x: width * typical.lowerBound / 100)

                Circle()
                    .fill(tint)
                    .frame(width: dot, height: dot)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                    // Inset by the dot's own width so a 1st- or 99th-centile
                    // marker sits inside the track rather than half outside it.
                    .offset(x: (width - dot) * standing.percentile / 100)
            }
        }
        .frame(height: 12)
    }

    /// Both ends named, because "higher is better" is a property of this axis
    /// and not of every metric on it — the whole point of the orientation.
    private var scaleKey: some View {
        HStack {
            Text("bottom 25%")
            Spacer()
            Text("around average")
            Spacer()
            Text("top 10%")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
