import Foundation

/// **What actually moved overnight, channel by channel, each against its own
/// night-to-night spread** — backlog S5, the reader's own request.
///
/// ## The gap this closes
///
/// Every other sleep section describes the night: how long it was, what shape
/// it had, when the heart settled, how disturbed the breathing was. The reader
/// asked for something different — *what changed while you slept* — and the
/// difference is the comparison. A night is only informative against the nights
/// before it, and the app already holds six or seven separate nocturnal
/// channels that nothing has ever placed side by side.
///
/// ## The honest version, which is the only version
///
/// **A delta on its own is not a finding.** Respiratory rate is stable to a few
/// tenths of a breath a minute, so 0.4 higher is a real move; overnight HRV
/// routinely swings 15 ms for no reason at all, so 8 ms higher is Tuesday. The
/// only way to report several channels together without one of them shouting
/// over the rest is to divide each by **its own** night-to-night spread — which
/// is what this does, and what it prints on screen.
///
/// So every channel carries four numbers and never fewer: last night's value,
/// the middle of the nights before it, the spread of those nights, and how many
/// there were. A channel with fewer than `minimumReferenceNights` behind it
/// gets no verdict at all, because a standard deviation from four nights is a
/// number pretending to be an error bar.
///
/// ⚠️ **This is not a second symptom radar and must never read like one.** The
/// radar asks whether channels are leaning *together*, weights them by how
/// specific each is to illness, collapses the ones that are one measurement
/// twice, and grades the result against a stated false-alarm budget. This asks
/// a smaller, flatter question — *what moved* — with no weighting, no
/// collapsing and no score. That is deliberate: the moment a list of deltas
/// acquires a total it is making the radar's claim without the radar's
/// calibration behind it.
public enum OvernightChange {

    // MARK: - The dials, stated once

    /// How far back "your usual" comes from. Four weeks: long enough that a
    /// spread means something, short enough that last season's sleep is not
    /// setting this week's band.
    public static let referenceNights = 28

    /// The fewest prior nights a channel can be judged against. Seven — below
    /// that the spread is estimated to about ±30% of itself, and dividing by it
    /// would produce a confident-looking multiple of a number nobody knows.
    public static let minimumReferenceNights = 7

    /// How far a channel has to move before it is worth naming, in its own
    /// night-to-night standard deviations. One: about two thirds of ordinary
    /// nights land inside it, which is exactly the claim the wording makes.
    public static let notableZ = 1.0

    /// And how far before the wording stops hedging. Two — roughly one night in
    /// twenty on a channel that is behaving.
    public static let markedZ = 2.0

    /// How far a channel's own latest reading may sit from the night being
    /// reported and still belong to it.
    ///
    /// One day, and it is not slack: sources disagree about which calendar day
    /// a night belongs to. A ring writes the night's summary at wake; a
    /// thermometer reading taken on waking is stamped that morning; some
    /// providers key a night to the evening it began. Insisting on one exact
    /// day would silently drop channels for a filing convention rather than for
    /// missing data — so a neighbouring day is allowed, and **the row prints
    /// its own date** whenever it differs from the night's.
    public static let neighbouringDays = 1

    // MARK: - Types

    /// One channel's answer for one night.
    public struct Channel: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        /// The day this channel's reading is filed under — usually the night's,
        /// occasionally its neighbour. See `neighbouringDays`.
        public let day: Date
        public let value: Double
        /// The middle of the nights before this one.
        public let reference: Double
        /// How far either side of that this channel usually lands — the error
        /// bar, and the divisor.
        public let spread: Double
        /// How many nights the two figures above rest on.
        public let referenceNights: Int
        /// True when a rise is the direction that would worry the symptom
        /// radar. Carried so a view can say *up* or *down* without deciding for
        /// itself what "worse" means — and `nil` for a channel where neither
        /// direction is a concern.
        public let risingIsConcerning: Bool?

        public var id: MetricType { metric }

        /// How much it moved, in the channel's own units.
        public var delta: Double { value - reference }

        /// How much it moved, in the channel's own night-to-night spreads.
        ///
        /// Zero rather than infinity on a channel that has never moved: a
        /// perfectly flat reference is a source repeating one number, and
        /// dividing by nothing would make the flattest channel the loudest.
        public var z: Double { spread > 0 ? delta / spread : 0 }

        /// **Inside ordinary night-to-night variation.** The sentence the
        /// reader asked to be said plainly rather than implied by a small
        /// number.
        public var isOrdinary: Bool { abs(z) < notableZ }
        public var isMarked: Bool { abs(z) >= markedZ }

        /// ⚠️ **How many decimals this channel's numbers are worth, taken from
        /// its own spread** — and every one of the three cases below was
        /// visible on one screenshot of the shipped section.
        ///
        /// `MetricValueFormatter` renders a respiratory rate as an integer and
        /// a temperature deviation to one decimal, which is right on a chart
        /// axis and wrong here, because this section's whole subject is a
        /// *difference*. The screen read **"14 br/min … 0.5 below your usual
        /// 14 br/min"**, and **"0.2 °C below your usual 0.2 °C"**, and a
        /// deviation of −0.04 °C printed as **"-0.0 °C"**. All three are
        /// arithmetically true at the precision shown and all three read as
        /// nonsense.
        ///
        /// The rule that fixes all of them at once: **print finer than the
        /// scatter you are dividing by**, because a move of about one scatter
        /// is the smallest thing this section ever calls notable and it has to
        /// be visible as a difference from the figure beside it.
        ///
        /// One decimal by default; none where the scatter is wider than three
        /// units and a decimal would be noise; two where it is narrower than
        /// three tenths and one decimal is not enough to separate the move from
        /// the middle it moved from — the temperature-deviation case, which
        /// printed **"0.2 °C below your usual 0.2 °C"** with one.
        public var decimals: Int {
            if spread >= 3 { return 0 }
            return spread >= 0.3 ? 1 : 2
        }

        public init(metric: MetricType, day: Date, value: Double, reference: Double,
                    spread: Double, referenceNights: Int, risingIsConcerning: Bool?) {
            self.metric = metric
            self.day = day
            self.value = value
            self.reference = reference
            self.spread = spread
            self.referenceNights = referenceNights
            self.risingIsConcerning = risingIsConcerning
        }
    }

    /// A nightly series handed in by the caller: one value a night, oldest
    /// first.
    ///
    /// **A parameter rather than a fetch**, for the reason `OvernightCardiac`
    /// takes its windows from outside: two of these channels are read from
    /// inside the sleep window and the rest are nightly figures off
    /// `VitalReader`, and a type that fetched both would own a second opinion
    /// about what a night is. The section assembles them; this decides what
    /// they mean.
    public struct Series: Sendable, Equatable {
        public let metric: MetricType
        /// Oldest first. Duplicated days are the caller's problem — both
        /// sources this is fed from already de-duplicate.
        public let nights: [Point]

        public init(metric: MetricType, nights: [Point]) {
            self.metric = metric
            self.nights = nights
        }

        public struct Point: Sendable, Equatable {
            public let day: Date
            public let value: Double

            public init(day: Date, value: Double) {
                self.day = day
                self.value = value
            }
        }
    }

    /// Everything a section needs.
    public struct Output: Sendable, Equatable {
        /// The night being reported — the most recent day any channel has.
        public let night: Date
        /// One row per channel that could be judged, in the order they were
        /// handed in.
        public let channels: [Channel]
        /// Channels that reported last night but have too little history behind
        /// them to be judged. **Carried rather than dropped**, so "we have not
        /// watched this long enough" cannot be mistaken for "this did not
        /// move".
        public let waiting: [MetricType]
        /// The most nights any one channel has behind it. **The honest number
        /// for an empty state**: "you have 4 of the 7 nights this needs" is a
        /// statement a reader can act on, where a count of channels waiting is
        /// not, and the deepest channel is the one that will cross the line
        /// first.
        public let nightsBehind: Int

        public init(night: Date, channels: [Channel], waiting: [MetricType],
                    nightsBehind: Int) {
            self.night = night
            self.channels = channels
            self.waiting = waiting
            self.nightsBehind = nightsBehind
        }

        /// The channels that moved beyond their own ordinary spread, hardest
        /// first. What the headline counts.
        public var moved: [Channel] {
            channels.filter { !$0.isOrdinary }.sorted { abs($0.z) > abs($1.z) }
        }

        /// The sentence for the channels that reported and could not be judged,
        /// and **nil when there are none** — `CoverageGate`'s rule that a met
        /// gate says nothing, applied by hand because the shortfall here is per
        /// channel rather than one count.
        public var waitingSentence: String? {
            guard !waiting.isEmpty else { return nil }
            let names = waiting.map { $0.displayName.lowercased() }
            let list = names.count == 1 ? names[0]
                : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
            return "Also recorded last night but not judged yet: \(list). "
                + "Each needs \(minimumReferenceNights) earlier nights before a spread "
                + "means anything, and a multiple of a spread nobody knows is worse "
                + "than no number at all."
        }
    }

    // MARK: - Building

    /// Judge each series against its own preceding nights.
    ///
    /// ⚠️ **The reference always excludes the night being judged**, for the
    /// reason `HealthWatchModel`'s reference gap exists: a night held against a
    /// window it is itself inside is being compared with itself, and on a short
    /// history that is enough to hide the very night worth seeing.
    public static func build(_ series: [Series],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> Output? {
        let latest = series.compactMap { $0.nights.last?.day }.max()
        guard let night = latest else { return nil }

        var channels: [Channel] = []
        var waiting: [MetricType] = []
        var deepest = 0
        for one in series {
            guard let last = one.nights.last,
                  let gap = calendar.dateComponents([.day],
                                                    from: calendar.startOfDay(for: last.day),
                                                    to: calendar.startOfDay(for: night)).day,
                  abs(gap) <= neighbouringDays
            else { continue }

            let priorCutoff = last.day.addingTimeInterval(-Double(referenceNights) * 86_400)
            let prior = one.nights
                .filter { $0.day < last.day && $0.day >= priorCutoff }
                .map(\.value)
            deepest = Swift.max(deepest, prior.count)
            guard prior.count >= minimumReferenceNights,
                  let reference = Baseline.mean(prior),
                  let spread = Baseline.standardDeviation(prior)
            else {
                waiting.append(one.metric)
                continue
            }
            channels.append(Channel(metric: one.metric, day: last.day, value: last.value,
                                    reference: reference, spread: spread,
                                    referenceNights: prior.count,
                                    risingIsConcerning:
                                        HealthWatchModel.risingIsConcerning(for: one.metric)))
        }
        guard !channels.isEmpty || !waiting.isEmpty else { return nil }
        return Output(night: night, channels: channels, waiting: waiting,
                      nightsBehind: deepest)
    }

    // MARK: - Wording

    /// The one-line answer, and it is allowed to say nothing happened.
    ///
    /// **"Nothing moved" is a real finding and is written as one.** A section
    /// that only ever speaks up when something is wrong trains the reader to
    /// read its silence as an all-clear it never gave — and on a night when
    /// every channel sat inside its own scatter, saying so out loud is more
    /// informative than a blank space.
    public static func headline(_ output: Output) -> String {
        let moved = output.moved
        let total = output.channels.count
        guard !moved.isEmpty else {
            guard total > 1 else {
                return "The one channel with enough nights behind it stayed inside its "
                    + "ordinary night-to-night range."
            }
            // The chance line belongs here too, and it says more here than it
            // does above: a night on which nothing moved is a *quieter* night
            // than usual, and that only reads as a finding once the reader
            // knows how many normally do.
            return "All \(total) channels stayed inside their own ordinary night-to-night "
                + "range. \(chanceSentence(total))"
        }
        // ⚠️ **Every one that moved is named, never the first three.** The
        // first version listed three under a count of four, so the sentence
        // read as a complete list and was not one.
        let names = moved.map { $0.metric.displayName.lowercased() }
        let list = names.count == 1 ? names[0]
            : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return "\(moved.count) of \(total) moved further than \(moved.count == 1 ? "it" : "they") usually do "
            + "from one night to the next — \(list). \(chanceSentence(total)) "
            + "Several channels leaning the same way is the symptom radar's question, not this one's; "
            + "this only says what moved."
    }

    /// ⚠️ **How many channels move this far on an ordinary night, from scatter
    /// alone** — and it is a bigger number than it feels like.
    ///
    /// A channel is called *moved* at one of its own standard deviations, and
    /// about 32% of ordinary nights clear that on any given channel
    /// (`2(1 − Φ(1))`). Across seven channels that is more than two a night, on
    /// a body doing nothing at all. Without this line "4 of 7 moved" reads as a
    /// finding, and the honest version of the section is the one that says how
    /// much of its own output is noise — the same reason the symptom radar
    /// states a false-alarm budget rather than implying one.
    public static func chanceSentence(_ total: Int) -> String {
        String(format: "About %.1f of %d do that on an ordinary night from normal scatter alone, "
               + "so this is a list to read, not a count to act on.",
               Double(total) * ordinaryShareBeyondOneSpread, total)
    }

    /// `2(1 − Φ(1))` — the share of ordinary nights a single channel spends
    /// more than one standard deviation from its own middle.
    static let ordinaryShareBeyondOneSpread = 0.3173

    /// One channel, in a sentence, with its spread in it.
    ///
    /// Every number that could be mistaken for a verdict is followed by the
    /// thing that qualifies it: the multiple is always printed beside the
    /// spread it is a multiple of, and the count of nights that spread rests on
    /// is never left off.
    public static func sentence(for channel: Channel) -> String {
        let direction = channel.delta >= 0 ? "above" : "below"
        let magnitude = "\(formatted(abs(channel.delta), in: channel)) \(direction) "
            + "your usual \(formatted(channel.reference, in: channel))"
        let spread = "your last \(channel.referenceNights) nights scatter by about "
            + formatted(channel.spread, in: channel)
        if channel.isOrdinary {
            return "\(magnitude) — inside ordinary night-to-night variation (\(spread))."
        }
        return String(format: "%@, about %.1f× your own night-to-night spread (%@).",
                      magnitude, abs(channel.z), spread)
    }

    /// A value on one channel's own scale, at the precision that channel's
    /// scatter justifies (`Channel.decimals`) and with its unit on it once.
    ///
    /// **Every number this section prints goes through here**, including the
    /// headline figure on the row, so a channel cannot show a value at one
    /// precision and a difference at another — which is how "14 br/min … 0.5
    /// below your usual 14 br/min" reached the screen.
    public static func formatted(_ value: Double, in channel: Channel) -> String {
        formatted(value, channel.metric, decimals: channel.decimals)
    }

    /// The same, for a caller with no channel in hand. `decimals` nil hands the
    /// value to `MetricValueFormatter`, which is right on an axis and too
    /// coarse inside a sentence about a difference.
    ///
    /// The unit is appended only where the formatter has not already put one
    /// there — `MetricValueFormatter` renders a saturation as "97%", and a
    /// caller tacking the unit on again produced "97% %".
    public static func formatted(_ value: Double, _ metric: MetricType,
                                 decimals: Int? = nil) -> String {
        let base: String
        if let decimals {
            // ⚠️ **Rounded first, then stripped of a signed zero.** A skin
            // temperature deviation of −0.04 printed as "-0.0 °C" on the
            // shipped section: true, useless, and it reads as a typing error.
            let scale = pow(10.0, Double(decimals))
            let rounded = (value * scale).rounded() / scale
            base = String(format: "%.\(decimals)f", rounded == 0 ? 0 : rounded)
        } else if value < 1 && value > 0 {
            // A difference under a whole unit would otherwise render as "0" on
            // an integer metric, which reads as "nothing changed" on a row
            // about to call the change notable.
            base = String(format: "%.1f", value)
        } else {
            base = MetricValueFormatter.string(value, metric)
        }
        let unit = metric.unit
        guard !unit.isEmpty, !base.hasSuffix(unit) else { return base }
        // No space before a percent sign, a space before everything else —
        // "0.4 %" is not how anybody writes it, and "3.1bpm" is not either.
        return unit == "%" ? base + unit : base + " " + unit
    }
}
