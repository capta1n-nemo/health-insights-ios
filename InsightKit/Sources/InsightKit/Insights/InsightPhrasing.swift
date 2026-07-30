import Foundation

/// Phrasing shared by the insight cards that were once all in
/// `AdditionalInsights.swift`. Internal rather than file-private now that they
/// live apart — Swift's `private` is file-scoped, so splitting a file always
/// widens whatever the moved code touched.

// Shared helpers for the extra insights.
func notReady(_ id: InsightID, _ title: String, _ message: String) -> InsightResult {
    InsightResult(id: id, title: title, primaryValue: nil, headline: "No data yet",
                  score: nil, confidence: .low, explanation: message,
                  drivers: [], unmetRequirements: [])
}

func trendWord(recent: Double, baseline: Double, higherIsBetter: Bool) -> String {
    let delta = recent - baseline
    if abs(delta) < 0.5 { return "steady" }
    let rising = delta > 0
    let good = rising == higherIsBetter
    return (rising ? "trending up" : "trending down") + (good ? " (good)" : "")
}

/// Whether a `trendWord` phrase describes movement in the unwanted direction.
///
/// `trendWord` appends "(good)" when the direction is the favourable one, so
/// anything moving and *not* marked good is what a card should lead with.
func isAdverseTrend(_ word: String) -> Bool {
    word != "steady" && !word.contains("(good)")
}
