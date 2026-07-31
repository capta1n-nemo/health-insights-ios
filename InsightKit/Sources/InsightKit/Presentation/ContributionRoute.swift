import Foundation

/// What a user can hand an insight, and therefore what its "View & add" section
/// offers.
///
/// This exists because the app had three unrelated ways to give it something:
/// a one-fact sheet behind "Add these for a better estimate", a blood-pressure
/// chart and add-button hidden behind a link to a different screen, and a
/// substance log reachable only from a toolbar button on a tab that doesn't
/// mention it. One card, one section, whatever the card.
///
/// The routes are about the *shape* of the contribution, not about which insight
/// it belongs to — that is what lets one view render all of them.
public enum ContributionRoute: Sendable, Equatable, Hashable {
    /// Dated paired cuff readings, with a calibration target to reach.
    case bloodPressureReadings
    /// A dated log of events the user adds as they happen.
    case substanceLog
    /// Standing facts held on the profile, one latest value each.
    ///
    /// Carries the kinds rather than deriving them at the call site, so a card
    /// offers exactly what its own model asks for and nothing else.
    case groundingFacts([GroundingKind])
}

public extension InsightModel {
    /// Derived from `requirements` rather than switched over `InsightID`.
    ///
    /// Deliberate: an `InsightID` already feeds five exhaustive switches and
    /// that is this repo's most frequent CI break. A sixth would make it worse,
    /// and would let a new insight compile with a "View & add" section that
    /// offers nothing. Every model already declares what facts it needs; this
    /// reads that declaration instead of asking for it a second time.
    ///
    /// Models backed by a dated log — blood pressure, substances — override,
    /// because a log is not a profile fact and no amount of reading
    /// `requirements` would say so.
    var contributions: [ContributionRoute] {
        requirements.isEmpty ? [] : [.groundingFacts(requirements.map(\.kind))]
    }
}
