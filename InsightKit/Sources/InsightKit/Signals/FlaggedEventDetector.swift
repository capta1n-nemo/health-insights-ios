import Foundation

/// **Finds the stretches worth asking about.**
///
/// One measured pattern, implemented honestly: a run of heart-rate readings
/// sitting well above *this person's own* typical level for *that part of the
/// day*, lasting long enough to be a stretch rather than an artefact, with too
/// little movement to explain it.
///
/// ## Why the reference is per-daypart and per-person
///
/// A single resting heart rate for a whole person is wrong twice. It is wrong
/// across people — the useful spread between adults is wider than most of the
/// departures this looks for — and it is wrong across the day, because everyone's
/// heart rate has a circadian shape and an evening reading judged against a
/// 24-hour average would flag every evening. So the reference is the median of
/// the reader's own readings in the same daypart over the preceding weeks, and
/// the spread is their own median absolute deviation.
///
/// **Median and MAD rather than mean and SD**, because the thing being detected
/// is an outlier and a mean is dragged by the outliers it is supposed to be
/// measuring against. MAD × 1.4826 is the standard consistency scaling to a
/// normal σ, which is what lets `FlagEvidence.departures` be described to the
/// reader as "your own normal variation" without lying about the units.
///
/// ## What it deliberately does not do
///
/// - **It does not flag anything movement explains.** A run, a brisk walk and a
///   flight of stairs all raise heart rate for the obvious reason, and a feed
///   that asked about them would be answered once and never opened again.
///   Attention is the scarce resource here. `activityStepFloor` is the line, and
///   the cost of drawing it is real: a reader can never tell the app "that
///   wasn't exercise", because those never reach them.
/// - **It does not infer a cause from physiology.** It cannot. Nothing in a
///   heart-rate trace distinguishes arousal from anxiety from an argument.
///   `candidates` is built from the *substance log* (which the reader wrote) and
///   from time-of-day priors (which are labelled as guesses), and never from the
///   shape of the signal.
/// - **It does not run on thin history.** `referenceGate` refuses below
///   `minimumReferenceDays`, and a detector with no reference has nothing to
///   call unusual.
public enum FlaggedEventDetector {

    /// Bumped whenever the rules below change in a way that would move a guess.
    /// Stored on every event and every artifact, so a judgement made against one
    /// version is never silently counted as evidence about another.
    public static let modelVersion = "flagged-event-1"

    // MARK: - The thresholds, and what each costs

    /// Days of the reader's own history the reference is built from.
    ///
    /// Four weeks: long enough that a fortnight of unusual living does not
    /// become the baseline, short enough that a genuine change in fitness is not
    /// fought against for a season.
    public static let referenceWindowDays = 28

    /// Days below which nothing is flagged at all. The reference has to be a
    /// reference before a departure from it means anything, and this is the
    /// refusal `CoverageGate` was made for.
    public static let minimumReferenceDays = 14

    /// Readings in a daypart before that daypart gets a reference. A median over
    /// six readings is a number, not a typical level.
    public static let minimumReferenceSamples = 20

    /// How far above typical a reading has to sit to count as elevated, in the
    /// reader's own robust standard deviations.
    ///
    /// 2.5 rather than 2: at 2 an ordinary week produces a handful of flags a
    /// day and the feed becomes noise, and a feed nobody opens measures nothing.
    /// The cost is stated rather than hidden — quieter departures are not
    /// surfaced at all, and the app never claims to have seen everything.
    public static let departureThreshold: Double = 2.5

    /// The shortest stretch worth a question. Under ten minutes a heart-rate
    /// excursion is as likely to be a strap moving as anything about the person.
    public static let minimumMinutes: Double = 10

    /// The fewest readings a stretch may be built from. A window can clear the
    /// duration bar on two samples forty minutes apart, and two points do not
    /// describe a stretch.
    public static let minimumSamples = 3

    /// How long a hole in the readings may be before a stretch is treated as
    /// two. Wearables drop out; 12 minutes bridges an ordinary gap without
    /// welding a morning and an evening together.
    public static let maximumGapMinutes: Double = 12

    /// Steps inside the window above which movement is taken to explain the
    /// elevation and nothing is flagged. Roughly a minute of walking.
    public static let activityStepFloor: Double = 120

    /// How long before the window a logged substance can still be a candidate.
    /// Generous on purpose: this raises an *option*, it does not assert a cause,
    /// and a caffeine peak three hours out is a perfectly reasonable thing to
    /// offer the reader.
    public static let substanceLookbackHours: Double = 3

    /// The most events to return from one pass, newest first. A backlog of
    /// eighty questions is not a feed.
    public static let maximumEvents = 20

    // MARK: - Detection

    /// - Parameters:
    ///   - samples: The full history. Heart rate drives detection; steps are
    ///     read to rule movement in or out.
    ///   - substanceEvents: The reader's own log, the only evidence-backed
    ///     source of candidates.
    ///   - since: Only windows starting at or after this are returned. The
    ///     reference is still built from everything before it.
    public static func detect(samples: [HealthMetricSample],
                              substanceEvents: [SubstanceEvent] = [],
                              since: Date? = nil,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> [FlaggedEvent] {
        let referenceStart = calendar.date(byAdding: .day, value: -referenceWindowDays,
                                           to: now) ?? .distantPast

        // ⚠️ **Scoped to the window *before* `samples(of:)`, and that ordering is
        // the whole cost of this function.**
        //
        // `samples(of:)` filters and then **sorts what survives**. On the
        // reader's own three-year export that is ~315k heart-rate readings
        // sorted to find the ~8k inside a four-week window — measured at 3.0 s
        // per call, and `recompute()` has thirty-three call sites, so the app
        // target's tests were SIGKILLed by the watchdog before this line existed
        // in its current form. It is also exactly the freeze the reader reported
        // on 2026-08-06 (*"the app becomes unresponsive"*), which is why the
        // insight pass runs off the main actor; this runs on it, so it has to be
        // cheap rather than merely elsewhere.
        //
        // One pass over the whole history, then everything else works on a
        // month. 473k samples: 3.0 s → 0.03 s.
        let scoped = samples.filter { $0.start >= referenceStart && $0.start <= now }
        let heart = scoped.samples(of: .heartRate)
        guard !heart.isEmpty else { return [] }

        guard let coverage = coverageDays(of: heart, calendar: calendar),
              coverage >= minimumReferenceDays else { return [] }

        let references = daypartReferences(heart, calendar: calendar)
        guard !references.isEmpty else { return [] }

        let steps = scoped.samples(of: .stepCount)
        let windowFloor = since ?? referenceStart

        // Elevated readings, in order, each judged against its own daypart.
        var elevated: [HealthMetricSample] = []
        for sample in heart where sample.start >= windowFloor && sample.start <= now {
            guard let ref = references[Daypart(of: sample.start, calendar: calendar)],
                  ref.spread > 0 else { continue }
            if (sample.value - ref.typical) / ref.spread >= departureThreshold {
                elevated.append(sample)
            }
        }

        var out: [FlaggedEvent] = []
        for run in runs(of: elevated) {
            guard run.count >= minimumSamples,
                  let first = run.first, let last = run.last else { continue }
            let start = first.start
            let end = Swift.max(last.end, last.start)
            guard end.timeIntervalSince(start) >= minimumMinutes * 60 else { continue }
            guard let ref = references[Daypart(of: start, calendar: calendar)] else { continue }

            let stepsInWindow = stepsBetween(start, end, in: steps)
            // Movement explains it. Not flagged, and the cost of that is on the
            // type comment rather than hidden here.
            if let stepsInWindow, stepsInWindow >= activityStepFloor { continue }

            let evidence = FlagEvidence(peak: run.map(\.value).max() ?? first.value,
                                        typical: ref.typical,
                                        spread: ref.spread,
                                        referenceDays: coverage,
                                        stepsInWindow: stepsInWindow,
                                        sampleCount: run.count)
            let event = FlaggedEvent(
                id: identifier(start: start, trigger: .restingHeartRateElevation),
                start: start, end: end,
                trigger: .restingHeartRateElevation,
                evidence: evidence,
                place: .unobserved,
                candidates: candidates(for: start, end: end,
                                       substanceEvents: substanceEvents,
                                       calendar: calendar))
            out.append(event)
        }

        return Array(out.sorted { $0.start > $1.start }.prefix(maximumEvents))
    }

    /// **What the feed is waiting for, when it has nothing to show.**
    ///
    /// Rule 7's obligation: an empty surface must say what it needs, not sit
    /// blank. Nil once the history is deep enough — a met gate says nothing.
    public static func referenceGate(samples: [HealthMetricSample],
                                     now: Date = Date(),
                                     calendar: Calendar = .current) -> CoverageGate? {
        let referenceStart = calendar.date(byAdding: .day, value: -referenceWindowDays,
                                           to: now) ?? .distantPast
        // Scoped before `samples(of:)`, for the reason `detect` gives at length.
        let heart = samples
            .filter { $0.type == .heartRate && $0.start >= referenceStart && $0.start <= now }
        return CoverageGate.ifShort(
            need: minimumReferenceDays,
            have: coverageDays(of: heart, calendar: calendar) ?? 0,
            // ⚠️ **A bare noun, because `CoverageGate` pluralises by appending
            // an "s".** This said "day of heart-rate history" and the simulator
            // rendered *"14 day of heart-rate historys"* — the gate has no way
            // to know which word in a phrase takes the plural. Whatever this
            // unit is has to read correctly with an "s" on the end of it.
            unit: "day",
            unlocks: "the app can tell an unusual half-hour of heart rate from an ordinary one")
    }

    // MARK: - The reference

    /// Which quarter of the day a reading falls in.
    ///
    /// Four buckets rather than 24 hourly ones: an hourly reference needs 24×
    /// the history to reach the same confidence, and the circadian shape this is
    /// correcting for is broad. Named rather than numbered so the code reads.
    enum Daypart: String, CaseIterable, Hashable {
        case night, morning, afternoon, evening

        init(of date: Date, calendar: Calendar) {
            switch calendar.component(.hour, from: date) {
            case 0..<6: self = .night
            case 6..<12: self = .morning
            case 12..<18: self = .afternoon
            default: self = .evening
            }
        }
    }

    struct Reference: Equatable {
        let typical: Double
        let spread: Double
        let count: Int
    }

    /// A robust typical level and spread per daypart, from the reader's own
    /// readings. Dayparts with too little in them are simply absent, so a
    /// reading in one of them is never judged.
    static func daypartReferences(_ samples: [HealthMetricSample],
                                  calendar: Calendar) -> [Daypart: Reference] {
        var buckets: [Daypart: [Double]] = [:]
        for sample in samples {
            buckets[Daypart(of: sample.start, calendar: calendar), default: []]
                .append(sample.value)
        }
        var out: [Daypart: Reference] = [:]
        for (part, values) in buckets where values.count >= minimumReferenceSamples {
            guard let typical = median(values) else { continue }
            // MAD × 1.4826 — the consistency constant that puts a median
            // absolute deviation on the same scale as a normal σ, so
            // `departures` can honestly be described as standard deviations of
            // the reader's own variation.
            guard let mad = median(values.map { abs($0 - typical) }) else { continue }
            let spread = mad * 1.4826
            // A perfectly flat stretch of readings (a stuck sensor, or a device
            // reporting one value all night) yields a zero spread, and dividing
            // by it would make every subsequent reading infinitely unusual. The
            // daypart is dropped instead.
            guard spread > 0 else { continue }
            out[part] = Reference(typical: typical, spread: spread, count: values.count)
        }
        return out
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// How many distinct days carry a reading. **Not the span** — a set with one
    /// reading in January and one in March covers two days, not sixty, and the
    /// gate has to say the true thing.
    static func coverageDays(of samples: [HealthMetricSample],
                             calendar: Calendar) -> Int? {
        guard !samples.isEmpty else { return nil }
        return Set(samples.map { calendar.startOfDay(for: $0.start) }).count
    }

    // MARK: - Windows

    /// Group consecutive elevated readings, splitting on a gap.
    static func runs(of samples: [HealthMetricSample]) -> [[HealthMetricSample]] {
        guard !samples.isEmpty else { return [] }
        var out: [[HealthMetricSample]] = []
        var current: [HealthMetricSample] = [samples[0]]
        for sample in samples.dropFirst() {
            let previous = current[current.count - 1]
            let gap = sample.start.timeIntervalSince(Swift.max(previous.end, previous.start))
            if gap > maximumGapMinutes * 60 {
                out.append(current)
                current = [sample]
            } else {
                current.append(sample)
            }
        }
        out.append(current)
        return out
    }

    /// Steps recorded across a window. Nil when nothing overlaps at all — which
    /// is **not** the same as zero steps, and the evidence sentence says so.
    /// A watch that was off the wrist reports nothing; a person sitting still
    /// reports nought.
    static func stepsBetween(_ start: Date, _ end: Date,
                             in steps: [HealthMetricSample]) -> Double? {
        let overlapping = steps.filter { $0.end > start && $0.start < end }
        guard !overlapping.isEmpty else { return nil }
        // Whole samples rather than a pro-rata slice: HealthKit's step buckets
        // are already short, and apportioning one would invent a within-bucket
        // distribution nobody measured.
        return overlapping.reduce(0) { $0 + $1.value }
    }

    /// Stable across re-runs. Rounded to the minute so a re-detection that moves
    /// a window's start by a few seconds does not mint a new question the reader
    /// has already answered.
    static func identifier(start: Date, trigger: FlagTrigger) -> String {
        let minute = (start.timeIntervalSince1970 / 60).rounded(.down)
        return "\(trigger.rawValue)-\(Int(minute))"
    }

    // MARK: - Candidates

    /// The option list, best first.
    ///
    /// ⚠️ **Two tiers, and they are not comparable.** Anything the reader logged
    /// is evidence and outranks everything else. Everything below it is a prior
    /// about the time of day and is weighted low enough that it can never
    /// overtake a logged event — which is the only ordering guarantee this
    /// function makes, and the only one it can honestly make.
    ///
    /// Place is **not** an input. There is no published basis for "an unusual
    /// location makes intimacy more likely than stress", and inventing one would
    /// be exactly the modelled-dressed-as-measured failure this app is built
    /// against. Location earns its place on the card as a memory aid for the
    /// reader and nowhere else.
    static func candidates(for start: Date, end: Date,
                           substanceEvents: [SubstanceEvent],
                           calendar: Calendar) -> [CauseCandidate] {
        var out: [CauseCandidate] = []
        var claimed: Set<EventCause> = []

        // Tier 1 — what the reader wrote down.
        let lookback = start.addingTimeInterval(-substanceLookbackHours * 3600)
        let logged = substanceEvents
            .filter { $0.timestamp >= lookback && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
        for event in logged {
            let cause = EventCause.from(event.substance)
            guard claimed.insert(cause).inserted else { continue }
            let minutes = Int(start.timeIntervalSince(event.timestamp) / 60)
            let when = minutes <= 0
                ? "during the window"
                : "\(minutes) minute\(minutes == 1 ? "" : "s") before it started"
            out.append(CauseCandidate(
                cause: cause,
                // Scaled by how hard the class hits the heart, so a logged
                // stimulant outranks a logged cup of tea. `acuteCardiacLoad` is
                // the app's existing ordering heuristic and is documented as one.
                weight: 0.60 + 0.30 * event.substance.acuteCardiacLoad,
                basis: .loggedByYou,
                why: "You logged \(event.substance.displayName.lowercased()) \(when)."))
        }

        // Tier 2 — priors about the time of day. Weak, labelled, and capped well
        // below tier 1.
        for cause in timeOfDayPriors(at: start, calendar: calendar)
        where claimed.insert(cause).inserted {
            out.append(CauseCandidate(cause: cause, weight: 0.30, basis: .timeOfDay))
        }

        // Tier 3 — the two answers that must always be available, so the list is
        // never a forced choice. Weight 0 keeps them last without a special case
        // in the sort.
        for cause in [EventCause.somethingElse, .nothingNotable]
        where claimed.insert(cause).inserted {
            out.append(CauseCandidate(cause: cause, weight: 0, basis: .alwaysOffered))
        }

        return out.sorted { $0.weight > $1.weight }
    }

    /// What tends to be going on at a given hour, **in the order this app is
    /// willing to guess**.
    ///
    /// ⚠️ **These are priors about ordinary life, not findings about the
    /// reader.** They are here because the reader asked to be *asked* — P32's
    /// own example is an evening question about sexual activity — and a question
    /// needs a subject. Every one of them carries `Basis.timeOfDay`, whose
    /// sentence tells the reader plainly that nothing measured supports it.
    ///
    /// Overnight deliberately omits `.intimacy`, and that is not squeamishness:
    /// an overnight elevation with no movement is the pattern an early fever
    /// actually makes, and offering the more sensitive option first on the
    /// weakest evidence in the app is how a wrong guess becomes memorable.
    static func timeOfDayPriors(at date: Date, calendar: Calendar) -> [EventCause] {
        switch Daypart(of: date, calendar: calendar) {
        case .night:
            return [.poorSleep, .feelingUnwell, .stress]
        case .morning:
            return [.stress, .caffeine]
        case .afternoon:
            return [.stress, .socialising]
        case .evening:
            return [.intimacy, .stress, .excitement]
        }
    }
}
