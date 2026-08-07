import Foundation
import InsightKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// **One day's summary, phrased on-device** — backlog `B11-2`, the reader's
/// *"an AI summary for that day"*.
///
/// The same contract `FoundationModelSummarizer` already holds and for the same
/// reason it was narrowed: **the numbers come from the validated models and the
/// model only phrases them.** The fact sheet is built in InsightKit
/// (`SickDayReport.factSheet`), where it is covered by tests the app target
/// cannot have — including the one that fails the build if the prompt ever names
/// a symptom.
///
/// ⚠️ **Never awaited on a path that reports work finished.** Repo rule 11, and
/// the defect behind it cost the reader every card on 2026-08-07 (D62). This is
/// called from a view's `.task` and its caller has already rendered
/// `SickDayReport.templateSummary`, so the page is complete and readable whether
/// this returns in a second, in a minute, or never.
///
/// ⚠️ **The instructions forbid the two things the evidence forbids.** No kind
/// of illness may be named that the facts do not already name, and a quiet
/// reading may never be phrased as reassurance —
/// `docs/illness-detection-evidence-2026-08-07.md` puts roughly two-thirds of
/// genuine infections outside these signals entirely, so "your readings look
/// fine" is a false comfort rather than a summary.
@MainActor
final class DaySummarizer {
    static let shared = DaySummarizer()

    private init() {}

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

    /// A one-to-two sentence account of the day, or the deterministic template
    /// where no model is available. **Never nil and never empty** — a page
    /// waiting on a model it may not have is a page with a hole in it.
    func summarize(report: SickDayReport) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 15.0, *), isModelAvailable {
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let prompt = """
                Summarise this one day for the reader in at most two short sentences. \
                Use only the facts listed. Do not invent numbers. Do not name any \
                illness, condition or pathogen that is not already in the facts. \
                Do not reassure: quiet readings are not evidence of health, and \
                saying so would be false. Plain text only.

                Facts:
                \(report.factSheet)
                """
                let response = try await session.respond(to: prompt)
                let text = PlainText.strip(response.content)
                if !text.isEmpty { return text }
            } catch {
                // Fall through to the template on any model error — the same
                // posture the Today summary takes, and the reason the template
                // is written first rather than as a fallback afterthought.
            }
        }
        #endif
        return report.templateSummary
    }

    private static let instructions = """
    You are a careful, plain-spoken health-log assistant summarising a single \
    past day for the person whose day it was. You explain pre-computed numbers \
    in plain language. You never diagnose, never name a condition, never give \
    medical advice, never state numbers that are not in the provided facts, and \
    you never present an absence of signal as good news. Write plain text only \
    — no Markdown, no asterisks, no bullet points or headings.
    """
}
