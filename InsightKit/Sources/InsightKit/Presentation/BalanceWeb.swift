import Foundation

/// A point in the web's own unit space: origin at the centre, radius 1 at the
/// outer ring, **y increasing downward** so the view can map it to screen
/// coordinates without flipping anything.
///
/// Deliberately not `CGPoint`: InsightKit builds on Linux, where CoreGraphics
/// does not exist, and the geometry is the half of this chart that can actually
/// be tested. The app target has no test target — see `add-chart` §5.
public struct WebPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Where each spoke of the balance web sits.
///
/// ## Why the area of the polygon is not a quantity
///
/// A radar's enclosed area is the sum of `½·r₁·r₂·sin θ` over adjacent pairs —
/// so it depends on **which spokes happen to be neighbours**, which is a
/// decision about axis order, not a fact about the reader. Reordering the axes
/// changes the area without a single score moving.
///
/// Two things follow, and both are enforced rather than hoped for:
///
/// 1. **The order is fixed** to `InsightID.colourSlot` — the daily block, then
///    the trend block — which is already the app's one documented ordering of
///    insights. `orderedSpokes` is the only place the order is decided, so the
///    shape a reader learns on Monday is the same shape on Friday.
/// 2. **Nothing in the UI reads the area out.** The summary sentence quotes the
///    spread between the highest and lowest score, which *is* a fact about the
///    reader, and the vertices carry the numbers. The filled shape is there to
///    make a dent findable at a glance, and a dent is a genuinely truthful read:
///    a short spoke is a low score.
public enum BalanceWebGeometry {

    /// The grid rings, as fractions of the outer radius. Quarters, so a reader
    /// can place a vertex without consulting a label — the same job the 50/70
    /// rule lines do on `ScoreHistoryChart`.
    public static let ringFractions: [Double] = [0.25, 0.5, 0.75, 1.0]

    /// The smallest number of spokes that encloses anything.
    ///
    /// Two scores draw a line segment, which reads as a chart with a bug in it
    /// rather than as a shape. Below this the hero falls back to the plain rows.
    public static let minimumSpokes = 3

    /// Angle of a spoke, in radians, starting at twelve o'clock and going
    /// clockwise on screen.
    ///
    /// `-π/2` puts index 0 at the top: in a y-down space `sin(-π/2) = -1`, which
    /// is one radius *above* the centre.
    public static func angle(index: Int, count: Int) -> Double {
        guard count > 0 else { return -.pi / 2 }
        return -.pi / 2 + 2 * .pi * Double(index) / Double(count)
    }

    /// Score to radius, linear, with no inner floor.
    ///
    /// The obvious refinement is to hold a floor of ~0.15 so a zero still shows
    /// something. It is rejected: the vertex position *is* the encoding here, and
    /// a floor draws a score of 0 in the same place as a score of 15. A zero
    /// belongs at the centre, where the grid rings say it is.
    public static func radiusFraction(forScore score: Double) -> Double {
        min(max(score / 100, 0), 1)
    }

    /// A spoke's vertex in unit space.
    public static func point(index: Int, count: Int, radiusFraction: Double) -> WebPoint {
        let a = angle(index: index, count: count)
        let r = min(max(radiusFraction, 0), 1)
        return WebPoint(x: cos(a) * r, y: sin(a) * r)
    }

    /// The closed polygon through every spoke, outer ring at `scale`.
    ///
    /// Used for the grid rings too, by passing a constant fraction.
    public static func polygon(fractions: [Double], scale: Double = 1) -> [WebPoint] {
        fractions.enumerated().map { index, fraction in
            point(index: index, count: fractions.count, radiusFraction: fraction * scale)
        }
    }
}

/// Every scored insight's current standing, laid out for the balance web.
///
/// ## What this replaced, and the one thing it gives up
///
/// The Insights tab used to open with `ScoreComparisonChart` — every score on
/// one 0–100 time axis. It answered a real question ("are my scores moving as
/// one thing or pulling apart") and it cost the most expensive computation in
/// the app to ask it: `AppModel.scoreHistory(for:)` replays 90 days per insight,
/// walking the sample set once per replayed day, and the tab requested one for
/// *every* scored card the moment it opened. See `AppModel.maxConcurrentReplays`,
/// whose doc comment records the four-to-six second scroll freezes that came of
/// it.
///
/// This snapshot is built from two things that are **already in memory** when
/// the tab opens: `InsightResult.score`, computed by `recompute()`, and
/// `ScoreChange`, which `AppModel` caches from *stored* score rows. No replay,
/// so the hero draws on the first frame.
///
/// **What is given up is the time axis**, and it is given up rather than faked:
/// this is a picture of balance *now*, not of co-movement over months. The two
/// partial restorations are honest ones — each spoke carries its own reference
/// mark, so movement per insight is still visible, and the full comparison chart
/// is still reachable, unchanged, one tap away where its replays cost only the
/// reader who asked for them.
public struct BalanceWebSnapshot: Sendable, Equatable {

    /// One insight's spoke.
    public struct Spoke: Sendable, Equatable, Identifiable {
        public let id: InsightID
        /// The card's own title, for accessibility and the detail link.
        public let title: String
        /// The label drawn on the chart. Nine of these ring a phone-width
        /// circle, so it has to be a word.
        public let shortTitle: String
        /// Today's score, 0…100 — the same number the card's dial shows.
        public let score: Double
        /// The mean of the window this card is judged against, when there is
        /// enough stored history to have judged it. `nil` is "we cannot say yet",
        /// which is why it is not defaulted to the score.
        public let reference: Double?
        /// Which way it has moved, from the same `ScoreChange` as the card's
        /// chip — so the web and the chip cannot disagree.
        public let direction: ScoreChange.Direction?

        /// How many days back the reference averages over, from the same
        /// `ScoreChange`. Carried so the legend can say what "usual" means
        /// instead of leaving the reader to guess — and because **it is not one
        /// number**: a `.daily` card compares against the trailing week and a
        /// `.trend` card against the quarter, so the grey shape is a composite.
        public let referenceDays: Int?

        public init(id: InsightID, title: String, shortTitle: String,
                    score: Double, reference: Double?,
                    direction: ScoreChange.Direction?,
                    referenceDays: Int? = nil) {
            self.id = id
            self.title = title
            self.shortTitle = shortTitle
            self.score = score
            self.reference = reference
            self.direction = direction
            self.referenceDays = referenceDays
        }

        public var radiusFraction: Double {
            BalanceWebGeometry.radiusFraction(forScore: score)
        }
        public var referenceFraction: Double? {
            reference.map { BalanceWebGeometry.radiusFraction(forScore: $0) }
        }
    }

    public let spokes: [Spoke]

    public init(spokes: [Spoke]) {
        self.spokes = spokes
    }

    /// An empty web, which is what a cold launch has before `recompute()` lands.
    public static let empty = BalanceWebSnapshot(spokes: [])

    /// Whether there are enough spokes to enclose a shape at all.
    public var isDrawable: Bool { spokes.count >= BalanceWebGeometry.minimumSpokes }

    /// Whether the reference outline may be drawn as a **closed polygon**.
    ///
    /// Only when every drawn spoke has a reference. A closed shape through a
    /// subset is a different shape — it would run its edges straight past the
    /// spokes it has no value for, and a reader has no way to see which vertices
    /// were skipped. Where the reference is partial the view draws per-spoke
    /// ticks instead, which can be individually absent without lying.
    public var hasCompleteReference: Bool {
        !spokes.isEmpty && spokes.allSatisfy { $0.reference != nil }
    }

    public var highest: Spoke? { spokes.max { $0.score < $1.score } }
    public var lowest: Spoke? { spokes.min { $0.score < $1.score } }

    /// Highest score minus lowest, in points. `nil` below two spokes.
    public var spread: Double? {
        guard let highest, let lowest, spokes.count >= 2 else { return nil }
        return highest.score - lowest.score
    }

    /// Where a spread stops reading as "these are all much the same".
    ///
    /// Fifteen points, which is the width of `Theme`'s amber band (45→70) minus
    /// a little: a spread that fits inside one band genuinely is one story, and
    /// a spread that crosses a band boundary is two. Not a tuned number — it is
    /// the band width, so it moves if the bands do.
    public static let balancedSpreadPoints = 15.0

    /// One sentence under the web, quoting what the picture actually shows.
    ///
    /// Deliberately about *spread*, never about co-movement: this chart has no
    /// time axis and must not be captioned as though it had one.
    public var summary: String? {
        guard let spread, let highest, let lowest else { return nil }
        let points = Int(spread.rounded())
        if spread <= Self.balancedSpreadPoints {
            return "Your scores sit within \(points) points of each other, "
                + "\(Int(lowest.score.rounded())) to \(Int(highest.score.rounded()))."
        }
        return "Your scores span \(points) points — \(highest.shortTitle) highest at "
            + "\(Int(highest.score.rounded())), \(lowest.shortTitle) lowest at "
            + "\(Int(lowest.score.rounded()))."
    }

    /// What the grey shape is actually averaging over, in words.
    ///
    /// **The reader asked what "usual" means, and the honest answer is that it
    /// is not one window.** `ScoreChangeReader` gives a `.daily` card the
    /// trailing week and a `.trend` card the trailing quarter, because a card
    /// seen every morning and a card seen once a month are asking different
    /// questions. So the grey web is a composite, and a legend claiming a single
    /// period would be wrong on most of its own vertices.
    ///
    /// Returns nil when nothing has a reference — there is no shape to describe.
    public var referenceDescription: String? {
        let windows = Set(spokes.compactMap(\.referenceDays))
        guard !windows.isEmpty else { return nil }
        func phrase(_ days: Int) -> String {
            switch days {
            case 7: return "week"
            case 28: return "4 weeks"
            case 30: return "month"
            case 90: return "3 months"
            default: return "\(days) days"
            }
        }
        if windows.count == 1, let only = windows.first {
            return "Your average over the last \(phrase(only))."
        }
        let sorted = windows.sorted()
        guard let shortest = sorted.first, let longest = sorted.last else { return nil }
        return "Your own average — the last \(phrase(shortest)) for the daily cards, "
            + "the last \(phrase(longest)) for the slower ones."
    }

    /// Build from what the tab already holds.
    ///
    /// Pure and `Sendable` in both directions, so it can run on a detached task
    /// — see `InsightsHeroModel`. Order is `InsightID.colourSlot`, never the
    /// order `results` happens to arrive in, so the shape is stable between
    /// launches. See the note on area in `BalanceWebGeometry`.
    public static func build(results: [InsightResult],
                            changes: [InsightID: ScoreChange]) -> BalanceWebSnapshot {
        let spokes = results
            .compactMap { result -> Spoke? in
                guard let score = result.score, result.id.belongsOnBalanceWeb else { return nil }
                let change = changes[result.id]
                return Spoke(id: result.id, title: result.title,
                             shortTitle: result.id.shortTitle,
                             score: score, reference: change?.reference,
                             direction: change?.direction,
                             referenceDays: change?.referenceDays)
            }
            .sorted { $0.id.colourSlot < $1.id.colourSlot }
        return BalanceWebSnapshot(spokes: spokes)
    }
}

public extension InsightID {

    /// Whether this card's score belongs on "How your scores compare".
    ///
    /// **Not every 0–100 number is a score in the sense this chart compares.**
    /// The web asks *how well is each dimension going*, with radius as the
    /// answer and hue as the band. A **detector** does not answer that: the
    /// symptom radar reports 100 when it has found nothing, so on a real record
    /// it drew as the single highest spoke — silence rendered as excellence, on
    /// the one card whose entire design exists to stop exactly that.
    ///
    /// The card's own copy is careful ("Nothing stirring", and it says outright
    /// that it catches fewer than half of illnesses early); the chart was
    /// undoing that in a glance, which is worse, because the web is what the
    /// reader sees first and it is the one surface where cards are read against
    /// each other. A quiet night moves the odds of being ill from roughly 7% to
    /// roughly 4% — see `docs/research-notes.md`. That is not a 100.
    ///
    /// Exhaustive on purpose: a new card must decide, and "it is a score people
    /// compare" is a judgement, not a default.
    var belongsOnBalanceWeb: Bool {
        switch self {
        case .readiness, .sleep, .energy, .substanceImpact, .heartHealth,
             .fitness, .cardiovascularRisk, .bloodPressure, .bodyComposition,
             .nutrition, .metabolism:
            return true
        // **On the web.** Unlike the radar — which is a detector and was taken
        // off on 2026-08-04 — this is a 0–100 score of the same kind as its
        // neighbours, comparable with them and moving on the same scale.
        case .sustainedLoad:
            return true
        // **On the web.** A 0-100 score of the same kind as its neighbours, and
        // the only one on the chart that survives a fortnight of wearing
        // nothing - which is precisely when a reader looks at the web and finds
        // half of it missing.
        case .gait:
            return true
        case .symptomRadar:
            return false
        }
    }

    /// One word for the chart, where nine labels ring a phone-width circle and
    /// "Body Composition" would collide with both its neighbours.
    ///
    /// Exhaustive rather than a truncation of `InsightResult.title`: truncating
    /// gives "Cardiovascu…" and "Substance I…", and a new insight deserves a
    /// compile error asking for its word rather than an ellipsis chosen for it.
    var shortTitle: String {
        switch self {
        case .readiness: return "Readiness"
        case .sleep: return "Sleep"
        case .energy: return "Energy"
        case .substanceImpact: return "Substances"
        case .sustainedLoad: return "Stress"
        case .gait: return "Walking"
        case .heartHealth: return "Heart"
        case .fitness: return "Fitness"
        case .cardiovascularRisk: return "Risk"
        case .bloodPressure: return "BP"
        case .bodyComposition: return "Body"
        case .nutrition: return "Food"
        case .metabolism: return "Burn"
        case .symptomRadar: return "Radar"
        }
    }
}
