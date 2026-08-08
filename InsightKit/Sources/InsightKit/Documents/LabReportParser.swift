import Foundation

/// **Reads a pathology report's text into values, with a stated confidence in
/// each one.**
///
/// Pure and dependency-free, so the extraction is unit-tested against realistic
/// report text with no camera, Vision, PDFKit or model dependency — the same
/// split `ScreenTimeScreenshotParser` uses, and for the same reason: the part
/// that can be wrong in a way nobody notices is the part that must be testable
/// on Linux.
///
/// ## What changed on 2026-08-07 (backlog `Q7`, `I6`)
///
/// It used to know two analytes — total and HDL cholesterol — because those are
/// the two the cardiovascular models want as grounding facts. Everything else on
/// the page was discarded at the parser. It now reads **any** analyte the report
/// prints: catalogued ones are converted to a canonical unit and range-checked,
/// and uncatalogued ones are kept under the laboratory's own label with the
/// value exactly as printed.
///
/// The two-analyte entry point (`extract(from:)`) is still here and still
/// returns the same type, because the grounding path calls it and a cholesterol
/// reaching SCORE2 deserves the narrowest, oldest, most-tested route.
///
/// ## The misread guard
///
/// ⚠️ **A misread lab value is worse than no lab value.** So every extracted
/// number carries the checks that were run on it (`LabValueCheck`), and a
/// pathology report is unusually good at supporting them: **it prints its own
/// reference interval beside almost every value**, in the same unit, from the
/// same laboratory. That interval is an independent second statement about the
/// magnitude the number should have.
///
/// This is the screen-time parser's trick — cross-check a total against a figure
/// the image already prints — with the same extension that one later got:
/// **select, don't merely reject.** Where a line offers several numbers, the
/// printed interval picks between them (`LabValueCheck.selectedByPrintedRange`)
/// rather than only vetoing a wrong one.
public enum LabReportParser {

    // MARK: - The grounding path (unchanged surface)

    /// One recognised grounding value, in the app's canonical unit.
    ///
    /// Kept as it was: `ImportLabView` and the grounding save path both read it,
    /// and narrowing what feeds SCORE2 to lipids-only is deliberate.
    public struct Extracted: Sendable, Equatable {
        public let kind: GroundingKind
        public let value: Double            // canonical unit (mmol/L for lipids)
        public let displayUnit: String
        public let matchedText: String
        /// How much to believe the reading. Added 2026-08-07: this value can end
        /// up in a ten-year cardiovascular risk estimate, and until now nothing
        /// distinguished a crisp scan from a blurred photo of a crease.
        public let confidence: LabConfidence

        public init(kind: GroundingKind, value: Double, displayUnit: String,
                    matchedText: String, confidence: LabConfidence = .unverified) {
            self.kind = kind
            self.value = value
            self.displayUnit = displayUnit
            self.matchedText = matchedText
            self.confidence = confidence
        }
    }

    /// The grounding facts a report yields — lipids only, first occurrence wins.
    ///
    /// ⚠️ **Doubtful readings are dropped here and only here.** Everywhere else
    /// in this file a doubtful value is *kept and flagged*, because the reader
    /// can look at it beside their paperwork and decide. A grounding fact is
    /// different: it is consumed by a risk model that will not ask, so the bar
    /// to become one is higher than the bar to be shown.
    public static func extract(from text: String) -> [Extracted] {
        let scan = parseReport(text)
        var seen = Set<GroundingKind>()
        var out: [Extracted] = []
        for result in scan.results {
            guard let kind = result.analyte.groundingKind else { continue }
            guard result.confidence != .doubtful else { continue }
            // ⚠️ **A measured number, or nothing.** `measuredNumber` is nil for a
            // censored bound, a word and a not-measured result. A `>90` eGFR
            // entering a risk model as 90 would turn the assay's ceiling into a
            // reading, and nothing downstream could tell afterwards — the failure
            // `LabValue` was introduced to make unrepresentable.
            guard let measured = result.value.measuredNumber else { continue }
            guard seen.insert(kind).inserted else { continue }
            out.append(Extracted(kind: kind, value: measured,
                                 displayUnit: result.unit,
                                 matchedText: result.evidence?.rawLabel
                                    ?? result.analyte.displayName,
                                 confidence: result.confidence))
        }
        return out
    }

    // MARK: - The general path

    /// Everything one report's text yielded.
    public struct Scan: Sendable, Equatable {
        public let results: [LabResult]
        /// The collection date printed on the report, where one was found.
        public let collectedAt: Date?
        /// Lines that carry words but that the parser could not pair with a
        /// value — the raw material `I6`'s on-device model is given, and the
        /// honest measure of what the rule-based parser is missing.
        public let unpairedLines: [String]
        /// The recognised text, kept so a model proposal can be checked against
        /// it. Never leaves the device; see `LabModelVerifier`.
        public let sourceText: String

        public init(results: [LabResult], collectedAt: Date?,
                    unpairedLines: [String], sourceText: String) {
            self.results = results
            self.collectedAt = collectedAt
            self.unpairedLines = unpairedLines
            self.sourceText = sourceText
        }

        /// Results whose analyte the catalogue did not recognise — the ones a
        /// model could usefully *rename* into a known analyte so they join an
        /// existing trend instead of starting a new one.
        public var unrecognisedResults: [LabResult] {
            results.filter { !$0.analyte.isKnown }
        }
    }

    /// Read a whole report.
    ///
    /// - Parameters:
    ///   - text: recognised text, one line per recognised line.
    ///   - source: how the document arrived, recorded on every result.
    ///   - importedAt: the fallback collection date, used only when the report
    ///     prints none. Never defaulted to `Date()` inside the parser — the
    ///     screen-time reader was filed into the wrong week for exactly that
    ///     reason, and a lab result imported months later would date itself to
    ///     the import.
    public static func parseReport(_ text: String,
                                   source: LabResultSource = .photo,
                                   importedAt: Date = Date()) -> Scan {
        let printedDate = collectionDate(in: text)
        let collectedAt = printedDate ?? importedAt
        var results: [LabResult] = []
        var unpaired: [String] = []
        var seenKeys = Set<String>()

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard !isNoiseLine(line) else { continue }

            guard let row = parseLine(line) else {
                if line.contains(where: \.isLetter) { unpaired.append(line) }
                continue
            }

            // First occurrence per analyte wins, in page order. A report that
            // states a value twice states it identically — the summary line and
            // the table row — so this only ever decides which of two equal
            // numbers is kept, and page order is the one a reader can predict.
            guard seenKeys.insert(row.analyte.key).inserted else { continue }

            results.append(LabResult(analyte: row.analyte,
                                     value: row.value,
                                     unit: row.unit,
                                     referenceRange: row.range,
                                     collectedAt: collectedAt,
                                     collectedAtIsExact: printedDate != nil,
                                     source: source,
                                     evidence: row.evidence,
                                     isConfirmedByReader: false))
        }

        return Scan(results: results, collectedAt: printedDate,
                    unpairedLines: unpaired, sourceText: text)
    }

    // MARK: - One line

    struct Row {
        let analyte: LabAnalyte
        let value: Double
        let unit: String
        let range: LabReferenceRange?
        let evidence: LabExtractionEvidence
    }

    /// Lines that are furniture, not data. Cheap to skip and expensive not to:
    /// a column header reading "Result 0.0 - 5.0 mmol/L" parses beautifully into
    /// a value nobody measured.
    static func isNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        // A header row: names the columns and carries no analyte.
        let headerWords = ["reference range", "ref range", "ref. range",
                           "result units", "test result", "analyte result",
                           "units range", "page ", "printed on", "report date",
                           "authorised by", "authorized by", "reported by",
                           "specimen type", "laboratory no", "lab no",
                           "nhs no", "patient name", "date of birth", "d.o.b"]
        if headerWords.contains(where: { lower.contains($0) }) { return true }
        // No letters at all: a stray number, a page rule, an artefact.
        if !line.contains(where: \.isLetter) { return true }
        return false
    }

    static func parseLine(_ line: String) -> Row? {
        var checks: [LabValueCheck] = []

        // 1. The printed reference interval, taken out of play first so its own
        //    numbers can never be mistaken for the result.
        let rangeFind = printedRange(in: line)
        let withoutRange: String
        if let rangeFind {
            withoutRange = line.replacingCharacters(in: rangeFind.range, with: " ")
        } else {
            withoutRange = line
        }

        // 2. Every remaining number is a candidate value — except digits that
        //    are *inside a word*. "HbA1c", "Vitamin B12" and "1.73m2" all carry
        //    a digit that belongs to the analyte's name; reading the `1` out of
        //    HbA1c as the result was the first thing this parser did when it
        //    stopped being a two-analyte special case.
        let candidates = numberTokens(in: withoutRange).filter { token in
            guard token.range.lowerBound > withoutRange.startIndex else { return true }
            let preceding = withoutRange[withoutRange.index(before: token.range.lowerBound)]
            return !preceding.isLetter
        }
        guard !candidates.isEmpty else { return nil }

        // 3. Choose between the candidates. **Select, don't merely reject** —
        //    the extension the screen-time reader got, and the reason a leading
        //    specimen-number column does not become the result.
        //
        //    Three independent signals, each worth the same: words before it,
        //    a unit after it, and agreement with the printed interval. A tie
        //    goes to the leftmost, which is where a result column sits.
        func score(_ token: NumberToken) -> Int {
            var score = 0
            let before = String(withoutRange[withoutRange.startIndex..<token.range.lowerBound])
            if before.filter(\.isLetter).count >= 2 { score += 2 }
            if let unit = unitToken(after: token.range, in: withoutRange),
               isUnitLike(unit) { score += 2 }
            if let printed = rangeFind?.parsed, printed.contains(token.value) { score += 2 }
            return score
        }
        let scored = candidates.map { (token: $0, score: score($0)) }
        let best = scored.max { lhs, rhs in
            lhs.score == rhs.score
                ? lhs.token.range.lowerBound > rhs.token.range.lowerBound
                : lhs.score < rhs.score
        }
        guard let chosen = best?.token else { return nil }

        // 4. The label is whatever precedes the chosen candidate. An empty label
        //    means a bare number — a continuation line or an artefact.
        let rawLabel = String(withoutRange[withoutRange.startIndex..<chosen.range.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t0123456789.:|"))
        guard rawLabel.contains(where: \.isLetter) else { return nil }
        // A label made only of a flag or an ordinal is not an analyte name.
        guard rawLabel.filter(\.isLetter).count >= 2 else { return nil }

        let entry = LabAnalyteCatalog.match(label: rawLabel)

        // Record the selection only where the printed interval was what decided
        // it — that is the check the reader is being shown, and claiming it for
        // a choice the interval did not make would be a false reassurance.
        if let printed = rangeFind?.parsed, let leftmost = candidates.first,
           leftmost.range != chosen.range,
           printed.contains(chosen.value), !printed.contains(leftmost.value) {
            let rejected = candidates.filter { $0.range != chosen.range }.map(\.value)
            checks.append(.selectedByPrintedRange(chosen: chosen.value, rejected: rejected))
        }

        // 5. The unit sits after the chosen number, past any high/low flag.
        let printedUnit = unitToken(after: chosen.range, in: withoutRange)

        // 6. Convert, or keep verbatim, and say which.
        var value = chosen.value
        var unit = printedUnit ?? ""
        var analyte: LabAnalyte

        if let entry {
            analyte = entry.analyte
            if let printedUnit, !printedUnit.isEmpty {
                if let converted = LabAnalyteCatalog.convert(value, from: printedUnit, for: entry) {
                    value = converted
                    unit = entry.canonicalUnit
                    checks.append(.unitRecognised(printedUnit))
                } else {
                    // ⚠️ Never convert on a guess. A wrong factor is invisible
                    // afterwards — the number looks perfectly reasonable.
                    unit = printedUnit
                    checks.append(.unitUnrecognised(printedUnit))
                }
            } else if let inferred = inferUnit(for: entry, value: value,
                                               range: rangeFind?.parsed) {
                value = inferred.value
                unit = entry.canonicalUnit
                checks.append(.unitInferredFromRange(inferred.assumedUnit))
            } else {
                unit = entry.canonicalUnit
                checks.append(.unitMissing)
            }
            checks.append(entry.plausible.contains(value)
                          ? .plausibleMagnitude : .implausibleMagnitude)
        } else {
            analyte = LabAnalyte.unknown(label: rawLabel, unit: printedUnit)
            unit = printedUnit ?? ""
            if let printedUnit, !printedUnit.isEmpty {
                checks.append(.unitRecognised(printedUnit))
            } else {
                checks.append(.unitMissing)
            }
            // No catalogue entry means no plausible range, and saying so is the
            // point: the reader is told this value was read but not sized.
            checks.append(.magnitudeUncheckable)
        }

        // 7. The printed interval, against the value that was finally chosen.
        //
        //    ⚠️ The interval is compared in the unit it was *printed* in, which
        //    is the unit the value was printed in too. Comparing a converted
        //    value against an unconverted interval is a misread generator in its
        //    own right, so the comparison uses the pre-conversion number.
        if let printed = rangeFind?.parsed {
            if printed.contains(chosen.value) {
                checks.append(.insidePrintedRange)
            } else if let excursion = printed.excursion(chosen.value),
                      excursion >= grossExcursion {
                checks.append(.grosslyOutsidePrintedRange(excursion: excursion))
            } else {
                checks.append(.outsidePrintedRange(
                    excursion: printed.excursion(chosen.value) ?? 0))
            }
        } else {
            checks.append(.noPrintedRange)
        }

        // 8. Characters OCR is known to confuse, in the value itself.
        if let confusing = ambiguity(in: chosen.text) {
            checks.append(.ambiguousCharacters(confusing))
        }

        // The stored interval is expressed in the same unit as the stored value,
        // so a converted value keeps a converted interval or none at all.
        let storedRange = convertedRange(rangeFind?.parsed,
                                         entry: entry, printedUnit: printedUnit)

        let evidence = LabExtractionEvidence(rawLabel: rawLabel,
                                             rawValueText: chosen.text,
                                             rawLine: line,
                                             method: .deterministic,
                                             checks: checks)
        return Row(analyte: analyte, value: value, unit: unit,
                   range: storedRange, evidence: evidence)
    }

    /// How many interval-widths outside the printed range counts as a misread
    /// rather than a result.
    ///
    /// ⚠️ **Deliberately far out.** A genuinely raised cholesterol or a ferritin
    /// of 12 in a range starting at 30 is *outside* its interval and is a real
    /// result, not a misread — flagging those as errors would be the app
    /// second-guessing a laboratory. Eight interval-widths is roughly where a
    /// mis-placed decimal point lives and real physiology does not.
    public static let grossExcursion: Double = 8

    // MARK: - Number scanning

    struct NumberToken: Equatable {
        let text: String
        let value: Double
        let range: Range<String.Index>
    }

    /// Every number in a string, with the characters it was read from.
    ///
    /// Handles both decimal conventions, and the ambiguity between them:
    /// `1,234` with exactly three following digits is a thousands separator;
    /// `1,23` is a decimal comma. Anything else with a comma is left to
    /// `ambiguity(in:)` to flag.
    static func numberTokens(in s: String) -> [NumberToken] {
        var tokens: [NumberToken] = []
        var index = s.startIndex
        while index < s.endIndex {
            guard s[index].isNumber else {
                index = s.index(after: index)
                continue
            }
            let start = index
            var sawSeparator = false
            while index < s.endIndex {
                let ch = s[index]
                if ch.isNumber { index = s.index(after: index); continue }
                if ch == "." || ch == "," {
                    // Only a separator if a digit follows it.
                    let next = s.index(after: index)
                    if next < s.endIndex, s[next].isNumber, !sawSeparator {
                        sawSeparator = true
                        index = s.index(after: index)
                        continue
                    }
                }
                break
            }
            let text = String(s[start..<index])
            if let value = numericValue(text) {
                tokens.append(NumberToken(text: text, value: value, range: start..<index))
            }
        }
        return tokens
    }

    static func numericValue(_ text: String) -> Double? {
        guard let separatorIndex = text.firstIndex(where: { $0 == "." || $0 == "," }) else {
            return Double(text)
        }
        let fractionDigits = text.distance(from: text.index(after: separatorIndex),
                                           to: text.endIndex)
        if text[separatorIndex] == "," {
            // "1,234" — three digits after a comma is a thousands separator in
            // every convention that uses one.
            if fractionDigits == 3 {
                return Double(text.replacingOccurrences(of: ",", with: ""))
            }
            return Double(text.replacingOccurrences(of: ",", with: "."))
        }
        return Double(text)
    }

    /// Characters in a recognised number that text recognition is known to
    /// confuse, or a separator convention that could go either way.
    static func ambiguity(in raw: String) -> String? {
        // A comma with three following digits genuinely reads two ways — "1,234"
        // is 1234 in Britain and 1.234 in Germany — and a lab value where that
        // matters is a lab value nobody should silently pick a country for.
        if let comma = raw.firstIndex(of: ","),
           raw.distance(from: raw.index(after: comma), to: raw.endIndex) == 3 {
            return raw
        }
        // Letters inside a number token cannot happen — `numberTokens` only
        // accepts digits and separators — so what is left is the reverse case,
        // handled by the label side, and a lone zero-length guard here.
        return nil
    }

    // MARK: - Units

    /// The unit printed after a value.
    ///
    /// Skips a single high/low flag first: reports print `5.2 H mmol/L` and
    /// `5.2 * mmol/L`, and reading `H` as the unit would fail every conversion
    /// and stamp the value `unitUnrecognised`.
    static func unitToken(after valueRange: Range<String.Index>, in s: String) -> String? {
        var rest = String(s[valueRange.upperBound...])
        rest = rest.trimmingCharacters(in: .whitespaces)
        // Strip an abnormal flag: one or two letters, or a symbol, standing alone.
        let flagCandidates = ["hh", "ll", "h", "l", "a", "*", "†", "(h)", "(l)", "!"]
        for flag in flagCandidates {
            if rest.lowercased().hasPrefix(flag) {
                let after = rest.index(rest.startIndex, offsetBy: flag.count)
                let remainder = String(rest[after...])
                if remainder.first?.isWhitespace ?? remainder.isEmpty {
                    rest = remainder.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        guard !rest.isEmpty else { return nil }

        // A unit is the run of characters up to whitespace, but units contain
        // spaces in practice ("10^9 /L", "mL/min/1.73m2"), so take up to the
        // next thing that is clearly not part of one: a bracket, or a digit that
        // starts a new number after a space.
        var unit = ""
        var index = rest.startIndex
        while index < rest.endIndex {
            let ch = rest[index]
            if ch == "(" || ch == "[" || ch == "," { break }
            if ch.isWhitespace {
                // Keep going only if what follows still looks like unit text.
                let next = rest.index(after: index)
                guard next < rest.endIndex else { break }
                let following = rest[next]
                if following == "/" || following == "^" || following == "*" {
                    unit.append(contentsOf: "")
                    index = next
                    continue
                }
                break
            }
            unit.append(ch)
            index = rest.index(after: index)
        }
        let tidy = unit.trimmingCharacters(in: CharacterSet(charactersIn: " .:;"))
        guard !tidy.isEmpty, tidy.contains(where: { $0.isLetter || $0 == "%" }) else {
            return nil
        }
        // A word is not a unit. Real units are short; "Normal", "Negative" and
        // "Sample" are all longer than anything in the catalogue.
        guard tidy.count <= 14 else { return nil }
        return tidy
    }

    /// Every unit string the catalogue knows, plus the shapes a unit takes.
    ///
    /// Used only to *score* a candidate, never to reject a printed unit: an
    /// unrecognised unit is still stored verbatim and flagged
    /// (`LabValueCheck.unitUnrecognised`), because the reader's laboratory is
    /// allowed to use a unit this app has not met. What this decides is which
    /// number on a crowded line is the result.
    static let knownUnits: Set<String> = {
        var units = Set<String>()
        for entry in LabAnalyteCatalog.entries {
            units.insert(LabAnalyteCatalog.normaliseUnit(entry.canonicalUnit))
            for unit in entry.unitFactors.keys {
                units.insert(LabAnalyteCatalog.normaliseUnit(unit))
            }
        }
        units.formUnion(["%", "ratio", "fl", "pg", "g", "mg", "ng", "ug", "nmol",
                         "mmhg", "mm", "kg", "cm", "sec", "s", "bpm"])
        units.remove("")
        return units
    }()

    static func isUnitLike(_ unit: String) -> Bool {
        let key = LabAnalyteCatalog.normaliseUnit(unit)
        if knownUnits.contains(key) { return true }
        // A slash between two short tokens is what almost every unit not in the
        // catalogue still looks like: "mg/24h", "cells/uL".
        return key.contains("/") && key.count <= 14 && !key.contains(where: \.isWhitespace)
    }

    /// Work out which unit an unlabelled value must have been printed in, using
    /// the printed reference interval.
    ///
    /// **This is the select-don't-reject idea applied to units.** A cholesterol
    /// printed as `194` beside a range of `0 - 200` is obviously mg/dL, and a
    /// `5.0` beside `0 - 5.2` is obviously mmol/L, even though neither line says
    /// so. The interval decides, and the check records that it was an inference.
    ///
    /// Returns nil rather than guessing when no interval exists or when more
    /// than one unit fits — an ambiguous inference is not an inference.
    static func inferUnit(for entry: LabAnalyteCatalog.Entry, value: Double,
                          range: LabReferenceRange?) -> (value: Double, assumedUnit: String)? {
        guard let range, range.low != nil || range.high != nil else { return nil }
        var fits: [(Double, String)] = []
        for unit in entry.unitFactors.keys.sorted() {
            guard let converted = LabAnalyteCatalog.convert(value, from: unit, for: entry) else {
                continue
            }
            guard entry.plausible.contains(converted) else { continue }
            // The interval is printed in the same unit as the value, so the raw
            // value must sit in the raw interval whichever unit that is; what
            // the unit decides is the *converted* number. So the discriminator
            // is whether the converted interval is itself plausible.
            // A zero lower bound carries no information — half the reference
            // intervals a laboratory prints start at 0 ("0.0 - 5.0") and zero
            // is below every plausible range in the catalogue by construction.
            // Requiring it to convert into the plausible range would refuse
            // every inference on exactly the commonest layout.
            let lowOK = range.low.map { low -> Bool in
                if low == 0 { return true }
                guard let c = LabAnalyteCatalog.convert(low, from: unit, for: entry) else {
                    return false
                }
                return entry.plausible.contains(c)
            } ?? true
            let highOK = range.high.map { high -> Bool in
                guard let c = LabAnalyteCatalog.convert(high, from: unit, for: entry) else {
                    return false
                }
                return entry.plausible.contains(c)
            } ?? true
            if lowOK && highOK { fits.append((converted, unit)) }
        }
        guard fits.count == 1 else { return nil }
        return (fits[0].0, fits[0].1)
    }

    /// The printed interval expressed in the unit the value is stored in.
    static func convertedRange(_ range: LabReferenceRange?,
                               entry: LabAnalyteCatalog.Entry?,
                               printedUnit: String?) -> LabReferenceRange? {
        guard let range else { return nil }
        guard let entry, let printedUnit, !printedUnit.isEmpty else { return range }
        guard let low = range.low.map({ LabAnalyteCatalog.convert($0, from: printedUnit, for: entry) }) ?? .some(nil),
              let high = range.high.map({ LabAnalyteCatalog.convert($0, from: printedUnit, for: entry) }) ?? .some(nil)
        else { return range }
        // If either end failed to convert, keep the printed interval verbatim
        // rather than storing a half-converted one.
        if (range.low != nil && low == nil) || (range.high != nil && high == nil) {
            return range
        }
        return LabReferenceRange(low: low, high: high, printed: range.printed)
    }

    // MARK: - The printed reference interval

    struct RangeFind {
        let range: Range<String.Index>
        let parsed: LabReferenceRange
    }

    /// The reference interval a line printed, if any.
    ///
    /// Takes the **last** match on the line: reports print the result first and
    /// the interval to its right, and a leading match is almost always a value
    /// that happens to contain a hyphen.
    static func printedRange(in line: String) -> RangeFind? {
        let patterns = [
            #"[0-9]+(?:[.,][0-9]+)?\s*(?:-|–|—|to)\s*[0-9]+(?:[.,][0-9]+)?"#,
            #"[<>≤≥]\s*[0-9]+(?:[.,][0-9]+)?"#
        ]
        var best: Range<String.Index>?
        for pattern in patterns {
            var searchStart = line.startIndex
            while searchStart < line.endIndex,
                  let found = line.range(of: pattern, options: .regularExpression,
                                         range: searchStart..<line.endIndex) {
                if best == nil || found.lowerBound > best!.lowerBound { best = found }
                searchStart = found.upperBound
            }
        }
        guard let matched = best else { return nil }
        let printed = String(line[matched]).trimmingCharacters(in: .whitespaces)
        guard let parsed = parseRangeText(printed) else { return nil }
        return RangeFind(range: matched, parsed: parsed)
    }

    static func parseRangeText(_ text: String) -> LabReferenceRange? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<") || trimmed.hasPrefix("≤") {
            guard let value = numberTokens(in: trimmed).first?.value else { return nil }
            return LabReferenceRange(low: nil, high: value, printed: trimmed)
        }
        if trimmed.hasPrefix(">") || trimmed.hasPrefix("≥") {
            guard let value = numberTokens(in: trimmed).first?.value else { return nil }
            return LabReferenceRange(low: value, high: nil, printed: trimmed)
        }
        let numbers = numberTokens(in: trimmed)
        guard numbers.count >= 2 else { return nil }
        let low = numbers[0].value
        let high = numbers[1].value
        guard high >= low else { return nil }
        return LabReferenceRange(low: low, high: high, printed: trimmed)
    }

    // MARK: - The collection date

    /// The date the sample was taken, as printed.
    ///
    /// ⚠️ **Collection, not report date, and the distinction is not pedantry.**
    /// A report is often authorised days after the blood was drawn; filing the
    /// value under the report date puts it in the wrong week against every
    /// vital it might later be compared with. Where the document prints only a
    /// report date this returns nil, and the caller falls back on the import
    /// date with `collectedAtIsExact` false, so the imprecision is visible
    /// rather than hidden behind a confident-looking date.
    static func collectionDate(in text: String) -> Date? {
        let markers = ["collected", "collection date", "specimen date",
                       "sample taken", "date collected", "taken on",
                       "specimen collected"]
        let lower = text.lowercased()
        for marker in markers {
            guard let markerRange = lower.range(of: marker) else { continue }
            let windowEnd = lower.index(markerRange.upperBound, offsetBy: 40,
                                        limitedBy: lower.endIndex) ?? lower.endIndex
            let window = String(text[markerRange.upperBound..<windowEnd])
            if let date = firstDate(in: window) { return date }
        }
        return nil
    }

    static func firstDate(in s: String) -> Date? {
        let patterns: [(String, String)] = [
            (#"[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}"#, "dd/MM/yyyy"),
            (#"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, "yyyy-MM-dd"),
            (#"[0-9]{1,2}\s+[A-Za-z]{3,9}\s+[0-9]{4}"#, "d MMMM yyyy")
        ]
        for (pattern, format) in patterns {
            guard let found = s.range(of: pattern, options: .regularExpression) else { continue }
            let raw = String(s[found])
                .replacingOccurrences(of: ".", with: "/")
                .replacingOccurrences(of: "-", with: format == "yyyy-MM-dd" ? "-" : "/")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
            if format == "d MMMM yyyy" {
                formatter.dateFormat = "d MMM yyyy"
                if let date = formatter.date(from: raw) { return date }
            }
        }
        return nil
    }
}
