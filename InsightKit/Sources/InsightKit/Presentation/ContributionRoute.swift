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
    /// A file the reader shares in from another app — today Shotsy's backup.
    ///
    /// A route rather than a Settings-only affordance because **every input
    /// type has to appear here**: "View & add" is the card's answer to "what
    /// does this want from me", and an input reachable only from Settings is
    /// one the reader will never find. The user made that the rule on
    /// 2026-08-02, and it applies to the scans and photos still to come.
    case fileImport

    /// A GLP-1 regimen and everything logged against it — the dose history and
    /// the side effects recorded alongside it.
    ///
    /// **One route, three inputs**, because they are one conversation: you have
    /// a regimen, you log doses against it, and you note what it did to you.
    /// Splitting them would put three near-identical buttons on one card.
    case medication
    /// The reader's own read of their build, overriding the estimate.
    ///
    /// A route rather than a control buried in the somatotype chart, which is
    /// where it lived until 2026-08-02 — and which is exactly the failure the
    /// user found: *"there are things on the body comp page that are not in the
    /// add and view.. body type, log a dose, import from file."* A card that
    /// takes something from the reader has to say so in one place, and this is
    /// the place.
    case bodyType

    /// Standing facts held on the profile, one latest value each.
    ///
    /// Carries the kinds rather than deriving them at the call site, so a card
    /// offers exactly what its own model asks for and nothing else.
    case groundingFacts([GroundingKind])
}

public extension ContributionRoute {
    /// Every master-list entry this route covers.
    ///
    /// Exhaustive, and **plural** since 2026-08-02: `.medication` offers three
    /// inputs behind one button, and a one-to-one mapping would have left two
    /// of them reachable from a card while absent from the app's own list of
    /// what a card offers. `InputKindTests` reads this to check the other
    /// direction — that nothing which must be on a card has been left off every
    /// card.
    var inputKinds: [InputKind] {
        switch self {
        case .bloodPressureReadings: return [.cuffBloodPressure]
        case .substanceLog: return [.substanceEvent]
        case .fileImport: return [.fileImport]
        case .groundingFacts: return [.profileFacts]
        case .medication: return [.medicationRegimen, .medicationDose, .sideEffect]
        case .bodyType: return [.bodyType]
        }
    }
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
