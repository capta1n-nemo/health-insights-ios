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
                Summarise these health insights in two short, encouraging sentences for the user's dashboard. \
                Do not invent any numbers; only use the facts provided. Avoid medical advice or alarm.

                Facts:
                \(factSheet)
                """
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
    you keep an even, non-alarming tone.
    """

    static func factSheet(from results: [InsightResult]) -> String {
        results.compactMap { r in
            guard r.primaryValue != nil || r.score != nil else { return nil }
            return "- \(r.title): \(r.headline) [confidence: \(r.confidence.rawValue)]"
        }.joined(separator: "\n")
    }

    static func templateSummary(from results: [InsightResult]) -> String {
        let available = results.filter { $0.primaryValue != nil || $0.score != nil }
        guard !available.isEmpty else {
            return "Connect your data and add a few details to start seeing your heart-health insights."
        }
        let parts = available.map { "\($0.title.lowercased()) is \($0.headline)" }
        let joined = ListFormatter.localizedString(byJoining: parts)
        return "Here's your snapshot — \(joined). Tap any card for what's driving it."
    }
}
