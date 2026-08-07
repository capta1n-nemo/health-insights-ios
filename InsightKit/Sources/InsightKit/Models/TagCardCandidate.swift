import Foundation

/// **A tag that could feed a card, held back until somebody reviews it.**
///
/// The reader's instruction, 2026-08-07, and the reason this type exists rather
/// than a wire: activity-related tags *"become candidates for cards at the next
/// review"* — **not** inputs. Backlog `B12-3`.
///
/// ## Why "candidate" is a real state and not a euphemism
///
/// A tag is self-reported free text. Nothing measured it, nothing validated it,
/// and its category was decided by a stem match or by a language model reading
/// one word out of context. Feeding that into a Fitness score would put an
/// unfalsifiable number into a figure the reader is asked to trust — and it
/// would do it silently, which is the part that makes it indefensible. The gap
/// between *"we can see this is about kayaking"* and *"kayaking should move your
/// fitness score"* is a judgement about the reader's own life, and it is theirs.
///
/// ## What this type therefore is, and is not
///
/// It is **a review queue with a memory**: the candidates, what each could
/// contribute to, and what the reader said about it. It carries no `InsightID`,
/// no `MetricType`, no weight and no number. There is deliberately nothing here
/// a scoring path could read even by mistake — `TagCardCandidateDecision` is a
/// note to whoever builds the thing, not a switch that builds it.
///
/// ⚠️ **A reader answering "yes, count this" does not make it count.** The
/// surface says so in as many words, because a review UI that looks like a
/// toggle and behaves like a suggestion box is worse than no review UI: the
/// reader would believe their kayaking was in the score.
public struct TagCardCandidate: Sendable, Hashable, Identifiable {
    /// The distinct tag, with its occurrence count and dates.
    public let summary: TagSummary
    /// Where it *could* contribute — the same prose
    /// `TagApplicability.candidateNote` prints on the Tags page, kept in one
    /// place so the two surfaces can never disagree about what is on offer.
    public let candidateNote: String
    /// What the reader has said about it, if anything.
    public let decision: TagCardCandidateDecision

    public var id: String { summary.key }
    public var applicability: TagApplicability { summary.mapping.applicability }

    public init(summary: TagSummary, candidateNote: String,
                decision: TagCardCandidateDecision) {
        self.summary = summary
        self.candidateNote = candidateNote
        self.decision = decision
    }

    /// **Every candidate, most-used first, with the reader's answer attached.**
    ///
    /// Only tags whose category actually names a card are candidates — a "Travel"
    /// tag is not withheld from anything, so listing it in a review queue would
    /// be asking the reader to adjudicate a question nobody has.
    ///
    /// ⚠️ `.unclassified` is excluded on purpose. The app has not worked out what
    /// the tag is about, so asking whether it should count towards Fitness is
    /// asking the reader to answer a question the app has not managed to *pose*.
    /// Those tags belong on the Tags page, where the reader can place them first.
    public static func candidates(from summaries: [TagSummary],
                                  decisions: TagCandidateDecisionStore = TagCandidateDecisionStore())
    -> [TagCardCandidate] {
        summaries.compactMap { summary -> TagCardCandidate? in
            guard let note = summary.mapping.applicability.candidateNote else { return nil }
            return TagCardCandidate(summary: summary, candidateNote: note,
                                    decision: decisions.decision(for: summary.key))
        }
        .sorted {
            $0.summary.count == $1.summary.count
                ? $0.summary.lastUsed > $1.summary.lastUsed
                : $0.summary.count > $1.summary.count
        }
    }

    /// ⚠️ **The invariant this whole file is for, stated so a test can hold it.**
    ///
    /// Nothing in the app reads a candidate decision to change a score, a weight
    /// or a card's inputs. If that ever stops being true it stops being true here
    /// first, deliberately and with the reader's agreement — not as a side effect
    /// of somebody wiring a convenient boolean.
    public static let isWiredToAnyCard = false
}

/// **What the reader said about a candidate at review.**
///
/// Three states rather than a `Bool`, because "not looked at yet" is a real and
/// common answer and collapsing it into "no" would let the app claim the reader
/// declined something they never saw.
public enum TagCardCandidateDecision: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// The default. Nobody has been asked.
    case notReviewed
    /// *"Yes — this should count towards that card."* **A note, not a wire.**
    case shouldCount
    /// *"No — leave this out."* Equally a note: nothing was including it.
    case shouldNotCount

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notReviewed: return "Not reviewed"
        case .shouldCount: return "Should count"
        case .shouldNotCount: return "Leave it out"
        }
    }

    /// The honest one-liner under the control. Every one of these says plainly
    /// that nothing has changed, because nothing has.
    public var detail: String {
        switch self {
        case .notReviewed:
            return "You haven't said either way. Nothing is using this tag."
        case .shouldCount:
            return "Noted for the next review. It still isn't being used — wiring a tag into a score is a change to the app, not a setting."
        case .shouldNotCount:
            return "Noted. It wasn't being used, and now it won't be proposed again."
        }
    }

    public var symbolName: String {
        switch self {
        case .notReviewed: return "circle.dashed"
        case .shouldCount: return "checkmark.circle"
        case .shouldNotCount: return "minus.circle"
        }
    }
}

/// The reader's answers, keyed by `HealthTag.key`, persisted by the app.
///
/// Keyed by tag rather than by occurrence for the same reason `TagMappingStore`
/// is: reviewing "Kayaking" once covers every kayaking session, including the
/// ones that sync next month.
public struct TagCandidateDecisionStore: Codable, Sendable, Equatable {
    private var decisions: [String: TagCardCandidateDecision]

    public init(decisions: [String: TagCardCandidateDecision] = [:]) {
        self.decisions = decisions
    }

    public var isEmpty: Bool { decisions.isEmpty }

    public func decision(for key: String) -> TagCardCandidateDecision {
        decisions[key] ?? .notReviewed
    }

    /// Last answer wins, and `.notReviewed` erases rather than stores — there is
    /// no evidence to weigh here, only what the reader last said.
    public mutating func set(_ decision: TagCardCandidateDecision, for key: String) {
        if decision == .notReviewed {
            decisions.removeValue(forKey: key)
        } else {
            decisions[key] = decision
        }
    }

    /// How many candidates still have no answer, out of the ones on offer.
    public func unreviewedCount(among candidates: [TagCardCandidate]) -> Int {
        candidates.filter { decision(for: $0.summary.key) == .notReviewed }.count
    }
}
