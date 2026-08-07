import Foundation

/// **Social battery** — backlog B9-1.
///
/// The card was named on the backlog for weeks with no scope at all, and the
/// standing note said so: *"do not start it on the strength of the name."* It
/// was scoped by the reader on 2026-08-07, and they asked for all three
/// framings rather than one:
///
/// > *"I want all of the above! And of course, make sure any data points we
/// > derive go into the data tab, and they used appropriately in the weightings
/// > and 'what goes into this' charts. I want several bespoke charts, to show
/// > very good insights into people's 'social batteries'."*
///
/// So this model answers three questions, and they are deliberately kept apart
/// because two of them are much better evidenced than the third:
///
/// 1. **Depletion from social load.** How much contact there was, and what the
///    body did on the nights after. The exposure×response shape `WorkImpactModel`
///    already uses, pointed at *people* rather than at *work*.
/// 2. **What is left today.** ⚠️ **There is no percentage here and there will
///    not be one** — see `capacityRefusal`. Energy's own calibration is the open
///    `B19` problem and inheriting its constants would have been the fastest way
///    to make this card dishonest.
/// 3. **Whether contact restores or drains *this reader*.** The novel one, and
///    the one whose best answer is often *"we cannot tell yet"* — which this
///    model can actually say, because every response it computes carries a
///    standard error and a verdict that refuses when the interval spans zero.
///
/// ## ⚠️ Three design decisions that keep this from being Work impact again
///
/// **1. Personal contact counts.** Work impact is explicitly work-only: it drops
/// every personal event and every weekend. That is right for a card about work
/// and it is fatal for a card about people — dinner with friends is the exact
/// contact this card exists to measure, and a Saturday is where most of it
/// lives.
///
/// **2. So the weekend confound is handled by blocking, not by exclusion.**
/// `WorkImpactModel`'s own note names the trap precisely: a naive busy-versus-
/// quiet split is mostly a weekday-versus-weekend split, and would report that
/// company wrecks your recovery when what it found is that Saturday exists.
/// Rather than throw the weekend away, **the split is made inside each stratum
/// and the halves are then pooled** — a busy Saturday is compared with a quiet
/// Saturday, a busy Tuesday with a quiet Tuesday, and both differences go into
/// the same pool. That is textbook blocking, it keeps the personal half of the
/// reader's life in the data, and it is the one thing that makes this card's
/// finding different in kind from the work card's.
///
/// **3. The direction of the exposure term is learnt, not assumed.** Work impact
/// can safely assume more work is more load. This card cannot: for some readers
/// a full diary of people is restorative, and scoring their busiest fortnight as
/// their worst would be the app asserting a personality it never measured. So
/// `restorationIndex` interpolates the exposure curve continuously between
/// "heavy costs you" and "heavy suits you", from the reader's own body — and
/// sits near the middle, saying little either way, while the evidence is thin.
///
/// ## What this cannot see, said once
///
/// Social load and work load are correlated: a day with six meetings is both.
/// Nothing here separates *the people* from *the work* on a working day, and the
/// card says so in a driver line rather than implying a decomposition it has not
/// done. The evidence that is genuinely about people rather than about work is
/// the **chosen-contact** finding below, which is built from personal and casual
/// contact only.
public enum SocialBatteryModel {

    // MARK: - Windows and gates

    /// The stretch compared. Eight weeks, matching `WorkImpactModel` — about
    /// forty comparable days, and the least that can separate a busy day from a
    /// quiet one at this effect size.
    public static let windowDays = 56
    /// Days needed on each side of the pooled split before anything is reported.
    public static let minimumDaysPerHalf = 8
    /// Days a stratum needs before it is split at all. A stratum with fewer is
    /// **dropped entirely and named**, rather than folded in — folding it in is
    /// exactly the weekend confound this design exists to avoid.
    public static let minimumDaysPerStratum = 6
    /// Days each side of a *contact-kind* split needs before that kind earns a
    /// verdict. Smaller than the pooled gate because a kind is a subset of it,
    /// and the verdict refuses on its own interval anyway.
    public static let minimumDaysPerContactKind = 6

    /// The multiplier on a standard error at which a difference is called.
    ///
    /// **Two, because two is the conventional 95% z-interval** — not a number
    /// chosen here. Every verdict this model gives is "the interval excludes
    /// zero" and every one it refuses is "the interval contains zero".
    public static let intervalMultiplier = 2.0

    // MARK: - The two axes a day is described on

    /// **Weekday or weekend.** The block the split is made inside.
    ///
    /// Two strata rather than seven days, because seven would leave six days in
    /// most blocks and nothing could be split at all. The distinction that
    /// actually carries the confound — no work, more sleep, later mornings,
    /// different drinking — is weekday against weekend.
    public enum Stratum: String, Sendable, Equatable, CaseIterable, Identifiable {
        case weekday, weekend
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .weekday: return "Weekdays"
            case .weekend: return "Weekends"
            }
        }
    }

    /// **Contact the reader chose, against contact they owed.**
    ///
    /// This is framing 3's whole apparatus, and the split is deliberately coarse:
    /// nothing in a calendar says whether somebody wanted to be somewhere, so the
    /// two proxies are the two the classifier already establishes — a *personal*
    /// event is one the reader put in their own life, and a *casual* one is the
    /// reader's own "chill catchup" rather than "formal meeting with a client".
    ///
    /// ⚠️ **A proxy, and the card says so.** A casual work catch-up with somebody
    /// they dislike lands in `chosen` and should not. What makes it usable
    /// anyway is that it is the reader's own classification and they can correct
    /// any event on the review list, which recomputes this.
    public enum ContactKind: String, Sendable, Equatable, CaseIterable, Identifiable {
        /// Personal-context contact, and casual contact of any context.
        case chosen
        /// Work-context contact at standard or formal footing.
        case obligated
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .chosen: return "Contact you chose"
            case .obligated: return "Contact you owed"
            }
        }
        /// The clause a sentence about this kind uses.
        public var phrase: String {
            switch self {
            case .chosen: return "seeing people you chose to see"
            case .obligated: return "meetings you had to be in"
            }
        }
    }

    /// **How many people an event has to name before a block of time counts as
    /// company.** Two: the reader and somebody else.
    public static let guestsThatMakeABlockSocial = 2

    /// **What this card counts as contact, and it is deliberately not just
    /// `occasion == .meeting`.**
    ///
    /// ⚠️ **A real gap in the classifier, found building this card and worth
    /// stating rather than working around silently.** `CalendarEventClassifier
    /// .blockedTimeWords` holds `"lunch"`, and `casualWords` holds it too — so
    /// *"Lunch with friends"* classifies as **blocked time**, which
    /// `loadHours` discounts to half and which `occasion == .meeting` would drop
    /// from this card entirely. The same is true of `"walk"`, `"run"` and
    /// `"gym"`: every one of them is solo time for most readers and company for
    /// some, and no word list can tell those apart.
    ///
    /// **What can tell them apart is the guest list**, which is a fact off the
    /// event rather than a guess about its title: a block of time somebody else
    /// was invited to is contact, and a block of time nobody was invited to is
    /// not. So blocked time with at least `guestsThatMakeABlockSocial` people on
    /// it counts, at the *meeting* rate — the reader was with people, whatever
    /// the calendar called it — and blocked time with no stated guest list stays
    /// out.
    ///
    /// The honest limitation, and it is why the card says the headcounts are a
    /// floor: a lunch with friends that carries **no** guest list is invisible
    /// here. The fix for that is the classifier's word lists, not this card.
    ///
    /// Returns 0 for everything that is not contact — reminders, the reader's
    /// own leave, somebody else's absence, sick days and travel all included,
    /// for the reasons `loadHours` gives each of them.
    public static func contactHours(_ classification: CalendarEventClassification,
                                    attendeeCount: Int?) -> Double {
        switch classification.occasion {
        case .meeting:
            return classification.loadHours
        case .blockedTime:
            guard let attendees = attendeeCount,
                  attendees >= guestsThatMakeABlockSocial else { return 0 }
            // Re-read at the meeting rate rather than re-deriving the formula:
            // `loadHours` is the app's one stated assumption about what an hour
            // with people costs, and a second copy of it here is how two numbers
            // about one thing start disagreeing.
            return CalendarEventClassification(
                context: classification.context, occasion: .meeting,
                presence: classification.presence, formality: classification.formality,
                hours: classification.hours).loadHours
        case .reminder, .travel, .leave, .absence, .sick:
            return 0
        }
    }

    /// Which kind an event's classification is.
    ///
    /// One rule, stated once so the card and the model cannot disagree: personal
    /// context, **or** casual footing whatever the context, is chosen; everything
    /// else is owed.
    public static func kind(of classification: CalendarEventClassification) -> ContactKind {
        if classification.context == .personal { return .chosen }
        if classification.formality == .casual { return .chosen }
        return .obligated
    }

    // MARK: - One day, as this card reads it

    /// A day of the reader's own calendar, reduced to contact.
    ///
    /// ⚠️ **`hours` is `CalendarEventClassification.loadHours`, reused rather
    /// than re-weighted.** That property already states the app's assumption
    /// about what an hour costs — an in-person formal meeting weighs more than
    /// the same hour of a remote casual one — and inventing a *second* scale for
    /// the same idea is how two numbers about one thing start disagreeing. This
    /// card adds no multiplier of its own; the only new axis is `people`, and
    /// that is a count off the calendar rather than an assumption.
    public struct DayContact: Sendable, Equatable, Identifiable {
        public let day: Date
        public let stratum: Stratum
        /// Weighted contact hours — meetings only.
        public let hours: Double
        /// Meetings, unweighted. For the copy, never for the score.
        public let meetings: Int
        /// Heads across the day's meetings, counting only meetings whose size the
        /// calendar actually stated.
        public let people: Int
        /// How many of the day's meetings stated a size. `people` is a floor
        /// rather than a total whenever this is below `meetings`.
        public let sizedMeetings: Int
        public let chosenHours: Double
        public let obligatedHours: Double

        public var id: Date { day }

        public init(day: Date, stratum: Stratum, hours: Double, meetings: Int,
                    people: Int, sizedMeetings: Int,
                    chosenHours: Double, obligatedHours: Double) {
            self.day = day
            self.stratum = stratum
            self.hours = hours
            self.meetings = meetings
            self.people = people
            self.sizedMeetings = sizedMeetings
            self.chosenHours = chosenHours
            self.obligatedHours = obligatedHours
        }
    }

    /// What one comparison found, **with its uncertainty**.
    ///
    /// ⚠️ **The standard error is the whole point of this type**, and it is why
    /// framing 3 can honestly say "we cannot tell yet" instead of printing a
    /// personality. `pooled` alone is a number that always exists; `pooled`
    /// beside its interval is a number that knows when it means nothing.
    public struct Response: Sendable, Equatable {
        public let channels: [WorkImpactModel.Channel]
        /// Mean departure across channels, in SDs of the reader's own spread,
        /// signed so **positive is the unwelcome direction**.
        public let pooled: Double
        /// The standard error of `pooled`.
        ///
        /// ⚠️ **It assumes the channels are independent, and they are not** —
        /// resting heart rate and variability move together. So the interval
        /// below is if anything *narrower* than the truth, and the card says so
        /// rather than letting a reader read it as exact. Understating an
        /// interval is the one direction of error this model states out loud
        /// wherever it prints one.
        public let standardError: Double
        public let highDays: Int
        public let lowDays: Int

        public init(channels: [WorkImpactModel.Channel], pooled: Double,
                    standardError: Double, highDays: Int, lowDays: Int) {
            self.channels = channels
            self.pooled = pooled
            self.standardError = standardError
            self.highDays = highDays
            self.lowDays = lowDays
        }

        public var halfWidth: Double { intervalMultiplier * standardError }
        public var low: Double { pooled - halfWidth }
        public var high: Double { pooled + halfWidth }
        /// Whether the interval excludes zero — the only thing that licenses a
        /// direction being named.
        public var isDistinguishableFromZero: Bool { low > 0 || high < 0 }
    }

    /// What a kind of contact does to this reader, or why nothing can be said.
    public enum ContactVerdict: String, Sendable, Equatable {
        /// The body reads better on the nights after this kind of contact.
        case restores
        /// Worse.
        case drains
        /// Measured, and the interval spans zero. **A real answer.**
        case tooCloseToTell
        /// Not enough days of this kind on either side of its own split.
        case notEnoughDays
    }

    public struct KindFinding: Sendable, Equatable, Identifiable {
        public let kind: ContactKind
        public let response: Response?
        /// Days that carried any of this kind of contact at all, in the window.
        public let daysWithContact: Int
        public var id: String { kind.rawValue }

        public init(kind: ContactKind, response: Response?, daysWithContact: Int) {
            self.kind = kind
            self.response = response
            self.daysWithContact = daysWithContact
        }

        public var verdict: ContactVerdict {
            guard let response else { return .notEnoughDays }
            guard response.isDistinguishableFromZero else { return .tooCloseToTell }
            return response.pooled > 0 ? .drains : .restores
        }
    }

    /// **What is on today, and what is left of it.** Framing 2, with no
    /// percentage in it — see `capacityRefusal`.
    public struct TodayLoad: Sendable, Equatable {
        /// Weighted contact hours in events that have already ended.
        public let elapsedHours: Double
        /// Weighted contact hours still ahead in the diary.
        public let aheadHours: Double
        public let meetings: Int
        public let people: Int
        public let sizedMeetings: Int
        /// Today's total contact as a multiple of a typical day of theirs.
        public let level: Double
        /// Which side of the reader's own eight-week median today falls on.
        public let isBusyForThem: Bool

        public init(elapsedHours: Double, aheadHours: Double, meetings: Int,
                    people: Int, sizedMeetings: Int, level: Double,
                    isBusyForThem: Bool) {
            self.elapsedHours = elapsedHours
            self.aheadHours = aheadHours
            self.meetings = meetings
            self.people = people
            self.sizedMeetings = sizedMeetings
            self.level = level
            self.isBusyForThem = isBusyForThem
        }

        public var totalHours: Double { elapsedHours + aheadHours }
    }

    /// The four combinations of how much contact there was and what the body
    /// did — the same four-quadrant device `WorkImpactModel.Quadrant` uses, and
    /// for the same reason: a dial cannot distinguish *"a lot of people and it
    /// cost you"* from *"a lot of people and you were fine"*, and both are
    /// ordinary fortnights.
    public enum Quadrant: String, Sendable, Equatable, CaseIterable {
        /// Heavy contact, and the body shows it.
        case spent
        /// Heavy contact, and the body is steady or better. Good news, and said.
        case sustained
        /// Light contact, body off anyway — so it is not the people.
        case unexplained
        /// Light contact, steady body.
        case quiet
    }

    public struct Output: Sendable, Equatable {
        /// Every comparable day in the window, newest last. What the bespoke
        /// charts are drawn from.
        public let days: [DayContact]
        public let strata: [Stratum]
        /// Strata with too few days to split, dropped and named.
        public let droppedStrata: [Stratum]
        public let heavyDays: Int
        public let lightDays: Int
        public let heavyMedianHours: Double
        public let lightMedianHours: Double
        public let heavyMedianPeople: Double
        public let lightMedianPeople: Double
        /// **The unit everything on the calendar side is measured in**: the
        /// reader's own typical day of contact. It is the median the split is
        /// made at, so it is already what "busy *for them*" means here.
        public let typicalDayHours: Double
        public let typicalDayPeople: Double
        /// Share of days carrying a meeting whose size the calendar stated.
        /// Scales the people row's weight; see `peopleConfidence`.
        public let peopleCoverage: Double
        public let peakHours: Double
        public let peakPeople: Int
        public let peakDay: Date?
        public let overall: Response
        public let findings: [KindFinding]
        public let restorationIndex: Double
        public let responseShare: Double
        public let score: Double
        public let contributions: [MetricContribution]
        public let factors: [ScoreFactor]
        public let today: TodayLoad?

        /// How much more contact the busy half carried, in hours.
        public var contactGapHours: Double { heavyMedianHours - lightMedianHours }
        /// The gap as a multiple of a typical day of theirs.
        public var contactGapRatio: Double {
            typicalDayHours > 0 ? contactGapHours / typicalDayHours : 0
        }
        public var peopleGap: Double { heavyMedianPeople - lightMedianPeople }
        public var peopleGapRatio: Double {
            typicalDayPeople > 0 ? peopleGap / typicalDayPeople : 0
        }
        /// How far above a typical day the heaviest one stood, as a multiple.
        public var peakRatio: Double {
            typicalDayHours > 0
                ? Swift.max(0, (peakHours - typicalDayHours) / typicalDayHours) : 0
        }
        /// The two facets as one number, for the quadrant and for the series.
        /// Not itself scored — the facets are, each carrying its own row.
        public var exposureLevel: Double {
            contactFacetWeight * contactGapRatio + peopleFacetWeight * peopleGapRatio
        }
        public var daysCompared: Int { heavyDays + lightDays }

        public var quadrant: Quadrant {
            let heavy = exposureLevel >= heavyExposureLevel
            let responded = overall.pooled >= notableResponse
            switch (heavy, responded) {
            case (true, true): return .spent
            case (true, false): return .sustained
            case (false, true): return .unexplained
            case (false, false): return .quiet
            }
        }

        public func finding(_ kind: ContactKind) -> KindFinding? {
            findings.first { $0.kind == kind }
        }
    }

    // MARK: - Building the days

    /// Contact per day across the window, **including days with none**.
    ///
    /// ⚠️ **A day with no meetings is a zero, not a gap**, and that is a
    /// deliberate difference from `WorkImpactModel.workingDayProfile`, which
    /// builds days only where work events exist. A day the reader saw nobody is
    /// the *quiet* side of this card's whole comparison; dropping it would leave
    /// the model comparing busy days against slightly-less-busy days and would
    /// throw away the reader's most restful days entirely.
    ///
    /// The window therefore starts at the **first event the calendar holds**
    /// within it, never at the cutoff: before that the app cannot tell an empty
    /// day from an unsynced one, and counting an unsynced day as solitude is a
    /// confident wrong answer.
    ///
    /// Today is excluded — the night after it has not happened — and is reported
    /// separately by `todayLoad`.
    public static func contactDays(events: [CalendarEvent],
                                   judgements: [CalendarEventJudgement],
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [DayContact] {
        let byID = Dictionary(judgements.map { ($0.eventID, $0.effective) },
                              uniquingKeysWith: { first, _ in first })
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: today)
        else { return [] }

        struct Tally {
            var hours = 0.0
            var meetings = 0
            var people = 0
            var sized = 0
            var chosen = 0.0
            var obligated = 0.0
        }
        var tallies: [Date: Tally] = [:]
        var earliest: Date?

        for event in events where event.start >= cutoff && event.start < today {
            let day = calendar.startOfDay(for: event.start)
            earliest = earliest.map { Swift.min($0, day) } ?? day
            // ⚠️ An all-day entry is never contact. Its classification carries
            // 24 hours, and a single "Conference" banner would otherwise
            // outweigh a fortnight of real meetings.
            guard !event.isAllDay else { continue }
            let classification = byID[event.id] ?? CalendarEventClassifier.classify(event)
            // See `contactHours`: a meeting always, and a block of time with a
            // guest list on it. Reminders, leave, sickness and travel are not
            // contact whatever calendar they sit in.
            let load = contactHours(classification, attendeeCount: event.attendeeCount)
            guard load > 0 else { continue }
            var tally = tallies[day] ?? Tally()
            tally.hours += load
            tally.meetings += 1
            if let attendees = event.attendeeCount, attendees > 0 {
                tally.people += attendees
                tally.sized += 1
            }
            switch kind(of: classification) {
            case .chosen: tally.chosen += load
            case .obligated: tally.obligated += load
            }
            tallies[day] = tally
        }

        guard let start = earliest else { return [] }
        var out: [DayContact] = []
        var day = start
        while day < today {
            let tally = tallies[day] ?? Tally()
            out.append(DayContact(day: day, stratum: stratum(of: day, calendar: calendar),
                                  hours: tally.hours, meetings: tally.meetings,
                                  people: tally.people, sizedMeetings: tally.sized,
                                  chosenHours: tally.chosen,
                                  obligatedHours: tally.obligated))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    /// 1 = Sunday and 7 = Saturday in every Gregorian calendar.
    static func stratum(of day: Date, calendar: Calendar) -> Stratum {
        let weekday = calendar.component(.weekday, from: day)
        return (weekday == 1 || weekday == 7) ? .weekend : .weekday
    }

    /// Today's diary, split at `now` into what has happened and what is ahead.
    ///
    /// The ahead half is the reason this exists at all: it is the only
    /// forward-looking thing on the card, it is a **fact off the calendar**
    /// rather than a prediction, and it is what the reader actually asked for
    /// when they asked what is left.
    public static func todayLoad(events: [CalendarEvent],
                                 judgements: [CalendarEventJudgement],
                                 typicalDayHours: Double,
                                 medianHours: Double,
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> TodayLoad? {
        let byID = Dictionary(judgements.map { ($0.eventID, $0.effective) },
                              uniquingKeysWith: { first, _ in first })
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        var elapsed = 0.0
        var ahead = 0.0
        var meetings = 0
        var people = 0
        var sized = 0
        for event in events where event.start >= start && event.start < end {
            guard !event.isAllDay else { continue }
            let classification = byID[event.id] ?? CalendarEventClassifier.classify(event)
            let load = contactHours(classification, attendeeCount: event.attendeeCount)
            guard load > 0 else { continue }
            meetings += 1
            if let attendees = event.attendeeCount, attendees > 0 {
                people += attendees
                sized += 1
            }
            // An event still running counts as ahead: the reader is in it.
            if event.end <= now { elapsed += load } else { ahead += load }
        }
        guard meetings > 0 || elapsed > 0 || ahead > 0 else {
            return TodayLoad(elapsedHours: 0, aheadHours: 0, meetings: 0, people: 0,
                             sizedMeetings: 0, level: 0, isBusyForThem: false)
        }
        let total = elapsed + ahead
        return TodayLoad(elapsedHours: elapsed, aheadHours: ahead, meetings: meetings,
                         people: people, sizedMeetings: sized,
                         level: typicalDayHours > 0 ? total / typicalDayHours : 0,
                         isBusyForThem: total > medianHours)
    }

    // MARK: - The split, made inside each stratum

    /// Days above and below each stratum's **own** median, pooled.
    ///
    /// See the type's note: this is the blocking that lets personal contact and
    /// weekends stay in the data. A stratum with too few days to split is
    /// dropped whole and returned in `dropped`, never folded into the other —
    /// folding is precisely the confound.
    static func stratifiedSplit(_ days: [DayContact],
                                by value: (DayContact) -> Double,
                                minimumPerStratum: Int)
        -> (high: [DayContact], low: [DayContact], used: [Stratum], dropped: [Stratum]) {
        var high: [DayContact] = []
        var low: [DayContact] = []
        var used: [Stratum] = []
        var dropped: [Stratum] = []
        for stratum in Stratum.allCases {
            let block = days.filter { $0.stratum == stratum }
            guard block.count >= minimumPerStratum,
                  let median = Baseline.median(block.map(value)) else {
                if !block.isEmpty { dropped.append(stratum) }
                continue
            }
            let above = block.filter { value($0) > median }
            let below = block.filter { value($0) <= median }
            // A stratum in which every day is identical splits into nothing on
            // one side. It contributes no contrast, so it is dropped and named
            // rather than contributing a one-sided pile to the pool.
            guard !above.isEmpty, !below.isEmpty else {
                dropped.append(stratum)
                continue
            }
            high += above
            low += below
            used.append(stratum)
        }
        return (high, low, used, dropped)
    }

    // MARK: - The body's answer

    /// The three signals watched, and which direction is the unwelcome one.
    ///
    /// **The same three `WorkImpactModel` watches, deliberately.** They are the
    /// signals this app has next-morning coverage for, they are already scored
    /// against a departure curve here, and a card that watched a different three
    /// would be answering a different question from the one beside it on the
    /// same calendar.
    public static var watched: [(metric: MetricType, higherIsWorse: Bool)] {
        WorkImpactModel.watched
    }

    /// What the body did on the nights **after** each group of days.
    ///
    /// Next-morning throughout, for `WorkImpactModel`'s reason: an evening with
    /// friends cannot change the sleep that preceded it, and reading it the
    /// other way round would produce a confident finding about time running
    /// backwards.
    static func respond(high: [Date], low: [Date], samples: [HealthMetricSample],
                        minimumPerSide: Int, now: Date, calendar: Calendar) -> Response? {
        guard high.count >= minimumPerSide, low.count >= minimumPerSide else { return nil }
        var channels: [WorkImpactModel.Channel] = []
        var variances: [Double] = []
        for entry in watched {
            let daily = VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                                calendar: calendar)
            let byDay = Dictionary(daily.map { ($0.date, $0.value) },
                                   uniquingKeysWith: { first, _ in first })
            func values(for days: [Date]) -> [Double] {
                days.compactMap { day in
                    calendar.date(byAdding: .day, value: 1, to: day).flatMap { byDay[$0] }
                }
            }
            let highValues = values(for: high)
            let lowValues = values(for: low)
            guard highValues.count >= minimumPerSide, lowValues.count >= minimumPerSide,
                  let highMean = Baseline.mean(highValues),
                  let lowMean = Baseline.mean(lowValues),
                  let spread = Baseline.robustScale(highValues + lowValues), spread > 0
            else { continue }
            let raw = (highMean - lowMean) / spread
            channels.append(WorkImpactModel.Channel(
                metric: entry.metric, onHeavyDays: highMean, onLightDays: lowMean,
                towardWorse: entry.higherIsWorse ? raw : -raw))
            // The difference is already in units of the pooled spread, so the
            // standard error of a difference of two means is simply
            // √(1/n₁ + 1/n₂) — no variance term survives the standardisation.
            variances.append(1 / Double(highValues.count) + 1 / Double(lowValues.count))
        }
        guard channels.count >= 2 else { return nil }
        let pooled = channels.reduce(0) { $0 + $1.towardWorse } / Double(channels.count)
        // Mean of C channels: SE = √(Σ varᵢ) / C. Independence assumed, and the
        // type's own note says out loud that it does not hold.
        let se = variances.reduce(0, +).squareRoot() / Double(channels.count)
        return Response(channels: channels.sorted { $0.towardWorse > $1.towardWorse },
                        pooled: pooled, standardError: se,
                        highDays: high.count, lowDays: low.count)
    }

    // MARK: - Scoring

    /// Within the calendar's share: hours are a median over a dozen days and the
    /// headcount is thinner and often partly unknown, so hours lead.
    public static let contactFacetWeight = 0.65
    public static let peopleFacetWeight = 0.35

    /// Exposure at or above this — in multiples of the reader's own typical day
    /// — is a heavy stretch *for them*. Names the quadrant only; the score
    /// itself is a curve with no step in it.
    public static let heavyExposureLevel = 0.75
    /// The pooled departure at which the body has said something. The same 0.5
    /// `WorkImpactModel` marks a channel notable at.
    public static let notableResponse = 0.5

    /// The body comparison's share, as a function of how far apart the halves
    /// are.
    ///
    /// **Reused from `WorkImpactModel` rather than re-chosen**, and that is the
    /// honest move: the argument for it is identical — a difference measured
    /// across two groups of days that barely differ is weak evidence about what
    /// separates them — and a second set of constants for one idea is how two
    /// cards start disagreeing about the same reasoning.
    public static func responseShare(contrastRatio: Double) -> Double {
        WorkImpactModel.responseShare(gapRatio: contrastRatio)
    }

    /// One body channel's 0–100. Also `WorkImpactModel`'s, unchanged: it already
    /// scores a signed departure in SD and already rewards the welcome
    /// direction, which is exactly what a restorative reader produces.
    public static func responseScore(towardWorse: Double) -> Double {
        WorkImpactModel.responseScore(towardWorse: towardWorse)
    }

    /// Exposure scored as if contact **costs** this reader. `WorkImpactModel`'s
    /// curve, and its floor of 30 for its reason: a diary alone is never a
    /// health catastrophe, and what can take this card to the floor is the body.
    public static func costlyExposureScore(level: Double) -> Double {
        WorkImpactModel.exposureScore(level: level)
    }

    /// Exposure scored as if contact **suits** this reader.
    ///
    /// The mirror, and deliberately not a perfect one. It starts at 55 rather
    /// than at 30 — an empty diary is not a catastrophe either, it is simply the
    /// absence of something this reader benefits from — and it tops out at 92
    /// rather than 100, because a calendar on its own never earns a full mark.
    public static func restoringExposureScore(level: Double) -> Double {
        ScoreCurve.through([(0, 55), (0.5, 70), (1.0, 80), (2.0, 88), (3.5, 92)],
                           at: level)
    }

    /// **How far, and in which direction, the reader's own body says contact
    /// moves them** — −1 fully draining, +1 fully restoring, 0 unknown.
    ///
    /// ⚠️ **Continuous by construction, and that is a rule rather than a
    /// preference.** The tempting version is a verdict — "restorative" or
    /// "draining" — switched at the interval's edge, and that is exactly the
    /// class of defect `add-insight` §8 exists to stop: a term's contribution
    /// flipping on a boolean derived from a noisy continuous quantity, so the
    /// reader sees the score lurch and nothing in the app can explain it. The
    /// verdict *words* are switched, because words are copy; the *number* ramps.
    ///
    /// It reaches ±1 exactly where the 95% interval clears zero, so a difference
    /// too small to call moves the exposure curve only a little away from
    /// neutral.
    public static func restorationIndex(_ response: Response) -> Double {
        let se = Swift.max(response.standardError, 1e-6)
        let z = -response.pooled / (intervalMultiplier * se)
        return Swift.max(-1, Swift.min(1, z))
    }

    /// One exposure facet's 0–100, interpolated between the two curves by what
    /// the body has said.
    ///
    /// At an index of 0 this is the average of the two, which slopes gently
    /// down: a demand the app cannot yet grade is still a demand, and the card
    /// says so in the row's own detail rather than pretending neutrality is
    /// weightlessness.
    public static func exposureScore(level: Double, restorationIndex index: Double) -> Double {
        let t = (Swift.max(-1, Swift.min(1, index)) + 1) / 2
        return costlyExposureScore(level: level) * (1 - t)
            + restoringExposureScore(level: level) * t
    }

    /// **How much the headcount row is believed**, as a 0→1 ramp over how much
    /// of the reader's calendar states a meeting's size.
    ///
    /// ⚠️ A ramp rather than a threshold, for `add-insight` §8's reason: gating
    /// the row's *presence* on a coverage figure that moves as events sync would
    /// make a share appear and disappear with nothing behind it. Where the
    /// evidence is marginal the row carries a marginal weight, and its detail
    /// says what the coverage is.
    public static func peopleConfidence(coverage: Double) -> Double {
        ScoreCurve.through([(0, 0), (0.2, 0), (0.6, 1), (1, 1)], at: coverage)
    }

    // MARK: - Readiness

    /// Ready, or waiting on something nameable.
    ///
    /// The same three-way shape both calendar cards use, and for the defect
    /// their note records: a card that renders "Connect your calendar" to a
    /// reader whose calendar is connected has told them to do a thing they have
    /// already done.
    public enum Readiness: Sendable {
        case ready(Output)
        case waiting(CoverageGate)
        case noCalendar
    }

    public static func evaluate(events: [CalendarEvent],
                                judgements: [CalendarEventJudgement],
                                samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        if case .ready(let out) = analyse(events: events, judgements: judgements,
                                          samples: samples, now: now, calendar: calendar) {
            return out
        }
        return nil
    }

    public static func analyse(events: [CalendarEvent],
                               judgements: [CalendarEventJudgement],
                               samples: [HealthMetricSample],
                               now: Date = Date(),
                               calendar: Calendar = .current) -> Readiness {
        guard !events.isEmpty else { return .noCalendar }
        let days = contactDays(events: events, judgements: judgements,
                               now: now, calendar: calendar)
        guard days.count >= minimumDaysPerHalf * 2 else {
            return .waiting(CoverageGate(
                need: minimumDaysPerHalf * 2, have: days.count, unit: "day of calendar",
                unlocks: "this can contrast the days you saw people with the days you didn't"))
        }

        let split = stratifiedSplit(days, by: { $0.hours },
                                    minimumPerStratum: minimumDaysPerStratum)
        guard split.high.count >= minimumDaysPerHalf, split.low.count >= minimumDaysPerHalf
        else {
            return .waiting(CoverageGate(
                need: minimumDaysPerHalf,
                have: Swift.min(split.high.count, split.low.count),
                unit: "day on the quieter side of your own median",
                unlocks: "this can contrast your busier days for company with your quieter ones — right now they look alike"))
        }

        guard let overall = respond(high: split.high.map(\.day), low: split.low.map(\.day),
                                    samples: samples, minimumPerSide: minimumDaysPerHalf,
                                    now: now, calendar: calendar)
        else {
            return .waiting(CoverageGate(
                need: 2, have: 0, unit: "responding signal",
                unlocks: "this can tell a real effect of company from one instrument having a bad week"))
        }

        // ⚠️ **The scale everything on the calendar side is measured on.** There
        // is no published norm for how many hours of company is too many — that
        // is `docs/norms-and-telemetry.md`'s whole point — so an external band
        // would be a number invented here wearing clinical clothes. The reader's
        // own typical day is real, is theirs, and is already what the median
        // split above means. Every exposure row's copy says which it is.
        let allHours = days.map(\.hours).sorted()
        let median = Baseline.median(allHours) ?? 0
        let typicalDay = median > 0 ? median : (Baseline.mean(allHours) ?? 0)
        guard typicalDay > 0 else {
            return .waiting(CoverageGate(
                need: 1, have: 0, unit: "hour of company on a typical day",
                unlocks: "this can measure a busy day against your own normal one"))
        }

        let heavyMedianHours = Baseline.median(split.high.map(\.hours)) ?? 0
        let lightMedianHours = Baseline.median(split.low.map(\.hours)) ?? 0
        let heavyMedianPeople = Baseline.median(split.high.map { Double($0.people) }) ?? 0
        let lightMedianPeople = Baseline.median(split.low.map { Double($0.people) }) ?? 0
        let typicalPeople = Baseline.median(days.map { Double($0.people) }).flatMap {
            $0 > 0 ? $0 : Baseline.mean(days.map { Double($0.people) })
        } ?? 0
        let meetingDays = days.filter { $0.meetings > 0 }
        let coverage = meetingDays.isEmpty ? 0
            : Double(meetingDays.filter { $0.sizedMeetings > 0 }.count) / Double(meetingDays.count)

        let peak = days.max { $0.hours < $1.hours }
        let index = restorationIndex(overall)

        let contactGapRatio = (heavyMedianHours - lightMedianHours) / typicalDay
        let peopleGapRatio = typicalPeople > 0
            ? (heavyMedianPeople - lightMedianPeople) / typicalPeople : 0

        let metricShare = responseShare(contrastRatio: contactGapRatio)
        let metricTerms = overall.channels.map { channel in
            ScoreBlend.Term(
                metric: channel.metric,
                higherIsBetter: !(watched.first { $0.metric == channel.metric }?.higherIsWorse ?? true),
                score: responseScore(towardWorse: channel.towardWorse),
                weight: 1, detail: sentence(channel))
        }
        let factorTerms = exposureTerms(
            contactGapRatio: contactGapRatio, peopleGapRatio: peopleGapRatio,
            heavyMedianHours: heavyMedianHours, lightMedianHours: lightMedianHours,
            heavyMedianPeople: heavyMedianPeople, lightMedianPeople: lightMedianPeople,
            typicalDayHours: typicalDay, typicalDayPeople: typicalPeople,
            coverage: coverage, restorationIndex: index)
        guard let blended = ScoreBlend.blend(metrics: metricTerms, factors: factorTerms,
                                             metricShare: metricShare)
        else {
            return .waiting(CoverageGate(
                need: 1, have: 0, unit: "weighted signal",
                unlocks: "this can put a number on how company is landing"))
        }

        let findings = ContactKind.allCases.map { kind -> KindFinding in
            let value: (DayContact) -> Double = kind == .chosen
                ? { $0.chosenHours } : { $0.obligatedHours }
            let kindSplit = stratifiedSplit(days, by: value,
                                            minimumPerStratum: minimumDaysPerContactKind)
            let response = respond(high: kindSplit.high.map(\.day),
                                   low: kindSplit.low.map(\.day), samples: samples,
                                   minimumPerSide: minimumDaysPerContactKind,
                                   now: now, calendar: calendar)
            return KindFinding(kind: kind, response: response,
                               daysWithContact: days.filter { value($0) > 0 }.count)
        }

        return .ready(Output(
            days: days, strata: split.used, droppedStrata: split.dropped,
            heavyDays: split.high.count, lightDays: split.low.count,
            heavyMedianHours: heavyMedianHours, lightMedianHours: lightMedianHours,
            heavyMedianPeople: heavyMedianPeople, lightMedianPeople: lightMedianPeople,
            typicalDayHours: typicalDay, typicalDayPeople: typicalPeople,
            peopleCoverage: coverage,
            peakHours: peak?.hours ?? heavyMedianHours, peakPeople: peak?.people ?? 0,
            peakDay: peak?.day, overall: overall, findings: findings,
            restorationIndex: index, responseShare: metricShare,
            score: blended.score, contributions: blended.contributions,
            factors: blended.factors,
            today: todayLoad(events: events, judgements: judgements,
                             typicalDayHours: typicalDay, medianHours: median,
                             now: now, calendar: calendar)))
    }

    // MARK: - The calendar's weighted rows

    /// Keys are **baked into stored ids** — renaming one orphans its history, so
    /// they are declared here and treated like a `modelVersion`.
    static let contactGapKey = "contactHoursGap"
    static let peopleGapKey = "peopleGap"
    static let busyHoursKey = "contactHoursBusyDays"
    static let quietHoursKey = "contactHoursQuietDays"
    static let busyPeopleKey = "peopleBusyDays"
    static let quietPeopleKey = "peopleQuietDays"
    static let exposureKey = "socialExposure"
    static let pooledKey = "bodyDifferencePooled"
    static let restorationKey = "restorationIndex"
    static let daysComparedKey = "daysCompared"
    static let peakHoursKey = "busiestDayForCompany"
    static let todayContactKey = "contactHoursToday"
    static let chosenResponseKey = "chosenContactResponse"
    static let obligatedResponseKey = "obligatedContactResponse"

    static func exposureTerms(contactGapRatio: Double, peopleGapRatio: Double,
                              heavyMedianHours: Double, lightMedianHours: Double,
                              heavyMedianPeople: Double, lightMedianPeople: Double,
                              typicalDayHours: Double, typicalDayPeople: Double,
                              coverage: Double,
                              restorationIndex index: Double) -> [ScoreBlend.FactorTerm] {
        let ownRange = String(format: "Measured against a typical day of yours — %.1f h of company — because no published norm for how much company is too much exists to measure it against. This says busy for you, never busy.",
                              typicalDayHours)
        let direction: String
        switch index {
        case ..<(-0.3):
            direction = "Your own nights say company costs you, so more of it counts against here."
        case 0.3...:
            direction = "Your own nights say company suits you, so more of it counts in your favour here."
        default:
            direction = "Your own nights have not yet said which way company cuts for you, so this sits between the two — a demand nobody has graded is still a demand, and it counts mildly against until your data says otherwise."
        }
        let confidence = peopleConfidence(coverage: coverage)
        let peopleDetail: String
        if typicalDayPeople <= 0 {
            peopleDetail = "No event in your calendar states how many people were invited — so this carries no share of your score, because there is nothing here to weigh. Invitations with a guest list will start filling it in."
        } else if confidence <= 0 {
            peopleDetail = String(format: "Only %.0f%% of your days with meetings state how many people were in them — too few to weigh, so this carries no share of your score and is shown for the record. It starts counting above %.0f%% coverage.",
                                  coverage * 100, 0.2 * 100)
        } else {
            peopleDetail = String(format: "%.0f people on a busy day against %.0f on a quiet one, which is %.2f× the %.0f a typical day of yours carries. Counted only from events whose guest list your calendar states — %.0f%% of your days with meetings — so it is a floor rather than a total, and its share is scaled to that coverage. %@ %@",
                                  heavyMedianPeople, lightMedianPeople, peopleGapRatio,
                                  typicalDayPeople, coverage * 100, direction, ownRange)
        }
        return [
            .init(id: DerivedSeriesID(.socialBattery, contactGapKey),
                  name: "The gap between your busier and quieter days for company",
                  score: exposureScore(level: contactGapRatio, restorationIndex: index),
                  weight: contactFacetWeight,
                  detail: String(format: "%.1f h more company on the busier half — %.1f h against %.1f h, which is %.2f× a typical day of yours in extra contact alone. That time was real time you spent with people, so it carries a share. %@ %@",
                                 heavyMedianHours - lightMedianHours, heavyMedianHours,
                                 lightMedianHours, contactGapRatio, direction, ownRange)),
            .init(id: DerivedSeriesID(.socialBattery, peopleGapKey),
                  name: "The gap in how many people you were with",
                  score: exposureScore(level: peopleGapRatio, restorationIndex: index),
                  weight: peopleFacetWeight * confidence,
                  detail: peopleDetail),
        ]
    }

    /// The calendar's weighted rows, computed in `analyse` alongside the score
    /// rather than rebuilt here: the shares and the number have to come out of
    /// one blend, or the section states proportions that do not account for the
    /// dial above them.
    public static func calendarFactors(_ out: Output) -> [ScoreFactor] { out.factors }

    /// **Every figure this card works out, as a series** — `add-insight` §5a,
    /// the reader's own rule: *"any data points we derive go into the data tab."*
    ///
    /// Nothing here restates a single metric at face value, which is the one
    /// verdict that earns silence: the medians are over a stratified split
    /// nothing else makes, the pooled departure is a weighted mean of three
    /// standardised differences, and the restoration index is a ratio of two of
    /// those.
    public static func derivedOutputs(_ out: Output) -> [DerivedOutput] {
        var rows: [DerivedOutput] = [
            .init(key: busyHoursKey, displayName: "Company on your busier days",
                  unit: "h", value: out.heavyMedianHours,
                  // Neither direction is the good one until the reader's own
                  // body has said which — which is what `restorationIndex` is
                  // for, and it is a different series.
                  higherIsBetter: nil, precision: 1),
            .init(key: quietHoursKey, displayName: "Company on your quieter days",
                  unit: "h", value: out.lightMedianHours, higherIsBetter: nil, precision: 1),
            .init(key: contactGapKey, displayName: "The gap between your busier and quieter days for company",
                  unit: "h", value: out.contactGapHours, higherIsBetter: nil, precision: 1),
            .init(key: busyPeopleKey, displayName: "People with you on a busy day",
                  unit: "", value: out.heavyMedianPeople, higherIsBetter: nil, precision: 0),
            .init(key: quietPeopleKey, displayName: "People with you on a quiet day",
                  unit: "", value: out.lightMedianPeople, higherIsBetter: nil, precision: 0),
            .init(key: peopleGapKey, displayName: "The gap in how many people you were with",
                  unit: "", value: out.peopleGap, higherIsBetter: nil, precision: 0),
            .init(key: exposureKey, displayName: "How much company you were in, for you",
                  unit: "× a typical day", value: out.exposureLevel,
                  higherIsBetter: nil, precision: 2),
            .init(key: peakHoursKey, displayName: "Your busiest day for company",
                  unit: "h", value: out.peakHours, higherIsBetter: nil, precision: 1),
            .init(key: daysComparedKey, displayName: "Days compared",
                  unit: "days", value: Double(out.daysCompared),
                  higherIsBetter: true, precision: 0),
            .init(key: pooledKey, displayName: "How much your body differed after company",
                  unit: "SD", value: out.overall.pooled, higherIsBetter: false, precision: 2),
            .init(key: restorationKey,
                  displayName: "Whether company restores or drains you",
                  unit: "", value: out.restorationIndex,
                  // +1 is restoring. Higher is better in the only sense this
                  // series has: it is a statement about the reader, not a grade.
                  higherIsBetter: true, precision: 2),
        ]
        if let today = out.today {
            rows.append(.init(key: todayContactKey, displayName: "Company in today's diary",
                              unit: "h", value: today.totalHours,
                              higherIsBetter: nil, precision: 1))
        }
        for finding in out.findings {
            guard let response = finding.response else { continue }
            let key = finding.kind == .chosen ? chosenResponseKey : obligatedResponseKey
            let name = finding.kind == .chosen
                ? "What contact you chose does to you"
                : "What contact you owed does to you"
            rows.append(.init(key: key, displayName: name, unit: "SD",
                              value: response.pooled, higherIsBetter: false, precision: 2))
        }
        return rows
    }

    /// The figures the card produces rather than consumes.
    ///
    /// ⚠️ **Weight 0, and the zero is arithmetic rather than modesty**
    /// (`ScoreFactor.producedFigure`): each is a function *of* the rows above,
    /// so handing it a share would count the same evidence twice and put more
    /// than 100% on one card. Each detail carries the em-dash clause saying so,
    /// which `ScoreAttributionTests.testAnUnweightedRowAlwaysSaysWhy` enforces.
    public static func producedFigures(_ out: Output) -> [ScoreFactor] {
        var rows: [ScoreFactor] = [
            .producedFigure(DerivedSeriesID(.socialBattery, exposureKey),
                            name: "How much company you were in, for you",
                            detail: String(format: "%.2f× a typical day of yours — carries no share of its own, because it is the two weighted rows above added together and scoring it again would count the same hours twice.",
                                           out.exposureLevel)),
            .producedFigure(DerivedSeriesID(.socialBattery, pooledKey),
                            name: "How much your body differed after company",
                            detail: String(format: "%.2f SD %@, across %d signals — carries no share of its own, because it is the average of the body rows above and scoring it again would count the same nights twice.",
                                           abs(out.overall.pooled),
                                           out.overall.pooled > 0 ? "the unwelcome way" : "the welcome way",
                                           out.overall.channels.count)),
            .producedFigure(DerivedSeriesID(.socialBattery, restorationKey),
                            name: "Whether company restores or drains you",
                            detail: String(format: "%@ — carries no share of its own, because it is not an input at all: it is what decides which way the two calendar rows above are scored, and giving it a share as well would count it twice.",
                                           restorationPhrase(out))),
        ]
        if let today = out.today {
            rows.append(.producedFigure(
                DerivedSeriesID(.socialBattery, todayContactKey),
                name: "Company in today's diary",
                detail: String(format: "%.1f h, %.1f h of it still ahead — carries no share, because today's night has not happened yet and this card's number is about the eight weeks behind you.",
                               today.totalHours, today.aheadHours)))
        }
        for finding in out.findings {
            guard let response = finding.response else { continue }
            let key = finding.kind == .chosen ? chosenResponseKey : obligatedResponseKey
            rows.append(.producedFigure(
                DerivedSeriesID(.socialBattery, key),
                name: finding.kind == .chosen
                    ? "What contact you chose does to you"
                    : "What contact you owed does to you",
                detail: kindSentence(finding)
                    + " — carries no share, because it is a second reading of the same nights the body rows above are scored on, split a different way."))
        }
        return rows
    }

    // MARK: - Copy

    /// The refusal, in the reader's own terms, and it is the honest half of
    /// framing 2.
    ///
    /// They asked for *"capacity remaining today"*. The scoped note beside the
    /// ask names the trap: this overlaps Energy heavily, **and Energy's own
    /// calibration is the open `B19` problem** — its reservoir constants were
    /// chosen here rather than measured, and copying them would have produced a
    /// confident percentage resting on nothing.
    ///
    /// So the card prints what it actually knows — how much company is behind
    /// today, how much is still ahead, and how that compares with the reader's
    /// own typical day — and says plainly why there is no number beside it.
    /// A percentage would be the most reassuring thing on this card and the
    /// least true.
    public static let capacityRefusal = "There is no percentage here, and that is deliberate. Nothing on your phone measures a social battery, so any figure would be this app inventing a scale and then charging you for believing it. What is real is below: how much company today has already carried, how much is still in your diary, and how that compares with a typical day of yours — plus what your own nights have done after days like it."

    public static func headline(_ out: Output) -> String {
        let restoring = out.restorationIndex >= 0.6
        switch out.quadrant {
        case .spent:
            return out.overall.pooled >= 1.2 ? "A lot of people, and it is costing you"
                                             : "A lot of people, and you are feeling it"
        case .sustained:
            return restoring ? "A full diary, and it seems to suit you"
                             : "A full diary, and you are carrying it well"
        case .unexplained:
            return "Your body is off, and it is not your diary"
        case .quiet:
            return restoring ? "A quiet stretch, and you thrive on company"
                             : "A quiet stretch for company"
        }
    }

    /// The quadrant said out loud, as the card's first driver line.
    public static func quadrantLine(_ out: Output) -> String {
        let load = String(format: "%.1f h against %.1f h", out.heavyMedianHours,
                          out.lightMedianHours)
        switch out.quadrant {
        case .spent:
            return "Your busier days for company are busy by your own standards — \(load) — and your body is showing it on the nights after them. That combination is what this card is for, and it is the one reading here that means something is worth changing."
        case .sustained:
            return "Your busier days for company are busy by your own standards — \(load) — and your body is not showing it: resting heart rate, variability and sleep look much the same after a day full of people as after a quiet one. That is genuinely good news, and it is not the same thing as an empty diary."
        case .unexplained:
            return "Your body differs between these two groups of days, but how much company you had barely does — \(load). Whatever is moving resting heart rate, variability or sleep, this card cannot honestly call it people: there is not enough difference between your busier and quieter days for company to be the explanation."
        case .quiet:
            return "A quiet stretch for company by your own standards — \(load) — and your body agrees: nothing separates the busier days from the quieter ones."
        }
    }

    /// What the restoration index amounts to, in words. **Switched on the
    /// interval, not on the index** — the words are copy and may step; the
    /// number that reaches the score never does.
    public static func restorationPhrase(_ out: Output) -> String {
        guard out.overall.isDistinguishableFromZero else {
            return String(format: "Too close to call — your busier and quieter days for company differ by %.2f SD, and the range around that (%.2f to %.2f) still contains zero",
                          out.overall.pooled, out.overall.low, out.overall.high)
        }
        return out.overall.pooled < 0
            ? String(format: "Company appears to restore you — your body reads %.2f SD better on the nights after your busier days (%.2f to %.2f)",
                     abs(out.overall.pooled), abs(out.overall.high), abs(out.overall.low))
            : String(format: "Company appears to drain you — your body reads %.2f SD worse on the nights after your busier days (%.2f to %.2f)",
                     out.overall.pooled, out.overall.low, out.overall.high)
    }

    /// One contact kind's finding, as a sentence — including the two ways it can
    /// honestly refuse.
    public static func kindSentence(_ finding: KindFinding) -> String {
        switch finding.verdict {
        case .notEnoughDays:
            return "Not enough days of \(finding.kind.phrase) yet to split them against your quieter ones — this needs \(minimumDaysPerContactKind) on each side of your own median, in at least one of weekdays or weekends. You have \(finding.daysWithContact) days with any at all."
        case .tooCloseToTell:
            guard let response = finding.response else { return "" }
            return String(format: "We cannot tell yet. After days of %@ your body reads %.2f SD from your quieter ones, and the range around that — %.2f to %.2f — still contains zero. That is a real answer, not a missing one: on the evidence so far this could go either way.",
                          finding.kind.phrase, response.pooled, response.low, response.high)
        case .restores:
            guard let response = finding.response else { return "" }
            return String(format: "%@ appears to restore you: your body reads %.2f SD better on the nights after those days, and the range around that (%.2f to %.2f) stays on the good side of zero.",
                          finding.kind.title, abs(response.pooled),
                          abs(response.high), abs(response.low))
        case .drains:
            guard let response = finding.response else { return "" }
            return String(format: "%@ appears to drain you: your body reads %.2f SD worse on the nights after those days, and the range around that (%.2f to %.2f) stays on the bad side of zero.",
                          finding.kind.title, response.pooled, response.low, response.high)
        }
    }

    static func sentence(_ channel: WorkImpactModel.Channel) -> String {
        let direction = channel.towardWorse > 0 ? "worse" : "better"
        return String(format: "%@ %@ on the nights after your busier days for company — %@ against %@ — which is %.1f SD %@",
                      channel.metric.displayName,
                      abs(channel.towardWorse) < 0.3 ? "is about the same" : "runs \(direction)",
                      MetricValueFormatter.string(channel.onHeavyDays, channel.metric),
                      MetricValueFormatter.string(channel.onLightDays, channel.metric),
                      abs(channel.towardWorse), direction)
    }

    /// What today's diary amounts to, without a percentage.
    public static func todaySentence(_ out: Output) -> String {
        guard let today = out.today else {
            return "Nothing in today's diary yet."
        }
        guard today.totalHours > 0 else {
            return String(format: "Nothing with other people in today's diary — against a typical day of yours carrying %.1f h of it.",
                          out.typicalDayHours)
        }
        let people = today.sizedMeetings > 0
            ? String(format: " with at least %d people across %d of them",
                     today.people, today.sizedMeetings)
            : ""
        let ahead = today.aheadHours > 0
            ? String(format: " %.1f h of it is still ahead of you.", today.aheadHours)
            : " All of it is behind you."
        return String(format: "Today carries %.1f h of company across %d meeting%@%@ — %.2f× a typical day of yours, which puts it on the %@ side of your own median.%@",
                      today.totalHours, today.meetings, today.meetings == 1 ? "" : "s",
                      people, today.level, today.isBusyForThem ? "busier" : "quieter", ahead)
    }

    /// What a day like today has historically cost, **or the refusal**.
    public static func todayPrecedentSentence(_ out: Output) -> String {
        guard let today = out.today, today.totalHours > 0 else {
            return "On your quieter days for company your body has read \(String(format: "%.2f", abs(out.overall.pooled))) SD \(out.overall.pooled > 0 ? "better" : "worse") than on your busier ones — though see the range on that below before reading much into it."
        }
        guard out.overall.isDistinguishableFromZero else {
            return "What days like today have cost you: not yet distinguishable from nothing. The difference between your busier and quieter days for company is smaller than the range around it, so this card will not put a figure on today until that changes."
        }
        let group = today.isBusyForThem ? "busier" : "quieter"
        let sign = today.isBusyForThem ? out.overall.pooled : -out.overall.pooled
        return String(format: "Days like today sit on the %@ side of your own median, and on those days your body has read %.2f SD %@ than on the other side (range %.2f to %.2f). That is a statement about the group today belongs to, not a prediction about tonight.",
                      group, abs(sign), sign > 0 ? "worse" : "better",
                      out.overall.low, out.overall.high)
    }
}
