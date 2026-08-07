import Foundation

/// **How much more is needed, and how far along you are.**
///
/// The reader, 2026-08-06: *"it needs to be mentioned appropriately for
/// transparency, so users know why things are - or are not showing in the
/// app."* Backlog D46.
///
/// ## The problem this exists to stop
///
/// This app withholds a figure whenever the data under it is too thin — which
/// is right, and is most of what makes it trustworthy. But a withheld figure
/// and an absent one look identical from the outside: the reader sees nothing
/// and cannot tell *"there is no data"* from *"there is not enough data yet"*.
/// **Only the second is a reason to keep going**, and it is the one the app was
/// failing to say.
///
/// One place already did it right and the reader singled it out approvingly —
/// the calendar review section's *"It needs 10 before that figure means
/// anything"* — and `CycleModel.lengthSentence` does the same. Everywhere else
/// a gate was a bare `nil`. This is that sentence, made into a type so a new
/// gate has to produce one.
///
/// ## Why a type rather than a convention
///
/// A convention would be honoured by whoever remembered it. A model that
/// returns `CoverageGate?` alongside its output cannot withhold a figure
/// without also saying what it is waiting for — the same reason `DataDomain`
/// and `InputKind` are enums rather than lists in a comment.
///
/// ⚠️ **A met gate says nothing.** `sentence` is nil once the requirement is
/// satisfied. A card that keeps mentioning a threshold it has already cleared
/// is nagging, and this app does not nag — `SuggestionEngine` already ranks
/// "a feature you haven't tried" below every grounding gap for the same reason.
public struct CoverageGate: Sendable, Equatable, Hashable {

    /// How many are needed before the figure is offered.
    public let need: Int
    /// How many there are.
    public let have: Int
    /// What is being counted, **singular** — "worn day", "complete cycle",
    /// "marker", "reviewed event". Pluralised where used.
    public let unit: String
    /// What becomes possible once it is met, as a clause that follows "and".
    ///
    /// Written from the reader's side: *"this can describe the range yours
    /// actually falls in"*, not *"the model can compute a range"*. What the
    /// app gains is not the point; what they gain is.
    public let unlocks: String

    public init(need: Int, have: Int, unit: String, unlocks: String) {
        self.need = need
        self.have = have
        self.unit = unit
        self.unlocks = unlocks
    }

    public var isMet: Bool { have >= need }
    public var remaining: Int { Swift.max(0, need - have) }

    /// A fraction for a progress indicator, capped at 1.
    public var progress: Double {
        guard need > 0 else { return 1 }
        return Swift.min(1, Double(have) / Double(need))
    }

    private func plural(_ count: Int) -> String {
        count == 1 ? unit : SectionCaveat.plural(count, unit)
    }

    /// The line to show where the figure would have been. `nil` once met.
    ///
    /// Three shapes, because "none yet" and "nearly there" are different
    /// messages and collapsing them into one loses the encouraging half:
    ///
    /// - nothing yet — say what to start doing, and what it will buy;
    /// - some — say **how many more**, which is the number that makes someone
    ///   carry on;
    /// - met — say nothing at all.
    public var sentence: String? {
        guard !isMet else { return nil }
        if have == 0 {
            return "Nothing recorded yet. This needs \(need) \(plural(need)), and then \(unlocks)."
        }
        return "\(have) of \(need) \(plural(need)) so far — \(remaining) more and \(unlocks)."
    }

    /// The same thing in a few words, for a row's trailing slot or a chip.
    public var shortLabel: String? {
        isMet ? nil : "\(have)/\(need)"
    }
}

public extension CoverageGate {

    /// Build one only where it bites — `nil` when the requirement is met, so a
    /// caller can write `gate: .ifShort(...)` and get silence for free.
    static func ifShort(need: Int, have: Int, unit: String,
                        unlocks: String) -> CoverageGate? {
        let gate = CoverageGate(need: need, have: have, unit: unit, unlocks: unlocks)
        return gate.isMet ? nil : gate
    }
}
