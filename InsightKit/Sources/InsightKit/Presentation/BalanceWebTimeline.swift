import Foundation

/// How wide one step of the morph slider is.
///
/// **The reader asked for granularity selection, and it is not decoration.** The
/// coverage rule below (`BalanceWebTimeline`) drops any card that is missing a
/// score in *any* step, so the step width is the reader's one lever over how
/// many spokes survive: a card that skips the odd day is whole at monthly steps
/// and full of holes at weekly ones. The picker is therefore the control that
/// trades *resolution* against *how much of the web you get to see*, and the
/// section says so on screen rather than leaving it to be discovered.
///
/// No `.day`. A daily step over a year is three hundred and sixty-five slider
/// positions — unusable as a control — and it would require every drawn card to
/// have been scored on every single day, which on a real record leaves nothing
/// standing.
public enum WebTimeGranularity: String, CaseIterable, Sendable, Identifiable {
    case week, month, quarter

    public var id: String { rawValue }

    /// The word on the segmented control.
    public var label: String {
        switch self {
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .quarter: return "Quarterly"
        }
    }

    /// One step, in words, for the caption under the slider.
    public var stepNoun: String {
        switch self {
        case .week: return "week"
        case .month: return "month"
        case .quarter: return "quarter"
        }
    }

    /// The bucket a date falls in, as a half-open `start ..< end`.
    ///
    /// Quarters are computed rather than asked of `Calendar`: `.quarter` is not
    /// a component every calendar answers for, and `dateInterval(of: .quarter…)`
    /// returns nil on some of them — a silent nil here would drop days out of
    /// the timeline rather than fail loudly.
    public func bucket(containing date: Date,
                       calendar: Calendar = .current) -> (start: Date, end: Date)? {
        switch self {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
            return (interval.start, interval.end)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
            return (interval.start, interval.end)
        case .quarter:
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { return nil }
            let startMonth = ((month - 1) / 3) * 3 + 1
            var components = DateComponents()
            components.year = year
            components.month = startMonth
            components.day = 1
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .month, value: 3, to: start) else { return nil }
            return (start, end)
        }
    }

    /// The bucket after this one. Used to walk the span forward without
    /// arithmetic on seconds — a fortnight of which lands in the wrong month
    /// twice a year.
    func nextBucketStart(after start: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .week: return calendar.date(byAdding: .weekOfYear, value: 1, to: start)
        case .month: return calendar.date(byAdding: .month, value: 1, to: start)
        case .quarter: return calendar.date(byAdding: .month, value: 3, to: start)
        }
    }
}

/// The balance web at every step of the reader's own history — the frames the
/// morph slider scrubs through.
///
/// ## The one rule this type exists to enforce
///
/// **A shape can only be compared with another shape if both are drawn on the
/// same axes, with a real value on every one of them.** That single sentence
/// decides everything below:
///
/// - **The spoke set is fixed for the whole timeline**, so scrubbing does not
///   rotate the chart. The angle a card sits at is the reader's only handle on
///   which vertex is which, and a spoke set that changed per frame would make
///   the web spin under the slider while every number stayed put.
/// - **A card is drawn only if it has a score in *every* step.** The tempting
///   alternatives are both dishonest in the same way: carrying the last known
///   score forward invents a reading for a stretch that has none, and dropping
///   the vertex to the centre draws "no data" at the same radius as "scored
///   zero" — the exact confusion `BalanceWebGeometry.radiusFraction` refuses a
///   floor in order to avoid.
/// - **What was dropped is named**, in `excluded`, because a card silently
///   missing from a chart of *all your scores* is unreadable as an absence.
///   Rule 7 in prose: the empty state has to say what it is waiting for.
///
/// ## What the grey underlay means here, and why it is not "usual"
///
/// On the Insights hero the grey web is the reader's *usual* — the mean of the
/// window each card is judged against. On a past frame that would be a second
/// past, which answers nothing. Here the grey shape is **where the reader is
/// now**, held still while the coloured shape moves, so every frame reads as
/// *then, against today*. `Spoke.referenceDays` is deliberately left nil so
/// `BalanceWebSnapshot.referenceDescription` — which describes a trailing
/// window — cannot volunteer a sentence that would be wrong on this screen.
public struct BalanceWebTimeline: Sendable, Equatable {

    /// One step of the slider.
    public struct Frame: Sendable, Equatable, Identifiable {
        /// First instant of the bucket.
        public let start: Date
        /// First instant of the *next* bucket — half open, so `start ..< end`.
        public let end: Date
        /// The web as it stood, averaged over the bucket.
        public let snapshot: BalanceWebSnapshot
        /// How many scored days went into this frame, summed over its spokes.
        /// A frame built from three days is a thinner claim than one built from
        /// ninety, and the caption is allowed to say so.
        public let scoredDayCount: Int

        public var id: Date { start }

        public init(start: Date, end: Date, snapshot: BalanceWebSnapshot,
                    scoredDayCount: Int) {
            self.start = start
            self.end = end
            self.snapshot = snapshot
            self.scoredDayCount = scoredDayCount
        }
    }

    public let granularity: WebTimeGranularity
    /// Oldest first. The slider maps 1:1 onto these.
    public let frames: [Frame]
    /// Short titles of the cards that had history in the span but were dropped
    /// for missing a step. Alphabetical, so the sentence is stable between
    /// launches rather than following dictionary order.
    public let excluded: [String]
    /// The span actually drawn — the first scored day to the last, across every
    /// card considered. **The screen must print this**: a chart that silently
    /// changes the stretch of life it covers is the ambiguity this app exists
    /// to avoid, and the span moves whenever a replay lands.
    public let span: ClosedRange<Date>?

    public init(granularity: WebTimeGranularity, frames: [Frame],
                excluded: [String], span: ClosedRange<Date>?) {
        self.granularity = granularity
        self.frames = frames
        self.excluded = excluded
        self.span = span
    }

    public static func empty(_ granularity: WebTimeGranularity) -> BalanceWebTimeline {
        BalanceWebTimeline(granularity: granularity, frames: [], excluded: [], span: nil)
    }

    /// Whether there is anything to morph *between*.
    ///
    /// Two frames, not one: a slider with a single position is a control that
    /// does nothing, and a single frame is the hero web with extra chrome.
    public var isMorphable: Bool {
        frames.count >= 2 && (frames.first?.snapshot.isDrawable ?? false)
    }

    /// How many cards are drawn on every frame.
    public var spokeCount: Int { frames.first?.snapshot.spokes.count ?? 0 }

    /// Total days of scored history the timeline rests on.
    public var dayCount: Int? {
        guard let span else { return nil }
        return Int((span.upperBound.timeIntervalSince(span.lowerBound) / 86_400).rounded()) + 1
    }

    // MARK: - Building

    /// Build the frames from replayed-and-stored score histories.
    ///
    /// - Parameters:
    ///   - histories: every scored day the app holds, per insight. Cards that do
    ///     not belong on the balance web (`InsightID.belongsOnBalanceWeb`) are
    ///     dropped here, so a detector cannot arrive on this chart by the back
    ///     door after being kept off the hero.
    ///   - titles: the card titles, for the vertex's accessibility label. A
    ///     missing one falls back to the short title rather than failing —
    ///     `InsightResult.title` is not available on every path that can build
    ///     a timeline (the export, a test).
    ///
    /// Pure and `Sendable` in both directions so it can run detached, exactly as
    /// `BalanceWebSnapshot.build` does for the hero.
    public static func build(histories: [InsightID: [ScorePoint]],
                             titles: [InsightID: String] = [:],
                             granularity: WebTimeGranularity,
                             calendar: Calendar = .current) -> BalanceWebTimeline {
        // 1. Candidates: on the web, and with something to draw.
        let candidates = histories
            .filter { $0.key.belongsOnBalanceWeb && !$0.value.isEmpty }
        guard !candidates.isEmpty else { return .empty(granularity) }

        let allDates = candidates.values.flatMap { $0.map(\.date) }
        guard let earliest = allDates.min(), let latest = allDates.max(),
              earliest <= latest,
              let firstBucket = granularity.bucket(containing: earliest, calendar: calendar)
        else { return .empty(granularity) }
        let span = earliest...latest

        // 2. The bucket boundaries, walked forward by calendar unit rather than
        //    by seconds: a month is not 30 days and a week crosses a DST change
        //    twice a year, both of which slide a naive stride off the boundary.
        var bucketStarts: [Date] = []
        var cursor = firstBucket.start
        // A generous ceiling rather than `while true`. Quarterly over a century
        // is 400 buckets; weekly over a century is 5,200. This cannot be reached
        // by real data and stops a malformed calendar spinning forever.
        let ceiling = 10_000
        while cursor <= latest, bucketStarts.count < ceiling {
            bucketStarts.append(cursor)
            guard let next = granularity.nextBucketStart(after: cursor, calendar: calendar),
                  next > cursor else { break }
            cursor = next
        }
        guard bucketStarts.count >= 1 else { return .empty(granularity) }

        // 3. Bucket every card's points once. Index = position in `bucketStarts`.
        func bucketIndex(for date: Date) -> Int? {
            // Binary search for the last start at or before `date`.
            var low = 0
            var high = bucketStarts.count
            while low < high {
                let mid = (low + high) / 2
                if bucketStarts[mid] <= date { low = mid + 1 } else { high = mid }
            }
            return low > 0 ? low - 1 : nil
        }

        /// mean score per bucket, and how many days went into it
        var bucketed: [InsightID: [Int: (total: Double, count: Int)]] = [:]
        for (id, points) in candidates {
            var perBucket: [Int: (total: Double, count: Int)] = [:]
            for point in points {
                guard let index = bucketIndex(for: point.date) else { continue }
                let existing = perBucket[index] ?? (0, 0)
                perBucket[index] = (existing.total + point.score, existing.count + 1)
            }
            bucketed[id] = perBucket
        }

        // 4. The coverage rule: present in **every** bucket, or not drawn.
        let bucketCount = bucketStarts.count
        var drawn: [InsightID] = []
        var excluded: [String] = []
        for id in bucketed.keys {
            let filled = bucketed[id]?.count ?? 0
            if filled == bucketCount { drawn.append(id) } else { excluded.append(id.shortTitle) }
        }
        guard !drawn.isEmpty else {
            return BalanceWebTimeline(granularity: granularity, frames: [],
                                      excluded: excluded.sorted(), span: span)
        }
        // Same order as the hero, for the same reason: the shape a reader learns
        // in one place is the shape they meet in the other. See the note on area
        // in `BalanceWebGeometry`.
        drawn.sort { $0.colourSlot < $1.colourSlot }

        // 5. "Now" — the newest bucket's score per spoke — is the grey underlay
        //    on every frame, so the reader compares then against today rather
        //    than against another past.
        let lastIndex = bucketCount - 1
        var now: [InsightID: Double] = [:]
        for id in drawn {
            if let cell = bucketed[id]?[lastIndex], cell.count > 0 {
                now[id] = cell.total / Double(cell.count)
            }
        }

        // 6. The frames.
        var previous: [InsightID: Double] = [:]
        var frames: [Frame] = []
        frames.reserveCapacity(bucketCount)
        for index in 0..<bucketCount {
            let start = bucketStarts[index]
            let end = granularity.nextBucketStart(after: start, calendar: calendar) ?? start
            var spokes: [BalanceWebSnapshot.Spoke] = []
            var days = 0
            var current: [InsightID: Double] = [:]
            for id in drawn {
                guard let cell = bucketed[id]?[index], cell.count > 0 else { continue }
                let score = cell.total / Double(cell.count)
                days += cell.count
                current[id] = score
                spokes.append(.init(id: id,
                                    title: titles[id] ?? id.shortTitle,
                                    shortTitle: id.shortTitle,
                                    score: score,
                                    reference: now[id],
                                    direction: direction(from: previous[id], to: score),
                                    referenceDays: nil))
            }
            frames.append(Frame(start: start, end: end,
                                snapshot: BalanceWebSnapshot(spokes: spokes),
                                scoredDayCount: days))
            previous = current
        }

        return BalanceWebTimeline(granularity: granularity, frames: frames,
                                  excluded: excluded.sorted(), span: span)
    }

    /// Movement against the step before, with the same two-point deadband every
    /// other change in the app uses (`ScoreChange.minimumPoints`).
    ///
    /// `nil` on the oldest frame — there is nothing behind it — which is a
    /// different silence from "steady" and is drawn as no arrow rather than a
    /// flat one.
    static func direction(from previous: Double?,
                          to score: Double) -> ScoreChange.Direction? {
        guard let previous else { return nil }
        let delta = score - previous
        guard abs(delta) >= ScoreChange.minimumPoints else { return .steady }
        return delta > 0 ? .up : .down
    }
}
