import Foundation

/// **How long it takes you to come back** — backlog §C S6, the reader's own
/// request for a recovery tracker on Readiness.
///
/// ## The question, and why "Score over time" does not already answer it
///
/// Readiness answers *how am I today*, and the score chart above this draws the
/// trace of those answers. Neither says the thing a reader actually wants from a
/// recovery tracker: **after a bad day, how many days do you normally need?**
/// That is a property of the *shape* of the trace rather than of any point on
/// it, and eyeballing it off a ninety-day line is exactly the work a card is
/// supposed to do for somebody.
///
/// It is also the one question that gets more useful the longer the app runs,
/// and the only one on this card whose answer is a personal constant rather than
/// a reading.
///
/// ## What counts as a dip, and what counts as recovered
///
/// Both edges are the reader's own distribution, never a fixed number. A score
/// of 62 is an ordinary Tuesday for one person and the worst week of the year
/// for another, and a tracker built on a published threshold would tell the
/// second group they never recover and the first that they never dip.
///
/// - **Typical** is the median of the window, and **spread** is the robust scale
///   of it — median absolute deviation rather than a standard deviation, for the
///   reason the whole app now uses it: an SD has a breakdown point of zero, so
///   one flu would widen the ruler enough to hide the next one.
/// - A dip **opens** on the first day below `typical − 1 SD`.
/// - It **closes** on the first later day back at or above `typical`. Not back
///   above the dip line — coming back to the edge of the hole is not climbing
///   out of it, and measuring to the edge would report a recovery about half as
///   long as the real one.
///
/// ## ⚠️ The gap rule, which is most of the honesty here
///
/// A replayed score exists only on days that recorded at least two of the card's
/// signals, so the series has holes — a weekend the ring spent on charge, a week
/// away from the watch. If a dip on Monday is followed by nothing until the
/// following Tuesday, "eight days to recover" is a fabrication: nobody watched
/// seven of them.
///
/// So an episode is **resolved** only when no step inside it skips more than
/// `maximumGapDays`. Episodes that fail that test are kept and counted — the
/// section says how many were lost to gaps — but they never reach the median,
/// because a typical recovery time computed from unwatched days is worse than
/// no figure at all.
public enum RecoveryTracker {

    /// Days of replayed score needed before any of this is offered. Two weeks is
    /// the shortest window in which a median and a spread mean anything.
    public static let minimumPoints = 14

    /// How far below typical a day has to fall to open a dip, in robust SDs.
    ///
    /// One, deliberately, rather than the two an outlier test would use. This is
    /// not asking *is this day surprising* — it is asking *when did the reader
    /// have a bad day*, and a reader has bad days considerably more often than
    /// once in twenty.
    public static let dipThresholdSD = 1.0

    /// The largest hole a single episode may step over before it stops counting
    /// as observed. Three days: a long weekend off the wearable is the common
    /// case, and stepping over more than that is guessing.
    public static let maximumGapDays = 3

    /// Resolved episodes needed before a typical recovery time is stated. Two,
    /// because one is an anecdote — and `CoverageGate` says so out loud rather
    /// than the figure silently not appearing.
    public static let minimumEpisodes = 2

    /// One dip, and what happened after it.
    public struct Episode: Sendable, Equatable, Identifiable {
        /// The first day below the dip line.
        public let start: Date
        /// The lowest day of the dip, and its score.
        public let trough: Date
        public let troughScore: Double
        /// The first day back at or above typical. `nil` when the dip has not
        /// closed — either because it is still open today, or because the
        /// series ended inside it.
        public let recovered: Date?
        /// Whether every step inside the episode was actually watched. See the
        /// gap rule in the type comment.
        public let isObserved: Bool
        /// Days of replayed score inside the episode, so a row can say how much
        /// of it anybody saw.
        public let observedPoints: Int

        public var id: Date { start }

        /// Calendar days from the dip opening to the day it closed. `nil` while
        /// the episode is open.
        public var days: Int? {
            recovered.map { Int(($0.timeIntervalSince(start) / 86_400).rounded()) }
        }

        /// Counted toward the typical figure. Both halves matter: an unobserved
        /// episode has a number that nobody watched, and an open one has none.
        public var countsTowardTypical: Bool { isObserved && days != nil }
    }

    public struct Output: Sendable, Equatable {
        /// Newest first — a recovery tracker is read from the top.
        public let episodes: [Episode]
        /// The reader's own typical day over the window, which is what a dip is
        /// measured from and returned to.
        public let typical: Double
        /// The line a day has to fall below to open a dip.
        public let dipFloor: Double
        /// Median days to recover, across resolved episodes. `nil` below
        /// `minimumEpisodes`, and `gate` says so.
        public let typicalDays: Double?
        /// The dip still running today, where there is one.
        public let openEpisode: Episode?
        /// Days of replayed score the window held.
        public let observedDays: Int
        /// Episodes a gap in the record swallowed. Reported rather than hidden:
        /// a tracker quietly dropping half its evidence is the failure this
        /// whole type is written around.
        public let unobservedEpisodes: Int
        /// What is missing, while something is. `nil` once met.
        public let gate: CoverageGate?

        /// Days the open dip has been running, as of the last score.
        public func daysOpen(asOf now: Date) -> Int? {
            openEpisode.map { Int((now.timeIntervalSince($0.start) / 86_400).rounded()) }
        }
    }

    /// `nil` when the replayed history is too short to describe a distribution.
    ///
    /// Takes `[ScorePoint]` rather than samples on purpose: the 90-day replay
    /// this needs is already computed for "Score over time", and re-deriving it
    /// would run seventeen models a second time to reach a number the screen is
    /// already holding.
    public static func evaluate(_ points: [ScorePoint],
                                calendar: Calendar = .current) -> Output? {
        let ordered = points.sorted { $0.date < $1.date }
        guard ordered.count >= minimumPoints else { return nil }

        let scores = ordered.map(\.score)
        guard let typical = Baseline.median(scores),
              let spread = Baseline.robustScale(scores), spread > 0
        else { return nil }
        let floor = typical - dipThresholdSD * spread

        var episodes: [Episode] = []
        var index = 0
        while index < ordered.count {
            guard ordered[index].score < floor else {
                index += 1
                continue
            }
            episodes.append(episode(from: index, in: ordered, typical: typical,
                                    calendar: calendar))
            // Resume *after* the day the dip closed, so two dips separated by a
            // single recovered day stay two dips rather than merging into one
            // long one whose "recovery" spans a week of normal days.
            let closed = episodes[episodes.count - 1].recovered
            if let closed {
                index = (ordered.firstIndex { $0.date >= closed } ?? ordered.count - 1) + 1
            } else {
                index = ordered.count
            }
        }

        let resolved = episodes.filter(\.countsTowardTypical).compactMap { $0.days }
            .map(Double.init)
        let open = episodes.last.flatMap { $0.recovered == nil ? $0 : nil }

        return Output(
            episodes: episodes.reversed(),
            typical: typical,
            dipFloor: floor,
            typicalDays: resolved.count >= minimumEpisodes ? Baseline.median(resolved) : nil,
            openEpisode: open,
            observedDays: ordered.count,
            unobservedEpisodes: episodes.filter { !$0.isObserved }.count,
            gate: .ifShort(need: minimumEpisodes, have: resolved.count,
                           unit: "recovered dip",
                           unlocks: "this can say how long you usually take to come back"))
    }

    /// Walk one dip forward from `start` until the score is back at typical.
    private static func episode(from start: Int, in points: [ScorePoint],
                                typical: Double, calendar: Calendar) -> Episode {
        var trough = points[start]
        var observed = 0
        var isObserved = true
        var recovered: Date?
        var previous = points[start]

        for point in points[start...] {
            let gap = calendar.dateComponents([.day], from: previous.date, to: point.date).day ?? 0
            if gap > maximumGapDays { isObserved = false }
            previous = point
            observed += 1
            if point.score < trough.score { trough = point }
            if point.date > points[start].date, point.score >= typical {
                recovered = point.date
                break
            }
        }

        return Episode(start: points[start].date,
                       trough: trough.date, troughScore: trough.score,
                       recovered: recovered, isObserved: isObserved,
                       observedPoints: observed)
    }

    /// The one-line answer, in words. Shared so a preview and a heading cannot
    /// disagree about what the number means.
    public static func phrase(_ out: Output) -> String {
        if let days = out.typicalDays {
            return days < 1.5
                ? "You are usually back to normal the next day"
                : String(format: "You usually take about %.0f days to come back", days)
        }
        if out.episodes.isEmpty {
            return "No day has fallen far enough below your normal to count as a dip"
        }
        return out.gate?.sentence ?? "Not enough recovered dips to say yet"
    }
}
