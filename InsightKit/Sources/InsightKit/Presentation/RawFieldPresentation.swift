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
    /// ⚠️ **A leaf is only a name when it is a distinctive one**, and on the
    /// reader's own record two kinds are not. Both were visible on screen the
    /// first time this rendered:
    ///
    /// - **Generic aggregators.** `oura.daily_spo2.spo2_percentage.average`
    ///   became "Average", which names nothing at all.
    /// - **Collisions.** "Activity balance" appeared twice and "Body
    ///   temperature" twice, with different values — the same leaf under
    ///   `daily_readiness` and `daily_sleep`, indistinguishable on the row.
    ///
    /// Both are fixed by borrowing the parent, and both are fixed *only* where
    /// they occur — see `titles(for:)`, which is what a list should call.
    public static func title(forPath path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        guard let leaf = parts.last else { return path }
        guard genericLeaves.contains(leaf.lowercased()), parts.count >= 2 else {
            return humanised(leaf)
        }
        return "\(humanised(parts[parts.count - 2])) \(humanised(leaf).lowercased())"
    }

    /// Leaves that describe *how a number was reduced* rather than what it
    /// measures. Alone, each names nothing.
    static let genericLeaves: Set<String> = [
        "average", "avg", "mean", "median", "total", "sum", "min", "max",
        "minimum", "maximum", "value", "count", "score", "percentage", "percent",
        "index", "level", "amount", "duration", "start", "end",
    ]

    /// Path components that describe a payload's **shape** rather than its
    /// subject. Borrowing one adds a word and no information.
    ///
    /// Found on screen: two rows read "Contributors efficiency" and
    /// "Contributors latency" — the collision widening had reached for the
    /// nearest parent and the nearest parent was Oura's container name. Skipping
    /// them means the widening reaches past to `daily_sleep`, which is the thing
    /// a reader was actually trying to tell apart.
    static let structuralTokens: Set<String> = [
        "contributors", "contributor", "data", "values", "items", "detail",
        "details", "summary", "attributes", "properties", "fields",
    ]

    /// Titles for a whole list, with collisions resolved.
    ///
    /// **A name only has to be unique among the names beside it**, which is why
    /// this takes the list rather than being a property of one identifier. Where
    /// two paths reduce to the same title, both grow one parent token — and only
    /// those two. The eleven Oura contributors keep their short, legible names
    /// precisely because they do not collide with each other.
    ///
    /// Repeats until unique or the paths run out, so three-way collisions
    /// resolve too rather than being half-fixed.
    public static func titles(for paths: [String]) -> [String: String] {
        var depth = [String: Int]()
        for path in paths { depth[path] = 1 }

        func render(_ path: String, _ levels: Int) -> String {
            var parts = path.split(separator: ".").map(String.init)
            guard let leaf = parts.last else { return path }
            // Structural containers are dropped before anything counts levels,
            // so widening reaches the nearest component that names something.
            // The leaf itself is kept whatever it is — a field genuinely called
            // `data` is still that field.
            parts = parts.dropLast().filter { !structuralTokens.contains($0.lowercased()) } + [leaf]
            // One extra level for a generic leaf, before any collision widening,
            // so "Average" starts life as "SpO₂ percentage average".
            let extra = genericLeaves.contains(leaf.lowercased()) ? 1 : 0
            let take = Swift.min(parts.count, levels + extra)
            let tail = parts.suffix(take)
            guard let first = tail.first else { return path }
            return ([humanised(first)] + tail.dropFirst().map { decapitalised(humanised($0)) })
                .joined(separator: " ")
        }

        // Bounded by the longest path, so this always terminates.
        let deepest = paths.map { $0.split(separator: ".").count }.max() ?? 1
        for _ in 0..<deepest {
            let rendered = Dictionary(grouping: paths) { render($0, depth[$0] ?? 1) }
            let clashing = rendered.filter { $0.value.count > 1 }.flatMap { $0.value }
            if clashing.isEmpty { break }
            for path in clashing { depth[path, default: 1] += 1 }
        }
        return Dictionary(uniqueKeysWithValues: paths.map { ($0, render($0, depth[$0] ?? 1)) })
    }

    /// A raw number, in the fewest digits that do not lose it.
    ///
    /// A fixed two decimals printed "32.00 years" for a vascular age and
    /// "70.00" for a score out of 100 — precision the value does not have,
    /// claimed on every row at once.
    public static func formatted(_ value: Double, unit raw: String) -> String {
        let (converted, unit) = self.converted(value, unit: raw)
        let magnitude = abs(converted)
        let places = magnitude >= 100 ? 0 : (magnitude >= 10 ? 1 : 2)
        var text = String(format: "%.\(places)f", converted)
        // Trim a decimal part that turned out to be nothing: a whole number
        // printed with decimals looks like a measurement it is not.
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return unit.isEmpty ? text : "\(text) \(unit)"
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

    /// Drop a leading capital when a borrowed token moves mid-name — **unless
    /// the word is an acronym**, which sentence case does not apply to.
    ///
    /// It shipped without the exception for one screenshot: "Daily readiness hrv
    /// balance". The test is an uppercase letter *after* the first character,
    /// which is exactly what `humanised` leaves behind when it substitutes one
    /// — "HRV", "SpO₂", "VO₂ max" — and which no ordinary word has.
    static func decapitalised(_ text: String) -> String {
        guard let firstWord = text.split(separator: " ").first,
              !firstWord.dropFirst().contains(where: \.isUppercase),
              let first = text.first
        else { return text }
        return first.lowercased() + text.dropFirst()
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
    ///
    /// ⚠️ **"values", not "steps".** It said steps, and on screen that row sat
    /// among genuine step counts reading "185 steps" — a length dressed as a
    /// measurement, in the units of the metric directly above it.
    public static func codedSeriesSummary(_ text: String) -> String {
        "\(text.count) values"
    }
}
