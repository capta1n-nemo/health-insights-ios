import Foundation

/// Phrasing shared by the insight cards that were once all in
/// `AdditionalInsights.swift`. Internal rather than file-private now that they
/// live apart — Swift's `private` is file-scoped, so splitting a file always
/// widens whatever the moved code touched.

// Shared helpers for the extra insights.

/// A card with nothing to say and nothing the reader can do about it.
///
/// The headline is fixed at "No data yet" because that is the whole truth here:
/// there is no route to offer. **If there is a route, use `invitingInput`
/// instead** — `isWorthShowing` will keep this card off the tab anyway, since a
/// card with no number and no ask has not earned the space.
func notReady(_ id: InsightID, _ title: String, _ message: String) -> InsightResult {
    InsightResult(id: id, title: title, primaryValue: nil, headline: "No data yet",
                  score: nil, confidence: .low, explanation: message,
                  drivers: [], unmetRequirements: [], invitesInput: false)
}

/// A card that cannot score yet but *can* tell the reader what would fix that.
///
/// **`action` has no default, and that is the point.** On 2026-08-03 Nutrition
/// and Metabolism shipped invisible, because a card with no number and no unmet
/// requirement is filtered off the tab by `InsightResult.isWorthShowing` — the
/// fix was `invitesInput`, which put them back on it. Looking at the running app
/// on 2026-08-04 showed the fix was only half of one: both cards appeared and
/// both said **"No data yet"**, because `notReady` hard-coded that headline for
/// everybody and the row renders the headline, not the explanation. They were
/// visible and still asked for nothing.
///
/// Beside them, Blood Pressure reads "Log a reading — 0 of 5 cuff readings in
/// the last 30 days" and Heart Attack & Stroke Risk reads "Add your details".
/// Those are what a card asking for something looks like.
///
/// So the ask is now a required argument rather than a convention: a card that
/// declares it invites input cannot compile without saying what to do about it.
/// Same reasoning as `InsightSection`'s `caveat`.
///
/// - Parameters:
///   - action: The imperative the row shows in place of a figure — "Log what
///     you eat", "Add your details". Not a description of the gap.
///   - message: The detail behind it, shown when the card is opened.
func invitingInput(_ id: InsightID, _ title: String,
                   action: String, message: String) -> InsightResult {
    InsightResult(id: id, title: title, primaryValue: nil, headline: action,
                  score: nil, confidence: .low, explanation: message,
                  drivers: [], unmetRequirements: [], invitesInput: true)
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
