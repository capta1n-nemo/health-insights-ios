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
/// ## What changed on 2026-08-09: a real corpus
///
/// Measured against the reader's own Australian reports — Sullivan Nicolaides,
/// My Health Record, InstantScripts/QML — this parser was wrong in five ways
/// that a synthetic fixture cannot show you, and each of them is now a named
/// rule with a named test:
///
/// 1. **Five dates on a page and only one of them is the collection date.** See
///    `collectionMarkers`. Two of the three laboratories print a *later*
///    contradicting date in a wrapper or a header, above the document that knows
///    better.
/// 2. **Two results in five are not numbers.** A word (`Negative`), a bound
///    (`<5`), or a stated failure (`N/A  SpecimenUnsuitable`). See `parseLine`,
///    which now recognises those three shapes **before** it looks for a number —
///    `HSV 1 DNA (NAA)  Not Detected` carries a `1` that the numeric path
///    happily filed as a herpes PCR result of one.
/// 3. **`L` is both a unit and a flag.** See `abnormalFlag(after:in:)`.
/// 4. **A number inside a date is not a result.** See `valueCells(in:)`.
/// 5. **The specimen was being discarded as furniture.** See `specimen(in:)`.
/// 6. **One analyte is printed both ways on the same report.** `HepB surface
///    antibody` reads *Negative* on one line and `<5 IU/L` on another. See
///    `LabReportedForm` and the `.either` arm of `qualitativeRow` — with two
///    shapes to choose from, one of those two lines was always mishandled.
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
        /// What was tested, as the report named it — "Serum", "EDTA whole
        /// blood", "Mid-stream urine".
        ///
        /// ⚠️ **Nil is not "blood".** A potassium from serum and a potassium
        /// from plasma are different numbers, and a urine protein filed as a
        /// serum one is a different test entirely, so nothing here may be
        /// defaulted. See `specimen(in:)` for why this used to be thrown away.
        public let specimen: String?

        public init(results: [LabResult], collectedAt: Date?,
                    unpairedLines: [String], sourceText: String,
                    specimen: String? = nil) {
            self.results = results
            self.collectedAt = collectedAt
            self.unpairedLines = unpairedLines
            self.sourceText = sourceText
            self.specimen = specimen
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
        // ⚠️ Read before the noise filter runs, not after. `isNoiseLine` throws
        // the specimen row away — rightly, since "Specimen Type Serum" parses
        // into nothing — and until this line existed that discarded the only
        // statement on the page of *what was tested*.
        let specimenType = specimen(in: text)
        var results: [LabResult] = []
        var unpaired: [String] = []
        var indexByKey: [String: Int] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard !isNoiseLine(line) else { continue }

            guard let row = parseLine(line) else {
                if line.contains(where: \.isLetter) { unpaired.append(line) }
                continue
            }

            let result = LabResult(analyte: row.analyte,
                                   value: row.value,
                                   unit: row.unit,
                                   referenceRange: row.range,
                                   collectedAt: collectedAt,
                                   collectedAtIsExact: printedDate != nil,
                                   source: source,
                                   evidence: row.evidence,
                                   isConfirmedByReader: false)

            // First occurrence per analyte wins, in page order. A report that
            // states a value twice states it identically — the summary line and
            // the table row — so this only ever decides which of two equal
            // numbers is kept, and page order is the one a reader can predict.
            if let existing = indexByKey[row.analyte.key] {
                if supersedes(stored: results[existing], row: row) {
                    results[existing] = result
                }
                continue
            }
            indexByKey[row.analyte.key] = results.count
            results.append(result)
        }

        return Scan(results: results, collectedAt: printedDate,
                    unpairedLines: unpaired, sourceText: text,
                    specimen: specimenType)
    }

    /// Whether a later line replaces one already stored for the same analyte.
    ///
    /// ⚠️ **The one exception to first-occurrence-wins, and the corpus forced
    /// it.** That rule rests on a premise — a report states the same value twice
    /// identically — which `LabReportedForm.either` broke: the reader's report
    /// prints `HepB surface antibody Negative` and, further down,
    /// `HepB surface antibody <5 IU/L`. Those two lines do not say the same
    /// thing, and page order would keep the word and discard the titre — which is
    /// the half that answers the question the test was ordered for.
    ///
    /// So a measurement replaces a word already stored for a dual-form analyte.
    /// **Never the reverse, and never for anything else**: a word replacing a
    /// number is the misread `qualitativeRow` refuses within a single line, and
    /// this is that same ordering applied across two of them. For every analyte
    /// that is not `.either`, the two shapes cannot both be right, and the first
    /// occurrence still wins untouched.
    static func supersedes(stored: LabResult, row: Row) -> Bool {
        guard LabAnalyteCatalog.entry(forKey: row.analyte.key)?.form == .either,
              stored.value.shape == .qualitative else { return false }
        return row.value.shape == .quantitative || row.value.shape == .censored
    }

    // MARK: - One line

    struct Row {
        let analyte: LabAnalyte
        /// ⚠️ Was a `Double` until 2026-08-09. See `LabValue`: a censored bound
        /// that arrives here as a number is a ceiling filed as a reading, and
        /// nothing downstream can tell afterwards.
        let value: LabValue
        let unit: String
        let range: LabReferenceRange?
        let evidence: LabExtractionEvidence
    }

    /// Lines that are furniture, not data. Cheap to skip and expensive not to:
    /// a column header reading "Result 0.0 - 5.0 mmol/L" parses beautifully into
    /// a value nobody measured.
    ///
    /// ⚠️ **"specimen type" is here and "specimen" is not**, and the difference
    /// is a whole class of result: `Iron  N/A  SpecimenUnsuitable` is a
    /// laboratory saying a test failed, which is a fact about the reader's record
    /// worth keeping. Widening this to the bare word would silently delete every
    /// one of them.
    static func isNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        // A header row: names the columns and carries no analyte.
        let headerWords = ["reference range", "ref range", "ref. range",
                           "result units", "test result", "analyte result",
                           "units range", "page ", "printed on", "report date",
                           "authorised by", "authorized by", "reported by",
                           "specimen type", "specimen:", "sample type",
                           "laboratory no", "lab no",
                           "nhs no", "patient name", "date of birth", "d.o.b"]
        if headerWords.contains(where: { lower.contains($0) }) { return true }
        // No letters at all: a stray number, a page rule, an artefact.
        if !line.contains(where: \.isLetter) { return true }
        return false
    }

    /// Read one line, in the order the failures demand.
    ///
    /// ⚠️ **Everything that is not a measurement is recognised first, and that
    /// ordering is the fix for a live misread.** `HSV 1 DNA (NAA)  Not Detected`
    /// carries a `1` that is not inside a word, so the numeric path scored it as
    /// the result and filed a herpes PCR as *HSV = 1*; `Syphilis (CMIA) Screen`
    /// prints a signal-to-cutoff index beside its word on some layouts, and that
    /// index is not the finding either. The numeric path therefore only ever sees
    /// lines that no other shape claimed.
    static func parseLine(_ line: String) -> Row? {
        if let row = notMeasuredRow(line) { return row }
        if let row = qualitativeRow(line) { return row }
        return numericRow(line)
    }

    // MARK: - Shape one: the laboratory produced no value

    /// What a report prints in the value column when there is no value.
    ///
    /// ⚠️ **`N/A` keeps its slash on purpose.** A bare "NA" is sodium, and
    /// "(NAA)" is the nucleic-acid method printed beside half the serology in
    /// this corpus — matching either would turn a real result into a failure.
    static let noValueTokens = ["n/a", "n.a.", "not performed", "not tested",
                                "quantity not sufficient", "qns"]

    /// Sentences a laboratory writes instead of a value, when the reason is too
    /// long for the column.
    ///
    /// The corpus case is a full blood count whose platelet row is simply absent,
    /// with *"An accurate platelet count could not be provided due to platelet
    /// clumping"* printed underneath. Dropping that line loses the one thing the
    /// reader needs to know about their own platelets that day.
    static let failureSentences = ["could not be provided", "could not be performed",
                                   "could not be reported", "unable to be performed",
                                   "not able to be performed", "no result could be",
                                   "could not be calculated"]

    static func notMeasuredRow(_ line: String) -> Row? {
        // Form one: the value cell itself says there is no value, with the
        // laboratory's reason printed after it.
        if let found = firstOccurrence(ofAny: noValueTokens, in: line) {
            let label = trimmedLabel(String(line[line.startIndex..<found.lowerBound]))
            guard isAnalyteLabel(label) else { return nil }
            let tail = String(line[found.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t:|-"))
            // The laboratory's own words where it gave any, and the token it
            // printed where it did not. Never the app's paraphrase: the reason is
            // the useful half, and "SpecimenUnsuitable" is a sentence the reader
            // can take back to whoever took the blood.
            let reason = tail.contains(where: \.isLetter) ? tail : String(line[found])
            return notMeasuredRow(label: label,
                                  entry: LabAnalyteCatalog.match(label: label),
                                  reason: reason, line: line)
        }

        // Form two: a comment sentence naming a test that could not be produced.
        guard failureSentences.contains(where: {
            line.range(of: $0, options: .caseInsensitive) != nil
        }) else { return nil }
        // ⚠️ Only a **catalogued** analyte, and only from the sentence itself. An
        // uncatalogued one would have to be named by guessing which words of an
        // English sentence were the analyte, and a wrong guess here invents a
        // test the reader never had.
        guard let entry = LabAnalyteCatalog.match(label: line) else { return nil }
        return notMeasuredRow(label: entry.displayName, entry: entry,
                              reason: line.trimmingCharacters(in: .whitespaces),
                              line: line)
    }

    static func notMeasuredRow(label: String, entry: LabAnalyteCatalog.Entry?,
                               reason: String, line: String) -> Row {
        let analyte = entry?.analyte ?? LabAnalyte.unknown(label: label, unit: nil)
        let evidence = LabExtractionEvidence(rawLabel: label, rawValueText: reason,
                                             rawLine: line, method: .deterministic,
                                             checks: [.notMeasuredStated(reason)])
        // No unit, because there is no value to put one on. `LabResult`
        // suppresses it anyway, and storing one here would leave "Not measured
        // mmol/L" one refactor away.
        return Row(analyte: analyte, value: .notMeasured(.statedByLaboratory(reason)),
                   unit: "", range: nil, evidence: evidence)
    }

    // MARK: - Shape two: the result is a word

    /// Words a pathology report prints where a number would go, **longest
    /// first** at match time.
    ///
    /// ⚠️ **Order is load-bearing and negatives come first.** "Not detected"
    /// contains "detected"; taking the shorter match would file every negative
    /// PCR in this reader's record as a positive one. `LabQualitativeOrdinal`
    /// carries the same warning for placing the word on a scale — this list is
    /// the half that *finds* it on the line.
    ///
    /// The tail of the list is words the ordinal scale deliberately cannot place.
    /// They are here so a report printing one is **kept and flagged**
    /// (`.qualitativeWordUnrecognised`) rather than silently dropped — the
    /// qualitative twin of `unitUnrecognised`, and the reason that check has
    /// anything to fire on at all.
    static let qualitativeWords: [String] = [
        "not detected", "non reactive", "non-reactive", "nonreactive",
        "nil detected", "not isolated", "no growth", "not seen", "undetected",
        "weakly reactive", "weak positive", "indeterminate", "inconclusive",
        "equivocal", "borderline", "negative", "detected", "reactive",
        "positive", "isolated", "present", "absent",
        // Not on the negative/equivocal/positive scale, on purpose.
        "normal", "abnormal", "trace", "seen", "insufficient", "pending"
    ]

    /// The word a line ended on, verbatim, and where it started.
    ///
    /// ⚠️ **The word must be the last thing on the line.** In a two-column report
    /// the result is the last column, and requiring that is what keeps an
    /// interpretive comment — *"A negative result does not exclude recent
    /// infection"* — from becoming an analyte. Only characters that carry no
    /// meaning may follow it; a full stop may not, because a full stop means a
    /// sentence.
    static func qualitativeWord(in line: String) -> Range<String.Index>? {
        var best: Range<String.Index>?
        for word in qualitativeWords.sorted(by: { $0.count > $1.count }) {
            var searchStart = line.startIndex
            while searchStart < line.endIndex,
                  let found = line.range(of: word, options: [.caseInsensitive],
                                         range: searchStart..<line.endIndex) {
                searchStart = found.upperBound
                // A word boundary in front: "isolated" inside "re-isolated" is
                // not a result, and neither is one inside an analyte's name.
                if found.lowerBound > line.startIndex {
                    let previous = line[line.index(before: found.lowerBound)]
                    if previous.isLetter || previous.isNumber { continue }
                }
                let trailing = line[found.upperBound...]
                guard trailing.allSatisfy({ $0.isWhitespace || "*†!)]".contains($0) })
                else { continue }
                // Among the matches that end the line, the one that starts
                // earliest reaches furthest back — "not detected" over "detected".
                if best == nil || found.lowerBound < best!.lowerBound { best = found }
            }
        }
        return best
    }

    static func qualitativeRow(_ line: String) -> Row? {
        guard let wordRange = qualitativeWord(in: line) else { return nil }
        let label = trimmedLabel(String(line[line.startIndex..<wordRange.lowerBound]))
        guard isAnalyteLabel(label) else { return nil }

        let entry = LabAnalyteCatalog.match(label: label)
        if let entry {
            // ⚠️ **Switched rather than tested, so a fourth form cannot be
            // forgotten here.** This is where a word either becomes the result or
            // is refused, and the two failures it sits between are both live: a
            // measurement thrown away because a word followed it, and a word
            // thrown away because the catalogue insisted on a number.
            switch entry.form {
            case .measurement:
                // A catalogued analyte the laboratory reports as a **number** does
                // not get to be a word because a word appeared at the end of its
                // line. `Glucose 5.4 mmol/L Normal` is a glucose of 5.4, and
                // reading it as the word "Normal" would throw the measurement away.
                return nil
            case .word:
                break
            case .either:
                // ⚠️ A dual-form analyte gets **the uncatalogued rule**, which is
                // the honest one: the catalogue cannot say which shape this line
                // is, so the line decides, and a number with a unit in front of
                // the word outranks the word. `HepB surface antibody <5 IU/L` and
                // `HepB surface antibody Negative` are both read correctly by
                // that one test, and neither needs the other's line to exist.
                if lineCarriesAMeasurement(line, before: wordRange) { return nil }
            }
        } else if lineCarriesAMeasurement(line, before: wordRange) {
            // The same guard for an analyte the catalogue has never met: a number
            // with a unit beside it is a measurement whatever else the line says.
            return nil
        }

        // Verbatim. Three laboratories write the same finding three ways, and the
        // report's own word is what the reader compares against their paperwork.
        let printed = String(line[wordRange])
        let result = LabQualitativeResult(printed: printed)
        let check: LabValueCheck = result.ordinal == nil
            ? .qualitativeWordUnrecognised(printed)
            : .qualitativeWordRecognised(printed)
        let analyte = entry?.analyte ?? LabAnalyte.unknown(label: label, unit: nil)
        let evidence = LabExtractionEvidence(rawLabel: label, rawValueText: printed,
                                             rawLine: line, method: .deterministic,
                                             checks: [check])
        return Row(analyte: analyte, value: .qualitative(result),
                   unit: "", range: nil, evidence: evidence)
    }

    /// Whether the line prints a number with a unit beside it, before the word.
    static func lineCarriesAMeasurement(_ line: String,
                                        before word: Range<String.Index>) -> Bool {
        let cells = valueCells(in: line).filter { $0.range.upperBound <= word.lowerBound }
        guard !cells.isEmpty else { return false }
        let interval = printedRange(in: line, cells: cells)?.range
        return cells.contains { cell in
            guard let unit = unitToken(after: cell.range.upperBound, in: line,
                                       excluding: interval) else { return false }
            return isUnitLike(unit)
        }
    }

    // MARK: - Shape three: a number, measured or bounded

    static func numericRow(_ line: String) -> Row? {
        var checks: [LabValueCheck] = []

        // 1. Every number the line prints that could be a result, with the
        //    censoring operator in front of it where there was one.
        let cells = valueCells(in: line)
        guard !cells.isEmpty else { return nil }

        // 2. The printed reference interval, taken out of play so its own numbers
        //    can never be mistaken for the result.
        let rangeFind = printedRange(in: line, cells: cells)
        let candidates = cells.filter { !overlaps($0.range, rangeFind?.range) }
        guard !candidates.isEmpty else { return nil }

        // 3. Choose between the candidates. **Select, don't merely reject** —
        //    the extension the screen-time reader got, and the reason a leading
        //    specimen-number column does not become the result.
        //
        //    Three independent signals, each worth the same: words before it,
        //    a unit after it, and agreement with the printed interval. A tie
        //    goes to the leftmost, which is where a result column sits.
        func score(_ cell: ValueCell) -> Int {
            var score = 0
            let before = line[line.startIndex..<cell.range.lowerBound]
            if before.filter(\.isLetter).count >= 2 { score += 2 }
            let afterFlag = abnormalFlag(after: cell.range, in: line)?.end
            if let unit = unitToken(after: afterFlag ?? cell.range.upperBound, in: line,
                                    excluding: rangeFind?.range),
               isUnitLike(unit) { score += 2 }
            if let printed = rangeFind?.parsed, printed.contains(cell.value) { score += 2 }
            return score
        }
        let scored = candidates.map { (cell: $0, score: score($0)) }
        let best = scored.max { lhs, rhs in
            lhs.score == rhs.score
                ? lhs.cell.range.lowerBound > rhs.cell.range.lowerBound
                : lhs.score < rhs.score
        }
        guard let chosen = best?.cell else { return nil }

        // 4. The label is whatever precedes the chosen candidate, minus a
        //    reference interval that happened to be printed to its left. An empty
        //    label means a bare number — a continuation line or an artefact.
        var labelText = String(line[line.startIndex..<chosen.range.lowerBound])
        if let interval = rangeFind?.range, interval.upperBound <= chosen.range.lowerBound {
            labelText = String(line[line.startIndex..<interval.lowerBound]) + " "
                + String(line[interval.upperBound..<chosen.range.lowerBound])
        }
        let rawLabel = labelText
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

        // 5. The laboratory's own out-of-range marker, then the unit past it.
        let flag = abnormalFlag(after: chosen.range, in: line)
        if let flag { checks.append(.printedAbnormalFlag(flag.text)) }
        let printedUnit = unitToken(after: flag?.end ?? chosen.range.upperBound,
                                    in: line, excluding: rangeFind?.range)

        // 6. A bound is not a measurement, and saying so is the whole job of
        //    `LabValue`. Recorded before any conversion, because the operator
        //    survives the conversion: a `<5 mg/dL` is still a `<` afterwards.
        if chosen.op != nil { checks.append(.censoredBound(chosen.printed)) }

        // 7. Convert, or keep verbatim, and say which.
        var number = chosen.value
        var unit = printedUnit ?? ""
        var analyte: LabAnalyte

        if let entry {
            analyte = entry.analyte
            if entry.form == .word, chosen.op != nil {
                // ⚠️ **A bound on an analyte the catalogue expects as a word and
                // nothing else is exempt from the magnitude guard, and only a
                // bound is.** `Entry.noMagnitude` exists to stop a
                // signal-to-cutoff *index* being filed as the finding — but
                // `LabValue.measuredNumber` is nil for a censored value, so a
                // bound cannot be filed as one at all and there is nothing left
                // for the guard to protect.
                //
                // ⚠️ Written `form == .word`, not `isQualitative`, and the two
                // are the same test today only because they mean the same thing:
                // a `.either` analyte has a real unit table and a real plausible
                // range, so its `<5 IU/L` converts and is sized like any other
                // measurement and must not be waved through here. That is a
                // stronger reading than the exemption, not a weaker one.
                unit = printedUnit ?? ""
                checks.append(.magnitudeUncheckable)
            } else {
                if let printedUnit, !printedUnit.isEmpty {
                    if let converted = LabAnalyteCatalog.convert(number, from: printedUnit,
                                                                 for: entry) {
                        number = converted
                        unit = entry.canonicalUnit
                        checks.append(.unitRecognised(printedUnit))
                    } else {
                        // ⚠️ Never convert on a guess. A wrong factor is invisible
                        // afterwards — the number looks perfectly reasonable.
                        unit = printedUnit
                        checks.append(.unitUnrecognised(printedUnit))
                    }
                } else if let inferred = inferUnit(for: entry, value: number,
                                                   range: rangeFind?.parsed) {
                    number = inferred.value
                    unit = entry.canonicalUnit
                    checks.append(.unitInferredFromRange(inferred.assumedUnit))
                } else {
                    unit = entry.canonicalUnit
                    checks.append(.unitMissing)
                }
                checks.append(entry.plausible.contains(number)
                              ? .plausibleMagnitude : .implausibleMagnitude)
            }
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

        // 8. The printed interval, against the value that was finally chosen.
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

        // 9. Characters OCR is known to confuse, in the value itself.
        if let confusing = ambiguity(in: chosen.token.text) {
            checks.append(.ambiguousCharacters(confusing))
        }

        // The stored interval is expressed in the same unit as the stored value,
        // so a converted value keeps a converted interval or none at all.
        let storedRange = convertedRange(rangeFind?.parsed,
                                         entry: entry, printedUnit: printedUnit)

        let evidence = LabExtractionEvidence(rawLabel: rawLabel,
                                             rawValueText: chosen.printed,
                                             rawLine: line,
                                             method: .deterministic,
                                             checks: checks)
        let value: LabValue = chosen.op.map { LabValue.censored($0, number) }
            ?? .quantitative(number)
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

    // MARK: - Labels

    /// Words that open a sentence rather than name an analyte.
    ///
    /// ⚠️ This list is half of a guard against a shape a real report prints on
    /// every page: its interpretive comments end in the same vocabulary its
    /// results do. *"...could not be provided due to platelet clumping"* and
    /// *"A negative result does not exclude recent infection"* both look exactly
    /// like a two-column row to anything that only checks for a trailing word,
    /// and without this the reader's record gains an analyte called "This test
    /// was".
    static let proseWords: Set<String> = [
        "a", "an", "the", "this", "these", "those", "that", "please", "note",
        "notes", "comment", "comments", "result", "results", "was", "were",
        "is", "are", "be", "been", "because", "due", "no", "not", "all", "some",
        "further", "if", "and", "or", "but", "however", "we", "your", "you",
        "it", "there", "has", "have", "had", "may", "can", "could", "should",
        "would", "sample", "specimen", "report", "reported", "suggest",
        "suggests", "recommend", "recommended", "clinical", "correlation",
        "advised", "interpretation", "performed"
    ]

    /// Whether a string could be the name of an analyte.
    ///
    /// Eight words is the backstop; `proseWords` does the real work. The corpus's
    /// longest genuine label is six tokens (`HIV 1 / 2 total antibody`), so the
    /// cap is set where a laboratory stops and a sentence keeps going.
    static func isAnalyteLabel(_ label: String) -> Bool {
        let words = label.split(whereSeparator: \.isWhitespace)
        guard (1...8).contains(words.count) else { return false }
        guard label.filter(\.isLetter).count >= 2 else { return false }
        for word in words {
            let key = String(word).lowercased().filter(\.isLetter)
            if !key.isEmpty, proseWords.contains(key) { return false }
        }
        return true
    }

    static func trimmedLabel(_ raw: String) -> String {
        var label = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t|"))
        while let last = label.last, last == ":" || last == "." || last == "-" {
            label.removeLast()
            label = label.trimmingCharacters(in: .whitespaces)
        }
        return label
    }

    /// The earliest occurrence of any of `needles`, case-insensitively.
    static func firstOccurrence(ofAny needles: [String],
                                in haystack: String) -> Range<String.Index>? {
        var best: Range<String.Index>?
        for needle in needles {
            guard let found = haystack.range(of: needle, options: .caseInsensitive)
            else { continue }
            if best == nil || found.lowerBound < best!.lowerBound { best = found }
        }
        return best
    }

    // MARK: - Number scanning

    struct NumberToken: Equatable {
        let text: String
        let value: Double
        let range: Range<String.Index>
    }

    /// A number on a line together with the censoring operator printed in front
    /// of it, so the two are never separated by anything downstream.
    struct ValueCell: Equatable {
        /// `<`, `>`, `≤`, `≥` where the report printed one.
        let op: LabCensorOperator?
        let token: NumberToken
        /// Operator and number together. An interval that covers the number
        /// covers its sign with it, and blanking one blanks both.
        let range: Range<String.Index>
        /// Exactly as printed — "<5", ">90", "146".
        let printed: String

        var value: Double { token.value }
    }

    static func censorOperator(_ character: Character) -> LabCensorOperator? {
        switch character {
        case "<": return .lessThan
        case ">": return .greaterThan
        case "\u{2264}": return .lessOrEqual
        case "\u{2265}": return .greaterOrEqual
        default: return nil
        }
    }

    /// Every number on a line that could be a result.
    ///
    /// Two things are excluded, and both are misreads this parser has actually
    /// made:
    ///
    /// - **Digits inside a word.** "HbA1c", "Vitamin B12" and "1.73m2" all carry
    ///   one that belongs to the analyte's name; reading the `1` out of HbA1c as
    ///   the result was the first thing this parser did when it stopped being a
    ///   two-analyte special case.
    /// - ⚠️ **Digits inside a date.** `Collected: 20/04/2026 11:38` used to yield
    ///   an analyte called "Collected" with a value of 20, and a My Health Record
    ///   table row yielded one called "-Dec" with a value of 25. A number that is
    ///   part of a date is never a result, and the date scanner already knows
    ///   exactly where each one starts and ends.
    static func valueCells(in line: String) -> [ValueCell] {
        let dateRanges = dates(in: line).map(\.range)
        return numberTokens(in: line).compactMap { token -> ValueCell? in
            if token.range.lowerBound > line.startIndex,
               line[line.index(before: token.range.lowerBound)].isLetter {
                return nil
            }
            if dateRanges.contains(where: { $0.overlaps(token.range) }) { return nil }

            var start = token.range.lowerBound
            var op: LabCensorOperator?
            var cursor = token.range.lowerBound
            while cursor > line.startIndex {
                let previous = line.index(before: cursor)
                let character = line[previous]
                if character == " " || character == "\t" { cursor = previous; continue }
                if let found = censorOperator(character) { op = found; start = previous }
                break
            }
            return ValueCell(op: op, token: token,
                             range: start..<token.range.upperBound,
                             printed: String(line[start..<token.range.upperBound]))
        }
    }

    static func overlaps(_ range: Range<String.Index>, _ other: Range<String.Index>?) -> Bool {
        guard let other else { return false }
        return range.overlaps(other)
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

    // MARK: - Flags and units

    /// Markers that are only ever a flag, never a unit.
    static let alwaysFlags: Set<String> = ["h", "hh", "ll", "a", "*", "**", "\u{2020}",
                                           "(h)", "(l)", "!", "h*", "l*", "hi", "lo"]

    /// The laboratory's own out-of-range marker, printed between the value and
    /// the reference interval.
    ///
    /// ⚠️ **`L` is a flag *and* a unit, and only its position tells them apart.**
    /// `Bicarbonate 19 L 20 - 32 mmol/L` marks a low bicarbonate; `Urine volume
    /// 1.2 L` measures litres. A flag never ends the line — the interval or the
    /// unit always follows it — so a lone `L` with nothing after it is litres and
    /// a lone `L` with anything after it is a flag. Reading a flagged `L` as
    /// litres was live here until 2026-08-09 and stamps a bicarbonate
    /// `unitUnrecognised`; reading litres as a flag loses the only unit the line
    /// printed. `H` needs none of this — nothing is measured in H.
    ///
    /// ⚠️ The flag is **recorded, never interpreted** (`printedAbnormalFlag`). It
    /// is the laboratory's statement about the reader's result, not the app's
    /// check on its own reading, and it is the one entry in `LabValueCheck` that
    /// says nothing about the extraction.
    static func abnormalFlag(after valueRange: Range<String.Index>,
                             in line: String) -> (text: String, end: String.Index)? {
        var index = valueRange.upperBound
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        var end = index
        while end < line.endIndex, !line[end].isWhitespace { end = line.index(after: end) }
        guard end > index else { return nil }
        let token = String(line[index..<end])
        let key = token.lowercased()
        if alwaysFlags.contains(key) { return (token, end) }
        if key == "l", line[end...].contains(where: { !$0.isWhitespace }) {
            return (token, end)
        }
        return nil
    }

    /// The unit printed after a value, skipping the reference interval if that is
    /// what sits between the two.
    ///
    /// ⚠️ The interval is stepped **over**, not stopped at: `Bicarbonate 19 L
    /// 20 - 32 mmol/L` prints its unit on the far side of its own interval, and
    /// a scanner that stopped at the interval would call that line unitless.
    static func unitToken(after start: String.Index, in line: String,
                          excluding interval: Range<String.Index>?) -> String? {
        guard start <= line.endIndex else { return nil }
        let rest: String
        if let interval, interval.lowerBound >= start {
            rest = String(line[start..<interval.lowerBound]) + " "
                + String(line[interval.upperBound...])
        } else {
            rest = String(line[start...])
        }
        return unitToken(in: rest)
    }

    static func unitToken(in text: String) -> String? {
        let rest = text.trimmingCharacters(in: .whitespaces)
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

    /// The reference interval a line printed, given what else is on the line.
    ///
    /// ⚠️ **A one-sided interval and a censored result are the same characters**,
    /// and only the rest of the line separates them. `HepB surface antibody <5
    /// IU/L` has one `<5` on it and that `<5` is the *result*; `eGFR >90 >59` has
    /// two, and the last is the interval. So a one-sided form is only believed to
    /// be an interval when something else on the line is still available to be
    /// the value. Get this backwards and a hepatitis B surface antibody arrives
    /// with no value at all, or an eGFR of `>90` — an assay ceiling — is stored
    /// as a measured 90 and walks into a renal trend.
    static func printedRange(in line: String, cells: [ValueCell]) -> RangeFind? {
        guard let find = printedRangeCandidate(in: line) else { return nil }
        let isOneSided = find.parsed.low == nil || find.parsed.high == nil
        guard isOneSided else { return find }
        let outside = cells.filter { !$0.range.overlaps(find.range) }
        return outside.isEmpty ? nil : find
    }

    /// The rightmost thing on the line shaped like an interval.
    ///
    /// Takes the **last** match: reports print the result first and the interval
    /// to its right, and a leading match is almost always a value that happens to
    /// contain a hyphen.
    static func printedRangeCandidate(in line: String) -> RangeFind? {
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
        if trimmed.hasPrefix("<") || trimmed.hasPrefix("\u{2264}") {
            guard let value = numberTokens(in: trimmed).first?.value else { return nil }
            return LabReferenceRange(low: nil, high: value, printed: trimmed)
        }
        if trimmed.hasPrefix(">") || trimmed.hasPrefix("\u{2265}") {
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

    // MARK: - The specimen

    /// What the report says was tested.
    ///
    /// Read off the whole document rather than a result line, because the
    /// specimen is stated once at the top and applies to everything under it.
    /// The marker must open its line — *"the specimen type was unsuitable for
    /// analysis"* is a comment about a failure, not a declaration of a specimen.
    static func specimen(in text: String) -> String? {
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            for word in ["specimen", "sample"] {
                guard line.lowercased().hasPrefix(word) else { continue }
                var rest = String(line.dropFirst(word.count))
                    .trimmingCharacters(in: .whitespaces)
                var sawType = false
                if rest.lowercased().hasPrefix("type") {
                    rest = String(rest.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    sawType = true
                }
                var sawSeparator = false
                while let first = rest.first, first == ":" || first == "-" || first == "|" {
                    rest.removeFirst()
                    rest = rest.trimmingCharacters(in: .whitespaces)
                    sawSeparator = true
                }
                // ⚠️ Without one of these, "Specimen collected 09-Dec-25" would
                // be read as a specimen called "collected 09-Dec-25".
                guard sawType || sawSeparator else { continue }
                guard rest.contains(where: \.isLetter) else { continue }
                return rest
            }
        }
        return nil
    }

    // MARK: - The collection date

    /// Markers that name the moment the sample was **taken**, best rank first.
    ///
    /// ⚠️ **Collection, not report date, and the distinction is not pedantry.**
    /// A report is often authorised days after the blood was drawn; filing the
    /// value under the report date puts it in the wrong week against every vital
    /// it might later be compared with.
    ///
    /// ⚠️ **Rank 0 beats rank 1 even though both say "collected", and that is the
    /// InstantScripts trap.** That portal prints a header `Collected:
    /// 2024-12-12 13:15:00` above an embedded QML document whose own structured
    /// field reads `204 Collection : 12/12/2024 11:50 am`. The header is later
    /// than the document's own `Completed` line, so it cannot be a collection
    /// time at all — it is the portal's timestamp wearing the laboratory's label.
    /// The structured field wins, and rank is how that is said once rather than
    /// per laboratory.
    ///
    /// Nothing else on the page is a marker, which is the other half of the fix:
    /// Sullivan Nicolaides prints `Requested`, `Collected`, `Received`,
    /// `Reported on` and `Document created`, and four of those five are dates the
    /// reader's blood was nowhere near.
    static let collectionMarkers: [(marker: String, rank: Int)] = [
        ("collection date", 0), ("date collected", 0), ("date of collection", 0),
        ("collection time", 0), ("specimen collected", 0), ("collection", 0),
        ("collected on", 1), ("collected", 1), ("taken on", 1),
        ("sample taken", 1), ("specimen date", 1)
    ]

    /// The date the sample was taken, as printed.
    ///
    /// Returns nil where the document prints only a report date, and the caller
    /// falls back on the import date with `collectedAtIsExact` false, so the
    /// imprecision is visible rather than hidden behind a confident-looking date.
    static func collectionDate(in text: String) -> Date? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var best: (date: Date, rank: Int)?
        for (number, line) in lines.enumerated() {
            for (marker, rank) in collectionMarkers {
                guard let found = line.range(of: marker, options: .caseInsensitive)
                else { continue }
                let column = line.distance(from: line.startIndex, to: found.lowerBound)
                var date = dates(in: String(line[found.upperBound...])).first?.date
                if date == nil, !line.contains(where: \.isNumber) {
                    date = dateUnderHeading(at: column, below: number, in: lines)
                }
                // `collectionMarkers` is ordered best-rank-first, so the first
                // marker that matches a line is the best that line offers.
                guard let date else { break }
                if best == nil || rank < best!.rank { best = (date, rank) }
                break
            }
        }
        return best?.date
    }

    /// The date under a column heading, on the row beneath it.
    ///
    /// My Health Record prints its embedded report inside a table whose heading
    /// row reads `Collection Date | Observation Date | Test Result Name | …` and
    /// whose dates are all on the next line.
    ///
    /// ⚠️ **Nearest column, not first date.** The observation date sits beside
    /// the collection date and is a different day on any report authorised later
    /// than it was drawn; taking the leftmost date only works until a laboratory
    /// orders its columns differently, and this reader's corpus already contains
    /// three column orders.
    static func dateUnderHeading(at column: Int, below line: Int,
                                 in lines: [String]) -> Date? {
        var next = line + 1
        while next < lines.count,
              lines[next].trimmingCharacters(in: .whitespaces).isEmpty { next += 1 }
        guard next < lines.count else { return nil }
        let row = lines[next]
        let candidates = dates(in: row).map { find in
            (date: find.date,
             column: row.distance(from: row.startIndex, to: find.range.lowerBound))
        }
        return candidates.min { abs($0.column - column) < abs($1.column - column) }?.date
    }

    // MARK: - Reading a printed date

    /// The date shapes this corpus prints. Australian reports are **day-first**:
    /// `20/04/2026` is only readable as the twentieth of April, and a month-first
    /// reading of it produces a month of 20, which `calendarFields` refuses
    /// rather than swapping — a swapped date is a silent lie about when blood was
    /// taken, and refusing leaves `collectedAtIsExact` false where it belongs.
    static let datePatterns = [
        #"[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}"#,
        #"[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}"#,
        #"[0-9]{1,2}[- ][A-Za-z]{3,9}[- ][0-9]{2,4}"#
    ]

    /// Every date on a line, each one's range covering the time of day where the
    /// report printed one directly after it.
    ///
    /// ⚠️ **The time is not decoration.** InstantScripts' header and the document
    /// it wraps name the same *day* and differ only in the hour, so a parser that
    /// read days alone could not tell which of the two contradicting fields it
    /// had believed — and neither could its tests.
    static func dates(in s: String) -> [(date: Date, range: Range<String.Index>)] {
        var found: [(Date, Range<String.Index>)] = []
        for pattern in datePatterns {
            var searchStart = s.startIndex
            while searchStart < s.endIndex,
                  let match = s.range(of: pattern, options: .regularExpression,
                                      range: searchStart..<s.endIndex) {
                searchStart = match.upperBound
                guard let fields = calendarFields(String(s[match])) else { continue }
                let time = timeOfDay(after: match, in: s)
                guard let date = utcDate(year: fields.year, month: fields.month,
                                         day: fields.day,
                                         hour: time?.hour ?? 0,
                                         minute: time?.minute ?? 0) else { continue }
                found.append((date, match.lowerBound..<(time?.end ?? match.upperBound)))
            }
        }
        var kept: [(Date, Range<String.Index>)] = []
        for candidate in found.sorted(by: { $0.1.lowerBound < $1.1.lowerBound }) {
            if kept.contains(where: { $0.1.overlaps(candidate.1) }) { continue }
            kept.append(candidate)
        }
        return kept.map { (date: $0.0, range: $0.1) }
    }

    static func firstDate(in s: String) -> Date? { dates(in: s).first?.date }

    static let monthNames = ["january", "february", "march", "april", "may", "june",
                             "july", "august", "september", "october", "november",
                             "december"]

    static func monthNumber(_ name: String) -> Int? {
        let key = name.lowercased()
        guard key.count >= 3 else { return nil }
        return monthNames.firstIndex { $0.hasPrefix(key) || key.hasPrefix($0) }
            .map { $0 + 1 }
    }

    /// The calendar fields a printed date names, or nil if it does not name one.
    ///
    /// ⚠️ **A two-digit year is this century.** `09-Dec-25` is 2025. Resolving it
    /// against "now" would make the parser's answer depend on when it ran — which
    /// a test cannot pin and a reader cannot predict — and a pathology report old
    /// enough for 1925 to be the right reading is not one this app will be shown.
    static func calendarFields(_ raw: String) -> (year: Int, month: Int, day: Int)? {
        let parts = raw.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." || $0 == " " })
        guard parts.count == 3 else { return nil }
        let first = String(parts[0]), second = String(parts[1]), third = String(parts[2])

        var year: Int
        var month: Int
        var day: Int
        if first.count == 4, let isoYear = Int(first), let isoMonth = Int(second),
           let isoDay = Int(third) {
            year = isoYear; month = isoMonth; day = isoDay
        } else {
            guard let dayValue = Int(first) else { return nil }
            if let numeric = Int(second) { month = numeric }
            else if let named = monthNumber(second) { month = named }
            else { return nil }
            guard var yearValue = Int(third) else { return nil }
            if third.count <= 2 { yearValue += 2000 }
            year = yearValue; day = dayValue
        }
        // ⚠️ The year bound is what stops "Ferritin 30 August 400" — a plausible
        // enough result line — parsing as the year 400 and having its numbers
        // struck out of `valueCells` as part of a date.
        guard (1900...2200).contains(year), (1...12).contains(month),
              (1...31).contains(day) else { return nil }
        return (year, month, day)
    }

    /// The time of day printed straight after a date — `11:38`, `13:15:00`,
    /// `11:50 am` — and where it ends.
    static func timeOfDay(after range: Range<String.Index>,
                          in s: String) -> (hour: Int, minute: Int, end: String.Index)? {
        var index = range.upperBound
        while index < s.endIndex, s[index] == " " || s[index] == "\t" {
            index = s.index(after: index)
        }
        var hourDigits = ""
        while index < s.endIndex, s[index].isNumber, hourDigits.count < 2 {
            hourDigits.append(s[index])
            index = s.index(after: index)
        }
        guard !hourDigits.isEmpty, var hour = Int(hourDigits),
              index < s.endIndex, s[index] == ":" else { return nil }
        index = s.index(after: index)
        var minuteDigits = ""
        while index < s.endIndex, s[index].isNumber, minuteDigits.count < 2 {
            minuteDigits.append(s[index])
            index = s.index(after: index)
        }
        guard minuteDigits.count == 2, let minute = Int(minuteDigits) else { return nil }

        // An optional seconds field, which InstantScripts prints and nothing
        // reads — but which must be consumed so `valueCells` does not find a
        // result of "00" sitting in a timestamp.
        if index < s.endIndex, s[index] == ":" {
            var cursor = s.index(after: index)
            var digits = 0
            while cursor < s.endIndex, s[cursor].isNumber, digits < 2 {
                cursor = s.index(after: cursor)
                digits += 1
            }
            if digits == 2 { index = cursor }
        }

        var end = index
        var cursor = index
        while cursor < s.endIndex, s[cursor] == " " { cursor = s.index(after: cursor) }
        let meridiem = String(s[cursor...].prefix(2)).lowercased()
        if meridiem == "am" {
            if hour == 12 { hour = 0 }
            end = s.index(cursor, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
        } else if meridiem == "pm" {
            if hour < 12 { hour += 12 }
            end = s.index(cursor, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute, end)
    }

    /// A `Date` from calendar fields, in UTC.
    ///
    /// ⚠️ **UTC, because the report prints no zone.** Every date in this file is
    /// built the same way, so two results from one report are always comparable
    /// with each other. What the parser must never do is invent a zone-dependent
    /// instant that shifts with wherever the phone happens to be when the
    /// document is imported.
    static func utcDate(year: Int, month: Int, day: Int,
                        hour: Int = 0, minute: Int = 0) -> Date? {
        guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }
}
