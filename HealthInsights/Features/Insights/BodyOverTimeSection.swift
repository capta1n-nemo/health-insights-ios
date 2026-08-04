import SwiftUI
import InsightKit

/// **"Your body over time"** — Body Composition's body model.
///
/// ## What it is for
///
/// The reader asked for a body they can watch change: a model of themselves
/// that morphs between measurements and runs on into what the trend implies.
/// This is that section.
///
/// Two things make it honest rather than decorative:
///
/// - **It is built from their own girths**, so a waist that fell 4 cm draws
///   4 cm narrower. Where a girth has never been measured it is estimated from
///   height, weight and body fat — which is what lets the section render before
///   the reader has ever measured anything, and a body model that only appears
///   *after* a scan cannot be the thing that persuades somebody to take one.
/// - **The projected half is drawn differently and stops where the evidence
///   does.** `BodyModelParameters.project` refuses a forecast when the weight
///   trend is inside its own noise, so the scrubber simply has nothing past
///   today for a reader whose weight is steady — rather than drawing a
///   confident future out of a flat line.
struct BodyOverTimeSection: View {
    @Environment(AppModel.self) private var model

    /// Where the scrubber sits: 0 is the oldest measurement, 1 is today, and
    /// past 1 runs into the projection.
    @State private var position: Double = 1

    /// How far ahead the scrubber can run, in weeks. Twelve — far enough to be
    /// worth seeing, short enough that a fitted weekly slope is not being asked
    /// to describe next year.
    private static let projectionWeeks: Double = 12

    var body: some View {
        NestedInsightSection(title: "Your body over time",
                             trailing: trailingLabel,
                             caveat: caveat) {
            if let shown {
                // The mesh replaces the outline, which read as a shield rather
                // than a body. Geometry comes from InsightKit (tested on
                // Linux); this section only chooses *when* to build it.
                BodyMeshView(mesh: BodyMeshBuilder.mesh(for: shown.parameters),
                             isProjected: shown.isProjected)
                    .frame(height: 300)
                BodyMeshLegend(hasMeasured: !shown.parameters.isWhollyEstimated)
                scrubber
                readout(shown)
            } else {
                Text("Add your height and a recent weight and your body will be drawn here. Measuring your waist makes it yours rather than a build estimated from the two.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - What the scrubber is showing

    private struct Shown {
        let parameters: BodyModelParameters
        let isProjected: Bool
        let date: Date
    }

    /// Every measured body the app can build, oldest first.
    ///
    /// One per scan, plus today's — which may be the only one, and that is the
    /// common case for a reader who has not measured yet.
    private var timeline: [BodyModelParameters] {
        model.memoized("bodyTimeline") {
            guard let height = model.samples.latestValue(.height),
                  let sex = model.profile.sex else { return [BodyModelParameters]() }
            let scans = model.bodyScans.sorted { $0.capturedAt < $1.capturedAt }
            var out = scans.compactMap { scan in
                BodyModelParameters.build(
                    heightMetres: height,
                    weightKg: model.samples.latestValue(.bodyMass) ?? 0,
                    bodyFatPercentage: model.samples.latestValue(.bodyFatPercentage),
                    sex: sex, measurements: scan.measurements, date: scan.capturedAt)
            }
            // Today, from whatever is current — the end every scrubber run
            // finishes at, and the only entry a reader with no scans has.
            if let today = BodyModelParameters.build(
                heightMetres: height,
                weightKg: model.samples.latestValue(.bodyMass) ?? 0,
                bodyFatPercentage: model.samples.latestValue(.bodyFatPercentage),
                sex: sex, measurements: model.reconciledMeasurements(), date: Date()) {
                out.append(today)
            }
            return out
        }
    }

    private var velocity: CompositionVelocity? {
        model.memoized("bodyVelocity") {
            CompositionVelocityModel.evaluate(samples: model.samples, now: Date())
        }
    }

    /// Whether there is a forecast to scrub into at all.
    private var canProject: Bool {
        guard let velocity else { return false }
        return BodyModelParameters.project(timeline.last ?? timeline.first!,
                                           velocity: velocity, weeks: 1) != nil
    }

    private var shown: Shown? {
        let bodies = timeline
        guard let latest = bodies.last else { return nil }

        if position <= 1 {
            // Between the oldest measured body and today.
            guard bodies.count >= 2 else {
                return Shown(parameters: latest, isProjected: false, date: latest.date)
            }
            let span = Double(bodies.count - 1)
            let scaled = position * span
            let index = min(Int(scaled), bodies.count - 2)
            let blend = BodyModelParameters.interpolate(from: bodies[index],
                                                        to: bodies[index + 1],
                                                        t: scaled - Double(index))
            return Shown(parameters: blend, isProjected: false, date: blend.date)
        }

        // Past today: into the projection.
        guard let velocity,
              let projected = BodyModelParameters.project(
                latest, velocity: velocity,
                weeks: (position - 1) * Self.projectionWeeks) else {
            return Shown(parameters: latest, isProjected: false, date: latest.date)
        }
        return Shown(parameters: projected, isProjected: true, date: projected.date)
    }

    // MARK: - Chrome

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: $position, in: 0...(canProject ? 2 : 1))
                .tint(Theme.accent)
            HStack {
                Text(timeline.count >= 2 ? "First measured" : "Today")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if canProject {
                    Text("In \(Int(Self.projectionWeeks)) weeks")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder private func readout(_ shown: Shown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(shown.isProjected
                     ? "Projected \(shown.date.formatted(.dateTime.month().day()))"
                     : shown.date.formatted(.dateTime.month().day().year()))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let waist = shown.parameters.girth(.waist) {
                    Text(String(format: "waist %.0f cm", waist))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(shown.isProjected ? .secondary : .primary)
                }
            }
            if shown.isProjected, let velocity {
                Text(String(format: "On your current trend, ±%.1f kg — the usual spread of a real weigh-in about the fitted line.",
                            BodyModelParameters.projectionSpreadKg(velocity)))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trailingLabel: String? {
        guard let shown else { return nil }
        return shown.isProjected ? "projected" : nil
    }

    /// The caveat is not optional on this section and never says "measured".
    ///
    /// Every body drawn here is part estimate — a reader with no scan has all
    /// seven girths estimated, and even a full scan leaves the shape between
    /// stations to the renderer.
    private var caveat: SectionCaveat {
        .computed(.partial,
                  "A representation built from your measurements, not a picture of you. "
                  + "Girths you haven't measured are estimated from your height, weight "
                  + "and body fat, and the shape between them is drawn rather than "
                  + "measured.")
    }
}
