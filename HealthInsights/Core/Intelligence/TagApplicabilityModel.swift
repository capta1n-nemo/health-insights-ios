import Foundation
import InsightKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// **Working out what a tag the app has never seen before is about — on the
/// phone, and only on the phone.**
///
/// ## Why a model at all
///
/// `TagLexicon` places a tag by matching word stems, which covers inflections
/// and compounds of words somebody thought of. It cannot cover a word nobody
/// thought of — "wing foiling", "padel-tennis social", a tag in another
/// language, a private shorthand — and Oura lets a person invent any of those.
/// The reader's requirement was explicit: *"when they are imported, in the data
/// section we use AI to map them to relevant high-level categories"*.
///
/// ## The three rules this file exists to keep
///
/// 1. **The prompt never leaves the device.** `FoundationModels` runs Apple's
///    on-device model; there is no network call in this file and no API client
///    is imported. A tag is the reader's own words about their own day, and the
///    app's whole premise is that such things stay on the phone.
/// 2. **The deterministic path must work without it.** `SystemLanguageModel` is
///    unavailable on most hardware this app runs on, and unavailable on *any*
///    hardware with Apple Intelligence switched off. So this type is a
///    *refinement* asked after `TagLexicon` has already answered — never the
///    only answer. `isAvailable` returning false is an ordinary state, not a
///    degraded one, and nothing in the Tags page is empty because of it.
/// 3. **The model chooses; it does not invent.** Its reply is matched against
///    `TagApplicability.classifiable` and anything else becomes
///    `.unclassified`. A model that returns "Watersports" has not named a
///    category this app has, and inventing one to accommodate it would put a
///    heading in the Data tab that no other part of the app understands.
///
/// ## And what it deliberately does not do
///
/// It does not wire anything to a card. The reader was explicit that
/// activity-related tags *"become candidates for cards at the next review"* —
/// see `TagApplicability.candidateNote`, which is prose rather than an
/// `InsightID` for exactly that reason, and `TagCardCandidate`, which is where
/// that review happens and which carries no weight, no metric and no card id.
///
/// It also does not decide anything the reader has already decided: a `.reader`
/// mapping outranks everything here, and this type is never asked about a tag
/// the reader has placed themselves.
@MainActor
final class TagApplicabilityModel {

    /// Whether the on-device model can be used right now. Mirrors
    /// `FoundationModelSummarizer.isModelAvailable` — same switch-don't-compare
    /// treatment of `availability`, which carries a reason when unavailable.
    var isAvailable: Bool {
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

    /// How many tags one pass will ask about.
    ///
    /// A first sync can bring in a hundred distinct tags at once, and asking the
    /// model about all of them would spend battery on a screen the reader may
    /// not even open. Callers pass them **most-used first**, so a cap means the
    /// tags that matter are placed on the first pass and the long tail resolves
    /// over later ones. Nothing is lost by waiting: an unresolved tag still
    /// appears, still counts, and still says plainly that it is unplaced.
    static let perPassLimit = 12

    /// What one pass learned. **Two lists, not one**, because "placed it" and
    /// "asked and got nowhere" are different facts and only the first used to be
    /// carried back.
    struct Pass: Sendable {
        /// The tags it actually placed, keyed by `HealthTag.key`.
        var placed: [String: TagApplicabilityMapping] = [:]
        /// The tags it answered about and named no category for — a settled
        /// "I don't know", to be remembered so the queue can move on. **Never a
        /// thrown call**: see `Outcome`.
        var declined: Set<String> = []

        var isEmpty: Bool { placed.isEmpty && declined.isEmpty }
    }

    /// Ask the model about the tags the deterministic tiers could not place.
    ///
    /// - Parameters:
    ///   - summaries: distinct tags, **most-used first**.
    ///   - alreadyDeclined: tag keys the model has answered about before and
    ///     could not place. ⚠️ **Skipping these is not an optimisation — it is
    ///     the only thing that lets the queue advance.** Without it the same
    ///     dozen unplaceable tags sit at the head of `wantsModelReview` on every
    ///     launch and the thirteenth tag is never asked at all, so a reader with
    ///     twenty invented tags has some the model has never once seen. It also
    ///     stops the app spending battery re-asking a question it has already had
    ///     the answer to.
    /// - Returns: an empty `Pass` is the correct and common answer — no model on
    ///   this device, or nothing left worth asking about.
    func resolve(_ summaries: [TagSummary],
                 alreadyDeclined: Set<String> = []) async -> Pass {
        let wanted = summaries
            .filter { $0.mapping.wantsModelReview && !alreadyDeclined.contains($0.key) }
            .prefix(Self.perPassLimit)
        guard !wanted.isEmpty, isAvailable else { return Pass() }

        var out = Pass()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 15.0, *) {
            for summary in wanted {
                switch await ask(about: summary) {
                case .placed(let mapping): out.placed[summary.key] = mapping
                case .declined: out.declined.insert(summary.key)
                // ⚠️ Deliberately dropped rather than recorded. A throw is Apple
                // Intelligence being switched off mid-pass, a guardrail, a
                // timeout — all transient, and remembering one would retire a
                // tag permanently over a momentary failure.
                case .failed: break
                }
            }
        }
        #endif
        return out
    }

    // MARK: - One tag

    /// **The three ways asking about one tag can end**, kept apart because two of
    /// them used to be the same `nil` and the caller could not tell a settled
    /// "I don't know" from a call that never happened.
    enum Outcome: Sendable {
        case placed(TagApplicabilityMapping)
        /// The model replied and named nothing this app has a category for.
        case declined
        /// The call threw. Says nothing about the tag.
        case failed
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 15.0, *)
    private func ask(about summary: TagSummary) async -> Outcome {
        do {
            // A fresh session per tag rather than one session per pass: a shared
            // transcript lets an earlier answer bias a later one, and these are
            // independent questions about unrelated words. A wrong answer should
            // cost one tag, not the rest of the batch.
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: Self.prompt(for: summary))
            let reply = PlainText.strip(response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // The model answered. If it named nothing this app has — including
            // its own "Not yet classified" escape hatch — that is a real answer
            // and the caller records it, so the tag stops blocking the queue.
            guard let applicability = Self.category(named: reply) else { return .declined }
            return .placed(TagApplicabilityMapping(
                applicability: applicability,
                method: .onDeviceModel,
                // **Deliberately below every lexicon hit's ceiling and well
                // below a provider code's.** Standing rule 6 — every estimate
                // states its own uncertainty — and this is the least certain
                // tier there is: a language model reading one word out of
                // context, with nothing to check it against.
                confidence: 0.45,
                rationale: "Worked out on this device by the on-device model, from the words “\(summary.name)”. Nothing checked it, so correct it if it is wrong."))
        } catch {
            // Any model error — unavailable mid-flight, guardrail, timeout —
            // leaves the tag exactly as the lexicon left it. Silence here is the
            // designed behaviour, not a swallowed failure: the caller's fallback
            // is a complete answer already. ⚠️ And it is `.failed` rather than
            // `.declined`: a transient failure must not be remembered as the
            // model's verdict on the word.
            return .failed
        }
    }

    private static let instructions = """
    You classify short personal tags a person put on a day in a health app. You \
    answer with exactly one category name from the list you are given, copied \
    character for character, and nothing else — no explanation, no punctuation, \
    no Markdown. If none of the categories fits, answer exactly: Not yet classified.
    """

    private static func prompt(for summary: TagSummary) -> String {
        let options = TagApplicability.classifiable
            .map { "- \($0.rawValue): \($0.summary)" }
            .joined(separator: "\n")
        return """
        Tag: "\(summary.name)"

        Which one of these categories is that tag about?

        \(options)

        Answer with one category name exactly as written above, or "Not yet classified".
        """
    }
    #endif

    /// Match a reply to a category. **Exact-name matching after folding**, and
    /// nothing cleverer: a fuzzy match is how "Not yet classified" would end up
    /// being read as a real category because it shares a word with one.
    static func category(named reply: String) -> TagApplicability? {
        let normalised = reply
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: " &")))
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
        guard let match = TagApplicability.classifiable.first(where: {
            $0.rawValue.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                locale: Locale(identifier: "en_US_POSIX")) == normalised
        }) else { return nil }
        return match
    }
}
