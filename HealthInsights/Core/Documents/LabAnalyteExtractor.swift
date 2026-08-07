import Foundation
import InsightKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// **Backlog `I6` — arbitrary lab analytes, on device.**
///
/// The deterministic parser (`LabReportParser`) reads a report's simple layout
/// well: a label, a number, a unit, and the reference interval printed beside
/// it. Two things defeat it, and both are common:
///
/// - **A label the catalogue has no synonym for.** "Phosphatase, alkaline (bone
///   isoform)" is alkaline phosphatase, and the parser will store it under the
///   laboratory's own words — a second series the reader will never search for.
/// - **A column-major OCR.** Recognition of a multi-column table often emits
///   every label, then every value, so the parser sees rows of words with no
///   numbers and rows of numbers with no words.
///
/// Apple's on-device model is good at exactly those two jobs — naming and
/// pairing — and disqualified from every other one here.
///
/// ## The three rules this class exists to hold
///
/// 1. ⚠️ **The prompt never leaves the device.** `LanguageModelSession` is
///    Apple's on-device model. There is no other model call in this file, no
///    network client anywhere near it, and a report's text is never put in a
///    string that reaches `APIClient`. The reader's rule for this whole app is
///    that a photographed report is read on their phone; `I6` does not get an
///    exception for being clever.
/// 2. ⚠️ **The deterministic path must still work when the model is
///    unavailable.** Most devices cannot run it — an unsupported device, Apple
///    Intelligence switched off, a model still downloading — and on all of them
///    this returns exactly what the parser found. The model *adds*; it is never
///    the path.
/// 3. ⚠️ **The model never produces a number.** Everything it says is verified
///    against the recognised text by `LabModelVerifier`, which is pure and
///    tested on Linux: a value whose digits are not on the page is discarded.
///    See that type — the verification is not a nicety on top of the model, it
///    is the reason the model is allowed near a lab result at all.
@MainActor
final class LabAnalyteExtractor {

    /// Whether the on-device model can be used right now. Same shape as
    /// `FoundationModelSummarizer.isModelAvailable`, which is the pattern of
    /// record for this app.
    var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 15.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        #endif
        return false
    }

    /// What one document yielded, and how.
    struct Outcome {
        let results: [LabResult]
        /// Whether the model ran at all. Shown to the reader, because "the app
        /// read nine values" and "the app read nine values and a model found two
        /// more" are different claims.
        let modelRan: Bool
        /// Proposals the verification threw away, with the reason. Logged rather
        /// than shown: a reader does not need to know a model hallucinated, but
        /// whoever is debugging a missing value does.
        let refusals: [String]
    }

    /// Read a document's text into results.
    ///
    /// - Parameters:
    ///   - text: the recognised (or text-layer) characters of the document.
    ///   - source: how the document arrived, stamped on every result.
    ///   - importedAt: the date to fall back on when the report prints none.
    func extract(from text: String, source: LabResultSource,
                 importedAt: Date = Date()) async -> Outcome {
        let scan = LabReportParser.parseReport(text, source: source, importedAt: importedAt)

        // Rule 2: this is the answer on every device, and the model only ever
        // adds to it.
        guard isModelAvailable, !worthAsking(scan).isEmpty else {
            return Outcome(results: scan.results, modelRan: false, refusals: [])
        }

        let proposals = await propose(for: scan)
        guard !proposals.isEmpty else {
            return Outcome(results: scan.results, modelRan: true, refusals: [])
        }

        // Rule 3: nothing the model said is believed until it is found on the
        // page. `reconcile` also lets a rename *replace* the unnamed result
        // rather than sit beside it.
        let reconciled = LabModelVerifier.reconcile(proposals, with: scan, source: source)
        let refusals = reconciled.verdicts.compactMap { verdict -> String? in
            guard let refusal = verdict.refusal else { return nil }
            return "\(verdict.proposal.label): \(refusal)"
        }
        return Outcome(results: reconciled.results, modelRan: true, refusals: refusals)
    }

    /// What is left over for the model to look at.
    ///
    /// Only two things: lines the parser could not pair, and results it read but
    /// could not name. If a report is a clean two-column layout of catalogued
    /// analytes there is nothing here and the model is never started — which is
    /// the common case, and it keeps the fast path fast.
    private func worthAsking(_ scan: LabReportParser.Scan) -> [String] {
        var lines = scan.unpairedLines
        lines.append(contentsOf: scan.unrecognisedResults.compactMap { $0.evidence?.rawLine })
        return lines
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 15.0, *)
    private func session() -> LanguageModelSession {
        LanguageModelSession(instructions: LabModelVerifier.modelInstructions)
    }
    #endif

    /// Ask the model to name and pair, and hand its answer to the verifier.
    ///
    /// The response format and its parser both live in
    /// `LabModelVerifier.proposals(fromModelResponse:)`, where they are tested
    /// — the app target has no test host, and the prompt and the thing that
    /// polices its output are one design that must not be reviewed apart.
    private func propose(for scan: LabReportParser.Scan) async -> [LabModelVerifier.Proposal] {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 15.0, *) else { return [] }
        let candidateText = worthAsking(scan).joined(separator: "\n")
        guard !candidateText.isEmpty else { return [] }

        let prompt = """
        Below are lines from a pathology report that a rule-based parser could \
        not match to a known analyte. For each laboratory measurement you can \
        identify, output one line in exactly this format and nothing else:

        LABEL | ANALYTE_KEY_OR_BLANK | VALUE | UNIT_OR_BLANK | SOURCE_LINE

        LABEL and SOURCE_LINE must be copied character-for-character from the \
        text below. VALUE must be the digits exactly as they appear there — \
        never rounded, converted or reformatted. If you cannot find the value \
        in the text, omit the row. ANALYTE_KEY must be one of the keys listed, \
        or left blank if none of them is what this measurement is.

        Keys:
        \(LabModelVerifier.mappableKeys)

        Text:
        \(candidateText)
        """

        do {
            let response = try await session().respond(to: prompt)
            return LabModelVerifier.proposals(fromModelResponse: response.content)
        } catch {
            // Rule 2 again: any model error is silence, never a failure of the
            // import. The reader keeps everything the parser found.
            DiagnosticsLog.shared.null("Import", "On-device analyte model returned nothing")
            return []
        }
        #else
        return []
        #endif
    }

}
