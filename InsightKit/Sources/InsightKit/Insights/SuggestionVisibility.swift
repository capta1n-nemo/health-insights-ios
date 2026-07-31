import Foundation

/// A suggestion the user has waved away, and when.
public struct SuggestionDismissal: Sendable, Equatable, Codable, Identifiable {
    public let suggestionID: String
    public let dismissedAt: Date

    public init(suggestionID: String, dismissedAt: Date) {
        self.suggestionID = suggestionID
        self.dismissedAt = dismissedAt
    }

    public var id: String { suggestionID }
}

/// Which suggestions each surface may show, given what the user has dismissed.
///
/// `SuggestionEngine` decides what is *true*. This decides what is *worth
/// saying again*, which is a different question and the one the app was missing
/// entirely: suggestions were generated, ranked, and then shown unconditionally
/// forever, with no way to put one down.
///
/// ## "Completed" needs no per-suggestion definition
///
/// The obvious design is for each suggestion to declare what finishing it means,
/// and it would need three different answers — a grounding gap closes when the
/// fact is entered, a departure closes when the signal comes back, and a
/// contrast drawn from the user's own history never closes at all, because it is
/// an observation rather than a task.
///
/// None of that is necessary. **The engine only emits a suggestion while its
/// condition holds**, so a suggestion disappearing from the engine's output *is*
/// it being resolved — by any of the three routes, without this type knowing
/// which. So the rule is simply: a dismissal for something no longer being
/// suggested is dead, and gets pruned.
///
/// ## Why Today and Insights differ
///
/// Today answers "how am I right now" and is the screen a person opens twenty
/// times a week; a suggestion that will not go away there is nagging. Insights
/// is the screen you go to on purpose, so it keeps the whole list — dismissed
/// entries included — as the persistent reminder the user asked for.
public enum SuggestionVisibility {

    /// How long a dismissal keeps a suggestion off Today.
    ///
    /// Thirty days. Long enough that waving something away means something, and
    /// short enough that a fact still missing after a month is worth raising
    /// once more — a suggestion silenced forever is indistinguishable from one
    /// that was never generated.
    public static let dismissalLifetime: TimeInterval = 30 * 86_400

    /// How many suggestions Today may show at once.
    ///
    /// One. Today is a glance, and the ranking already says which one is
    /// best-founded. The full list is one tap away on Insights.
    public static let todayLimit = 1

    /// One suggestion as the Insights list sees it.
    public struct Row: Sendable, Equatable, Identifiable {
        public let suggestion: Suggestion
        /// Dismissed and still inside its thirty days.
        public let isDismissed: Bool
        public var id: String { suggestion.id }
    }

    public struct Resolved: Sendable, Equatable {
        /// What Today may show, best-founded first, already capped.
        public let today: [Suggestion]
        /// Everything currently true, dismissed or not, best-founded first.
        public let insights: [Row]
        /// Dismissal ids that no longer correspond to anything the engine is
        /// saying. The caller should delete these — see the note above; this is
        /// what "hide it once the associated tasks are done" reduces to.
        public let resolvedDismissals: [String]
    }

    public static func resolve(suggestions: [Suggestion],
                               dismissals: [SuggestionDismissal],
                               now: Date = Date()) -> Resolved {
        let live = Set(suggestions.map(\.id))
        var silencedUntil: [String: Date] = [:]
        var resolved: [String] = []
        for dismissal in dismissals {
            guard live.contains(dismissal.suggestionID) else {
                resolved.append(dismissal.suggestionID)
                continue
            }
            let expires = dismissal.dismissedAt.addingTimeInterval(dismissalLifetime)
            // Keep the *latest* dismissal if somehow there are two — dismissing
            // again should extend the silence, never shorten it.
            if let held = silencedUntil[dismissal.suggestionID], held >= expires { continue }
            silencedUntil[dismissal.suggestionID] = expires
        }

        let rows = suggestions.map { suggestion in
            Row(suggestion: suggestion,
                isDismissed: silencedUntil[suggestion.id].map { $0 > now } ?? false)
        }
        return Resolved(
            today: rows.filter { !$0.isDismissed }.prefix(todayLimit).map(\.suggestion),
            insights: rows,
            resolvedDismissals: resolved)
    }
}
