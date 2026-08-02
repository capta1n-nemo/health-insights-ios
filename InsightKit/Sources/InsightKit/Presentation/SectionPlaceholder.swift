import Foundation

/// What a card section says when it has nothing to show.
///
/// ## Why an empty section is drawn at all
///
/// Every section on `InsightDetailView` used to disappear when its data didn't
/// clear a floor — and the floors are high, so on a card with a couple of
/// signals most of the screen simply wasn't there. **A section that vanishes is
/// an absence the reader cannot read.** "Score over time" missing means one of:
///
/// - the 90-day replay hasn't finished yet,
/// - no day has had two of this card's signals recording at once,
/// - exactly one day has.
///
/// Only a person holding the source could tell those apart, and the third is a
/// day away from fixing itself while the first fixes itself in a second. The
/// same is true of every other section here: "Patterns worth a look" absent
/// means *no data*, *not enough overlapping days*, or *nothing stood out* — and
/// only the last of those is reassuring.
///
/// So the sections always render, and this is what they render instead.
///
/// ## Why the reason is computed rather than written once
///
/// "Not yet enough data" pinned under a card that has two years of data would be
/// a lie, and the reader has no way to check it. Each placeholder is derived
/// from the same floors the section's own producer gates on —
/// `PatternFinder.defaultMinimumPairs`, `ScoreHistory.minimumContributors`,
/// `PeriodContrast.minimumDaysPerPeriod` — so the explanation cannot drift from
/// the rule it explains, and it quotes the actual shortfall.
///
/// In InsightKit because the app target has no test target and this is a claim
/// about the user's data, not decoration.
///
/// These builders answer *why the producer produced nothing* and are only
/// meaningful where it did. They deliberately do **not** re-run it to check:
/// that would double the cost of the most expensive sections on the screen to
/// re-derive a fact the caller already holds. The section runs its producer,
/// finds an empty result, and asks this for the reason.
public struct SectionPlaceholder: Sendable, Equatable {

    /// One line. It is what the collapsed section shows, so for most readers it
    /// is the whole of this section they will ever see and it has to stand up
    /// alone.
    public let headline: String
    /// The paragraph behind it: why there is nothing here, and what would change
    /// that. Never "check back later" without saying what is being waited for.
    public let detail: String

    public init(headline: String, detail: String) {
        self.headline = headline
        self.detail = detail
    }

    // MARK: - Patterns worth a look

    /// Why `PatternFinder` returned nothing.
    public static func patterns(series: [NormalizedSeries],
                                score: [ScorePoint],
                                minimumPairs: Int = PatternFinder.defaultMinimumPairs,
                                minimumMagnitude: Double = PatternFinder.defaultMinimumMagnitude,
                                calendar: Calendar = .current) -> SectionPlaceholder {
        guard !series.isEmpty else { return nothingRecording }

        let overlaps = comparableOverlaps(series, score: score, calendar: calendar)
        guard let best = overlaps.max() else {
            return SectionPlaceholder(
                headline: "Only one signal here so far",
                detail: "A pattern is a relationship between two things. This card "
                    + "is drawing a single signal and has no run of scores to read "
                    + "it against yet, so there is no pair to compare. Nothing is "
                    + "wrong — there is just nothing to hold up against anything.")
        }
        guard best >= minimumPairs else {
            return SectionPlaceholder(
                headline: "Not enough overlapping days yet",
                detail: "Looking for a pattern needs \(minimumPairs) days on which "
                    + "both signals were recorded. The closest pair here overlaps "
                    + "on \(best) \(SectionCaveat.plural(best, "day")). This fills "
                    + "in on its own as you keep recording, or sooner if you widen "
                    + "the timeframe above.")
        }
        return SectionPlaceholder(
            headline: "Nothing worth flagging right now",
            detail: "There are enough days to look, and your signals moved "
                + "independently over this window — none of them tracked another, "
                + "or your score, closely enough (a correlation of "
                + "\(formatted(minimumMagnitude)) or more) to be worth pointing "
                + "at. That is the ordinary state of a set of steady signals "
                + "rather than a gap in the data.")
    }

    // MARK: - What comes first

    /// Why `LagFinder` returned nothing.
    public static func leads(series: [NormalizedSeries],
                             score: [ScorePoint],
                             minimumPairs: Int = PatternFinder.defaultMinimumPairs,
                             requiredImprovement: Double = LagFinder.requiredImprovement,
                             calendar: Calendar = .current) -> SectionPlaceholder {
        guard !series.isEmpty else { return nothingRecording }
        guard score.count >= minimumPairs else {
            return SectionPlaceholder(
                headline: "Not enough score history yet",
                // No markdown in any of this copy: it reaches SwiftUI as a
                // `String` variable rather than a literal, so `Text` takes the
                // `StringProtocol` overload and asterisks would render as
                // asterisks.
                detail: "Asking whether a signal arrives before your score, rather "
                    + "than alongside it, means shifting it against a run of "
                    + "scores, and that needs "
                    + "\(minimumPairs) days of them. There "
                    + "\(score.count == 1 ? "is" : "are") \(score.count) so far. "
                    + "This section starts working on its own once the history is "
                    + "long enough.")
        }

        let scoreDays = score.map { (calendar.startOfDay(for: $0.date), $0.score) }
        let best = series.map { PatternFinder.align($0, to: scoreDays, calendar: calendar).count }
            .max() ?? 0
        guard best >= minimumPairs else {
            return SectionPlaceholder(
                headline: "Not enough overlapping days yet",
                detail: "Your score has \(score.count) days behind it, but the "
                    + "signals on this card were recorded on at most \(best) of "
                    + "them — \(minimumPairs) shared days is the floor for reading "
                    + "one against the other. Recording those signals more often "
                    + "is what closes the gap.")
        }
        return SectionPlaceholder(
            headline: "Nothing runs ahead of your score",
            detail: "Every signal here explains today about as well as it explains "
                + "tomorrow, so none of them is an early warning over this window. "
                + "That is the usual answer: a lead is only reported when a signal "
                + "beats its own same-day reading by a clear margin, and most "
                + "signals simply don't. Nothing to act on.")
    }

    // MARK: - Score over time

    /// Why the score chart has no line.
    ///
    /// **The `isComputing` arm is the one that matters.** `AppModel.scoreHistory`
    /// returns `[]` on first ask and replays 90 days off the main actor, so a
    /// card opened cold has an empty history for a second or two. Saying "no
    /// scored days yet" there would be a false statement that corrects itself
    /// after the reader has already read it — and the reader has no way to know
    /// which of the two they saw.
    public static func scoreHistory(points: Int,
                                    isComputing: Bool,
                                    minimumContributors: Int = ScoreHistory.minimumContributors)
    -> SectionPlaceholder {
        if isComputing {
            return SectionPlaceholder(
                headline: "Working out your history",
                detail: "Rebuilding this card's score for each of the last 90 days "
                    + "from the readings as they stood on each one. It appears "
                    + "here on its own as soon as that finishes.")
        }
        if points == 1 {
            return SectionPlaceholder(
                headline: "One scored day so far",
                detail: "A line needs two. One more day on which at least "
                    + "\(minimumContributors) of this card's signals record is "
                    + "all this is waiting for.")
        }
        return SectionPlaceholder(
            headline: "No scored days yet",
            detail: "A day only counts once at least \(minimumContributors) of "
                + "this card's signals recorded on it — a score resting on a "
                + "single reading isn't one. Nothing in the last 90 days has "
                + "cleared that yet, so there is no line to draw.")
    }

    // MARK: - What's driving this

    /// Why the card didn't attribute its number to individual signals.
    public static func drivers(hasScore: Bool) -> SectionPlaceholder {
        guard hasScore else {
            return SectionPlaceholder(
                headline: "No number to break down yet",
                detail: "This card can't produce a score from what it has, so "
                    + "there is nothing to attribute to individual signals. The "
                    + "sections below say what it reads and what is missing.")
        }
        return SectionPlaceholder(
            headline: "Nothing singled itself out",
            detail: "This card produced a number, and no one signal was far "
                + "enough from your usual pattern to be worth naming as the "
                + "reason. An ordinary day looks exactly like this.")
    }

    // MARK: - The bespoke sections

    /// A card's own picture, waiting on a countable floor.
    ///
    /// One builder for the nine bespoke sections that are all the same shape —
    /// *this needs N of something and has M* — rather than nine near-identical
    /// paragraphs. What makes it honest is that both numbers are passed in:
    /// "not enough yet" without the shortfall is the empty state this whole type
    /// was written to replace, and a caller that cannot say how far off it is
    /// probably does not know its own floor.
    ///
    /// The bespoke sections were the last eleven that still simply vanished.
    /// They are a card's own subject, so their absence is the *most* confusing
    /// of any section here: "Your fortnight" gone means no sleep data at all, or
    /// fewer nights than the model scores on, and those are a provider problem
    /// and a patience problem respectively.
    public static func needsMore(subject: String, have: Int, need: Int,
                                 noun: String, plural: String? = nil) -> SectionPlaceholder {
        let haveNoun = SectionCaveat.plural(have, noun, plural: plural)
        return SectionPlaceholder(
            headline: have == 0 ? "Nothing recorded yet" : "Not enough yet",
            detail: "\(subject) needs \(need) "
                + "\(SectionCaveat.plural(need, noun, plural: plural)), and there "
                + "\(have == 1 ? "is" : "are") \(have) \(haveNoun) so far. "
                + "It fills in on its own as more arrive — nothing is wrong.")
    }

    /// A card's own picture, waiting on something only the reader can supply:
    /// a cuff reading, a date of birth, a scale that reports body fat.
    ///
    /// Separate from `needsMore` because the two are opposite instructions.
    /// "Keep recording and this fills in" is wrong when nothing the reader does
    /// passively will ever produce the value.
    /// `remedy` says where the reader actually closes the gap. The default is
    /// this card's own "View & add" section — right for a grounding fact the
    /// card collects, and wrong for anything else: this copy once pointed a
    /// missing-scale message and a missing-details message on a card *without*
    /// that section at a place that either said "All set" or didn't exist. A
    /// remedy the reader can't follow is worse than none, so callers whose
    /// input lives elsewhere must say where.
    public static func needsInput(subject: String, what: String,
                                  remedy: String = "see \"View & add\" near the bottom of this card")
    -> SectionPlaceholder {
        SectionPlaceholder(
            headline: "Waiting on you",
            detail: "\(subject) is drawn from \(what), and the app doesn't have "
                + "any yet. This is the one kind of gap that won't close on its "
                + "own — \(remedy).")
    }

    /// A card's own picture that cannot be computed from what is here, for a
    /// reason that is about the model rather than about a count.
    public static func notComputable(subject: String, because: String) -> SectionPlaceholder {
        SectionPlaceholder(headline: "Can't draw this yet",
                           detail: "\(subject) \(because)")
    }

    // MARK: - How this is weighted

    /// Why a card has no shares to draw.
    ///
    /// **This used to be four cards and is now one.** It said *"Not a weighted
    /// average"* wherever every contributor arrived at weight 0, which conflated
    /// three different situations and got two of them wrong:
    ///
    /// - Body Composition and Fitness each rest on **one** measurement scored
    ///   against a published range. "No signal has a percentage share of it"
    ///   describes a card that does not exist — one signal has all of it.
    /// - Substance Impact and Heart Attack & Stroke Risk both have exactly
    ///   computable shares (`SubstanceResponseAnalyzer.penaltyShares`,
    ///   `RiskAttribution`). "Nobody chose these proportions" was the true
    ///   statement and it is not the same as "there are none".
    /// - Blood Pressure's cuff route genuinely has no share — and even there,
    ///   *"this is a measurement, taken at face value"* says more than a
    ///   negation does.
    ///
    /// So the model states its `ScoreWeighting` and this is reached only when
    /// that basis carries no shares, or when nothing was said at all.
    public static func weighting(basis: ScoreWeighting,
                                 areReported: Bool,
                                 contributorCount: Int) -> SectionPlaceholder {
        switch basis {
        case .measurement(let what):
            return SectionPlaceholder(
                headline: "A measurement, not a blend",
                detail: "\(what) There is no share to divide up — the number is "
                    + "the reading itself. The "
                    + "\(contributorCount) \(SectionCaveat.plural(contributorCount, "signal")) "
                    + "this card reads "
                    + "\(contributorCount == 1 ? "is" : "are") charted under "
                    + "\"What goes into this\" below.")
        case .unstated where !areReported:
            return SectionPlaceholder(
                headline: "No weighting reported",
                detail: "This card hasn't published how much each of its inputs "
                    + "counts toward its number, so there is nothing to divide "
                    + "up here. What it reads is charted under \"What goes into "
                    + "this\" below.")
        case .unstated:
            return SectionPlaceholder(
                headline: "Nothing to divide up yet",
                detail: "This card has no number at the moment, so there is no "
                    + "share of one to attribute to its "
                    + "\(contributorCount) \(SectionCaveat.plural(contributorCount, "input")). "
                    + "The sections below say what it reads and what it is "
                    + "waiting for.")
        // A basis that carries shares and reached here anyway means every
        // contributor came back at zero — on the worst-offender pool that is a
        // real and reassuring state, and it must not read as a failure.
        case .worstOffender:
            return SectionPlaceholder(
                headline: "Nothing took anything off",
                detail: "This card's number comes off the top for each signal "
                    + "that responded badly, and none of them did over this "
                    + "window. Nothing to divide up because there is nothing to "
                    + "divide, which is the good answer here.")
        case .weightedAverage, .singleMeasure, .equation, .fit:
            return SectionPlaceholder(
                headline: "No shares to draw yet",
                detail: "This card weights its inputs, and none of them has a "
                    + "value to weight right now. It fills in as soon as one "
                    + "does — see \"What goes into this\" below for what it is "
                    + "watching for.")
        }
    }

    // MARK: - What goes into this

    /// Why the overlay has no series. `inputCount` is what the card *declares*,
    /// which is the number that makes the difference between "this card reads
    /// nothing" and "this card reads nine things and none of them recorded".
    public static func overlay(inputCount: Int) -> SectionPlaceholder {
        guard inputCount > 0 else {
            return SectionPlaceholder(
                headline: "This card declares no chartable inputs",
                detail: "Nothing to plot, and nothing you can do about it — this "
                    + "is a gap in the app rather than in your data. Every other "
                    + "card reads at least one signal.")
        }
        return SectionPlaceholder(
            headline: "No readings over this window",
            detail: "This card reads \(inputCount) "
                + "\(SectionCaveat.plural(inputCount, "signal")), and "
                + "\(inputCount == 1 ? "it has" : "none of them has") recorded "
                + "anything over the timeframe above. Widening it, or connecting "
                + "a source that measures "
                + "\(inputCount == 1 ? "it" : "them") is what fills the chart.")
    }

    // MARK: - What changed

    /// Why the period contrast found nothing. Same two-reason split as the
    /// findings sections: not enough history, versus enough and nothing moved.
    public static func periodContrast(comparable: Int,
                                      windowDays: Int = PeriodContrast.windowDays,
                                      minimumDaysPerPeriod: Int = PeriodContrast.minimumDaysPerPeriod)
    -> SectionPlaceholder {
        guard comparable > 0 else {
            return SectionPlaceholder(
                headline: "Not enough history to compare yet",
                detail: "This puts your last \(windowDays) days against the "
                    + "\(windowDays) before them, and needs at least "
                    + "\(minimumDaysPerPeriod) days of readings in each. No "
                    + "signal on this card has that much on both sides yet — "
                    + "keep recording and it fills in on its own.")
        }
        // Written out per number rather than stitched from a ternary. The
        // stitched version read "1 signal had enough readings … and it shifted
        // far enough … to be worth reporting" — the singular arm dropped the
        // negation and stated the exact opposite of the section it captions.
        let didNotMove = comparable == 1
            ? "One signal had enough readings in both windows to compare, and it "
                + "didn't move far enough against its own spread to be worth reporting."
            : "\(comparable) signals had enough readings in both windows to "
                + "compare, and none moved far enough against their own spread "
                + "to be worth reporting."
        return SectionPlaceholder(
            headline: "Your normal hasn't moved",
            detail: didNotMove + " Your baseline is where it was a month ago, "
                + "which is the good answer here.")
    }

    // MARK: -

    /// Shared by both findings sections, because it is the same fact about the
    /// same card.
    static let nothingRecording = SectionPlaceholder(
        headline: "Nothing recording for this card yet",
        detail: "Reading signals against each other needs signals. None of this "
            + "card's inputs has produced a reading in this window, so there is "
            + "nothing to compare. Connecting a source, entering a reading, or "
            + "widening the timeframe above is what fills this in.")

    /// How many days each pair the finder would actually consider overlaps on:
    /// every two series that are not two readings of one measurement, plus each
    /// series against the score. Mirrors `PatternFinder`'s own pairing so the
    /// shortfall quoted is the shortfall that gated it.
    static func comparableOverlaps(_ series: [NormalizedSeries],
                                   score: [ScorePoint],
                                   calendar: Calendar) -> [Int] {
        var counts: [Int] = []
        for i in series.indices {
            for j in series.indices where j > i {
                guard !series[i].metric.sharesMeasurementBasis(with: series[j].metric)
                else { continue }
                counts.append(PatternFinder.align(series[i], series[j],
                                                  calendar: calendar).count)
            }
        }
        if !score.isEmpty {
            let scoreDays = score.map { (calendar.startOfDay(for: $0.date), $0.score) }
            for one in series {
                counts.append(PatternFinder.align(one, to: scoreDays,
                                                  calendar: calendar).count)
            }
        }
        return counts
    }

    /// `0.3`, not `0.300000` — and not `String(describing:)`, which is what put
    /// a float's full decimal expansion on screen the last time.
    static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
