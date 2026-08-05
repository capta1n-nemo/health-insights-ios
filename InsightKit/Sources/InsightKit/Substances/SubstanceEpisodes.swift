import Foundation

/// **The episode is the unit of evidence, not the reading and not the day.**
///
/// The reader wants to know what a substance does to them, and their own answer
/// to how you'd know was the right one: *"if I take substances 3 times, and all
/// 3 times I see certain metrics all get impacted.. I can now draw a
/// conclusion."* That is replication, and replication across independent
/// occasions is the only defence against testing dozens of metrics at once.
///
/// Two events an hour apart are one exposure. Two a fortnight apart are two.
/// Counting readings instead — which the card did until 2026-08-05 — turned
/// four occasions into tens of thousands of "observations" and made every
/// uncertainty discount vacuous.
public enum SubstanceEpisodes {

    /// Events closer together than this are the same exposure.
    ///
    /// Chosen for what it groups rather than from a pharmacological argument:
    /// an evening's several drinks are one night out, and a dose the next
    /// evening is a separate occasion. ⚠️ **It is a real limit for a daily
    /// user** — someone who drinks most evenings has one continuous episode
    /// under any gap rule, and no amount of history will ever give them three
    /// independent occasions. For them the card cannot answer the replication
    /// question at all, and must say so rather than quietly reporting one
    /// episode as three.
    public static let gapHours: Double = 24

    public struct Episode: Sendable, Equatable {
        public let substance: SubstanceClass
        public let start: Date
        public let end: Date
        public let eventCount: Int

        /// The stretch a response would show up in: the exposure itself plus
        /// the window afterwards.
        public func responseWindow(_ after: TimeInterval) -> ClosedRange<Date> {
            start...end.addingTimeInterval(after)
        }
    }

    /// Group a log into exposure episodes, newest last.
    ///
    /// **Split by substance as well as by time.** A stimulant on Monday and
    /// alcohol on Tuesday are two exposures of two different things, and
    /// merging them would attribute one's response to the other — which is the
    /// single most misleading thing this card could do.
    public static func episodes(events: [SubstanceEvent],
                                calendar: Calendar = .current) -> [Episode] {
        var out: [Episode] = []
        let gap = gapHours * 3600
        for substance in Set(events.map(\.substance)) {
            let sorted = events.filter { $0.substance == substance }
                .map(\.timestamp).sorted()
            guard var start = sorted.first else { continue }
            var end = start
            var count = 0
            for time in sorted {
                if time.timeIntervalSince(end) > gap {
                    out.append(Episode(substance: substance, start: start, end: end,
                                       eventCount: count))
                    start = time
                    count = 0
                }
                end = time
                count += 1
            }
            out.append(Episode(substance: substance, start: start, end: end,
                               eventCount: count))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// How many independent occasions of one substance the log holds.
    public static func count(of substance: SubstanceClass, in events: [SubstanceEvent],
                             calendar: Calendar = .current) -> Int {
        episodes(events: events, calendar: calendar).filter { $0.substance == substance }.count
    }

    /// **How many occasions before this card will assert anything.**
    ///
    /// Three is the reader's own number and it is also the floor at which
    /// "every time" starts to mean something. It is *not* enough to make a
    /// finding safe on its own — independent statistical review of this
    /// reader's record found that at three episodes, with roughly eight
    /// effective dimensions among the watched metrics, every candidate effect
    /// was removable by same-day movement or by sleep duration, and the record
    /// supported **zero** confirmations. So three is the point at which the
    /// card may begin *describing* a repeated pattern, never the point at which
    /// it may call one proven.
    public static let minimumEpisodesToDescribe = 3

    /// The named alternative explanation for a metric, or nil where there is no
    /// well-measured one.
    ///
    /// **Every reported row carries one, and that is the whole honesty
    /// mechanism.** On this reader's own data `heartRate`'s apparent response
    /// to stimulants falls from 0.91 to 0.03 standard deviations once same-day
    /// step count is in the model — the effect was their own movement. A card
    /// that had shown "heart rate up, 3 times out of 3" would have been
    /// confidently wrong, and the reader would have had no way to know.
    public static func alternativeExplanation(for metric: MetricType) -> String? {
        switch metric.family {
        case .cardiac, .autonomic, .circulatory, .respiratory:
            return "how much you moved that day"
        case .sleep:
            return "how long you slept"
        case .activity:
            return "what you had planned that day"
        case .metabolic:
            return "what you ate"
        default:
            return nil
        }
    }
}
