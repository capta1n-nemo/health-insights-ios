import Foundation

/// Which band a 0–100 score falls in.
///
/// Defined here rather than in the app's `Theme` because two things now read it
/// — the dial's colour and the Today summary's wording — and a card drawn amber
/// while the prose calls it good is the kind of disagreement nobody notices
/// until a reader does. `Theme.color(forScore:)` switches on this.
public enum ScoreBand: Sendable, Equatable {
    case good, fair, poor

    public static let fairFloor: Double = 45
    public static let goodFloor: Double = 70

    public init(score: Double) {
        switch score {
        case Self.goodFloor...: self = .good
        case Self.fairFloor..<Self.goodFloor: self = .fair
        default: self = .poor
        }
    }
}

/// The Today card's opening paragraph: **what is going well, what is not, and
/// anything that cannot wait.**
///
/// The reader, 2026-08-05: *"what you're doing very well and very poorly, and
/// any overall insights that are most important. like, hey! looks like you're
/// about to get sick."*
///
/// What it replaced enumerated every scored card in registry order:
///
/// > Here's your snapshot — readiness is Take it easy, symptom radar is Nothing
/// > stirring, sleep is Poor, energy is 85 · High, heart health is Fair, fitness
/// > is Needs work, heart attack & stroke risk is 0.7%, blood pressure is
/// > 144/88, and body composition is Body fat 30.6%.
///
/// Nine clauses of equal weight is a list, not a summary — the reader has to do
/// the ranking the card exists to do for them. It also read badly, because
/// `"\(title.lowercased()) is \(headline)"` assumes every headline is a
/// predicate and several are values: *"body composition is Body fat 30.6%"* was
/// the reader's own example.
///
/// **This lives in InsightKit, and the LLM path does not replace it.** The app
/// target has no test target, so selection logic written there cannot be tested
/// at all; the on-device model still phrases the fact sheet when it is
/// available, but *which* facts reach the sheet is decided here and is covered.
public enum DailyHighlights {

    /// The line shown when nothing can be scored yet.
    public static let emptyState =
        "Connect your data and add a few details to start seeing your health insights."

    /// One card, reduced to the clause the summary would use for it.
    ///
    /// Exposed so the fact sheet handed to the on-device model carries the same
    /// selection the deterministic text does — otherwise the two paths tell the
    /// reader different things depending on which device they opened.
    public struct Highlight: Sendable, Equatable {
        public let id: InsightID
        public let title: String
        public let headline: String
        public let score: Double
        public var band: ScoreBand { ScoreBand(score: score) }
    }

    /// The cards worth leading with, in the order they should be read.
    ///
    /// At most three, and never the same card twice. The order is a claim about
    /// what the reader needs first, not about the scores:
    ///
    /// 1. **Anything in the poor band**, worst first — the "about to get sick"
    ///    slot. A card the app is worried about outranks a card doing well.
    /// 2. **The best card**, so the summary is not only bad news.
    /// 3. **The weakest of the rest**, which is where the effort goes.
    public static func highlights(from results: [InsightResult]) -> [Highlight] {
        let scored = results.compactMap { r -> Highlight? in
            guard let score = r.score, !r.headline.isEmpty else { return nil }
            return Highlight(id: r.id, title: r.title, headline: r.headline, score: score)
        }
        guard !scored.isEmpty else { return [] }

        let byScore = scored.sorted { $0.score < $1.score }
        var picked: [Highlight] = []
        func add(_ h: Highlight?) {
            guard let h, !picked.contains(where: { $0.id == h.id }) else { return }
            picked.append(h)
        }

        // Worst-first among the genuinely poor. Two is the cap: a reader whose
        // whole panel is red is not helped by being told so five times, and the
        // cards are all one tap away.
        for poor in byScore.filter({ $0.band == .poor }).prefix(2) { add(poor) }
        // **The best — but a detector is never "best".** The symptom radar at
        // 100 means nothing was detected, and the card itself says in as many
        // words that quiet is not an all-clear: the published validation of this
        // approach catches 43% of confirmed illnesses at 95% specificity.
        // Opening the day with "looking best today: symptom radar — nothing
        // stirring" would contradict the card one tap away, and it is the same
        // ruling that took the radar off the comparison web on 2026-08-04
        // ("a detector is not a score"). It can still *lead* when it is not
        // quiet, which is the state the reader actually wants surfaced.
        add(byScore.last { $0.id != .symptomRadar })
        // The weakest still unmentioned — not simply the weakest, which is
        // often the card already leading, and then the reader hears about two
        // things instead of three.
        add(byScore.first { h in !picked.contains(where: { $0.id == h.id }) })
        return Array(picked.prefix(3))
    }

    /// The deterministic summary paragraph.
    public static func summary(from results: [InsightResult]) -> String {
        let picked = highlights(from: results)
        guard !picked.isEmpty else { return emptyState }

        var sentences: [String] = []
        for (index, h) in picked.enumerated() {
            sentences.append(sentence(for: h, position: index, of: picked.count))
        }
        sentences.append("Tap any card for what's driving it.")
        return sentences.joined(separator: " ")
    }

    /// One card's clause.
    ///
    /// **The headline is attached with a dash, never with "is".** Some headlines
    /// are verdicts ("Take it easy") and some are values ("Body fat 30.6%"), and
    /// only one of those survives being made the complement of a copula. A dash
    /// reads correctly for both, which is why the phrasing is uniform rather
    /// than switched on the card.
    static func sentence(for h: Highlight, position: Int, of total: Int) -> String {
        let lead: String
        switch (position, h.band) {
        case (0, .poor):
            lead = "Worth a look today: \(h.title)"
        case (0, _):
            lead = "Looking best today: \(h.title)"
        case (_, .poor):
            lead = "Also low: \(h.title)"
        case (_, .good):
            lead = "Doing well: \(h.title)"
        default:
            lead = "Most room to move: \(h.title)"
        }
        return "\(lead) — \(h.headline.lowercasedFirstWordIfVerdict), \(Int(h.score.rounded())) out of 100."
    }
}

private extension String {
    /// A headline that is a sentence-cased verdict ("Take it easy", "Needs
    /// work") reads better mid-clause in lower case; one carrying a figure or a
    /// proper noun ("Body fat 30.6%", "144/88") must be left alone.
    ///
    /// The test is whether the headline contains a digit — a value headline
    /// always does, and none of the verdicts do.
    var lowercasedFirstWordIfVerdict: String {
        guard !contains(where: \.isNumber), let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
