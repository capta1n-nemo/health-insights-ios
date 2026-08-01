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

    /// What a picture of this split actually draws, bottom of the stack first.
    ///
    /// Not the same list as `parts`, and the difference is water. `parts` is the
    /// partition of body mass — water cannot appear in it without counting the
    /// same kilograms twice. But a *drawing* wants water visible, so the block
    /// hosting it is cut in two: the watery share and the rest. The sum is
    /// unchanged, which is the property that lets the same list drive both the
    /// single bar and the stacked area without either inventing mass.
    ///
    /// Shared rather than derived twice: the bar and the trend chart drawing
    /// different bands for the same body is precisely the kind of disagreement
    /// this repo keeps extracting types to prevent.
    public struct Band: Sendable, Equatable, Identifiable {
        /// What the band *is*, so a palette can colour it by substance rather
        /// than by an arbitrary hue slot.
        public enum Kind: String, Sendable, Equatable, CaseIterable {
            case fat, muscleWater, muscle, bone, otherLean, lean
        }
        public let kind: Kind
        public let label: String
        public let kilograms: Double
        /// Share of total mass, 0…1.
        public let fraction: Double
        public var id: String { kind.rawValue }
    }

    public var bands: [Band] {
        parts.map { part in
            let kind: Band.Kind
            switch part.metric {
            case .bodyFatPercentage: kind = .fat
            case .muscleMass: kind = .muscle
            case .boneMass: kind = .bone
            case .leanBodyMass: kind = part.label == "Lean" ? .lean : .otherLean
            default: kind = .otherLean
            }
            return Band(kind: kind, label: part.label,
                        kilograms: part.kilograms, fraction: part.fraction)
        }
    }

    /// Where the water film is painted, as cumulative kilograms up the stack.
    ///
    /// Water is **not** a band and must never become one. It was briefly cut out
    /// of its host as a slice of its own, which made the muscle band stop being
    /// red over that stretch — so the water stopped looking like something *on*
    /// muscle and started looking like a third substance beside it. No blend of
    /// two adjacent slices can fix that, because the problem is the geometry
    /// rather than the colour.
    ///
    /// So the host band is drawn whole, in its own colour, and this is the
    /// rectangle a translucent film goes over: from the top of everything below
    /// the host, up by the water's mass. The red underneath shows through, which
    /// is the entire point and the only way the relationship reads.
    public struct WaterSpan: Sendable, Equatable {
        /// Cumulative mass at the bottom edge of the film.
        public let from: Double
        /// Cumulative mass at its top edge, clamped inside the host band.
        public let to: Double
    }

    public var waterSpan: WaterSpan? {
        guard let water else { return nil }
        var below: Double = 0
        for band in bands {
            if band.kind == hostKind(water.host) { break }
            below += band.kilograms
        }
        let host = bands.first { $0.kind == hostKind(water.host) }?.kilograms ?? 0
        guard host > 0 else { return nil }
        return WaterSpan(from: below, to: below + Swift.min(water.kilograms, host))
    }

    private func hostKind(_ metric: MetricType) -> Band.Kind {
        metric == .muscleMass ? .muscle : .lean
    }

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
        /// The lean subdivision on this day was inferred from a neighbouring
        /// weigh-in rather than measured. The bar is real; how it divides
        /// between muscle and bone is an estimate, and must be drawn as one.
        public let isEstimated: Bool
        public var id: Date { date }
    }

    public struct Series: Sendable, Equatable {
        public let points: [Dated]
        /// The day the lean band subdivides, or `nil` when the whole window is
        /// one resolution and there is no transition to explain.
        public let finerSplitBegins: Date?
    }

    /// Every weigh-in in the history, on a **consistent set of bands**.
    ///
    /// ## The defect this exists to fix
    ///
    /// The first version gave every day the finest split its own readings
    /// supported, which was honest and drew a broken chart. The scale logs a
    /// weight far more often than a full composition, so band membership changed
    /// from point to point — `[Fat, Muscle, Bone]` on Monday, `[Fat, Lean]` on
    /// Wednesday — and a stacked area whose series vanishes at one x collapses
    /// that band to zero and back. The result was a row of notches, which is what
    /// "missing data breaks the graph" looks like.
    ///
    /// So a day that measured its lean mass but not the muscle/bone division now
    /// borrows the division from the nearest day that did, and is flagged
    /// `isEstimated` so the chart can draw it as the inference it is. The
    /// *quantities* are never invented — total, fat and lean are all measured on
    /// that day. Only the ratio splitting lean is borrowed, and only when some
    /// day in the history actually measured one.
    public static func series(samples: [HealthMetricSample],
                              calendar: Calendar = .current) -> Series {
        let byDay = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.start) }
        let measured = byDay.keys.sorted().compactMap { day -> Dated? in
            guard let split = from(samples: byDay[day] ?? []) else { return nil }
            return Dated(date: day, split: split, isEstimated: false)
        }
        let hasMuscle = { (point: Dated) in
            point.split.parts.contains { $0.metric == .muscleMass }
        }
        // Nothing in the whole history divides lean, so there is no ratio to
        // borrow and nothing to estimate — every day keeps its own coarse split.
        guard measured.contains(where: hasMuscle) else {
            return Series(points: measured, finerSplitBegins: nil)
        }

        let points = measured.map { point -> Dated in
            guard !hasMuscle(point) else { return point }
            // The nearest day that did measure the division. Nearest rather than
            // previous, so the first weigh-ins of a history are estimated from
            // the scale that came later rather than left as notches.
            guard let donor = measured
                    .filter(hasMuscle)
                    .min(by: { abs($0.date.timeIntervalSince(point.date))
                             < abs($1.date.timeIntervalSince(point.date)) }),
                  let estimated = point.split.subdivided(like: donor.split)
            else { return point }
            return Dated(date: point.date, split: estimated, isEstimated: true)
        }

        return Series(points: points,
                      finerSplitBegins: points.contains { $0.isEstimated }
                        ? points.first(where: { !$0.isEstimated && hasMuscle($0) })?.date
                        : nil)
    }

    // MARK: - What changed over a window

    /// One band's movement between the first and last weigh-in of a window.
    public struct BandChange: Sendable, Equatable, Identifiable {
        public let kind: Band.Kind
        public let label: String
        public let delta: Double
        public var id: String { kind.rawValue }

        /// Whether this band moving *up* is the welcome direction.
        ///
        /// `nil` for the ones where neither direction is news: water tracks
        /// hydration and the hour of the weigh-in more than anything else, and
        /// unattributed lean is a rounding bucket.
        public var higherIsBetter: Bool? {
            switch kind {
            case .fat: return false
            case .muscle, .bone, .lean: return true
            case .muscleWater, .otherLean: return nil
            }
        }
    }

    /// The change across a window, whole and by band.
    ///
    /// The chart shows what the body *is* at every point and never said what it
    /// had *done*, which is the question a composition history is opened for —
    /// and the one the card's own narrative already answers in prose. A total on
    /// its own would not be enough: two kilograms off is a different event
    /// depending on whether it came from fat or from muscle, and that split is
    /// the whole reason this chart has bands rather than one weight line.
    public struct Change: Sendable, Equatable {
        public let from: Date
        public let to: Date
        public let totalDelta: Double
        public let bands: [BandChange]
        /// Water is not a band, so its movement is reported alongside them
        /// rather than among them. `nil` when either end has no water reading.
        public let waterDelta: Double?
    }

    /// First weigh-in of the window against the last.
    ///
    /// Deliberately the plain endpoint difference rather than a fitted slope:
    /// "what have I lost since March" is a question about two readings, and a
    /// regression would answer a subtly different one while looking like this.
    /// `nil` under two points, where there is no change to report.
    ///
    /// Bands are matched by kind, so a band present at one end and not the other
    /// is skipped rather than counted as having appeared from nothing.
    public static func change(over points: [Dated]) -> Change? {
        guard let first = points.first, let last = points.last,
              points.count >= 2, first.date < last.date else { return nil }
        let start = Dictionary(uniqueKeysWithValues:
            first.split.bands.map { ($0.kind, $0) })
        let bands = last.split.bands.compactMap { end -> BandChange? in
            guard let begin = start[end.kind] else { return nil }
            return BandChange(kind: end.kind, label: end.label,
                              delta: end.kilograms - begin.kilograms)
        }
        let waterDelta: Double? = {
            guard let a = first.split.water?.kilograms,
                  let b = last.split.water?.kilograms else { return nil }
            return b - a
        }()
        return Change(from: first.date, to: last.date,
                      totalDelta: last.split.total - first.split.total,
                      bands: bands, waterDelta: waterDelta)
    }

    /// This split's lean block divided in the same proportions as `donor`'s.
    ///
    /// Returns `nil` when there is no undivided lean block to divide, or when the
    /// donor has no division to lend — in both cases the caller keeps what it
    /// had rather than receiving something invented.
    func subdivided(like donor: BodyCompositionSplit) -> BodyCompositionSplit? {
        guard let lean = parts.first(where: { $0.metric == .leanBodyMass }) else { return nil }
        let donorLean = donor.parts
            .filter { $0.metric != .bodyFatPercentage }
            .reduce(0) { $0 + $1.kilograms }
        guard donorLean > 0 else { return nil }

        var rebuilt = parts.filter { $0.metric != .leanBodyMass }
        for donorPart in donor.parts where donorPart.metric != .bodyFatPercentage {
            let share = donorPart.kilograms / donorLean
            let kilograms = lean.kilograms * share
            rebuilt.append(Part(metric: donorPart.metric, label: donorPart.label,
                                kilograms: kilograms, fraction: kilograms / total))
        }
        // Keep the drawing order the donor established, so the bands stack the
        // same way on every point and the chart cannot shuffle mid-series.
        let order = donor.parts.map(\.metric)
        rebuilt.sort { (order.firstIndex(of: $0.metric) ?? .max)
                     < (order.firstIndex(of: $1.metric) ?? .max) }

        let host = rebuilt.first { $0.metric == .muscleMass }
            ?? rebuilt.first { $0.metric == .leanBodyMass }
        return BodyCompositionSplit(
            total: total,
            parts: rebuilt,
            waterPercentage: waterPercentage,
            water: water.flatMap { existing in
                host.map { host in
                    WaterInset(kilograms: existing.kilograms, host: host.metric,
                               fractionOfHost: Swift.min(1, existing.kilograms / host.kilograms),
                               exceedsHost: existing.kilograms > host.kilograms)
                }
            },
            isPartial: isPartial)
    }
}
