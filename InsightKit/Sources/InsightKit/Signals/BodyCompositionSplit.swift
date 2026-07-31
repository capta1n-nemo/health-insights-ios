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

    /// Body water drawn *inside* the block that hosts it, rather than beside it.
    ///
    /// Water is not a part of the bar and cannot become one: it is held within
    /// lean tissue, so a block of its own would count the same kilograms twice —
    /// once as muscle and again as water. Drawing it as an inset says "this much
    /// of that block is water", which is the true relationship.
    public struct WaterInset: Sendable, Equatable {
        public let kilograms: Double
        /// The block it is drawn inside — muscle where the scale reports it,
        /// otherwise the undivided lean block.
        public let host: MetricType
        /// Share of the host block, 0…1.
        public let fractionOfHost: Double
        /// Total body water exceeds the block hosting it, so the inset is
        /// clamped and the view should say so rather than draw an overflow.
        ///
        /// Physiologically ordinary: muscle is roughly 75% water, but blood,
        /// organs and even fat carry the rest, so total body water can exceed
        /// muscle mass in someone lean-light. Flagged rather than hidden.
        public let exceedsHost: Bool
    }

    /// Total body mass the parts are shares of.
    public let total: Double
    /// Heaviest first — fat, then the lean components.
    public let parts: [Part]
    /// Body water as a percentage of total mass, as the scale reports it.
    public let waterPercentage: Double?
    /// Where body water sits inside the bar, when there is a block to host it.
    public let water: WaterInset?
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
        let waterPercentage = samples.latestValue(.bodyWaterPercentage)

        // Water goes inside muscle where the scale reports muscle, and inside
        // the undivided lean block otherwise. Never inside fat: the point of the
        // inset is that water is held in *lean* tissue.
        var water: WaterInset?
        if let percentage = waterPercentage, percentage > 0 {
            let mass = weight * percentage / 100
            if let host = parts.first(where: { $0.metric == .muscleMass })
                ?? parts.first(where: { $0.metric == .leanBodyMass }),
               host.kilograms > 0 {
                water = WaterInset(kilograms: mass, host: host.metric,
                                   fractionOfHost: Swift.min(1, mass / host.kilograms),
                                   exceedsHost: mass > host.kilograms)
            }
        }

        return BodyCompositionSplit(
            total: weight,
            parts: parts,
            waterPercentage: waterPercentage,
            water: water,
            // A tolerance rather than an equality: these are four independent
            // readings from a bioimpedance scale and they will not sum exactly.
            isPartial: abs(accounted - weight) > 0.5)
    }

    // MARK: - The same split, over time

    /// One split per day the scale actually reported one.
    ///
    /// ## Why per measured day, and not per calendar day
    ///
    /// The obvious build carries the last known value forward so every day has a
    /// point. That would draw a body that changes on days nothing was measured,
    /// and over this data it would be mostly invention: the Withings scale logged
    /// 220 weights but only 153 full compositions, and body fat reaches back to
    /// 2020 while muscle, bone and water begin on 2024-12-25 when the Body Smart
    /// arrived. Every point here is a real weigh-in.
    ///
    /// ## The split changes resolution partway through, on purpose
    ///
    /// Before the Body Smart there is fat and lean and no way to divide the lean;
    /// after it there is muscle and bone. Rather than flatten the recent detail
    /// to match the old data, or fabricate the old detail to match the recent,
    /// each day gets the finest split its *own* readings support — so the lean
    /// band visibly subdivides on the day the scale started saying more.
    /// `finerSplitBegins` is that date, for a caption; `nil` when the whole
    /// window has one resolution.
    /// One weigh-in's split, dated.
    ///
    /// A named type rather than a tuple because Swift key paths cannot refer to
    /// tuple elements, so `ForEach(points, id: \.date)` at the call site would
    /// not compile — a trap this repo has hit before and which only CI would
    /// catch, SwiftUI being unavailable to the local suite.
    public struct Dated: Sendable, Equatable, Identifiable {
        public let date: Date
        public let split: BodyCompositionSplit
        public var id: Date { date }
    }

    public struct Series: Sendable, Equatable {
        public let points: [Dated]
        /// The day the lean band subdivides, or `nil` when the whole window is
        /// one resolution and there is no transition to explain.
        public let finerSplitBegins: Date?
    }

    public static func series(samples: [HealthMetricSample],
                              calendar: Calendar = .current) -> Series {
        let byDay = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.start) }
        let points = byDay.keys.sorted().compactMap { day -> Dated? in
            guard let split = from(samples: byDay[day] ?? []) else { return nil }
            return Dated(date: day, split: split)
        }
        // Only worth reporting when the window actually contains both
        // resolutions, otherwise the caption would explain a transition the
        // reader cannot see.
        let isFine = { (point: Dated) in
            point.split.parts.contains { $0.metric == .muscleMass }
        }
        return Series(points: points,
                      finerSplitBegins: points.contains { !isFine($0) }
                        ? points.first(where: isFine)?.date
                        : nil)
    }
}
