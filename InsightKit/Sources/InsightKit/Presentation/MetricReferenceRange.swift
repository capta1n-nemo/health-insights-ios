import Foundation

/// A padded y-range, so a single point or a flat line isn't glued to an edge.
///
/// Lived in `ScrollableMetricChart` in the app target, where nothing could test
/// it. It decides what a chart's axis claims about the spread of the data, which
/// is a correctness question — and `chartDomain` below now builds on it.
public func paddedYDomain(_ values: [Double], logarithmic: Bool = false) -> ClosedRange<Double>? {
    guard let lo = values.min(), let hi = values.max() else { return nil }
    let useLog = logarithmic && values.allSatisfy { $0 > 0 }
    if lo == hi {
        let pad = Swift.max(abs(lo) * 0.05, 1)
        let lower = useLog ? Swift.max(lo * 0.9, 0.0001) : lo - pad
        return lower...(hi + pad)
    }
    let span = hi - lo
    let lower = useLog ? Swift.max(lo * 0.7, 0.0001) : lo - span * 0.1
    return lower...(hi + span * 0.1)
}

/// The published range an ordinary reading sits in, for the handful of vitals
/// that actually have one.
///
/// Deliberately **not** `VitalSignsCheck.Spec`. That table's `hardLow`/`hardHigh`
/// are *alarm* bounds — the line past which a reading is called unusual whatever
/// the personal baseline. Shading a chart between them says almost nothing: blood
/// oxygen's alarm floor is 94% with no ceiling at all, so the band would cover
/// every point ever plotted. This carries the *normal* band instead, plus the
/// shoulder either side, plus the sentence a caption has to print — none of which
/// the alarm table has, or should have.
///
/// The two tables stay independent and are held together by a test asserting a
/// normal band is never wider than its own alarm bounds, rather than by
/// derivation. Modelled on `BloodPressureEstimator.Category.systolicRange`,
/// which is the same idea for the one chart that already shades.
public struct MetricReferenceRange: Sendable, Equatable {

    /// A stripe on the value axis. A `nil` bound is genuinely open — heart-rate
    /// recovery has a floor and no useful ceiling.
    public struct Band: Sendable, Equatable {
        public let low: Double?
        public let high: Double?

        public init(low: Double? = nil, high: Double? = nil) {
            self.low = low
            self.high = high
        }

        public func contains(_ value: Double) -> Bool {
            (low.map { value >= $0 } ?? true) && (high.map { value < $0 } ?? true)
        }

        /// Bounds that exist, for a chart deciding how far to widen its axis.
        public var finiteBounds: [Double] { [low, high].compactMap { $0 } }
    }

    /// Where a healthy adult's readings sit.
    public let normal: Band
    /// The shoulder below `normal`, when going low means something. `nil` where
    /// it doesn't: a resting heart rate under 60 is usually training.
    public let cautionBelow: Band?
    /// The shoulder above `normal`.
    public let cautionAbove: Band?
    /// One sentence, printed verbatim under the chart. Says what the band is and
    /// who it applies to — a band with no caption is a coloured rectangle.
    public let caption: String
    /// Where the numbers came from, printed as the caption's second line. A
    /// number cannot be added here without an attribution beside it.
    public let provenance: String

    public init(normal: Band, cautionBelow: Band? = nil, cautionAbove: Band? = nil,
                caption: String, provenance: String) {
        self.normal = normal
        self.cautionBelow = cautionBelow
        self.cautionAbove = cautionAbove
        self.caption = caption
        self.provenance = provenance
    }

    /// Every finite edge, lowest first.
    public var edges: [Double] {
        ([cautionBelow, cautionAbove].compactMap { $0 } + [normal])
            .flatMap(\.finiteBounds).sorted()
    }
}

/// One stripe, already clipped to a chart's visible y-domain.
public struct MetricReferenceBand: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case normal, caution }
    public let kind: Kind
    public let lower: Double
    public let upper: Double

    public init(kind: Kind, lower: Double, upper: Double) {
        self.kind = kind
        self.lower = lower
        self.upper = upper
    }

    public var id: String { "\(kind.rawValue)-\(lower)-\(upper)" }
}

public extension MetricReferenceRange {

    /// The stripes to shade for a given visible y-domain.
    ///
    /// Clipped here rather than in the view, for two reasons. An open-ended band
    /// has no numeric bound to hand a `RectangleMark` — the blood-pressure chart
    /// works around that with a literal `?? 260` — and the decision *not* to
    /// shade is a rule about honesty, which belongs where it can be tested.
    ///
    /// Returns `[]` when the normal band would cover `fullPlotFraction` or more
    /// of the domain. A wholly green plot is not reassurance, it is ink: the
    /// caption already states the range in words and the axis already says where
    /// the data sits.
    func bands(in domain: ClosedRange<Double>,
               fullPlotFraction: Double = 0.9) -> [MetricReferenceBand] {
        var out: [MetricReferenceBand] = []
        // Normal appended last so it draws over the shoulders; `ForEach`
        // preserves order.
        let stripes: [(MetricReferenceBand.Kind, Band?)] =
            [(.caution, cautionBelow), (.caution, cautionAbove), (.normal, normal)]
        for (kind, band) in stripes {
            guard let band else { continue }
            let lower = Swift.max(band.low ?? domain.lowerBound, domain.lowerBound)
            let upper = Swift.min(band.high ?? domain.upperBound, domain.upperBound)
            guard upper > lower else { continue }
            out.append(MetricReferenceBand(kind: kind, lower: lower, upper: upper))
        }
        let height = domain.upperBound - domain.lowerBound
        guard height > 0,
              let normalStripe = out.first(where: { $0.kind == .normal }),
              (normalStripe.upper - normalStripe.lower) / height < fullPlotFraction
        else { return [] }
        return out
    }

    /// The y-range a chart should show, so the band is legible without the data
    /// being squashed.
    ///
    /// Starts from `paddedYDomain(values)` and pulls in each band edge lying
    /// within `maxExpansion` data-spans of the opposite data bound. Each edge is
    /// tested against the *unexpanded* bounds, so the result doesn't depend on
    /// the order edges are visited.
    ///
    /// The budget is what stops a CGM morning spanning 0.6 mmol/L being
    /// flattened into a line so that a 3.9–10.0 band can be drawn around it.
    static func chartDomain(values: [Double],
                            reference: MetricReferenceRange?,
                            maxExpansion: Double = 3) -> ClosedRange<Double>? {
        guard let base = paddedYDomain(values) else { return nil }
        guard let reference else { return base }
        let span = Swift.max(base.upperBound - base.lowerBound, .leastNormalMagnitude)
        var lower = base.lowerBound
        var upper = base.upperBound
        for edge in reference.edges {
            if edge < base.lowerBound,
               base.upperBound - edge <= span * (1 + maxExpansion) {
                lower = Swift.min(lower, edge)
            }
            if edge > base.upperBound,
               edge - base.lowerBound <= span * (1 + maxExpansion) {
                upper = Swift.max(upper, edge)
            }
        }
        return lower...upper
    }
}
