import Foundation
import InsightKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns the computed, numeric insight results into a short, plain-language
/// "Today" summary — entirely on-device.
///
/// When Apple's on-device Foundation model is available (iOS 26+, Apple
/// Intelligence-capable device) it uses `LanguageModelSession`. Everywhere else
/// it falls back to a deterministic template, so the feature degrades gracefully
/// and never depends on the cloud. Numbers always come from the validated models
/// — the LLM only phrases them, it never invents values.
@MainActor
final class FoundationModelSummarizer {

    /// Whether the on-device model can be used right now.
    var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 15.0, *) {
            // `availability` carries an associated reason when unavailable, so
            // switch rather than compare for equality.
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        #endif
        return false
    }

    /// Produce a 1–2 sentence summary of today's insights.
    func summarize(results: [InsightResult]) async -> String {
        let factSheet = Self.factSheet(from: results)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 15.0, *), isModelAvailable {
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let prompt = """
                Summarise these health insights in two short sentences for the user's dashboard. \
                These are already the few that matter most today — say what is going well and \
                what is not, and do not rank them differently or add cards that are not listed. \
                Do not invent any numbers; only use the facts provided. Avoid medical advice or alarm.

                Facts:
                \(factSheet)
                """
                let response = try await session.respond(to: prompt)
                // The model occasionally emits Markdown (**bold**, bullets) even
                // when asked not to — strip it so the dashboard shows clean prose.
                let text = PlainText.strip(response.content)
                if !text.isEmpty { return text }
            } catch {
                // Fall through to the template on any model error.
            }
        }
        #endif

        return Self.templateSummary(from: results)
    }

    // MARK: - Fact sheet & fallback

    private static let instructions = """
    You are a concise, supportive health-dashboard assistant. You explain \
    pre-computed metrics in plain language. You never diagnose, never give \
    medical advice, never state numbers that aren't in the provided facts, and \
    you keep an even, non-alarming tone. Write plain text only — no Markdown, \
    no asterisks, no bullet points or headings.
    """

    /// **The model is given the selection, not the whole panel.**
    ///
    /// It used to receive every scored card, which meant the LLM did the
    /// ranking — a judgement about what matters most to someone's health, made
    /// by a text model, differently on each run and untestable because the app
    /// target has no test target. `DailyHighlights` makes that choice in
    /// InsightKit where it is covered, and the model's job is narrowed to
    /// phrasing what it is handed.
    static func factSheet(from results: [InsightResult]) -> String {
        let picked = Set(DailyHighlights.highlights(from: results).map(\.id))
        return results.compactMap { r in
            guard picked.contains(r.id) else { return nil }
            return "- \(r.title): \(r.headline) [confidence: \(r.confidence.rawValue)]"
        }.joined(separator: "\n")
    }

    static func templateSummary(from results: [InsightResult]) -> String {
        DailyHighlights.summary(from: results)
    }
}
