import Foundation

/// What a findings section says when it has found nothing.
///
/// ## Why an empty section is drawn at all
///
/// "Patterns worth a look" and "What comes first" used to disappear when their
/// finders returned nothing, which is most of the time and on most cards. A
/// section that vanishes teaches the reader that its absence means nothing in
/// particular — when in fact it means one of three quite different things:
///
/// - nothing is recording for this card yet,
/// - there is data but not enough overlapping days to look for a relationship,
/// - there are plenty of days and nothing stood out, which is the *good* answer
///   and the one the reader never got told.
///
/// Those are not interchangeable, and only the third is reassuring. So the
/// sections always render and this type is what they render instead of findings.
///
/// ## Why the reason is computed rather than written once
///
/// "Not yet enough data" pinned under a card that has two years of data would be
/// a lie, and the reader has no way to check it. Each placeholder is derived
/// from the same floors the finder itself gates on — `defaultMinimumPairs`,
/// `defaultMinimumMagnitude` — so the explanation cannot drift away from the
/// rule it is explaining, and it quotes the actual shortfall.
///
/// In InsightKit because the app target has no test target and this is a claim
/// about the user's data, not decoration.
///
/// These builders answer *why the finder found nothing* and are only meaningful
/// where it did. They deliberately do **not** re-run the finder to check: that
/// would double the cost of the two most expensive sections on the screen to
/// re-derive a fact the caller already holds. The section calls the finder,
/// finds an empty result, and asks this for the reason.
public struct FindingsPlaceholder: Sendable, Equatable {

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
                                calendar: Calendar = .current) -> FindingsPlaceholder {
        guard !series.isEmpty else { return nothingRecording }

        let overlaps = comparableOverlaps(series, score: score, calendar: calendar)
        guard let best = overlaps.max() else {
            return FindingsPlaceholder(
                headline: "Only one signal here so far",
                detail: "A pattern is a relationship between two things. This card "
                    + "is drawing a single signal and has no run of scores to read "
                    + "it against yet, so there is no pair to compare. Nothing is "
                    + "wrong — there is just nothing to hold up against anything.")
        }
        guard best >= minimumPairs else {
            return FindingsPlaceholder(
                headline: "Not enough overlapping days yet",
                detail: "Looking for a pattern needs \(minimumPairs) days on which "
                    + "both signals were recorded. The closest pair here overlaps "
                    + "on \(best) \(SectionCaveat.plural(best, "day")). This fills "
                    + "in on its own as you keep recording, or sooner if you widen "
                    + "the timeframe above.")
        }
        return FindingsPlaceholder(
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
                             calendar: Calendar = .current) -> FindingsPlaceholder {
        guard !series.isEmpty else { return nothingRecording }
        guard score.count >= minimumPairs else {
            return FindingsPlaceholder(
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
            return FindingsPlaceholder(
                headline: "Not enough overlapping days yet",
                detail: "Your score has \(score.count) days behind it, but the "
                    + "signals on this card were recorded on at most \(best) of "
                    + "them — \(minimumPairs) shared days is the floor for reading "
                    + "one against the other. Recording those signals more often "
                    + "is what closes the gap.")
        }
        return FindingsPlaceholder(
            headline: "Nothing runs ahead of your score",
            detail: "Every signal here explains today about as well as it explains "
                + "tomorrow, so none of them is an early warning over this window. "
                + "That is the usual answer: a lead is only reported when a signal "
                + "beats its own same-day reading by a clear margin, and most "
                + "signals simply don't. Nothing to act on.")
    }

    // MARK: -

    /// Shared by both sections, because it is the same fact about the same card.
    static let nothingRecording = FindingsPlaceholder(
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
