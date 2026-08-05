import Foundation

public extension InsightID {
    /// The hue this insight prefers. Not necessarily the one it gets — see
    /// `InsightPalette.slots(for:)`, which resolves collisions per chart.
    ///
    /// Twelve insights and eight validated hues, so preferences *must* collide;
    /// the question is only whether two colliding cards can be on screen at
    /// once. `Theme.insightTint` used to answer that with a fixed table and a
    /// comment claiming safety because "never more than four are on screen at
    /// once" — but the user picks which four, so heartAge and bloodPressure
    /// (both violet), cardioFitness and bodyComposition, heartHealth and
    /// restingHeartRateTrend, cardioTrajectory and substanceImpact could each be
    /// chosen together and draw as one colour.
    ///
    /// That is the same belief-about-co-occurrence that shipped wrong once
    /// already for metric colours, and it stopped being hypothetical the moment
    /// Substance Impact got a score and could reach the comparison chart at all.
    ///
    /// Ordered so the insights most likely to be compared together get first
    /// claim: the four daily cards, then the trend cards.
    var colourSlot: Int {
        switch self {
        // The daily block first, because those are the four most likely to be
        // drawn against each other on the comparison chart, and the first slots
        // are the hues that separate best.
        case .readiness: return 0
        case .sleep: return 1
        case .energy: return 2
        case .substanceImpact: return 3
        // Then the trend block.
        case .heartHealth: return 4
        case .fitness: return 5
        case .cardiovascularRisk: return 6
        case .bloodPressure: return 7
        case .bodyComposition: return 8
        case .nutrition: return 9
        case .metabolism: return 10
        // The next unused preference integer, NOT a renumbering into the daily
        // block — moving existing slots would silently recolour every trend
        // card app-wide. 11 % 8 lands on Substance Impact's hue and
        // `slots(for:)` steps the later claimant per chart, which the distinct
        // integers here keep safe.
        case .symptomRadar: return 11
        case .sustainedLoad: return 12
        case .gait: return 13
        case .biologicalAge: return 14
        }
    }
}

/// Which hue each insight wears on one chart.
///
/// The insight-side twin of `MetricPalette`, and for the same reason: assignment
/// per chart rather than globally, because distinctness *within the chart in
/// front of you* is the property that actually matters. An insight keeps its own
/// preferred hue wherever that hue is free, so the same card usually looks the
/// same from one screen to the next; where two would collide, the later one steps
/// to the next free hue.
public enum InsightPalette {
    /// Hues in the validated categorical palette — the same eight the metric
    /// charts draw from, so the two sit beside each other without clashing.
    public static let hueCount = MetricPalette.hueCount

    /// Hue per insight for one chart, in the order the series are drawn.
    public static func slots(for insights: [InsightID]) -> [InsightID: Int] {
        var used = Set<Int>()
        var out: [InsightID: Int] = [:]
        for insight in insights where out[insight] == nil {
            var slot = insight.colourSlot % hueCount
            var tried = 0
            while used.contains(slot) && tried < hueCount {
                slot = (slot + 1) % hueCount
                tried += 1
            }
            used.insert(slot)
            out[insight] = slot
        }
        return out
    }
}
