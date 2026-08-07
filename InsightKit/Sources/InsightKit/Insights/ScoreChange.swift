import Foundation

/// Which way a card's score has been going, and whether that is worth saying.
///
/// ## Why this does not compare with yesterday
///
/// The obvious version is "today against yesterday", and a survey of what the
/// serious apps actually ship says nobody does it: not Oura, Whoop, Garmin,
/// Apple, Fitbit or Withings. Every one of them compares a **short window
/// against a longer one**, or renders position within a personal range, and
/// none renders a day-over-day delta on a daily score.
///
/// The reason is measurement noise. Day-to-day variability in HRV — the input
/// that moves readiness most — sits around 5% and is reported between 3% and
/// 13% depending on method, while a genuinely hard training session moves it
/// 10–20%. So a day-over-day indicator on a composite built from HRV spends
/// most of its life reporting noise with a confident arrow attached, and the
/// user learns to ignore it, which is worse than not having it.
///
/// What this does instead keeps the thing that was actually wanted — direction,
/// at a glance, next to the number — and takes the comparison somewhere the
/// signal survives:
///
/// - **Daily cards** compare today against the **trailing week, today
///   excluded**. Still "has it gone up or down", still answers it every day,
///   and one ordinary night no longer decides the answer.
/// - **Trend cards** compare the **last four weeks against the trailing
///   quarter**. Short-against-long rather than this-month-against-last-month,
///   because a long reference is stable and doesn't drift along with the change
///   being measured — the same blindness `PeriodContrast` was written to avoid.
///
/// ## And why it stays quiet
///
/// The change is standardised against the reference period's own spread, so two
/// points of movement in a steady score outranks two points in a jumpy one. Below
/// the threshold the answer is "steady", which is a real answer — Apple
/// suppresses a trend outright when nothing has moved, and Garmin and Fitbit both
/// render "inside your usual range" rather than a direction. A card seen every
/// day has to earn the right to point at something.
public struct ScoreChange: Sendable, Equatable {

    public enum Direction: String, Sendable {
        case up, down, steady
    }

    /// The mean of the recent window.
    public let recent: Double
    /// The mean of the window it is judged against.
    public let reference: Double
    /// `recent − reference`, in score points.
    public let delta: Double
    /// The delta against the reference window's own spread.
    public let standardisedDelta: Double
    public let recentDays: Int
    public let referenceDays: Int
    /// What the comparison was, in words, for the tooltip or accessibility label.
    public let comparison: String

    /// Movement smaller than this share of the reference spread is noise.
    ///
    /// Higher on the daily cards than on the trend cards, and deliberately:
    /// Today is opened many times a week and a trend card a few times a month,
    /// so the cost of a false "it's up!" is an order of magnitude higher there.
    /// `PeriodContrast` uses 0.4 for the slow comparison and this matches it.
    public static let dailyThreshold = 0.5
    public static let trendThreshold = 0.4

    /// A flat score has no spread to standardise against, so a floor in points
    /// stops division by nearly nothing turning one point into a landslide.
    /// Two points on a 0–100 scale is the smallest change worth a word.
    public static let minimumPoints = 2.0

    let threshold: Double

    public var direction: Direction {
        guard abs(delta) >= Self.minimumPoints,
              abs(standardisedDelta) >= threshold else { return .steady }
        return delta > 0 ? .up : .down
    }

    public var isMeaningful: Bool { direction != .steady }

    /// "+4" / "−7", or nil when there is nothing to point at.
    public var label: String? {
        guard isMeaningful else { return nil }
        return String(format: "%@%.0f", delta > 0 ? "+" : "−", abs(delta))
    }

    /// The word for the chip in every state, including steady.
    ///
    /// Steady is a *measured* answer, not an absence — the app has enough
    /// history to judge and the score has not moved past its own usual spread.
    /// Rendering it (rather than hiding the chip) is the difference between "no
    /// change" and "we don't know yet", which the reader could not otherwise
    /// tell apart. A card with too little history returns no `ScoreChange` at
    /// all, so this string only ever describes a judgement that was actually
    /// made.
    ///
    /// **"Stable", not "No change"** (reader's wording, 2026-08-07). The old
    /// string described the *arithmetic* — the delta was too small to report —
    /// and so read as an absence sitting where a finding should be. "Stable"
    /// describes the reader's body, which is what the card is about, and it is
    /// the same kind of word as the "Drained" or "Ready" on the line above it.
    /// The chip draws it with a flat arrow rather than an equals sign for the
    /// same reason: the other two states are arrows, and a glyph from a
    /// different family reads as a different kind of thing.
    public static let steadyLabel = "Stable"

    public var chipLabel: String {
        switch direction {
        case .up, .down: return label ?? Self.steadyLabel
        case .steady: return Self.steadyLabel
        }
    }
}

/// Why a card has no direction to point in — or the direction, when it has one.
///
/// ## The state that was missing
///
/// `ScoreChangeReader` used to answer `ScoreChange?`, and the `nil` was doing
/// three different jobs at once: *there is no history yet*, *there is history
/// but today has not been scored*, and *there is history and it is not enough*.
/// The dashboard's `if let` had no `else`, so all three rendered as an empty
/// space beside the headline — and the reader could not tell a card that is
/// learning from a card that has given up. Backlog B15-2, and D46's complaint
/// one level up: **only "not enough yet" is a reason to keep going, and it was
/// the one state the app could not say.**
///
/// So this is a total answer. Every path out of the reader names its cause, and
/// the two that are not a measurement carry the words for it.
public enum ScoreChangeState: Sendable, Equatable {

    /// Enough history, and a judgement was made — including "stable", which is
    /// a measured answer and not an absence (see `ScoreChange.steadyLabel`).
    case measured(ScoreChange)

    /// Not enough scored days yet. The gate says how many more, and what they
    /// buy — which is the sentence `CoverageGate` exists to make compulsory.
    case learning(CoverageGate)

    /// There *is* history, and enough of it, but the most recent score is not
    /// today's. Distinct from `learning` on purpose: nothing is missing except
    /// a sync, so telling the reader to keep wearing something would be wrong
    /// advice. `LastNightCard` already says the same thing about the night.
    case notScoredToday

    public var change: ScoreChange? {
        if case .measured(let change) = self { return change }
        return nil
    }

    public var gate: CoverageGate? {
        if case .learning(let gate) = self { return gate }
        return nil
    }

    /// The word for a chip when there is no direction to draw. `nil` once a
    /// real `ScoreChange` exists, so a caller renders one or the other and
    /// never both.
    ///
    /// **"Learning trends", not "No data"** — the card has data, it is
    /// accumulating the history a comparison needs, and saying so is the
    /// difference between an absence and a progress bar.
    public var pendingLabel: String? {
        switch self {
        case .measured: return nil
        case .learning: return "Learning trends"
        case .notScoredToday: return "Not scored yet"
        }
    }

    /// The long form, for a tooltip, a caveat line or an accessibility label.
    public var explanation: String? {
        switch self {
        case .measured: return nil
        case .learning(let gate):
            return gate.sentence
        case .notScoredToday:
            return "Today has not been scored yet — there is nothing to hold "
                + "against your recent history until it has."
        }
    }
}

public enum ScoreChangeReader {

    /// Days of history the daily comparison holds today against.
    public static let dailyReferenceDays = 7
    /// And the minimum number of them that must actually carry a score. Seven
    /// nights is the floor Fitbit uses before readiness has a baseline at all,
    /// and four is the least that can describe a spread without one day owning
    /// it.
    public static let minimumDailyReference = 4

    public static let trendRecentDays = 28
    public static let trendReferenceDays = 90
    public static let minimumTrendRecent = 7
    public static let minimumTrendReference = 21

    /// The right comparison for a card, chosen by its cadence.
    ///
    /// Cadence already encodes the difference this hinges on — `.daily` cards
    /// are about right now and `.trend` cards about the last months — so the
    /// call site never has to pick a window, and the two can't drift apart.
    ///
    /// **`calendar` is forwarded, and that is not decoration.** This entry point
    /// used to take no calendar and call `daily` without one, so the parameter
    /// `daily` deliberately exposes was unreachable through the API every caller
    /// is told to use — it silently got `.current`. The suite pins UTC on
    /// purpose (see `TestClock`), the pin could not reach this path, and the
    /// result was a test that passed on CI's UTC container and failed on the
    /// user's UTC+8 Mac the first time it ran there: the fixture's latest point
    /// sat on the previous *local* day, so `isDate(inSameDayAs:)` refused it.
    ///
    /// `broad` takes none because it is pure interval arithmetic, with no
    /// day boundary anywhere in it.
    public static func trend(for id: InsightID, history: [ScorePoint],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> ScoreChange? {
        state(for: id, history: history, now: now, calendar: calendar).change
    }

    /// The same choice, but keeping the reason when there is no direction.
    ///
    /// The `ScoreChange?` entry points above are this one with the reason thrown
    /// away, and they stay because most callers only want the arrow. Anything
    /// that renders the *absence* of an arrow must use this instead — an empty
    /// space is not a statement, and the reader read it as one.
    public static func state(for id: InsightID, history: [ScorePoint],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> ScoreChangeState {
        switch id.cadence {
        case .daily: return dailyState(history: history, now: now, calendar: calendar)
        case .trend: return broadState(history: history, now: now)
        }
    }

    /// Today against the trailing week, today excluded.
    public static func daily(history: [ScorePoint], now: Date = Date(),
                             calendar: Calendar = .current) -> ScoreChange? {
        dailyState(history: history, now: now, calendar: calendar).change
    }

    /// What a daily card can say, and why, when it cannot say a direction.
    ///
    /// The order of the two failure tests is deliberate and is the whole reason
    /// this is not one `guard`. An empty history is *learning*; a history that
    /// exists but stops before today is *waiting for a sync*; and only once
    /// today is present does the size of the reference window decide. Testing
    /// staleness first on an empty history would report "not scored today" to
    /// someone who has never scored at all, which reads as a fault rather than
    /// as a start.
    public static func dailyState(history: [ScorePoint], now: Date = Date(),
                                  calendar: Calendar = .current) -> ScoreChangeState {
        let today = calendar.startOfDay(for: now)
        let windowStart = today.addingTimeInterval(-Double(dailyReferenceDays) * 86_400)
        let reference = history
            .filter { $0.date >= windowStart && $0.date < today }
            .map(\.score)

        func learning() -> ScoreChangeState {
            .learning(CoverageGate(
                need: minimumDailyReference, have: reference.count,
                unit: "scored day",
                unlocks: "this can say whether today is up or down on your usual"))
        }

        guard reference.count >= minimumDailyReference,
              let mean = Baseline.mean(reference) else { return learning() }

        guard let latest = history.max(by: { $0.date < $1.date }),
              // A score from days ago is not "today", and labelling it as such
              // would be the staleness bug this app has already paid for once.
              calendar.isDate(latest.date, inSameDayAs: today) else {
            return .notScoredToday
        }

        return .measured(build(
            recent: latest.score, reference: mean, spread: reference,
            recentDays: 1, referenceDays: dailyReferenceDays,
            comparison: "against your last \(reference.count) days",
            threshold: ScoreChange.dailyThreshold))
    }

    /// The last four weeks against the trailing quarter.
    ///
    /// The reference deliberately *includes* the recent window rather than
    /// stopping before it. This is the opposite of what `HealthWatchModel` does,
    /// and for the opposite reason: Health Watch is detecting a short run and
    /// must not let it contaminate its own baseline, while this is describing
    /// where a slow number sits within its own recent history — for which "the
    /// quarter" is the honest reference, and excising a third of it to make the
    /// contrast look bigger would be flattering the finding.
    public static func broad(history: [ScorePoint], now: Date = Date()) -> ScoreChange? {
        broadState(history: history, now: now).change
    }

    /// The trend comparison, keeping its reason.
    ///
    /// Two requirements have to be met and only one sentence can be shown, so
    /// the gate reported is **whichever is further from being met** — the one
    /// that will still be blocking after the other clears. Reporting the nearer
    /// one would promise a figure that does not arrive when it is reached, and
    /// a gate that lies once is not read again.
    public static func broadState(history: [ScorePoint],
                                  now: Date = Date()) -> ScoreChangeState {
        let recentStart = now.addingTimeInterval(-Double(trendRecentDays) * 86_400)
        let referenceStart = now.addingTimeInterval(-Double(trendReferenceDays) * 86_400)

        let recent = history.filter { $0.date >= recentStart }.map(\.score)
        let reference = history.filter { $0.date >= referenceStart }.map(\.score)

        let recentGate = CoverageGate(
            need: minimumTrendRecent, have: recent.count, unit: "scored day",
            unlocks: "the last four weeks can be compared with the months behind them")
        let referenceGate = CoverageGate(
            need: minimumTrendReference, have: reference.count, unit: "scored day",
            unlocks: "there is enough history to compare the last four weeks against")

        guard recent.count >= minimumTrendRecent,
              reference.count >= minimumTrendReference,
              let recentMean = Baseline.mean(recent),
              let referenceMean = Baseline.mean(reference) else {
            // The fallback covers only the arithmetic-impossible case where both
            // counts are met and a mean still came back nil; the longer
            // requirement is the honest thing to name there.
            let furthest = [recentGate, referenceGate]
                .filter { !$0.isMet }
                .min { $0.progress < $1.progress } ?? referenceGate
            return .learning(furthest)
        }

        return .measured(build(
            recent: recentMean, reference: referenceMean, spread: reference,
            recentDays: trendRecentDays, referenceDays: trendReferenceDays,
            comparison: "4 weeks against your last 3 months",
            threshold: ScoreChange.trendThreshold))
    }

    static func build(recent: Double, reference: Double, spread: [Double],
                      recentDays: Int, referenceDays: Int,
                      comparison: String, threshold: Double) -> ScoreChange {
        let delta = recent - reference
        let sd = Baseline.standardDeviation(spread) ?? 0
        return ScoreChange(
            recent: recent, reference: reference, delta: delta,
            // A flat reference has no spread, and a real move against one is a
            // real move — so treat it as decisively past the threshold rather
            // than as an undefined ratio. The points floor still applies.
            standardisedDelta: sd > 0 ? delta / sd : (delta == 0 ? 0 : delta.sign == .plus ? .infinity : -.infinity),
            recentDays: recentDays, referenceDays: referenceDays,
            comparison: comparison, threshold: threshold)
    }
}
