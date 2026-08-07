import Foundation

/// **Jetlag: how much, how it landed, and how long a recovery would take to
/// measure.**
///
/// The reader, 2026-08-07: *"One thing I want on the travel card: A way to
/// calculate jetlag, and how that impacts you, and how long it takes to recover
/// from it."* (Backlog `B21`.)
///
/// ## The dose is a signed phase shift, not hours in the air
///
/// A fourteen-hour flight north–south costs nothing circadian; a two-hour hop
/// across a zone boundary costs something. What the body has to do is move its
/// clock, so the dose is **the signed change in UTC offset**, and the sign
/// matters as much as the size.
///
/// ## Why eastward is harder — derived, then checked against the literature
///
/// ⚠️ **This is the one number on this card that could have become another
/// unlabelled constant, which is `B19`'s failure exactly. It is written here
/// with both its derivation and its source so that cannot happen quietly.**
///
/// The human circadian pacemaker does not run at 24 h. Under forced desynchrony
/// — the design that removes the subject's ability to self-select a schedule and
/// is therefore the one that can measure τ at all — Czeisler and colleagues
/// (*Science*, 1999; 284:2177–2181) put the intrinsic period at **≈ 24.18 h**,
/// with a strikingly small spread across their 24 subjects and no difference
/// between the young and the old.
///
/// τ > 24 h means the unconstrained clock **drifts later** every day. Flying
/// west asks it to go later, which is the direction it already wants; flying
/// east asks it to go earlier, against the drift. So the achievable phase shift
/// per day is asymmetric *by construction* — the derivation gives the sign of
/// the asymmetry, and it gives it for free.
///
/// The derivation does **not** give the size, and pretending otherwise would be
/// the same sin one level down. The size is measured, and the figures used here
/// are the standard clinical ones: roughly **1 day of adjustment per time zone
/// travelling west and about 1.5 travelling east** (Waterhouse, Reilly,
/// Atkinson & Edwards, *"Jet lag: trends and coping strategies"*, **Lancet**
/// 2007;369:1117–1129), equivalently a phase **delay** of about 1 h/day against
/// a phase **advance** of about 0.5–1 h/day (Eastman & Burgess, *"How to travel
/// the world without jet lag"*, **Sleep Medicine Clinics** 2009;4:241–255).
///
/// **These are population rates and this app says so wherever it prints them.**
/// They are not a measurement of this reader — the whole point of `tripsNeeded`
/// below is to say what it would take to replace them with one.
///
/// ## What this deliberately does not do
///
/// It does not fit a recovery curve. `TravelDrainModel.minimumTrips` is 2 and
/// the reader's record holds about that many; a curve through two trips is a
/// drawing, not a measurement. `tripsNeeded(effectSD:)` answers the question
/// that *is* answerable — how many trips before a fitted return means anything —
/// and it is answered from a power calculation with its effect size stated, not
/// from a number somebody liked the look of.
public enum JetlagModel {

    // MARK: - The published rates

    /// The intrinsic circadian period, hours. Czeisler et al., *Science* 1999.
    ///
    /// Carried as a stored constant rather than inlined because it is what makes
    /// the *direction* of the asymmetry a derivation instead of an assertion,
    /// and `directionRationale` prints it.
    public static let intrinsicPeriodHours: Double = 24.18

    /// Days of adjustment per time zone crossed **westward** (phase delay).
    /// Waterhouse et al., *Lancet* 2007.
    public static let daysPerZoneWestward: Double = 1.0

    /// Days of adjustment per time zone crossed **eastward** (phase advance).
    /// Waterhouse et al., *Lancet* 2007.
    public static let daysPerZoneEastward: Double = 1.5

    /// The sentence a card prints under the estimate. Lives here, in InsightKit,
    /// because it is the claim — and the app target has no test target.
    public static let directionRationale =
        "Going east is harder than going west, and that is not a rule of thumb: "
        + "the body clock free-runs slightly longer than a day — about "
        + "24.2 hours — so it drifts later on its own. Flying west asks it to go "
        + "later, which it was doing anyway. Flying east asks it to go earlier, "
        + "against the drift. The rates used here are published population "
        + "figures — about a day per time zone westward and about one and a half "
        + "eastward — not a measurement of you."

    /// The literature this card's estimate rests on, for the reader who wants it.
    public static let sources = [
        "Czeisler et al., Science 1999 — intrinsic circadian period ≈ 24.18 h.",
        "Waterhouse, Reilly, Atkinson & Edwards, Lancet 2007 — ~1 day per zone "
            + "westward, ~1.5 eastward.",
        "Eastman & Burgess, Sleep Medicine Clinics 2009 — phase delay ~1 h/day "
            + "against phase advance ~0.5–1 h/day.",
    ]

    // MARK: - One crossing

    /// A time-zone change, with everything known about how it was established.
    public struct Crossing: Sendable, Equatable, Identifiable {

        /// Where the fact came from, because the two are not equally good.
        public enum Evidence: String, Sendable, Equatable {
            /// A UTC offset recorded on the reading itself — see `SleepTravel`.
            /// The night's two ends carried different offsets, so the clock
            /// genuinely moved.
            case measured
            /// Inferred from the time zone stamped on calendar events. A reader
            /// who sets one event in another zone by hand produces the identical
            /// shape, and `CalendarModel.timeZoneChanges` says so itself.
            case calendar
        }

        public let day: Date
        /// Signed hours the clock moved. **Positive is eastward** — the clock
        /// went forward — which is the harder direction. Folded into (−12, +12].
        public let shiftHours: Double
        /// Zone left, when known. Nil for the first zone the record ever saw.
        public let from: String?
        /// Zone arrived in, when known.
        public let to: String?
        public let evidence: Evidence

        public var id: Date { day }
        public var isEastward: Bool { shiftHours > 0 }

        /// Days the published rates expect this dose to take.
        public var adjustmentDays: Double {
            JetlagModel.adjustmentDays(shiftHours: shiftHours)
        }

        /// ⚠️ **A measured one-hour shift may be daylight saving, not a flight.**
        ///
        /// The measured path reads a UTC offset off the reading and compares the
        /// two ends of a night. A clock going forward an hour on the last Sunday
        /// in March produces exactly that, and the offset alone cannot tell the
        /// two apart. It is still a real one-hour circadian shift — so it is not
        /// dropped — but a card must not call it a journey.
        ///
        /// The calendar path is immune: it keys on the zone *identifier*, and
        /// `Australia/Sydney` is `Australia/Sydney` on both sides of a DST
        /// boundary.
        public var possiblyDaylightSaving: Bool {
            evidence == .measured && abs(abs(shiftHours) - 1) < 0.05
        }

        public init(day: Date, shiftHours: Double, from: String?, to: String?,
                    evidence: Evidence) {
            self.day = day
            self.shiftHours = shiftHours
            self.from = from
            self.to = to
            self.evidence = evidence
        }
    }

    /// A signed offset difference folded into the half-open band (−12, +12].
    ///
    /// Sydney to Los Angeles is −19 h written out, and nobody's body delays
    /// nineteen hours: it advances five, the short way round. Folding is what
    /// makes the dose the *phase shift the clock has to make* rather than the
    /// arithmetic difference of two offsets.
    ///
    /// Exactly +12 is kept positive rather than folded to −12. It is a genuine
    /// tie — the clock can go either way — and treating it as the harder
    /// direction is the conservative reading of an estimate.
    public static func fold(_ hours: Double) -> Double {
        var folded = hours.truncatingRemainder(dividingBy: 24)
        if folded > 12 { folded -= 24 }
        if folded <= -12 { folded += 24 }
        return folded
    }

    /// Days of adjustment the published rates expect for a signed shift.
    ///
    /// Linear in the shift, which is what the source rates are — a *per zone*
    /// figure. It is not claimed to be linear beyond that: `Lancet` 2007 gives
    /// the rates as a rule of thumb over ordinary journeys, and beyond about
    /// eight zones the literature's own agreement thins.
    ///
    /// ⚠️ **The direction is read off the *folded* shift, never the raw one.**
    /// Sydney → Los Angeles is −19 h subtracted and +5 h folded: written out it
    /// looks westward, and the body advances. Testing the sign before folding
    /// charged that journey the easy rate and is the kind of error that never
    /// shows up until somebody actually flies the Pacific.
    public static func adjustmentDays(shiftHours: Double) -> Double {
        let folded = fold(shiftHours)
        return abs(folded) * (folded > 0 ? daysPerZoneEastward : daysPerZoneWestward)
    }

    /// The window a card should compare over, in whole days, for one crossing.
    ///
    /// ⚠️ **This is the figure `TravelDrainModel.recoveryDays = 4` should have
    /// been.** That constant has no source and does not vary with the dose: a
    /// one-zone hop and a twelve-zone haul got the same four days. This one is
    /// the dose times a published rate, floored at one day (a crossing that
    /// happened is at least one disrupted day) and capped, because a comparison
    /// window that swallows a fortnight stops being a comparison.
    ///
    /// It is deliberately **not** wired into `TravelDrainModel` here: that would
    /// move a shipped figure and its derived series inside a parallel wave. See
    /// the note on `TravelDrainModel.recoveryDays`.
    public static func windowDays(shiftHours: Double) -> Int {
        let days = adjustmentDays(shiftHours: shiftHours)
        return Swift.min(maximumWindowDays, Swift.max(1, Int(days.rounded(.up))))
    }

    /// Fourteen. Beyond a fortnight the "days after a trip" set stops being
    /// distinguishable from "days", and the contrast the card draws collapses.
    public static let maximumWindowDays = 14

    // MARK: - Finding the crossings

    /// Crossings inferred from the zones stamped on calendar events.
    ///
    /// ⚠️ **Why this walks the events rather than calling
    /// `CalendarModel.timeZoneChanges`.** That function returns the day and the
    /// zone moved *to*, and deliberately drops the zone moved *from* — which is
    /// exactly the term a signed offset needs. Reconstructing the previous zone
    /// from the previous element loses the very first change, and with two trips
    /// on the record losing one is losing half the evidence.
    ///
    /// The two must agree about *how many* changes there are, and they do:
    /// same key (`startOfDay` of the event start), same ordering, same
    /// "different from the one before" test. If `timeZoneChanges` ever returns
    /// its `from` zone, delete this and call it.
    public static func crossings(events: [CalendarEvent],
                                 calendar: Calendar = .current) -> [Crossing] {
        let dated = events
            .compactMap { event -> (Date, String)? in
                guard let zone = event.timeZoneIdentifier else { return nil }
                return (calendar.startOfDay(for: event.start), zone)
            }
            .sorted { $0.0 < $1.0 }

        var out: [Crossing] = []
        var previous: String?
        for (day, zone) in dated where zone != previous {
            defer { previous = zone }
            guard let from = previous else { continue }
            // The offset *on the day of the change*, not today's: a zone's
            // offset moves with daylight saving, and asking `TimeZone` for
            // "now" would misdate every winter crossing by an hour.
            guard let before = TimeZone(identifier: from),
                  let after = TimeZone(identifier: zone) else { continue }
            let shift = Double(after.secondsFromGMT(for: day)
                               - before.secondsFromGMT(for: day)) / 3600
            guard abs(shift) * 3600 >= SleepTravel.ZoneSpan.smallestRealZoneStep else { continue }
            out.append(Crossing(day: day, shiftHours: fold(shift),
                                from: from, to: zone, evidence: .calendar))
        }
        return out
    }

    /// Crossings **measured**, from the UTC offsets `SleepTravel` recovers off
    /// the readings themselves.
    ///
    /// This is the stronger evidence of the two and did not exist before
    /// 2026-08-07: a night whose two ends carry different offsets crossed a
    /// zone, and no inference is involved. It is also sparser — only providers
    /// that stamp an offset produce it, which today means Oura.
    public static func crossings(spans: [Date: SleepTravel.ZoneSpan]) -> [Crossing] {
        spans.filter(\.value.crossed)
            .map { day, span in
                Crossing(day: day, shiftHours: fold(span.shiftHours),
                         from: nil, to: nil, evidence: .measured)
            }
            .sorted { $0.day < $1.day }
    }

    /// One list of crossings, measurement preferred.
    ///
    /// A journey usually shows up in both places — the calendar knows the
    /// meeting was in Manila, the ring knows the clock moved eight hours — and
    /// counting it twice would double the reader's trip count and halve the
    /// apparent evidence per trip. Two crossings within `mergeWindowDays` of
    /// each other are one journey, and the measured one wins because it is the
    /// one that was recorded rather than inferred.
    ///
    /// Two days, because a flight that leaves on the 6th lands on the 7th, the
    /// calendar keys the meeting on the day it happens, and the ring keys the
    /// night on the morning it ends — three ways of naming one journey, spread
    /// over at most two days.
    public static let mergeWindowDays = 2

    public static func merged(_ lists: [Crossing]...,
                              calendar: Calendar = .current) -> [Crossing] {
        // Measured first, so the `contains` test below always keeps it.
        let all = lists.flatMap { $0 }
            .sorted { a, b in
                if a.evidence != b.evidence { return a.evidence == .measured }
                return a.day < b.day
            }
        var kept: [Crossing] = []
        for crossing in all {
            let clash = kept.contains { held in
                abs(held.day.timeIntervalSince(crossing.day))
                    <= Double(mergeWindowDays) * 86_400
            }
            if !clash { kept.append(crossing) }
        }
        return kept.sorted { $0.day < $1.day }
    }

    // MARK: - How many trips a measured recovery would need

    /// Two-sided α = 0.05 → 1.96, and 80% power → 0.8416.
    ///
    /// Written as named constants rather than a `probit` call: this package's
    /// suite runs on Linux, the two values are the ones every power table in
    /// medicine is built on, and a normal-quantile routine written here to
    /// produce two known numbers would be more code and more to be wrong.
    static let zAlphaTwoSided = 1.959_964
    static let zPower80 = 0.841_621

    /// **How many trips before a fitted recovery curve would mean anything.**
    ///
    /// The row this answers asks for a number rather than a fit, and this is how
    /// the number is got. A recovery curve is a per-day estimate: the mean of a
    /// channel on day 1 after a crossing, day 2, day 3 and so on. Each trip
    /// contributes **one observation to each of those days**, so the number of
    /// trips *is* the sample size at every point on the curve.
    ///
    /// For a one-sample comparison against the reader's own ordinary spread,
    /// n = ((z_α + z_β) / δ)² where δ is the effect in standard deviations of
    /// that spread. A full standard deviation — a large effect, and the most
    /// generous assumption available — needs **8**. Half a standard deviation,
    /// which is nearer what `TravelDrainModel` actually observes across its
    /// channels, needs **32**.
    ///
    /// So the honest answer to *"when can you tell me how long I take to
    /// recover?"* is not "soon": it is eight trips for a big effect and thirty
    /// or so for a realistic one — and that is the sentence the card prints.
    public static func tripsNeeded(effectSD: Double) -> Int {
        guard effectSD > 0 else { return .max }
        let n = pow((zAlphaTwoSided + zPower80) / effectSD, 2)
        return Swift.max(2, Int(n.rounded(.up)))
    }

    // MARK: - What the body did

    /// One watched signal, in the days after a crossing, against ordinary days.
    public struct Response: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        /// Mean over the days inside a crossing's expected adjustment window.
        public let afterCrossing: Double
        /// Mean over every other day in range.
        public let ordinary: Double
        /// How many days actually carried a reading inside the windows. **The
        /// denominator, printed** — a delta over three days is not the same
        /// claim as a delta over thirty and must not look like one.
        public let daysCounted: Int
        /// Signed in standard deviations of the reader's own ordinary spread,
        /// positive being the unwelcome direction. Comparable across channels;
        /// `difference` is not.
        public let towardWorse: Double

        public var id: String { metric.rawValue }
        public var difference: Double { afterCrossing - ordinary }

        public init(metric: MetricType, afterCrossing: Double, ordinary: Double,
                    daysCounted: Int, towardWorse: Double) {
            self.metric = metric
            self.afterCrossing = afterCrossing
            self.ordinary = ordinary
            self.daysCounted = daysCounted
            self.towardWorse = towardWorse
        }
    }

    public struct Output: Sendable, Equatable {
        /// Every crossing found, oldest first.
        public let crossings: [Crossing]
        /// The most recent one — the trip the reader is actually asking about.
        public let latest: Crossing?
        /// Per-channel movement across every crossing's window pooled together.
        /// **Not a score, and never scored.** See `Readiness`.
        public let responses: [Response]
        /// Trips before a fitted recovery curve is supportable at a large
        /// effect, and at a realistic one.
        public let tripsForLargeEffect: Int
        public let tripsForModerateEffect: Int

        /// Whether anything here was measured rather than inferred.
        public var hasMeasuredCrossing: Bool {
            crossings.contains { $0.evidence == .measured }
        }
    }

    /// Ready, or waiting on something nameable.
    ///
    /// Same shape and same reason as `TravelDrainModel.Readiness`: a card that
    /// says *"connect your calendar"* to a reader whose calendar is connected
    /// has named the wrong cause, and they act on it and nothing changes. That
    /// was a defect the reader found on their own phone on 2026-08-07.
    public enum Readiness: Sendable {
        case ready(Output)
        /// Crossings exist but the body data around them does not.
        case waiting(CoverageGate)
        /// One crossing, or none. A single flight is an anecdote; the dose can
        /// still be stated — it is arithmetic on an offset — but nothing about
        /// how it *landed* can be.
        case doseOnly(Output)
        /// Nothing anywhere knows the reader moved.
        case noEvidence
    }

    /// Everything the section needs, in one pass.
    ///
    /// `spans` comes from `SleepTravel.spans(raw:)` and is the measured half;
    /// `events` is the calendar half. Either may be empty.
    public static func analyse(events: [CalendarEvent],
                               spans: [Date: SleepTravel.ZoneSpan] = [:],
                               samples: [HealthMetricSample],
                               now: Date = Date(),
                               calendar: Calendar = .current) -> Readiness {
        let found = merged(crossings(spans: spans),
                           crossings(events: events, calendar: calendar),
                           calendar: calendar)
        guard !found.isEmpty else { return .noEvidence }

        // Days inside any crossing's own expected window — the union, so two
        // trips a week apart are not counted twice, and each window is the
        // length that crossing's dose earns rather than a flat four days.
        var disrupted = Set<Date>()
        for crossing in found {
            for offset in 0..<windowDays(shiftHours: crossing.shiftHours) {
                guard let day = calendar.date(byAdding: .day, value: offset,
                                              to: crossing.day) else { continue }
                disrupted.insert(calendar.startOfDay(for: day))
            }
        }

        var responses: [Response] = []
        for entry in WorkImpactModel.watched {
            let daily = VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                                calendar: calendar)
            let after = daily.filter { disrupted.contains($0.date) }.map(\.value)
            let ordinary = daily.filter { !disrupted.contains($0.date) }.map(\.value)
            guard after.count >= 2, ordinary.count >= 14,
                  let afterMean = Baseline.mean(after),
                  let ordinaryMean = Baseline.mean(ordinary),
                  let spread = Baseline.robustScale(ordinary), spread > 0
            else { continue }
            let raw = (afterMean - ordinaryMean) / spread
            responses.append(Response(metric: entry.metric,
                                      afterCrossing: afterMean,
                                      ordinary: ordinaryMean,
                                      daysCounted: after.count,
                                      towardWorse: entry.higherIsWorse ? raw : -raw))
        }

        let out = Output(crossings: found,
                         latest: found.last,
                         responses: responses.sorted { $0.towardWorse > $1.towardWorse },
                         tripsForLargeEffect: tripsNeeded(effectSD: 1.0),
                         tripsForModerateEffect: tripsNeeded(effectSD: 0.5))

        // One crossing states its dose and stops. The dose is arithmetic on an
        // offset and is true of one trip; everything downstream is a contrast,
        // and a contrast needs something to contrast against.
        guard found.count >= TravelDrainModel.minimumTrips else { return .doseOnly(out) }
        guard responses.count >= 2 else {
            return .waiting(CoverageGate(
                need: 2, have: responses.count, unit: "responding signal",
                unlocks: "this can show what a time-zone change actually does to "
                    + "you rather than only what the textbook says it should"))
        }
        return .ready(out)
    }
}
