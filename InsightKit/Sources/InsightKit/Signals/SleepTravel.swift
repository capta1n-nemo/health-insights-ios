import Foundation

/// **Sleep, for a reader who moves.**
///
/// The reader flew Manila → Sydney on 2026-08-07, slept on the plane, and asked
/// for all of it to *"clearly report in MY current timezone and all show
/// correctly"*. This type is the arithmetic that makes that answerable. It
/// changes no existing figure: `SleepNights` still decides what a night is and
/// how long it was, and every number here is either recovered from what that
/// already stored or read from data the ingestion path had been throwing away.
///
/// ## The three problems, kept separate
///
/// **1. Which zone renders a past night.** The stored `.sleepOnset` value is not
/// an instant — it is *signed hours from local midnight*, a rendered number,
/// baked at ingest against whatever zone the phone was in at the time. A night
/// slept in Manila and synced in Manila is stored as `−1.0` (23:00 Manila). Fly
/// to Sydney and nothing recomputes it; the card still says 23:00 for a moment
/// that, in the reader's own zone, was 01:00.
///
/// The instant is recoverable **exactly**, and that is the hinge this whole file
/// turns on — see `onsetInstant(of:)`. So the stored value can be re-rendered in
/// any zone, and the reader's instruction can be obeyed without a migration, a
/// re-sync, or a new field on `HealthMetricSample`.
///
/// **2. A flight night has no single day, and two durations disagree.** Sleep
/// from 23:00 Manila (UTC+8) to 07:00 Sydney (UTC+10) *elapsed* six hours while
/// the clock either side of it moved eight. `SleepNights` sums segment
/// durations, so what it reports is **elapsed**, and elapsed is the one that is
/// right — it is invariant to what any clock did overnight. That was already
/// true and was never said out loud, which is worse than being wrong: a reader
/// who does the subtraction themselves gets a different answer and has no way to
/// know which to believe. `wallClockHours(elapsedHours:span:)` produces the
/// other number so a card can show the gap and name it.
///
/// **3. Plane sleep is fragmented and mid-day.** `SleepNights` drops any sleep
/// starting between noon and 18:00 — correctly, since that is how a 3 pm nap is
/// kept out of last night's total — but it drops it *silently*. A reader who
/// slept four hours over the Timor Sea at 14:00 sees nothing at all.
/// `daytimeSleepHours(from:calendar:)` surfaces exactly what that filter
/// discarded, without changing what it discards.
///
/// ## Where the zone actually comes from
///
/// Until 2026-08-07 the app stored **no time zone on any health reading**, and
/// `CalendarModel.timeZoneChanges` — travel inferred from calendar events — was
/// the only thing that knew the reader had moved. It is an inference, and its
/// own doc says so: a reader who sets one event in another zone by hand produces
/// the identical shape.
///
/// There was a measurement all along and it was being deleted at the door. Oura
/// stamps `bedtime_start` as `2026-08-06T23:10:00+08:00`; `ISO8601DateFormatter`
/// resolved the offset into an instant and discarded it, and
/// `GenericJSONIngestor` excluded the date keys from the raw sweep, so the
/// string never reached the catalogue either. `PayloadDate.utcOffsetSeconds`
/// now keeps it, and `spans(raw:calendar:)` reads it back. **A night whose two
/// ends carry different offsets crossed a zone. That is measured, not guessed.**
///
/// Apple Health supplies no offset on this path, so an Apple-only night has no
/// span and must be reported as *unknown*, never as *did not travel*.
public enum SleepTravel {

    // MARK: - 1. Re-rendering a stored night in the reader's own zone

    /// The instant sleep began, recovered from a stored `.sleepOnset` sample.
    ///
    /// **Exact, to the minute the encoding kept**, and the reason is worth
    /// writing down because everything else here depends on it.
    ///
    /// `SleepOnset.samples` stores two things about a night, computed in one
    /// calendar and only ever in one: the sample's `start` is
    /// `SleepOnset.night(of:)` — local midnight on the wake day — and its
    /// `value` is `hoursFromMidnight`, the clock time of the onset measured from
    /// that same midnight, folded negative for an evening. Their sum is the
    /// original instant by construction:
    ///
    /// - 23:00 on the 6th → night key = the 7th at 00:00 local, value = −1.0,
    ///   and `key − 1 h` is the 6th at 23:00. ✔
    /// - 01:30 on the 7th → night key = the 7th at 00:00 local, value = +1.5,
    ///   and `key + 1.5 h` is the 7th at 01:30. ✔
    ///
    /// Because both terms were produced in the *same* calendar, the arithmetic
    /// is independent of which calendar that was: whatever zone the phone was in
    /// when this synced, the sum lands on the correct absolute instant. That is
    /// what makes a stored history re-renderable without re-syncing it.
    ///
    /// The one thing it does not survive is a DST transition falling between the
    /// onset and its night key, which shifts the recovery by an hour. That is
    /// half of one night, once or twice a year, in the zones that observe it —
    /// and it is a smaller error than the one this exists to fix.
    public static func onsetInstant(of sample: HealthMetricSample) -> Date? {
        guard sample.type == .sleepOnset else { return nil }
        return sample.start.addingTimeInterval(sample.value * 3600)
    }

    /// Signed hours from local midnight in `calendar` — **unfiltered**.
    ///
    /// `SleepOnset.hoursFromMidnight` returns nil outside ±6 h of midnight, and
    /// that is right for what it does: an *admission* test, deciding whether a
    /// moment of sleep is allowed to become a bedtime at all, so that a 15:00
    /// nap never poisons the consistency figure.
    ///
    /// Re-rendering a night that was already admitted is a different question,
    /// and re-applying the test here would be a real defect. A night admitted in
    /// Sydney and viewed from London is the same night; refusing to draw it
    /// because the reader has since moved eleven hours west would erase months
    /// of real history for no reason but the reader's longitude. The night was a
    /// night when it happened. This renders it.
    ///
    /// ⚠️ **The range is therefore [−12, +12), not ±6.** A reader who has
    /// crossed enough zones will see a real night render at −10 (14:00 by their
    /// current clock), and any axis, band or empty state built on the old ±6
    /// assumption will clip it or drop it. `SleepOnsetChart` and
    /// `SleepOnsetStripChart` both assume ±6 today.
    public static func clockHoursFromMidnight(_ instant: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        let clock = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        return clock >= 12 ? clock - 24 : clock
    }

    /// A stored night's bedtime, re-rendered in `calendar` — the reader's
    /// instruction, in one call. Nil for anything that is not a `.sleepOnset`.
    public static func onsetHours(of sample: HealthMetricSample,
                                  in calendar: Calendar) -> Double? {
        onsetInstant(of: sample).map { clockHoursFromMidnight($0, calendar: calendar) }
    }

    /// The calendar day a night key names, read in `calendar`.
    ///
    /// A night key is local midnight in the zone that minted it. Rendered
    /// directly in another zone it is no longer midnight — Manila's midnight is
    /// 02:00 in Sydney — and `startOfDay` on it can therefore land on the day
    /// before. The twelve-hour nudge puts the instant in the middle of the day
    /// it was minted for, so the label survives any offset difference under 12 h.
    ///
    /// **Stated rather than hidden: it does not survive a larger one.** Sydney
    /// and Honolulu are twenty hours apart, and a Sydney-minted key read in
    /// Honolulu labels the day before. Fixing that needs the minting zone stored
    /// alongside the key, which is a schema change and a migration; the reader's
    /// Manila↔Sydney move is two hours and comfortably inside. Do not let this
    /// paragraph disappear if someone widens the claim.
    public static func nightDay(of key: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: key.addingTimeInterval(12 * 3600))
    }

    /// Every stored `.sleepOnset`, rewritten so that **both halves of it are in
    /// the reader's current zone** — the other half of problem 1, and the half
    /// that was left open on 2026-08-07.
    ///
    /// ## Why re-rendering the value alone is not enough
    ///
    /// A stored onset is a pair: a night key (`start`) and signed hours from
    /// that key (`value`). `onsetHours(of:in:)` fixes the second, and every
    /// caller in this package reads the first through
    /// `VitalReader.dailySeries`, which re-buckets by `calendar.startOfDay(for:
    /// sample.start)`. So the key silently becomes **midnight here** while the
    /// value stays **hours from midnight there**, and the pair no longer
    /// describes any instant at all:
    ///
    /// - Bedtime 23:00 Manila is stored as key `7 Aug 00:00 +08`, value `−1.0`.
    /// - Bucketed in Sydney the key becomes `7 Aug 00:00 +10`, value still
    ///   `−1.0` → `6 Aug 23:00 +10`, two hours from the truth.
    /// - `SleepRegularityIndex.intervals` and `NightSleepDetail.windowLanes`
    ///   then rebuild the episode from `key + value`, so the error is not
    ///   cosmetic: it moves the whole sleep block on the grid.
    ///
    /// Worse westward, where it changes the *day*: a Sydney-minted key read in
    /// London is `6 Aug 15:00`, and `startOfDay` on that labels the night one
    /// day early — the shear `DayStamp` predicted in writing.
    ///
    /// ## What this returns
    ///
    /// One sample per stored onset, with:
    ///
    /// - `start` = `nightDay(of:)` — the night's label, resolved to local
    ///   midnight **here**, so `startOfDay` on it is a no-op and no later
    ///   bucketing can shear it.
    /// - `value` = the exact interval from that key to the recovered instant,
    ///   which keeps `start + value·3600 == onsetInstant` true by construction
    ///   rather than by coincidence. In every ordinary case that is the same
    ///   number `clockHoursFromMidnight` gives; it is derived from the key
    ///   instead so the identity cannot drift apart from it.
    ///
    /// **Idempotent**: re-rendering an already-rendered sample recovers the
    /// same instant, the same key and the same value, so a caller that applies
    /// it twice — or applies it after some future app-wide pass does — is safe.
    ///
    /// ⚠️ **Returns only the onsets, not the whole array**, and that is a
    /// performance decision with a measurement behind it. `MultiSource`'s
    /// evaluation memo is keyed on the sample buffer's *address*, so handing
    /// any model a rebuilt copy of the full 237k-sample array would miss the
    /// memo and cost a full scan per metric (28.8 ms each, measured). Every
    /// caller here reads `.sleepOnset` and nothing else out of what it passes,
    /// so passing only the onsets is equivalent — and it is a few hundred
    /// elements rather than a few hundred thousand.
    ///
    /// ⚠️ **The result is not bounded by `SleepOnset.plausibleHours`.** See
    /// `clockHoursFromMidnight`: the band is [−12, +12), and a chart or an axis
    /// that assumed ±6 will clip a real night once the reader has moved far
    /// enough.
    public static func onsets(in samples: [HealthMetricSample],
                              calendar: Calendar = .current) -> [HealthMetricSample] {
        samples.compactMap { sample in
            guard let instant = onsetInstant(of: sample) else { return nil }
            var key = nightDay(of: sample.start, calendar: calendar)
            var hours = instant.timeIntervalSince(key) / 3600
            // Beyond a twelve-hour offset difference the minted label cannot be
            // preserved — `nightDay` says so — and the honest resolution is the
            // one the reader actually lived: keep the instant, move the label.
            // A loop rather than an `if` because DST can make a "day" 23 or 25
            // hours, and stepping by calendar days is what keeps the key at
            // local midnight in those zones.
            var guardCount = 0
            while abs(hours) >= 12, guardCount < 3 {
                let step = hours >= 12 ? 1 : -1
                guard let moved = calendar.date(byAdding: .day, value: step, to: key)
                else { break }
                key = calendar.startOfDay(for: moved)
                hours = instant.timeIntervalSince(key) / 3600
                guardCount += 1
            }
            return HealthMetricSample(type: .sleepOnset, value: hours,
                                      start: key, end: key, source: sample.source)
        }
    }

    // MARK: - 2. Whether the night crossed a zone

    /// The UTC offset at each end of one night, and what moved between them.
    public struct ZoneSpan: Sendable, Equatable {
        /// Seconds from GMT where sleep began.
        public let atSleep: TimeInterval
        /// Seconds from GMT where it ended.
        public let atWake: TimeInterval

        public init(atSleep: TimeInterval, atWake: TimeInterval) {
            self.atSleep = atSleep
            self.atWake = atWake
        }

        /// Positive when the clock moved *forward* overnight — flying east.
        public var shift: TimeInterval { atWake - atSleep }
        public var shiftHours: Double { shift / 3600 }

        /// Fifteen minutes, because that is the smallest step any real zone
        /// takes (Nepal at +05:45, the Chathams at +12:45). A threshold rather
        /// than `!= 0` so a provider's rounding cannot invent a journey.
        public static let smallestRealZoneStep: TimeInterval = 15 * 60
        public var crossed: Bool { abs(shift) >= Self.smallestRealZoneStep }
    }

    /// Zone spans per night, from the offsets the ingestion path now keeps.
    ///
    /// Reads `zone_offset_seconds` / `zone_offset_seconds_at_end` — see
    /// `PayloadDate` — and keys each span by the same night rule the samples
    /// use, so a span and a night can be joined without either knowing about
    /// the other. Records lacking either end are skipped: half a span cannot say
    /// whether anything moved, and a missing offset is *unknown*, never zero.
    public static func spans(raw: [RawMetricSample],
                             calendar: Calendar = .current) -> [Date: ZoneSpan] {
        func offsets(_ field: String) -> [Date: TimeInterval] {
            var out: [Date: TimeInterval] = [:]
            for sample in raw
            where sample.identifier.hasSuffix(".\(field)") || sample.identifier == field {
                guard let seconds = sample.numericValue else { continue }
                out[sample.start] = seconds
            }
            return out
        }
        let starts = offsets(PayloadDate.startZoneOffsetField)
        let ends = offsets(PayloadDate.endZoneOffsetField)

        var out: [Date: ZoneSpan] = [:]
        for (instant, atSleep) in starts {
            guard let atWake = ends[instant] else { continue }
            let key = nightDay(of: SleepOnset.night(of: instant, calendar: calendar),
                               calendar: calendar)
            // A night can arrive as several records (Oura splits a broken night).
            // The widest span wins: if any part of the night crossed a zone, the
            // night crossed a zone, and reporting the narrowest would hide it.
            let span = ZoneSpan(atSleep: atSleep, atWake: atWake)
            if let held = out[key], abs(held.shift) >= abs(span.shift) { continue }
            out[key] = span
        }
        return out
    }

    // MARK: - 3. Elapsed versus what the clock said

    /// What the clock either side of the night reads, given how long it actually
    /// lasted.
    ///
    /// Fly east across two hours and a six-hour sleep looks like eight on the
    /// bedside clock; fly west and it looks like four. **`SleepNights` reports
    /// elapsed** — it sums segment durations, and a duration between two
    /// instants cannot be changed by a time zone. This function exists so a card
    /// can print the other number *next to* it and say which is which, rather
    /// than leaving the reader to find the discrepancy themselves and guess
    /// which one the app got wrong.
    public static func wallClockHours(elapsedHours: Double, span: ZoneSpan) -> Double {
        elapsedHours + span.shiftHours
    }

    // MARK: - 4. Sleep that is not a night

    /// Hours of sleep the night rule discarded, per calendar day.
    ///
    /// `SleepNights` drops any segment starting between noon and 18:00, which is
    /// how a 3 pm nap is kept from adding its minutes to last night. On a travel
    /// day that filter eats a real four-hour sleep over the Timor Sea and says
    /// nothing. This reports exactly the hours that filter removed — it does not
    /// change the filter, and must not: promoting daytime sleep into a night is
    /// the "7.5 h night reported as 4 h" family of defect that
    /// `SleepNights.minimumNightSeconds` and the Oura nap rule exist to close.
    ///
    /// Keyed by the calendar day the sleep began on, in `calendar`, because
    /// daytime sleep genuinely belongs to a day rather than to a night.
    public static func daytimeSleepHours(from segments: [SleepSegment],
                                         calendar: Calendar = .current) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for segment in segments where segment.kind.isAsleep {
            let hour = calendar.component(.hour, from: segment.start)
            // The exact complement of `SleepNights`' admission window, written
            // as the complement so the two can only ever move together.
            guard hour >= SleepNights.afternoonCutoffHour,
                  hour < Int(24 - SleepOnset.plausibleHours) else { continue }
            out[calendar.startOfDay(for: segment.start), default: 0] += segment.seconds / 3600
        }
        return out
    }

    /// The identifier `HealthKitService` catalogues Apple's per-stage segments
    /// under. Named here beside its reader, as `NightSleepDetail` does.
    static let appleSegmentIdentifier = "apple_health.sleep_segment"

    /// Sleep segments rebuilt from the raw catalogue.
    ///
    /// `HealthKitService` maps HealthKit's category samples into `SleepSegment`,
    /// hands them to `SleepNights` and then keeps them as raw rows so the
    /// hypnogram has something to draw. Those rows are persisted; the mapped
    /// segments are not. So a *view* — which sees only what was stored — has to
    /// come back through here, and this is the only way the plane nap in the
    /// reader's own history is reachable at all after the sync that fetched it.
    public static func segments(raw: [RawMetricSample]) -> [SleepSegment] {
        raw.compactMap { record in
            guard record.identifier == appleSegmentIdentifier,
                  case .text(let name) = record.value,
                  let kind = SleepSegment.Kind(rawValue: name),
                  record.end > record.start else { return nil }
            return SleepSegment(kind: kind, start: record.start, end: record.end)
        }
    }

    /// Daytime sleep from the raw catalogue, across **both** sources.
    ///
    /// The segment-based overload above can only see Apple, because Apple is the
    /// only source that publishes segments. Oura publishes whole records with a
    /// `type`, and `OuraResponseParser.countsTowardNight` is the one rule that
    /// decides whether such a record is part of a night — the same rule the
    /// parser and the model-internals export already share, called here rather
    /// than restated so a third answer cannot appear.
    ///
    /// ⚠️ **The reader's plane sleep is most likely an Oura record, not an Apple
    /// segment.** Reading only segments would have surfaced nothing at all for
    /// the journey this whole row exists to describe, on the one source they
    /// wear every night.
    ///
    /// ⚠️ **Known and left alone: the two paths disagree about a mid-afternoon
    /// record with an unrecognised type.** `SleepNights` drops anything starting
    /// between noon and 18:00 whatever it is called; `countsTowardNight` admits
    /// an unknown type at any hour, deliberately, so that a new Oura value
    /// cannot silently empty the sleep card. So an Oura record typed `sleep` at
    /// 14:00 becomes part of a night on that path and is not reported here. That
    /// is the parser's existing decision, not this function's — changing it
    /// belongs with the fragment work, and calling `countsTowardNight` rather
    /// than restating it is what keeps this from becoming a third answer.
    public static func daytimeSleepHours(raw: [RawMetricSample],
                                         calendar: Calendar = .current) -> [Date: Double] {
        var out = daytimeSleepHours(from: segments(raw: raw), calendar: calendar)

        let typeByStart = Dictionary(
            raw.filter { $0.identifier == "oura.sleep.type" }
                .compactMap { record -> (Date, String)? in
                    guard case .text(let type) = record.value else { return nil }
                    return (record.start, type)
                },
            uniquingKeysWith: { first, _ in first })

        for record in raw where record.identifier == "oura.sleep.total_sleep_duration" {
            guard let seconds = record.numericValue, seconds > 0 else { continue }
            let hour = calendar.component(.hour, from: record.start)
            guard !OuraResponseParser.countsTowardNight(type: typeByStart[record.start],
                                                        localStartHour: hour)
            else { continue }
            out[calendar.startOfDay(for: record.start), default: 0] += seconds / 3600
        }
        return out
    }

    /// How many separate bouts of sleep these segments describe.
    ///
    /// A night on a plane is not one block: it is a doze, a meal service, and
    /// another doze. Stage segments from one continuous sleep butt up against
    /// each other, so anything separated by more than `gapSeconds` of nothing is
    /// a genuinely separate bout. Half an hour, because a shorter gap is a wake
    /// within a night — which the `awake` stage already describes — and a longer
    /// threshold would merge an evening doze into the night behind it.
    ///
    /// Reported rather than acted on: a fragmented night is still one night, and
    /// this exists so a card can say *"four separate sleeps"* instead of quietly
    /// averaging them into a figure that describes none of them.
    public static func episodes(in segments: [SleepSegment],
                                gapSeconds: Double = 30 * 60) -> Int {
        let asleep = segments.filter { $0.kind.isAsleep && $0.seconds > 0 }
            .sorted { $0.start < $1.start }
        guard var reach = asleep.first?.end else { return 0 }
        var count = 1
        for segment in asleep.dropFirst() {
            if segment.start.timeIntervalSince(reach) > gapSeconds { count += 1 }
            reach = Swift.max(reach, segment.end)
        }
        return count
    }

    // MARK: - 5. One night, described honestly

    /// Everything a card needs to render one past night in the reader's own zone
    /// without overstating what is known about it.
    public struct Night: Sendable, Equatable, Identifiable {
        /// The day this night is called, stable in the viewing calendar.
        public let day: Date
        /// The instant sleep began. Canonical; every clock time derives from it.
        public let onset: Date?
        /// Bedtime as signed hours from midnight **in the reader's current
        /// zone** — the reader's explicit instruction.
        public let onsetHoursHere: Double?
        /// The same bedtime as the clock on the wall where they actually were,
        /// or nil when no source recorded a zone. **Nil means unknown**, and a
        /// card must say unknown rather than assume it matches.
        public let onsetHoursThere: Double?
        /// Time actually asleep. Invariant to travel.
        public let elapsedHours: Double?
        /// Measured zone change across the night, when a source recorded one.
        public let zone: ZoneSpan?
        /// Sleep on this day that no night could claim — the plane nap.
        public let daytimeHours: Double?

        public var id: Date { day }
        /// Nil when nothing recorded a zone: *unknown*, not *stayed put*.
        public var crossedZones: Bool? { zone.map(\.crossed) }
        /// What a bedside clock either side of the night would have read.
        public var wallClockHours: Double? {
            guard let elapsedHours, let zone else { return nil }
            return SleepTravel.wallClockHours(elapsedHours: elapsedHours, span: zone)
        }

        public init(day: Date, onset: Date?, onsetHoursHere: Double?,
                    onsetHoursThere: Double?, elapsedHours: Double?,
                    zone: ZoneSpan?, daytimeHours: Double?) {
            self.day = day
            self.onset = onset
            self.onsetHoursHere = onsetHoursHere
            self.onsetHoursThere = onsetHoursThere
            self.elapsedHours = elapsedHours
            self.zone = zone
            self.daytimeHours = daytimeHours
        }

        /// The sentence the card prints under the figure, or nil when the night
        /// needs no explaining.
        ///
        /// **This is the "say so on screen" half of the fix and it is not
        /// optional.** A duration that silently disagrees with the clock times
        /// beside it reads as a bug; the same duration with one line saying why
        /// reads as the app knowing something the reader would otherwise have to
        /// work out. Two sentences at most, no jargon, and it never claims a
        /// flight — only that the clock moved, which is all the data says.
        public var note: String? {
            var lines: [String] = []
            if let zone, zone.crossed {
                let hours = abs(zone.shiftHours)
                let direction = zone.shift > 0 ? "forward" : "back"
                lines.append("""
                    Your clock moved \(Self.hoursText(hours)) \(direction) overnight. \
                    The figure is time actually asleep; the clock times either \
                    side of it differ by that much.
                    """)
            }
            if let onsetHoursThere, let onsetHoursHere,
               abs(onsetHoursThere - onsetHoursHere) >= 0.25 {
                lines.append("""
                    Shown in your current time zone. Where you were, \
                    it was \(Self.clockText(onsetHoursThere)).
                    """)
            }
            if let daytimeHours, daytimeHours >= 0.5 {
                lines.append("""
                    Plus \(Self.hoursText(daytimeHours)) of daytime sleep, \
                    which is not counted in the night.
                    """)
            }
            return lines.isEmpty ? nil : lines.joined(separator: " ")
        }

        /// `2` → "2 hours", `1.5` → "1 hour 30 minutes". Built by hand rather
        /// than with a formatter: this package's suite runs on Linux, where
        /// several Foundation formatter paths are Darwin-only, and a sentence
        /// nothing can test is a sentence that ships wrong.
        public static func hoursText(_ hours: Double) -> String {
            let total = Int((abs(hours) * 60).rounded())
            var parts: [String] = []
            let h = total / 60, m = total % 60
            if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
            if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
            return parts.isEmpty ? "0 minutes" : parts.joined(separator: " ")
        }

        /// Signed hours from midnight back to a 24-hour clock: `−1.0` → "23:00".
        public static func clockText(_ signedHours: Double) -> String {
            let minutes = Int((signedHours * 60).rounded())
            let wrapped = ((minutes % 1440) + 1440) % 1440
            return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
        }
    }

    /// Every night the stored samples describe, re-rendered in `calendar` and
    /// annotated with whatever the raw catalogue knows about where the reader was.
    ///
    /// Takes the stored samples rather than segments on purpose: this is the
    /// *display* half of the fix, and its whole job is to make a two-year
    /// history that was written in half a dozen zones read correctly today,
    /// without re-syncing any of it.
    public static func nights(samples: [HealthMetricSample],
                              raw: [RawMetricSample] = [],
                              segments: [SleepSegment] = [],
                              calendar: Calendar = .current) -> [Night] {
        let zones = spans(raw: raw, calendar: calendar)
        // Both sources, and `segments` on top for a caller holding freshly
        // mapped ones the catalogue has not been written from yet. `max` rather
        // than `+`: the raw sweep already contains the Apple segments, so adding
        // would count the same nap twice for any caller that passes both.
        var daytime = daytimeSleepHours(raw: raw, calendar: calendar)
        for (day, hours) in daytimeSleepHours(from: segments, calendar: calendar) {
            daytime[day] = Swift.max(daytime[day] ?? 0, hours)
        }

        // Through `onsets(in:)` rather than re-deriving the pair here, so this
        // section and every chart elsewhere in the app cannot end up with two
        // answers for one night. The re-render keeps key and value in the
        // viewing zone together; `here` is read back off the pair for the same
        // reason.
        var onsets: [Date: (instant: Date, here: Double)] = [:]
        for sample in Self.onsets(in: samples, calendar: calendar) {
            let instant = sample.start.addingTimeInterval(sample.value * 3600)
            // Earliest wins, matching `SleepOnset.samples`' own rule, so two
            // sources describing one night cannot produce two answers here.
            if let held = onsets[sample.start], held.instant <= instant { continue }
            onsets[sample.start] = (instant, sample.value)
        }

        var durations: [Date: Double] = [:]
        for sample in samples where sample.type == .sleepDurationHours {
            let day = nightDay(of: sample.start, calendar: calendar)
            durations[day] = Swift.max(durations[day] ?? 0, sample.value)
        }

        let days = Set(onsets.keys).union(durations.keys).union(daytime.keys)
        return days.sorted().map { day in
            let zone = zones[day]
            // The clock where they were = the clock here, plus the difference
            // between the two zones at that moment. Only computable when a
            // source actually recorded the offset; otherwise it stays nil, and
            // nil is reported as unknown.
            let there: Double? = onsets[day].flatMap { onset -> Double? in
                guard let zone else { return nil }
                let hereOffset = Double(calendar.timeZone.secondsFromGMT(for: onset.instant))
                let shifted = onset.here + (zone.atSleep - hereOffset) / 3600
                // Fold back into the ±12 band the encoding uses.
                return shifted > 12 ? shifted - 24 : (shifted < -12 ? shifted + 24 : shifted)
            }
            return Night(day: day,
                         onset: onsets[day]?.instant,
                         onsetHoursHere: onsets[day]?.here,
                         onsetHoursThere: there,
                         elapsedHours: durations[day],
                         zone: zone,
                         daytimeHours: daytime[day])
        }
    }
}
