import Foundation

/// **What the Today curve is, in the reader's own numbers.**
///
/// The reader, 2026-08-05: they cannot read the Today chart, and asked for
/// "How does this work?" and "So what?".
///
/// The chart was drawing a reservoir draining hour by hour with a header that
/// read `"84 spent of 96"` and no statement anywhere of what a unit is, where
/// the morning figure came from, or what the reader is supposed to do with
/// either. It is the one chart in the app whose subject is *inside* a day, and
/// it was the only one with no sentence attached.
///
/// Two rules this text has to keep:
///
/// - **A unit that is not a real quantity must say so.** Energy here is not
///   kilocalories and not any measured thing — it is a 0–100 model, and calling
///   it "energy" without saying that invites the reader to compare it with a
///   calorie figure it has no relationship to.
/// - **No advice.** "You have 40 left, so stop" is a recommendation this app
///   does not make. Describing the shape is not the same as prescribing a day.
public enum EnergyCurveExplainer {

    /// Why the day started where it did — the part the reader cannot see on the
    /// chart at all, because it happened before the first point.
    ///
    /// `nil` when the model had neither input, in which case there is nothing
    /// honest to say about the morning.
    public static func howItWorks(_ output: EnergyModel.Output) -> String? {
        var parts: [String] = []
        if let hours = output.sleepHours {
            parts.append("you slept \(oneDecimal(hours)) h")
        }
        if let z = output.recoveryZ {
            let word: String
            switch z {
            case ..<(-0.75): word = "below your usual"
            case ..<0.75: word = "about your usual"
            default: word = "above your usual"
            }
            parts.append("your overnight recovery came in \(word)")
        }
        guard !parts.isEmpty else { return nil }

        let sentence = ListFormatter.localizedString(byJoining: parts)
        return "The bar starts each morning at whatever the night behind it earned — "
            + "\(sentence), which set today's start at \(whole(output.morningCharge)) out of 100. "
            + "It then drains through the day with whatever you actually do, "
            + "and refills a little through quiet hours. "
            // No Markdown. `Text` renders a String verbatim, and this app's
            // prose habit is doc comments where `**` is house style — the same
            // slip put literal asterisks on the HRV card earlier today.
            + "These are not calories: it is a 0–100 model of a reservoir, "
            + "so the useful comparison is this morning against your other mornings, "
            + "never against a food label."
    }

    /// What the shape is for. Descriptive, never a recommendation.
    public static func soWhat(_ output: EnergyModel.Output) -> String {
        let spent = whole(output.spent)
        let left = whole(Swift.max(0, output.level))
        var text = "So far today you have used \(spent) of that charge and \(left) is left. "
        if let energy = output.activeEnergy, let hours = output.exertionHours, hours > 0 {
            text += "Most of what comes off the bar is effort — \(whole(energy)) kcal of active "
                + "energy and \(oneDecimal(hours)) h above your resting heart rate today. "
        }
        text += "The point of the curve is its shape: two days that end in the same place "
            + "can get there by a steady slope or by one steep drop, and only one of those "
            + "is a day you would want to repeat. Nothing here is a target — it is a "
            + "description of a day you have already had."
        return text
    }

    private static func whole(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
