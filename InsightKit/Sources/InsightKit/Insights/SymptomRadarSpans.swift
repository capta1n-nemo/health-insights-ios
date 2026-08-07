import Foundation

// MARK: - B11-1: the episode as a block of days

public extension SymptomRadarModel {

    /// **A stretch of days the card was not quiet, memory included** — the
    /// "band" half of the reader's ruling on §B11-1.
    ///
    /// > *"Colour each day by its OWN statistic, and draw the accumulated
    /// > episode as a BAND across the days it spanned."*
    ///
    /// The two halves answer two different questions and that is the whole
    /// design. A day's own statistic says **how that morning looked** — so a
    /// recovering day is not painted red by something that happened on Tuesday.
    /// The span says **an illness was running through here** — so the block does
    /// not fall apart the moment one morning's numbers come back inside the
    /// reader's range. Both are needed because the reader has already asked the
    /// question that arises when only one is shown: *"why am I now back at 99%
    /// just 1 day later?"*
    ///
    /// ## Why this is not `episodes(in:calendar:)`
    ///
    /// `SymptomRadarEpisode` groups days by `Output.status` — **the day alone**,
    /// with no accumulation — because it exists to describe onset, peak and
    /// per-signal recovery, and every one of those is a fact about the day's own
    /// numbers. A span groups by `DayHistory.isFlagged`, which is the *verdict's*
    /// status: `max(today, accumulation)`, exactly what the card reported that
    /// morning. So a carried-forward day — quiet on its own numbers, still
    /// spoken for by memory — is **inside a span and outside an episode**, and
    /// that difference is precisely the thing the band exists to draw.
    ///
    /// The join rule is deliberately the same as `episodes`': at most two
    /// non-flagged days between two flagged ones keeps them in one span. One
    /// quiet morning mid-illness must not end the story, and this repo already
    /// settled that number once.
    struct FlaggedSpan: Sendable, Equatable, Identifiable {
        /// First flagged day, `startOfDay`.
        public let start: Date
        /// Last flagged day, `startOfDay`.
        public let end: Date
        /// The flagged days themselves, oldest first. Days *between* two
        /// flagged days that were not themselves flagged are inside
        /// `start...end` but are **not** in here — they were days the card said
        /// nothing, and the list must not claim otherwise.
        public let days: [DayHistory]
        /// Calendar days from `start` to `end` inclusive, so a span with one
        /// quiet morning in the middle still reads as the length it covered.
        public let dayCount: Int
        /// The lowest score any day in the span reached **on its own numbers**.
        /// Nil only if no day in the span was judgeable, which cannot happen —
        /// a day with no output is never flagged.
        public let lowestDailyScore: Double?
        /// Days the card spoke on that were quiet on their own numbers: the
        /// accumulation alone was carrying them. The reader's complaint, counted.
        public let carriedDays: Int

        public var id: Date { start }

        public init(start: Date, end: Date, days: [DayHistory], dayCount: Int,
                    lowestDailyScore: Double?, carriedDays: Int) {
            self.start = start
            self.end = end
            self.days = days
            self.dayCount = dayCount
            self.lowestDailyScore = lowestDailyScore
            self.carriedDays = carriedDays
        }

        /// Whether a calendar day falls inside the block — including the quiet
        /// mornings the join rule bridged, which is what makes this a band
        /// rather than a scatter of dots.
        public func contains(_ day: Date, calendar: Calendar = .current) -> Bool {
            let target = calendar.startOfDay(for: day)
            return target >= start && target <= end
        }

        /// Whether the span begins on this day, so a drawn band can round its
        /// leading edge rather than run off into the previous week.
        public func begins(on day: Date, calendar: Calendar = .current) -> Bool {
            calendar.isDate(day, inSameDayAs: start)
        }

        /// Whether the span ends on this day.
        public func ends(on day: Date, calendar: Calendar = .current) -> Bool {
            calendar.isDate(day, inSameDayAs: end)
        }
    }

    /// Cut spans out of a history, oldest first.
    ///
    /// One pass over a history that was itself built in one pass — the standing
    /// rule on this model (`history(over:)`): never `days × evaluate`.
    static func flaggedSpans(in history: [DayHistory],
                             calendar: Calendar = .current) -> [FlaggedSpan] {
        var groups: [[DayHistory]] = []
        for row in history where row.isFlagged {
            if let previous = groups.last?.last,
               daysBetween(previous.day, row.day, calendar: calendar) <= 3 {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }
        return groups.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            return FlaggedSpan(
                start: first.day,
                end: last.day,
                days: group,
                dayCount: daysBetween(first.day, last.day, calendar: calendar) + 1,
                lowestDailyScore: group.compactMap(\.dailyScore).min(),
                // `status` is the verdict's, `output.status` is the day's own —
                // a day where they disagree is a day memory spoke for.
                carriedDays: group.filter { $0.output?.status == .quiet }.count)
        }
    }

    /// The span covering a given day, if any. Linear, and deliberately so: a
    /// month of cells against a handful of spans is not worth an index, and an
    /// index is one more thing that can disagree with the list it came from.
    static func span(covering day: Date, in spans: [FlaggedSpan],
                     calendar: Calendar = .current) -> FlaggedSpan? {
        spans.first { $0.contains(day, calendar: calendar) }
    }
}
