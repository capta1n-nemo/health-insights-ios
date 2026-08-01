import Foundation

/// "Where are you with this, and what would move it" — for any `ContributionRoute`.
///
/// ## Why the three routes needed one of these
///
/// `ViewAndAddSection`'s own doc comment claims "the anatomy is fixed whatever
/// the route". Read against the code it was not: blood pressure had a grounded
/// summary, substances had none, and the facts route expressed the same idea as
/// a column of green ticks. Each route also previewed its own contents — three
/// readings, three events, every fact with its value — which is what this change
/// removes: the card says *where you are*, and the sub-menu behind the button
/// holds *what you have given*.
///
/// The parts that can be wrong are which state counts as grounded and what the
/// figure says, and those are the parts a view cannot test. Blood pressure is
/// deliberately not re-derived here — it defers to
/// `BloodPressureEstimator.CalibrationStatus`, which already owns the
/// five-then-two rule and its wording. A second opinion on "are you calibrated"
/// is exactly the kind of duplicate this app has been bitten by.
public struct ContributionSummary: Sendable, Equatable {

    /// Whether this route has everything it asks for.
    public let isGrounded: Bool
    /// The one figure in the section header — the thing that makes the section
    /// worth looking at when there is nothing to add.
    public let figure: String
    /// The sentence beside the seal.
    public let guidance: String
    /// Fill for a progress bar, or `nil` when there is nothing left to fill.
    /// A full bar next to a green seal says the same thing twice.
    public let progress: Double?
    /// The words on the button that opens the sub-menu.
    public let addLabel: String
    /// The words on the link under the button, or `nil` where the button's own
    /// destination already *is* the full view.
    ///
    /// Blood pressure has both because they answer different questions: the
    /// sheet takes a reading, and the metric screen holds the dated history, the
    /// chart and the calibration detail. The substance log and the grounding
    /// list are single screens that already show everything they have, so a link
    /// beside the button pointing at the same place would be two controls for
    /// one destination — which is the kind of thing this section was built to
    /// remove, not to spread.
    public let detailLabel: String?

    // MARK: - Routes

    /// Defers entirely to the calibration status for the grounded question, the
    /// target and the sentence. Only the labels are new.
    public static func bloodPressure(
        _ status: BloodPressureEstimator.CalibrationStatus
    ) -> ContributionSummary {
        ContributionSummary(
            isGrounded: status.isGrounded,
            figure: "\(status.recentReadings) in 30 days",
            guidance: status.guidance,
            progress: status.isGrounded || status.required == 0
                ? nil
                : Swift.min(1, Double(status.recentReadings) / Double(status.required)),
            addLabel: "Add a reading",
            detailLabel: status.totalReadings > 0
                ? "All \(status.totalReadings) \(SectionCaveat.plural(status.totalReadings, "reading")) and calibration detail"
                : "Readings and calibration detail")
    }

    /// A log has no target, so "grounded" here means only that there is
    /// something to compare against. Deliberately not a count threshold: the
    /// model decides for itself whether it has enough to say anything, and a
    /// second bar here would be this view inventing a requirement.
    public static func substances(logged: Int) -> ContributionSummary {
        ContributionSummary(
            isGrounded: logged > 0,
            figure: logged == 0 ? "None yet" : "\(logged) logged",
            guidance: logged == 0
                ? "Nothing logged yet. Logging what you have — and when — is what "
                    + "lets the app compare the hours afterwards against your ordinary days."
                : "\(logged) \(SectionCaveat.plural(logged, "entry", plural: "entries")) "
                    + "recorded. Private and on-device, so the app can show how your "
                    + "body responds — no judgement, and no amounts.",
            progress: nil,
            addLabel: logged == 0 ? "Log something" : "View & add entries",
            detailLabel: nil)
    }

    /// Standing profile facts: one target, one count.
    public static func facts(set: Int, of total: Int) -> ContributionSummary {
        let complete = total > 0 && set >= total
        return ContributionSummary(
            isGrounded: complete,
            figure: "\(set) of \(total) set",
            guidance: complete
                ? "All set. The app has everything it asks for here — open it to "
                    + "check or change anything you entered."
                : "\(total - set) still to give. The more of these the app has, the "
                    + "less it has to assume.",
            progress: complete || total == 0 ? nil : Double(set) / Double(total),
            addLabel: complete ? "View your details" : "Add your details",
            detailLabel: nil)
    }
}
