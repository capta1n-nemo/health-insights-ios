import SwiftUI
import InsightKit

/// Every vital the scan looked at, on one axis of distance-from-your-own-normal.
///
/// Readiness absorbed Vitals Check in the consolidation. The scan judges up to
/// seventeen signals against a 28-day personal baseline and produces a z-score
/// for each; what reached the card was one sentence apiece, and on an ordinary
/// day sixteen of them say "in your normal range". Counting the odd one out of a
/// list of seventeen sentences is work. As dots on a shared axis, "one thing is
/// off today" is a shape.
///
/// ## What the drawing has to get right
///
/// **The bands are the scan's own.** `VitalDeparture` surfaces `watchZ` and
/// `unusualZ` from `VitalSignsCheck`'s constants and the scan applies them
/// through the same function, so the shaded stretch here is exactly the stretch
/// the card calls ordinary. Copying 1.25 and 2.0 into this file would have been
/// the two-copies-of-a-threshold bug with the drift made invisible.
///
/// **Colour is severity, not identity.** Every other multi-series chart in this
/// app uses hue as identity, because several lines share one axis and the legend
/// is the only way to tell them apart. Here each row is labelled with its own
/// metric name, so hue is free to carry the verdict — and matches the tints
/// "What's driving this" already uses for the same three states.
///
/// **A dot near the middle can still be red.** An absolute clinical bound
/// overrides a personal baseline — a baseline built from consistently low oxygen
/// saturation must not normalise it — so a reading can be `.unusual` at a small
/// z. `isBeyondClinicalBound` marks those, because a red dot sitting in the
/// shaded band with no explanation reads as a rendering fault.
struct VitalDepartureStrip: View {
    let panel: VitalDeparturePanel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Not `row` — shadowing a method with a local of the same name has
            // bitten this codebase before, and it is noted in `activeContext.md`
            // as one of the two things nothing local catches.
            ForEach(panel.rows) { departure in
                metricRow(departure)
            }
            scaleKey
        }
    }

    private func metricRow(_ departure: VitalDeparture) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(departure.metric.displayName).font(.subheadline)
                if departure.isBeyondClinicalBound {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(tint(departure.band))
                }
                Spacer(minLength: 4)
                Text(MetricValueFormatter.string(departure.value, departure.metric))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(label(departure))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tint(departure.band))
            }
            track(departure)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(departure))
    }

    /// The axis runs −limit … +limit with zero in the middle.
    private func track(_ departure: VitalDeparture) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let limit = VitalDeparture.axisLimit
            let dot: CGFloat = 10
            // Fraction of the axis for a z, with the dot's own width taken out
            // so a pinned marker sits inside the track.
            let position = { (z: Double) in (width - dot) * (z + limit) / (2 * limit) }
            let ordinary = width * VitalDeparture.watchZ / limit   // both sides of centre

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))

                // "Ordinary", at the scan's own watch threshold.
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: ordinary)
                    .offset(x: (width - ordinary) / 2)

                // Baseline. A rule rather than a gap in the shading, because the
                // centre is the thing every dot is being read against.
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 1)
                    .offset(x: width / 2 - 0.5)

                Circle()
                    .fill(tint(departure.band))
                    .frame(width: dot, height: dot)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                    .offset(x: position(departure.plotted))

                // A departure past the end of the axis keeps its dot at the edge
                // and says so, rather than pretending the axis contained it.
                if departure.isClamped {
                    Image(systemName: departure.plotted > 0 ? "chevron.right" : "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tint(departure.band))
                        .offset(x: departure.plotted > 0 ? width - 6 : 0)
                }
            }
        }
        .frame(height: 12)
    }

    /// Matches the three tints "What's driving this" uses, so one state does not
    /// have two colours on one screen.
    private func tint(_ band: VitalDeparture.Band) -> Color {
        switch band {
        case .unusual: return Theme.accent
        case .watch: return Theme.warn
        case .ordinary: return .secondary
        }
    }

    private func label(_ departure: VitalDeparture) -> String {
        String(format: "%@%.1f SD", departure.z > 0 ? "+" : "−", abs(departure.z))
    }

    private func accessibilityLabel(_ departure: VitalDeparture) -> String {
        let direction = departure.z > 0 ? "above" : "below"
        let verdict: String
        switch departure.band {
        case .unusual: verdict = "unusual"
        case .watch: verdict = "worth watching"
        case .ordinary: verdict = "in your normal range"
        }
        return String(format: "%@, %.1f standard deviations %@ your baseline, %@",
                      departure.metric.displayName, abs(departure.z), direction, verdict)
    }

    private var scaleKey: some View {
        HStack {
            Text("below baseline")
            Spacer()
            Text("your normal")
            Spacer()
            Text("above baseline")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
