import Foundation

/// How a raw, unmodelled field is shown to a person rather than to a debugger.
///
/// The Data tab's "Other data" section is the app's promise that nothing it
/// receives is silently dropped, and on the reader's own record it renders 158
/// identifiers like this:
///
///     Basal Body Temperature      35.89 degC
///     Basal Energy Burned         144.9 kJ
///     Body Mass Index             32.26 count
///     Daily activity · Cla…       3311111111111…
///
/// Every line there is a different failure: a machine unit string, an energy
/// unit nobody uses, **"count" presented as a unit for BMI**, and a sleep-stage
/// string rendered as though it were a number.
///
/// The promise is worth keeping; the presentation was not. This is the pure,
/// testable half — the view asks it for a title, a unit and whether the value is
/// worth printing at all.
public enum RawFieldPresentation {

    // MARK: - Units

    /// A unit fit to sit beside a number, or empty where the value carries its
    /// own meaning.
    ///
    /// The mapping is small and deliberate: only units the reader's own record
    /// actually contains, so nothing here is speculative. Anything unrecognised
    /// passes through unchanged rather than being guessed at — an unfamiliar
    /// unit shown verbatim is honest, and a wrong one is not.
    public static func unit(_ raw: String) -> String {
        switch raw {
        // **"count" is not a unit.** HealthKit uses it for anything
        // dimensionless — BMI, a step tally, a flag — and printed it reads as a
        // quantity of something. 32.26 count is the clearest nonsense on the
        // screen.
        case "count", "count/min": return raw == "count/min" ? "/min" : ""
        case "degC": return "°C"
        case "degF": return "°F"
        case "dBASPL": return "dB"
        case "kcal/hr·kg": return "kcal/hr·kg"   // MET-ish; correct as written
        case "km/hr": return "km/h"
        case "mL/kg·min": return "mL/kg·min"
        default: return raw
        }
    }

    /// Whether a value should be converted before display, and to what.
    ///
    /// Only kilojoules today. Apple reports basal energy in kJ; every other
    /// energy figure in this app — dietary energy, active energy, the whole
    /// metabolism card — is kilocalories, and two energy units on one tab is a
    /// reader doing arithmetic to compare their own data.
    public static func converted(_ value: Double, unit raw: String) -> (value: Double, unit: String) {
        switch raw {
        case "kJ": return (value / 4.184, "kcal")
        default: return (value, unit(raw))
        }
    }

    // MARK: - Titles

    /// A field's name, from its identifier path.
    ///
    /// **The last component carries the meaning and it was the part being cut.**
    /// `oura.daily_activity.contributors.meeting_daily_targets` rendered as
    /// "Daily activity · Contributors: Mee…" — every visible character shared
    /// with ten sibling rows, and the one distinguishing word truncated away.
    /// Leading with the leaf inverts that: "Meeting daily targets" is legible at
    /// any width, and the group it belongs to is the section heading rather than
    /// a prefix repeated on every row.
    public static func title(forPath path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        guard let leaf = parts.last else { return path }
        return humanised(leaf)
    }

    /// `"meeting_daily_targets"` → `"Meeting daily targets"`; `"vo2_max"` →
    /// `"VO₂ max"`. Sentence case, not Title Case: a row of capitalised words
    /// reads as a menu rather than as a name.
    public static func humanised(_ token: String) -> String {
        let spaced = token
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        // Split camelCase without breaking an acronym run.
        var out = ""
        var previous: Character?
        for character in spaced {
            if let previous, previous.isLowercase, character.isUppercase { out.append(" ") }
            out.append(character)
            previous = character
        }
        let lowered = out.lowercased()
        for (needle, replacement) in acronyms where lowered.contains(needle) {
            return sentenceCased(lowered.replacingOccurrences(of: needle, with: replacement))
        }
        return sentenceCased(lowered)
    }

    private static let acronyms: [(String, String)] = [
        ("vo2 max", "VO₂ max"), ("vo2max", "VO₂ max"),
        ("hrv", "HRV"), ("spo2", "SpO₂"), ("bmi", "BMI"), ("uv", "UV"),
    ]

    private static func sentenceCased(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    // MARK: - Values that are not numbers

    /// Whether a value is a coded string that should be summarised rather than
    /// printed.
    ///
    /// Oura's hypnogram is a per-five-minute stage code — `"3311111111111…"` —
    /// and printing it as a value tells the reader nothing and pushes every
    /// other column off the row. A digit run longer than this is never a
    /// reading; it is a series wearing a scalar's clothes.
    public static let codedSeriesLength = 12

    public static func isCodedSeries(_ text: String) -> Bool {
        text.count >= codedSeriesLength && text.allSatisfy(\.isNumber)
    }

    /// What to show instead: how long the series is, which is the only honest
    /// scalar a coded series has.
    public static func codedSeriesSummary(_ text: String) -> String {
        "\(text.count) steps"
    }
}
