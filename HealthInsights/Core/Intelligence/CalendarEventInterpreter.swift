import Foundation
import InsightKit
// ⚠️ **Guarded, exactly as `FoundationModelSummarizer` guards it.** CI's runner
// SDK has no `FoundationModels`, so a bare import is a red build — and it was:
// this file cost this session its only red CI. The whole point of the module is
// that it may be absent, so importing it unconditionally contradicts the
// design as well as breaking the gate.
#if canImport(FoundationModels)
import FoundationModels
#endif

/// **The AI half of reading a calendar** — backlog §B6 C6.
///
/// The reader asked for the on-device model to read their events. It does, and
/// it is asked about exactly two things: **work versus personal on a title the
/// rules could not settle, and the sentiment of the meeting.**
///
/// ## Why only two
///
/// The other four axes are facts. Duration is subtraction, "did it have a
/// location" is a field being present, "was there a link" is a boolean the app
/// already derived, and travel placeholders are formulaic. Asking a language
/// model about any of those would be slower, non-deterministic and *less*
/// accurate than reading them — and would put a hallucination between the reader
/// and something their own calendar stated plainly.
///
/// `CalendarEventClassifier.refined` enforces the boundary rather than trusting
/// this file to respect it: a model answer for a context the calendar's own name
/// settled is discarded, and a test holds that.
///
/// ## ⚠️ The privacy shape
///
/// `SystemLanguageModel` runs **on device**. There is no network path here and
/// there must never be one: an event title is the most identifying string this
/// app holds. Nothing in this file logs, exports or persists the prompt.
///
/// On hardware without the model — which is most of it — `interpret` returns nil
/// and the deterministic classification stands unchanged. That is a degraded
/// answer, not a broken one, which is the same contract `FoundationModelSummarizer`
/// already keeps.
@MainActor
final class CalendarEventInterpreter {

    struct Reading: Sendable {
        let context: CalendarEventClassification.Context?
        let formality: CalendarEventClassification.Formality?
    }

    private static let instructions = """
        You classify one calendar entry for a personal health app. Answer only \
        about the two axes asked for. Reply with exactly two lines and nothing \
        else:
        CONTEXT: work | personal | unknown
        TONE: casual | standard | formal

        CONTEXT is whether the entry belongs to the person's working life or \
        their private life. Answer unknown when the title genuinely does not say.
        TONE is how formal the occasion is: casual for a catch-up, a coffee or a \
        one-to-one; formal for a client meeting, a board meeting, an interview \
        or a review; standard otherwise.
        """

    private var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        #endif
        return false
    }

    /// Nil when the model is unavailable, the title is empty, or the reply
    /// cannot be parsed — in every one of those cases the rules stand.
    func interpret(_ event: CalendarEvent) async -> Reading? {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, !title.isEmpty else { return nil }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }

        // Only the title and the calendar's name are sent. Not the location,
        // not the notes — neither is needed for these two questions, and a
        // prompt should carry the least that answers it.
        let prompt = "Calendar: \(event.calendarName)\nEntry: \(title)"
        let session = LanguageModelSession(instructions: Self.instructions)
        guard let response = try? await session.respond(to: prompt) else { return nil }
        return Self.parse(response.content)
        #else
        return nil
        #endif
    }

    /// Parsed strictly. **An unparseable reply yields nil rather than a
    /// default** — a model that answered oddly must not be silently recorded as
    /// having said "standard", because the `Decider` on that field would then
    /// claim the model decided something it did not.
    static func parse(_ text: String) -> Reading? {
        var context: CalendarEventClassification.Context?
        var formality: CalendarEventClassification.Formality?
        for line in text.lowercased().split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("context:") {
                context = CalendarEventClassification.Context(
                    rawValue: trimmed.replacingOccurrences(of: "context:", with: "")
                        .trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("tone:") {
                formality = CalendarEventClassification.Formality(
                    rawValue: trimmed.replacingOccurrences(of: "tone:", with: "")
                        .trimmingCharacters(in: .whitespaces))
            }
        }
        guard context != nil || formality != nil else { return nil }
        return Reading(context: context, formality: formality)
    }
}
