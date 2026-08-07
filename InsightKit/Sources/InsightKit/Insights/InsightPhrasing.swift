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
// `notReady` is deleted, not deprecated. It built the one thing a card must
// never be: visible with a headline of "No data yet" and `invitesInput: false`,
// which is both a dead end and — because `isWorthShowing` reads that flag — an
// invisible one. Its two callers (Sleep, Body Composition) each already carried
// a perfectly good sentence about what to connect; they just passed it as the
// *explanation*, and the row renders the headline. They use `invitingInput`
// below, whose `action` argument has no default.
//
// The reader's rule, 2026-08-05: "every card should show, even if it hasn't got
// data yet." Deleting the only constructor that could produce a card with
// nothing to say is what makes that rule hold by construction rather than by
// review. `CardVisibilityTests` asserts both halves — every card visible, and no
// card leading with a dead end.

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

/// **Not enough yet — and it is not the reader's fault or their job to fix.**
///
/// ⚠️ **Why this is a separate constructor from `invitingInput`.** Found on the
/// reader's own phone, 2026-08-07: Travel drain said *"Connect your calendar"*
/// while their calendar was connected. `TravelDrainModel.evaluate` returned
/// `nil` down three different paths — too few trips, too few days either side,
/// too few responding signals — and the card rendered the same invitation for
/// all of them. **So the app told them to do something they had already done.**
///
/// `invitingInput` requires an `action` on purpose, and that rule is right: a
/// card asking for input must say what to do. But it makes an *imperative* the
/// only way to explain an absent figure, and most absences are not the reader's
/// to act on — two more trips, ten more reviewed events, three more cycles.
/// Reaching for `invitingInput` there produces a false instruction, which is
/// worse than silence: the reader acts, and nothing changes.
///
/// So this is the other half of backlog D46. `invitingInput` says *do this*;
/// this says *this is what I am still counting, and how far along it is*, and
/// **it never sets `invitesInput`** — there is nothing to give.
func waitingOn(_ id: InsightID, _ title: String,
               gate: CoverageGate, context: String) -> InsightResult {
    // A met gate says nothing (`sentence` is nil), which should be unreachable
    // here — reaching it means a caller withheld a figure whose own gate says it
    // had enough. Say so rather than printing an empty explanation.
    let waiting = gate.sentence ?? "Still gathering the data behind this."
    return InsightResult(id: id, title: title, primaryValue: nil,
                         headline: "Learning",
                         score: nil, confidence: .low,
                         explanation: "\(context) \(waiting)",
                         drivers: [], unmetRequirements: [], invitesInput: false,
                         isLearning: true)
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
