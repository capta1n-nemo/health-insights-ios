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
    /// Withings sends numbered measure types, and the number reaches the screen.
    ///
    /// The reader, 2026-08-05: *"go and research all those Withings scores, make
    /// sense of the more obscure ones and what they are."* `withings.measure.170`
    /// tells nobody anything.
    ///
    /// ⚠️ **Each of these was checked against the reader's own values before
    /// being named**, because a mapping table copied from documentation is a
    /// guess until something confirms it:
    ///
    /// | Code | Their values | Name it fits |
    /// | --- | --- | --- |
    /// | 8 | 33.9–41.8 | fat mass in kg |
    /// | 170 | 4.5–5.5, unitless | visceral fat index |
    /// | 226 | 2318–2583 | basal metabolic rate in kcal/day |
    /// | 227 | 28–31 | metabolic age in years |
    ///
    /// Four more are **not measurements at all** — `attrib` (0 or 2: measured by
    /// the device, or typed in), `category` (always 1: a real measure rather
    /// than a goal), `model` ("Body Smart") and `modelid` (always 16). They are
    /// how the reading was taken, not what it says, and two of them are constant
    /// across every row the reader has. `isRecordingDetail` marks them so the
    /// Data tab can stop listing a constant as a data point.
    static let withingsMeasureNames: [String: String] = [
        "8": "Fat mass",
        "170": "Visceral fat index",
        "226": "Basal metabolic rate",
        "227": "Metabolic age",
    ]

    /// Recording details, and **the name each one should carry**.
    ///
    /// ⚠️ Naming them is half the point and was missed the first time: seen on
    /// screen, the row read "Attrib — how it was recorded — 0", which tells a
    /// reader nothing except that the app has a field it cannot explain. A
    /// field worth listing is a field worth naming.
    static let recordingDetailNames: [String: String] = [
        "attrib": "How it was measured",
        "category": "Measurement category",
        "model": "Device model",
        "modelid": "Device model ID",
        "deviceid": "Device ID",
        "hash_deviceid": "Device ID",
        "sleep_algorithm_version": "Sleep algorithm version",
        "sleep_analysis_reason": "Why sleep was analysed",
        "type": "Record type",
        "period": "Period number",
    ]

    static var recordingDetailLeaves: Set<String> { Set(recordingDetailNames.keys) }

    /// Whether a field describes **how** a reading was recorded rather than what
    /// was read. Not hidden — this tab is the app's answer to "what do you know
    /// about me", and a field it ingested belongs in that answer — but it should
    /// not sit among measurements pretending to be one.
    public static func isRecordingDetail(_ identifier: String) -> Bool {
        guard let leaf = identifier.split(separator: ".").last else { return false }
        return recordingDetailLeaves.contains(String(leaf).lowercased())
    }

    /// What an integer-coded recording detail's value **means** — or nil, in
    /// which case the row prints nothing at all.
    ///
    /// ⚠️ Naming these fields was only half the fix, and the half that shipped:
    /// on screen the rows still read **"How it was measured — 0", "Device model
    /// ID — 16", "Measurement categ… — 1"** — metadata dressed as readings,
    /// each with a trend chevron. A code either decodes to words a reader can
    /// use, or it does not print; there is no honest way to show "16" as a
    /// measurement. Decodings observed against the reader's own record (attrib
    /// is 0 or 2, category is always 1 — see `recordingDetailNames`); an
    /// unobserved code returns nil rather than a guess, the same rule
    /// `unit(_:)` follows.
    static let recordingDetailCodeWords: [String: [Int: String]] = [
        "attrib": [0: "Measured by the device", 2: "Entered by hand"],
        "category": [1: "A measurement"],
    ]

    public static func recordingDetailValueText(_ identifier: String, value: Double) -> String? {
        guard let leaf = identifier.split(separator: ".").last,
              let words = recordingDetailCodeWords[String(leaf).lowercased()],
              let code = Int(exactly: value)
        else { return nil }
        return words[code]
    }

    // MARK: - Oura stress & resilience (backlog N1's raw material)

    /// Names for the Oura stress and resilience fields, keyed by full path.
    ///
    /// Leaf-led titling makes half-names of these: "Stress high" is not a name,
    /// and "Day summary" under a section that never says *stress* names the
    /// wrong thing. The two durations use Oura's own vocabulary — its app calls
    /// them time "stressed" and "restored" — because these are its numbers,
    /// relayed rather than re-derived.
    static let ouraStressNames: [String: String] = [
        "oura.daily_stress.day_summary": "Day summary",
        "oura.daily_stress.stress_high": "Time stressed",
        "oura.daily_stress.recovery_high": "Time restored",
        "oura.daily_resilience.level": "Resilience level",
    ]

    /// Fields whose value is a number of **seconds** of the day spent in a
    /// state. A raw figure in the thousands rendered verbatim — hours of the
    /// day dressed as a count, in a list where every neighbouring number is a
    /// reading a person can use.
    static let secondsOfDayIdentifiers: Set<String> = [
        "oura.daily_stress.stress_high",
        "oura.daily_stress.recovery_high",
    ]

    /// Fields whose value is a categorical state word — Oura sends
    /// `"normal"` / `"stressful"` / `"restored"` for the day summary and
    /// `"limited"` through `"exceptional"` for resilience — which should read
    /// as a word, not as a wire token.
    static let stateWordIdentifiers: Set<String> = [
        "oura.daily_stress.day_summary",
        "oura.daily_resilience.level",
    ]

    /// Seconds → "2h 45m", the form every other duration in this app reads in
    /// (see `MetricValueFormatter`'s deep/REM minutes). Whole minutes: the
    /// source resolution is a five-minute stress period, so seconds are noise.
    public static func hoursAndMinutes(seconds: Double) -> String {
        let total = Int((seconds / 60).rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }

    public static func title(forPath path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        guard let leaf = parts.last else { return path }
        // Before anything else: a Withings measure number is not a name, and
        // widening it to "Measure 170" would not help either.
        if path.hasPrefix("withings.measure."), let named = withingsMeasureNames[leaf] {
            return named
        }
        if let named = ouraStressNames[path] { return named }
        if let named = recordingDetailNames[leaf.lowercased()] { return named }
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
            // A named Withings measure is already unique and already a name;
            // widening it would produce "Measure visceral fat index".
            if path.hasPrefix("withings.measure."), let named = withingsMeasureNames[leaf] {
                return named
            }
            // A named stress field is likewise already a name — same rule.
            if let named = ouraStressNames[path] { return named }
            if let named = recordingDetailNames[leaf.lowercased()] { return named }
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

    // MARK: - The row's trailing text, decided in one place

    /// The one string a catalogue row prints beside a numeric field's name — or
    /// nil where printing anything would dress metadata as a measurement.
    ///
    /// The view used to take part of this decision inline, which is how a named
    /// recording detail still rendered its wire code: recognition lived here,
    /// value rendering lived there, and the two halves never met. Every rule
    /// about what a number is allowed to claim now sits behind this one call,
    /// where it is tested: a recording detail decodes to words or stays silent,
    /// the two Oura stress durations render as time, and everything else keeps
    /// the unit-and-precision rules of `formatted`.
    public static func rowValue(_ value: Double, unit: String, identifier: String) -> String? {
        if isRecordingDetail(identifier) {
            return recordingDetailValueText(identifier, value: value)
        }
        if secondsOfDayIdentifiers.contains(identifier) {
            return hoursAndMinutes(seconds: value)
        }
        return formatted(value, unit: unit)
    }

    /// The same decision for a text value: a coded series summarises to its
    /// length, a known state word reads as a word ("solid" → "Solid"), and
    /// anything else passes through verbatim — an unfamiliar string shown as
    /// sent is honest, and a transformed one is a guess.
    public static func rowText(_ text: String, identifier: String) -> String {
        if isCodedSeries(text) { return codedSeriesSummary(text) }
        if stateWordIdentifiers.contains(identifier) { return humanised(text) }
        return text
    }
}
