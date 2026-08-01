import Foundation

/// The line under a legend row: which way the signal is moving, whether that is
/// the good direction for this particular signal, and how much of the score it
/// carries.
///
/// ## Why all three, every row, every time
///
/// The legend used to print *one* of them, chosen by an `if`: the weight where
/// there was one, the direction otherwise, and the good-or-bad judgement only
/// where the model had declared a direction. So on one card a signal carrying a
/// quarter of the score never said which way it was going, the signal below it
/// said "trending up" and never said it was unscored, and a third said
/// "trending down (worth watching)" — three rows, each silent about a different
/// thing, with nothing on screen to tell a reader which fact was missing from
/// which.
///
/// The three answers are independent: a signal can be rising, rising can be the
/// bad direction, and the whole thing can still be unscored. A row that shows
/// one of them has to pick, and any pick is wrong for some row. Stating all
/// three costs one line and removes the guessing.
///
/// ## Why this is a type in InsightKit
///
/// The app target has no test target, and this is wording that can be *wrong*
/// rather than merely ugly: "trending up · the good direction" printed against a
/// metric where rising is the bad direction is a false statement about the
/// user's health. Same reason `SectionCaveat` and `OverlaySelection` live here.
public struct LegendCaption: Sendable, Equatable {

    /// Which way it has moved over the window.
    public let direction: String
    /// Whether that is the direction you want for this signal.
    public let judgement: String
    /// Its share of the score.
    public let weighting: String

    public init(direction: String, judgement: String, weighting: String) {
        self.direction = direction
        self.judgement = judgement
        self.weighting = weighting
    }

    /// The three as one line. Middle dots rather than commas because these are
    /// three separate answers, not the clauses of one sentence.
    public var text: String { "\(direction) · \(judgement) · \(weighting)" }

    // MARK: - Building one

    /// For a signal that has readings in this window.
    ///
    /// - Parameters:
    ///   - trendPerWeek: `NormalizedSeries.trendPerWeek`. `nil` means the series
    ///     is too short to fit a line through, which is **not** the same as
    ///     flat — a fortnight of readings and four readings are different
    ///     answers and the caption says which one it has.
    ///   - higherIsBetter: `nil` where neither direction is better, which is a
    ///     real answer for a deviation metric that is best near zero.
    ///   - weight: the renormalised share of the score, 0 for a signal that is
    ///     charted but not weighed into it.
    public static func series(trendPerWeek: Double?,
                              higherIsBetter: Bool?,
                              weight: Double,
                              minimumSlope: Double = PatternFinder.minimumSlope) -> LegendCaption {
        // Only a signal that is actually moving gets a verdict on its movement;
        // the rest get the metric's own preference, which is the same question
        // one step earlier. Named `movement` rather than `direction` because
        // shadowing a function with a local of the same name has bitten here.
        let movement = direction(trendPerWeek, minimumSlope: minimumSlope)
        let judgement: String
        if let slope = trendPerWeek, abs(slope) >= minimumSlope {
            judgement = verdict(rising: slope > 0, higherIsBetter: higherIsBetter)
        } else {
            judgement = preference(higherIsBetter)
        }
        return LegendCaption(direction: movement, judgement: judgement,
                             weighting: share(weight))
    }

    /// For a declared input with nothing recorded in this window. It still has a
    /// preferred direction and still has a weight, and those were the two facts
    /// the old "No data" row dropped entirely.
    public static func noReadings(higherIsBetter: Bool?, weight: Double) -> LegendCaption {
        LegendCaption(direction: nothingRecorded,
                      judgement: preference(higherIsBetter),
                      weighting: share(weight, whenRecorded: true))
    }

    /// For a card charting a model's *declared* inputs because the model
    /// reported no contributions of its own — see `ChartedContributions`.
    ///
    /// The direction is still measured and still true; the other two are not
    /// known. Printing the stand-in's zeroes through `series(...)` would say
    /// "tracked, not scored · neither direction is better" on every row of the
    /// card, which are two findings no model produced.
    public static func unreported(trendPerWeek: Double?,
                                  minimumSlope: Double = PatternFinder.minimumSlope) -> LegendCaption {
        LegendCaption(direction: direction(trendPerWeek, minimumSlope: minimumSlope),
                      judgement: unknownPreference,
                      weighting: unknownShare)
    }

    /// Both at once: a stand-in for a declared input that also has nothing
    /// recorded in this window. Rare, and the row most likely to be read as a
    /// bug if it went blank.
    public static let unreportedAndUnrecorded = LegendCaption(
        direction: nothingRecorded, judgement: unknownPreference, weighting: unknownShare)

    // MARK: - The three phrases

    /// Which way it moved. `nil` is a series too short to fit a line through,
    /// which is **not** flat — saying "steady" there would be an invented
    /// reassurance, and it is the one of these three that a reader would act on.
    static func direction(_ trendPerWeek: Double?, minimumSlope: Double) -> String {
        guard let slope = trendPerWeek else { return "Too few days to call a direction" }
        guard abs(slope) >= minimumSlope else { return "Holding steady" }
        return slope > 0 ? "Trending up" : "Trending down"
    }

    /// Where the signal is actually moving, so the verdict is about *this*
    /// movement rather than about the metric in the abstract.
    static func verdict(rising: Bool, higherIsBetter: Bool?) -> String {
        guard let higherIsBetter else { return neitherDirection }
        return rising == higherIsBetter ? "the good direction" : "the direction to watch"
    }

    /// Where there is no movement to judge — steady, or too short to fit. The
    /// question "is up good here" still has an answer and the reader still wants
    /// it, so the caption gives the preference rather than going silent.
    static func preference(_ higherIsBetter: Bool?) -> String {
        guard let higherIsBetter else { return neitherDirection }
        return higherIsBetter ? "higher is better here" : "lower is better here"
    }

    /// Not "no judgement available" — the model is making a positive claim that
    /// neither end is the good end, which is true of a deviation that is best
    /// near zero. Deliberately distinct from `unknownPreference`, which is the
    /// absence of any claim at all.
    static let neitherDirection = "neither direction is better"

    /// The two absences, worded as absences. A model that reported nothing has
    /// not decided that nothing matters.
    static let unknownPreference = "no preferred direction reported"
    static let unknownShare = "no weighting reported"

    static let nothingRecorded = "No readings in this window"

    /// A weight of zero is a *statement*, not a missing value: the signal is
    /// charted because it is worth seeing and left out of the score because no
    /// validated curve for it exists here.
    static func share(_ weight: Double, whenRecorded: Bool = false) -> String {
        guard weight > 0 else { return "tracked, not scored" }
        let percent = Int((weight * 100).rounded())
        // A weight that rounds to zero would otherwise print "0% of this score"
        // beside a signal that genuinely counts — the one reading of this line
        // that is flatly untrue.
        let magnitude = percent == 0 ? "under 1%" : "\(percent)%"
        return whenRecorded
            ? "\(magnitude) of this score when recorded"
            : "\(magnitude) of this score"
    }
}
