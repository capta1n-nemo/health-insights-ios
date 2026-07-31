import Foundation

/// How the body's mass divides up, from whatever the scale actually reported.
///
/// `BodyCompositionInsight` narrates six measurements as separate lines and
/// scores none of them — its contributor weights are deliberately zero, because
/// the dial is BMI and body fat rather than a blend. So the card has plenty of
/// numbers and no picture of the one thing they jointly describe: what the
/// weight on the scale is *made of*.
///
/// In InsightKit rather than the view because every line of it is arithmetic
/// that can be quietly wrong, and the app target has no test target.
public struct BodyCompositionSplit: Sendable, Equatable {

    /// One block of the bar, in kilograms.
    public struct Part: Sendable, Equatable {
        public let metric: MetricType
        public let label: String
        public let kilograms: Double
        /// Share of total mass, 0…1.
        public let fraction: Double
    }

    /// Total body mass the parts are shares of.
    public let total: Double
    /// Heaviest first — fat, then the lean components.
    public let parts: [Part]
    /// Body water, which is *not* a part: it is distributed through lean tissue
    /// rather than sitting beside it, so adding it to the bar would double-count
    /// mass already counted as muscle. Carried separately for annotation.
    public let waterPercentage: Double?
    /// True when the parts are known not to account for all of `total`, so the
    /// view can say so rather than drawing a bar that silently doesn't fill.
    public let isPartial: Bool

    /// Build the split, or `nil` when the scale hasn't reported enough for one
    /// to be honest.
    ///
    /// Needs a weight and at least one of body-fat percentage or lean mass —
    /// with either, the other follows, because fat and lean partition body mass
    /// by definition. With neither there is nothing to divide and the card
    /// should show no bar rather than a single block labelled "you".
    public static func from(samples: [HealthMetricSample]) -> BodyCompositionSplit? {
        guard let weight = samples.latestValue(.bodyMass), weight > 0 else { return nil }
        let fatPercentage = samples.latestValue(.bodyFatPercentage)
        let leanReported = samples.latestValue(.leanBodyMass)

        // Prefer the measured figure on each side and derive only the missing
        // one. Deriving both from each other would be circular; deriving neither
        // when one is present would throw away a real measurement.
        let fatMass: Double
        let leanMass: Double
        switch (fatPercentage, leanReported) {
        case let (percentage?, _):
            fatMass = weight * percentage / 100
            leanMass = leanReported ?? (weight - fatMass)
        case let (nil, lean?):
            leanMass = lean
            fatMass = weight - lean
        default:
            return nil
        }
        guard fatMass >= 0, leanMass > 0 else { return nil }

        var parts: [Part] = [Part(metric: .bodyFatPercentage, label: "Fat",
                                  kilograms: fatMass, fraction: fatMass / weight)]

        // Muscle and bone are components *of* lean mass, not additions to it, so
        // they are only drawn when they fit inside it. A scale that disagrees
        // with itself — muscle plus bone exceeding the lean mass it also
        // reported — gets one undivided lean block rather than a bar summing
        // past the person's weight.
        let muscle = samples.latestValue(.muscleMass)
        let bone = samples.latestValue(.boneMass)
        let components = [(MetricType.muscleMass, "Muscle", muscle),
                          (MetricType.boneMass, "Bone", bone)]
            .compactMap { metric, label, value in value.map { (metric, label, $0) } }
        let componentTotal = components.reduce(0) { $0 + $1.2 }

        if !components.isEmpty, componentTotal <= leanMass + 0.05 {
            for (metric, label, value) in components {
                parts.append(Part(metric: metric, label: label,
                                  kilograms: value, fraction: value / weight))
            }
            // Whatever lean tissue the scale didn't attribute — organs, blood,
            // and its own rounding. Suppressed under 0.1 kg so a bar that adds
            // up doesn't grow a sliver labelled "other".
            let remainder = leanMass - componentTotal
            if remainder >= 0.1 {
                parts.append(Part(metric: .leanBodyMass, label: "Other lean",
                                  kilograms: remainder, fraction: remainder / weight))
            }
        } else {
            parts.append(Part(metric: .leanBodyMass, label: "Lean",
                              kilograms: leanMass, fraction: leanMass / weight))
        }

        let accounted = parts.reduce(0) { $0 + $1.kilograms }
        return BodyCompositionSplit(
            total: weight,
            parts: parts,
            waterPercentage: samples.latestValue(.bodyWaterPercentage),
            // A tolerance rather than an equality: these are four independent
            // readings from a bioimpedance scale and they will not sum exactly.
            isPartial: abs(accounted - weight) > 0.5)
    }
}
