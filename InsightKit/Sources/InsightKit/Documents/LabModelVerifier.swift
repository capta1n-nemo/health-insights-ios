import Foundation

/// **What the on-device model is allowed to say about a lab report, and how
/// every word of it is checked before anything is stored.**
///
/// Backlog `I6`. The model half of this feature lives in the app target
/// (`LabAnalyteExtractor`, which owns `LanguageModelSession`); *this* is the
/// half that can be wrong in a way nobody notices, so it is pure, lives in
/// InsightKit, and is tested on Linux.
///
/// ## The model never produces a number
///
/// It has exactly two jobs, and neither of them is measurement:
///
/// 1. **Naming.** A laboratory prints "Alk. Phos." or "Serum TSH level (XaELV)"
///    and the catalogue's synonym list does not have it. The model maps that
///    label to a known analyte key, so the value joins the reader's existing
///    trend instead of starting a second one under a different name.
/// 2. **Pairing.** OCR of a multi-column table often emits every label, then
///    every value — so the line-based parser sees rows of words with no numbers
///    and rows of numbers with no words. The model says which value goes with
///    which label.
///
/// In both cases the *number* comes from the recognised text, never from the
/// model. `verify(_:against:)` enforces that literally: a proposed value is kept
/// only if its digits appear verbatim in the source text, on the line the model
/// pointed at. A model that invents `5.2` cannot get it stored, because `5.2` is
/// not in the page.
///
/// ⚠️ **This is the difference between an aid and a hazard.** A misread lab value
/// is worse than none, and a *fabricated* one is worse still, because it carries
/// no OCR artefact to notice. The verification is not a nicety on top of the
/// model; it is the reason the model is allowed near this at all.
///
/// ⚠️ **The prompt never leaves the device.** `LanguageModelSession` is Apple's
/// on-device model and this app has no network path that could carry a report;
/// see `LabAnalyteExtractor` for the availability check and the deterministic
/// fallback, which must keep working when the model is unavailable.
public enum LabModelVerifier {

    /// One thing the model said, before anything has been believed.
    public struct Proposal: Sendable, Equatable, Codable {
        /// The label the model read, expected to appear in the source text.
        public let label: String
        /// The catalogue key the model thinks this label names, or nil for
        /// "a real analyte, but not one you know".
        public let analyteKey: String?
        /// The value's characters **as the model claims they appear on the
        /// page**. A string rather than a Double on purpose: the check is a
        /// substring search against the recognised text, and re-formatting a
        /// parsed number would defeat it.
        public let valueText: String
        /// The unit as printed, if the model found one.
        public let unitText: String?
        /// The source line the model says this came from, used to require the
        /// number and the label to be near each other rather than merely both
        /// present somewhere on a page of thirty numbers.
        public let sourceLine: String?

        public init(label: String, analyteKey: String?, valueText: String,
                    unitText: String?, sourceLine: String?) {
            self.label = label
            self.analyteKey = analyteKey
            self.valueText = valueText
            self.unitText = unitText
            self.sourceLine = sourceLine
        }
    }

    /// What verification decided about one proposal.
    public struct Verdict: Sendable, Equatable {
        public let proposal: Proposal
        public let accepted: LabResult?
        public let checks: [LabValueCheck]
        /// Why it was refused, for the diagnostics log. Nil when accepted.
        public let refusal: String?
        /// The deterministic result this one replaces, when the model's only
        /// contribution was to **rename** something the parser had already read
        /// under the laboratory's own label. See `reconcile`.
        public let supersedes: UUID?

        public init(proposal: Proposal, accepted: LabResult?,
                    checks: [LabValueCheck], refusal: String?,
                    supersedes: UUID? = nil) {
            self.proposal = proposal
            self.accepted = accepted
            self.checks = checks
            self.refusal = refusal
            self.supersedes = supersedes
        }
    }

    /// The parse and the model's contribution, reconciled into one list.
    public struct Reconciled: Sendable, Equatable {
        /// What to store: the deterministic results, minus any the model
        /// renamed, plus what it added.
        public let results: [LabResult]
        public let verdicts: [Verdict]

        public init(results: [LabResult], verdicts: [Verdict]) {
            self.results = results
            self.verdicts = verdicts
        }

        public var acceptedCount: Int { verdicts.filter { $0.accepted != nil }.count }
        public var refusedCount: Int { verdicts.filter { $0.accepted == nil }.count }
    }

    /// **The entry point the app calls.** Verify, then fold the survivors into
    /// the deterministic parse.
    ///
    /// Two things happen here that `verify` alone cannot do:
    ///
    /// - **Renaming.** The parser reads `Phosphatase, alkaline (bone isoform)`
    ///   as an uncatalogued analyte, because that string is in none of the
    ///   catalogue's synonym lists. If the model maps the *same line* onto
    ///   `alp`, the mapped result replaces the unnamed one — so the value joins
    ///   the reader's existing alkaline-phosphatase trend rather than starting a
    ///   parallel one under a label they will never search for.
    /// - **Nothing else is touched.** A model proposal can only supersede a
    ///   result the catalogue did not recognise, and only when its own quoted
    ///   line is the line that result came from. A recognised analyte is never
    ///   overwritten by a model, at all, under any circumstance.
    public static func reconcile(_ proposals: [Proposal],
                                 with scan: LabReportParser.Scan,
                                 source: LabResultSource) -> Reconciled {
        var verdicts = verify(proposals, against: scan, source: source)
        var results = scan.results
        var superseded = Set<UUID>()

        for (index, verdict) in verdicts.enumerated() {
            guard let accepted = verdict.accepted, accepted.analyte.isKnown else { continue }
            let label = normalise(verdict.proposal.label)
            let value = normalise(verdict.proposal.valueText)
            guard let replaced = results.first(where: { existing in
                guard !existing.analyte.isKnown, !superseded.contains(existing.id) else {
                    return false
                }
                let line = normalise(existing.evidence?.rawLine ?? "")
                return line.contains(label) && line.contains(value)
            }) else { continue }
            superseded.insert(replaced.id)
            verdicts[index] = Verdict(proposal: verdict.proposal, accepted: accepted,
                                      checks: verdict.checks, refusal: nil,
                                      supersedes: replaced.id)
        }

        results.removeAll { superseded.contains($0.id) }
        results.append(contentsOf: verdicts.compactMap(\.accepted))
        return Reconciled(results: results, verdicts: verdicts)
    }

    /// Check a batch of proposals against the text they claim to come from.
    ///
    /// - Parameters:
    ///   - proposals: what the model returned.
    ///   - scan: the deterministic parse of the same document. Its
    ///     `sourceText` is the ground truth every number is checked against,
    ///     and its `results` are what a proposal must not duplicate.
    ///   - source: the document route, stamped on every accepted result.
    public static func verify(_ proposals: [Proposal],
                              against scan: LabReportParser.Scan,
                              source: LabResultSource) -> [Verdict] {
        var verdicts: [Verdict] = []
        var claimedKeys = Set(scan.results.map(\.analyte.key))
        let haystack = normalise(scan.sourceText)

        for proposal in proposals {
            var checks: [LabValueCheck] = []

            // 1. The number must be in the page. This is the whole guard.
            let needle = normalise(proposal.valueText)
            guard !needle.isEmpty, haystack.contains(needle) else {
                checks.append(.notFoundInSourceText)
                verdicts.append(Verdict(proposal: proposal, accepted: nil, checks: checks,
                                        refusal: "value not present in the recognised text"))
                continue
            }

            // 2. The label must be in the page too. A model that maps a label
            //    it invented onto a real number is the same failure wearing the
            //    other hat.
            let labelNeedle = normalise(proposal.label)
            guard !labelNeedle.isEmpty, haystack.contains(labelNeedle) else {
                checks.append(.notFoundInSourceText)
                verdicts.append(Verdict(proposal: proposal, accepted: nil, checks: checks,
                                        refusal: "label not present in the recognised text"))
                continue
            }

            // 3. They must be near each other. Both appearing on a page of
            //    thirty analytes proves nothing about their belonging together,
            //    which is precisely the pairing job the model was given.
            if let line = proposal.sourceLine {
                let lineNeedle = normalise(line)
                guard haystack.contains(lineNeedle),
                      lineNeedle.contains(needle), lineNeedle.contains(labelNeedle) else {
                    checks.append(.notFoundInSourceText)
                    verdicts.append(Verdict(proposal: proposal, accepted: nil, checks: checks,
                                            refusal: "the line quoted is not in the text, or does not hold both the label and the value"))
                    continue
                }
            } else if !proximate(labelNeedle, needle, in: haystack) {
                checks.append(.notFoundInSourceText)
                verdicts.append(Verdict(proposal: proposal, accepted: nil, checks: checks,
                                        refusal: "the label and the value are too far apart in the text to be one row"))
                continue
            }

            checks.append(.corroboratedInSourceText)

            // 4. Parse the number ourselves. The model's characters, this app's
            //    arithmetic — a model that says "five point two" gets nothing.
            guard let parsed = LabReportParser.numberTokens(in: proposal.valueText).first,
                  parsed.text.count == proposal.valueText.trimmingCharacters(in: .whitespaces).count
            else {
                verdicts.append(Verdict(proposal: proposal, accepted: nil, checks: checks,
                                        refusal: "the value is not a bare number"))
                continue
            }

            // 5. Resolve the analyte. An unknown key is refused rather than
            //    silently downgraded: the model naming a catalogue entry that
            //    does not exist is a sign the whole response is confabulated.
            var analyte: LabAnalyte
            var value = parsed.value
            var unit = proposal.unitText ?? ""
            if let key = proposal.analyteKey, !key.isEmpty {
                guard let entry = LabAnalyteCatalog.entry(forKey: key) else {
                    verdicts.append(Verdict(proposal: proposal, accepted: nil, checks: checks,
                                            refusal: "named an analyte key the catalogue does not have: \(key)"))
                    continue
                }
                analyte = entry.analyte
                if let unitText = proposal.unitText, !unitText.isEmpty,
                   let converted = LabAnalyteCatalog.convert(value, from: unitText, for: entry) {
                    value = converted
                    unit = entry.canonicalUnit
                    checks.append(.unitRecognised(unitText))
                } else if let unitText = proposal.unitText, !unitText.isEmpty {
                    checks.append(.unitUnrecognised(unitText))
                } else {
                    unit = entry.canonicalUnit
                    checks.append(.unitMissing)
                }
                checks.append(entry.plausible.contains(value)
                              ? .plausibleMagnitude : .implausibleMagnitude)
            } else {
                analyte = LabAnalyte.unknown(label: proposal.label, unit: proposal.unitText)
                checks.append(.magnitudeUncheckable)
                if let unitText = proposal.unitText, !unitText.isEmpty {
                    checks.append(.unitRecognised(unitText))
                } else {
                    checks.append(.unitMissing)
                }
            }

            // 6. Never overwrite what the deterministic parser already found.
            //    The rule-based path is the one under test; the model is the
            //    supplement, and a supplement that can overrule its host is not
            //    a supplement.
            guard claimedKeys.insert(analyte.key).inserted else {
                verdicts.append(Verdict(proposal: proposal, accepted: nil, checks: checks,
                                        refusal: "the parser already read \(analyte.displayName) from this report"))
                continue
            }

            checks.append(.noPrintedRange)

            let evidence = LabExtractionEvidence(rawLabel: proposal.label,
                                                 rawValueText: proposal.valueText,
                                                 rawLine: proposal.sourceLine ?? proposal.label,
                                                 method: .onDeviceModel,
                                                 checks: checks)
            let result = LabResult(analyte: analyte, value: value, unit: unit,
                                   referenceRange: nil,
                                   collectedAt: scan.collectedAt ?? Date(),
                                   collectedAtIsExact: scan.collectedAt != nil,
                                   source: source, evidence: evidence,
                                   isConfirmedByReader: false)
            verdicts.append(Verdict(proposal: proposal, accepted: result,
                                    checks: checks, refusal: nil))
        }
        return verdicts
    }

    /// Lower-cased and whitespace-collapsed. OCR line-wraps unpredictably and a
    /// literal substring search against raw text would fail on a space.
    static func normalise(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .reduce(into: "") { acc, ch in
                if ch.isWhitespace {
                    if acc.last != " " { acc.append(" ") }
                } else {
                    acc.append(ch)
                }
            }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Whether a label and a value sit close enough to be one row.
    ///
    /// 80 characters is about one table row of recognised text including its
    /// unit and reference interval. Two analytes' worth of text is longer than
    /// that, which is the boundary this is drawing.
    static let proximityWindow = 80

    static func proximate(_ label: String, _ value: String, in haystack: String) -> Bool {
        var searchStart = haystack.startIndex
        while let labelRange = haystack.range(of: label, range: searchStart..<haystack.endIndex) {
            let windowEnd = haystack.index(labelRange.upperBound, offsetBy: proximityWindow,
                                           limitedBy: haystack.endIndex) ?? haystack.endIndex
            if haystack[labelRange.upperBound..<windowEnd].contains(value) { return true }
            searchStart = labelRange.upperBound
            if searchStart >= haystack.endIndex { break }
        }
        return false
    }
}

public extension LabModelVerifier {
    /// The instruction text the on-device session is given.
    ///
    /// Kept here rather than in the app target so it is **visible to the tests
    /// and to anyone reading the verifier** — the prompt and the thing that
    /// polices its output are one design and reviewing them apart is how the
    /// two drift.
    ///
    /// ⚠️ Read alongside `verify(_:against:)`: nothing in this prompt is
    /// trusted. Every constraint it states is also enforced afterwards, because
    /// a prompt is a request and a check is a guarantee.
    static let modelInstructions = """
    You extract laboratory analyte names and values from the text of a \
    pathology report. You never calculate, convert, interpret or comment on a \
    value. You never state a number that is not present character-for-character \
    in the text you were given; if you cannot find one, you omit the row \
    entirely. You do not diagnose and you do not say whether a value is normal.
    """

    /// Parse the model's answer.
    ///
    /// **The response format is a flat, pipe-separated line each** rather than
    /// JSON or guided generation, and the choice is a safety one. A small
    /// on-device model produces a malformed brace far more often than a
    /// malformed line — and since every field is checked against the page
    /// afterwards, a *parsing* failure costs one dropped row while a *believed*
    /// hallucination would cost a wrong lab value. The format fails on the cheap
    /// side by design.
    ///
    /// Lives here rather than beside the `LanguageModelSession` for the reason
    /// the whole verifier does: the app target has no test host, and this is the
    /// half that can be wrong quietly. Anything malformed is dropped without
    /// comment — the verifier would refuse it seconds later anyway.
    ///
    ///     LABEL | ANALYTE_KEY_OR_BLANK | VALUE | UNIT_OR_BLANK | SOURCE_LINE
    static func proposals(fromModelResponse text: String) -> [Proposal] {
        text.split(separator: "\n").compactMap { rawLine -> Proposal? in
            let fields = rawLine.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3 else { return nil }
            let label = fields[0]
            // A model that answers in prose ("Here are the values I found:")
            // produces lines with no pipes at all, which are already gone, and
            // occasionally one with a stray pipe — caught by the value having to
            // parse as a bare number in `verify`.
            guard !label.isEmpty, label.contains(where: \.isLetter) else { return nil }
            let key = fields[1].isEmpty ? nil : fields[1]
            let value = fields[2]
            guard !value.isEmpty else { return nil }
            let unit = fields.count > 3 && !fields[3].isEmpty ? fields[3] : nil
            let sourceLine = fields.count > 4 && !fields[4].isEmpty ? fields[4] : nil
            return Proposal(label: label, analyteKey: key, valueText: value,
                            unitText: unit, sourceLine: sourceLine)
        }
    }

    /// The catalogue keys a model may map a label onto, as a prompt fragment.
    ///
    /// Generated from the catalogue rather than written out, so a new analyte
    /// becomes mappable the moment it is added — one list, not two.
    static var mappableKeys: String {
        LabAnalyteCatalog.entries
            .map { "\($0.key) (\($0.displayName), \($0.canonicalUnit))" }
            .joined(separator: "\n")
    }
}
