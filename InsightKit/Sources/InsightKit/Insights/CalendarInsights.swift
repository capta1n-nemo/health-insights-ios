import Foundation

/// **Work impact and travel drain** — backlog #15 and #16, the two cards the
/// reader asked for by name and then had to ask about again, because both were
/// blocked on a calendar the app did not have.
///
/// Both compare the reader's body on one kind of day against the same body on
/// another kind, and both are therefore exposed to the same confound. It is
/// named once here because it decides the design of both:
///
/// ## ⚠️ The confound that shapes everything below: the weekend
///
/// A naive "busy days versus quiet days" comparison is mostly a comparison of
/// **weekdays versus weekends**. Saturday has no meetings, more sleep, later
/// wake-ups and different alcohol — so a card built that way would report that
/// meetings wreck your recovery when what it actually found is that Saturday
/// exists.
///
/// So: **both cards compare working days with working days only.** That throws
/// away data and it is the difference between a finding and an artefact.
public enum WorkImpactModel {

    /// The stretch compared. Eight weeks of working days is about forty
    /// observations, which is the least that can separate a busy day from a
    /// quiet one at this effect size.
    public static let windowDays = 56
    /// Working days needed in each half before anything is reported.
    public static let minimumDaysPerHalf = 8

    /// Signals worth asking about, and which direction is the unwelcome one.
    ///
    /// Deliberately few and deliberately next-morning: a meeting cannot change
    /// last night's sleep, so every one of these is read on the night *after*
    /// the day being judged. Getting that backwards would produce a confident
    /// finding about time running the wrong way.
    static let watched: [(metric: MetricType, higherIsWorse: Bool)] = [
        (.restingHeartRate, true),
        (.heartRateVariabilityRMSSD, false),
        (.sleepDurationHours, false),
    ]

    public struct Channel: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        /// Mean on the busiest working days.
        public let onHeavyDays: Double
        /// Mean on the quietest working days.
        public let onLightDays: Double
        /// Signed so **positive is always the unwelcome direction**.
        public let towardWorse: Double
        public var id: String { metric.rawValue }

        public var difference: Double { onHeavyDays - onLightDays }
    }

    public struct Output: Sendable, Equatable {
        public let channels: [Channel]
        public let heavyDays: Int
        public let lightDays: Int
        /// Median load on the heavy half, in hours.
        public let heavyMedianHours: Double
        public let lightMedianHours: Double
        public let score: Double
        /// Weighted mean departure, in SDs of the reader's own spread.
        public let pooled: Double
        public let contributions: [MetricContribution]

        /// **The card's independent variable, in one number.**
        ///
        /// How much busier the busy half actually was. A comparison across a
        /// twenty-minute gap and one across five hours produce the same kind of
        /// answer and are not the same evidence, and until 2026-08-06 nothing on
        /// this card said which it had.
        public var loadGapHours: Double { heavyMedianHours - lightMedianHours }

        /// Working days on both sides of the split.
        public var workingDaysCompared: Int { heavyDays + lightDays }
    }

    /// Load per working day, from the classified events.
    ///
    /// Weekends are excluded here rather than filtered later, so nothing
    /// downstream can accidentally reintroduce them.
    public static func workingDayLoad(events: [CalendarEvent],
                                      judgements: [CalendarEventJudgement],
                                      now: Date = Date(),
                                      calendar: Calendar = .current) -> [Date: Double] {
        let byID = Dictionary(uniqueKeysWithValues: judgements.map { ($0.eventID, $0.effective) })
        let cutoff = calendar.date(byAdding: .day, value: -windowDays,
                                   to: calendar.startOfDay(for: now)) ?? now
        var load: [Date: Double] = [:]
        for event in events where event.start >= cutoff {
            let day = calendar.startOfDay(for: event.start)
            let weekday = calendar.component(.weekday, from: day)
            // 1 = Sunday, 7 = Saturday in every Gregorian calendar.
            guard weekday != 1 && weekday != 7 else { continue }
            let classification = byID[event.id] ?? CalendarEventClassifier.classify(event)
            // Only work counts. A dentist appointment is a commitment and it is
            // not what this card is about. An OOO-shaped block never reaches
            // here whoever it belongs to (B7 H2): `.leave` buckets personal,
            // `.absence` buckets other, and both carry zero `loadHours` — so an
            // absence cannot inflate a working day even in a work calendar.
            guard CalendarEventBucket(classification) == .work else { continue }
            load[day, default: 0] += classification.loadHours
        }
        return load
    }

    public static func evaluate(events: [CalendarEvent],
                                judgements: [CalendarEventJudgement],
                                samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let load = workingDayLoad(events: events, judgements: judgements,
                                  now: now, calendar: calendar)
        guard load.count >= minimumDaysPerHalf * 2 else { return nil }

        // Split at the reader's own median rather than at a chosen number of
        // hours: "busy" means busy *for them*, and a fixed threshold would call
        // a part-time week empty and a consultant's week uniformly full.
        let sorted = load.values.sorted()
        let median = sorted[sorted.count / 2]
        let heavy = load.filter { $0.value > median }.keys.sorted()
        let light = load.filter { $0.value <= median }.keys.sorted()
        guard heavy.count >= minimumDaysPerHalf, light.count >= minimumDaysPerHalf
        else { return nil }

        var channels: [Channel] = []
        for entry in watched {
            let daily = VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                                calendar: calendar)
            let byDay = Dictionary(daily.map { ($0.date, $0.value) },
                                   uniquingKeysWith: { first, _ in first })
            /// The night *after* the day, because a meeting cannot change the
            /// sleep that preceded it.
            func values(for days: [Date]) -> [Double] {
                days.compactMap { day in
                    calendar.date(byAdding: .day, value: 1, to: day).flatMap { byDay[$0] }
                }
            }
            let heavyValues = values(for: heavy)
            let lightValues = values(for: light)
            guard heavyValues.count >= minimumDaysPerHalf,
                  lightValues.count >= minimumDaysPerHalf,
                  let heavyMean = Baseline.mean(heavyValues),
                  let lightMean = Baseline.mean(lightValues),
                  let spread = Baseline.robustScale(lightValues + heavyValues), spread > 0
            else { continue }
            let raw = (heavyMean - lightMean) / spread
            channels.append(Channel(metric: entry.metric, onHeavyDays: heavyMean,
                                    onLightDays: lightMean,
                                    towardWorse: entry.higherIsWorse ? raw : -raw))
        }
        guard channels.count >= 2 else { return nil }

        let pooled = channels.reduce(0) { $0 + $1.towardWorse } / Double(channels.count)
        let contributions = channels.map { channel in
            MetricContribution(
                metric: channel.metric,
                higherIsBetter: !watched.first { $0.metric == channel.metric }!.higherIsWorse,
                weight: 1 / Double(channels.count),
                detail: sentence(channel),
                componentScore: ScoreCurve.through(
                    [(-1.5, 95), (0, 78), (0.75, 55), (1.5, 35), (3, 18)],
                    at: channel.towardWorse))
        }

        let heavyMedian = heavy.compactMap { load[$0] }.sorted()
        let lightMedian = light.compactMap { load[$0] }.sorted()
        return Output(
            channels: channels.sorted { $0.towardWorse > $1.towardWorse },
            heavyDays: heavy.count, lightDays: light.count,
            heavyMedianHours: heavyMedian[heavyMedian.count / 2],
            lightMedianHours: lightMedian[lightMedian.count / 2],
            score: score(pooled: pooled), pooled: pooled,
            contributions: contributions)
    }

    public static func score(pooled: Double) -> Double {
        ScoreCurve.through([(-1.5, 95), (-0.5, 85), (0, 78),
                            (0.75, 55), (1.5, 35), (3, 18)], at: pooled)
    }

    static func sentence(_ channel: Channel) -> String {
        let direction = channel.towardWorse > 0 ? "worse" : "better"
        return String(format: "%@ %@ on your busier working days — %@ against %@ — which is %.1f SD %@",
                      channel.metric.displayName,
                      abs(channel.towardWorse) < 0.3 ? "is about the same" : "runs \(direction)",
                      MetricValueFormatter.string(channel.onHeavyDays, channel.metric),
                      MetricValueFormatter.string(channel.onLightDays, channel.metric),
                      abs(channel.towardWorse), direction)
    }

    // MARK: - What the calendar contributes, as data in its own right
    //
    // **The reader's complaint, 2026-08-06, and it was exactly right:** *"The
    // work impact card... 'What's changed' and 'what goes into this' will only
    // still just show Resting Heart Rate, HRV and sleep duration.... how is that
    // possible, the entire point of this card is to take into consideration work
    // impact, where is that on these sections?"*
    //
    // It was possible because `candidateMetrics` is `watched.map(\.metric)` and
    // the model emitted no `otherFactors` at all — so the one quantity the card
    // is *about*, the calendar load that decides which day lands in which half,
    // was declared nowhere the reader could look.
    //
    // ## ⚠️ Why these carry weight 0, and why that is the honest answer
    //
    // The brief for this work asked for real weights. The arithmetic will not
    // support them, and inventing one would break the reader's own standing rule
    // that a modelled figure is never dressed up: this card's number is
    // `ScoreCurve.through(…, at: pooled)`, and `pooled` is the mean of the
    // per-metric departures — the calendar load is nowhere in that sum. Two
    // readers with a 20-minute gap and a five-hour gap can score identically.
    //
    // Which is itself the finding worth putting on the card. So the load
    // quantities render as `producedFigure` rows in the weighting section's
    // *charted, not scored* group, each saying in its own words that it defines
    // the comparison rather than dividing the number — and they become series,
    // so "are my weeks getting heavier" is answerable from the Data tab instead
    // of only from a sentence that is regenerated and discarded every launch.
    //
    // The alternative — folding the gap into the score — changes every stored
    // number this card has and needs its own brief. It is backlog, not a
    // side effect of a rendering fix.

    static let busyHoursKey = "meetingHoursBusyDays"
    static let quietHoursKey = "meetingHoursQuietDays"
    static let loadGapKey = "meetingHoursGap"
    static let daysComparedKey = "workingDaysCompared"
    static let pooledKey = "bodyDifferencePooled"

    public static func derivedOutputs(_ out: Output) -> [DerivedOutput] {
        [
            .init(key: busyHoursKey, displayName: "Work hours on your busier days",
                  unit: "h", value: out.heavyMedianHours,
                  // Neither direction is the good one. A heavy week is a fact
                  // about a calendar, and this card is not entitled to call it
                  // a bad one — that is what the body channels are for.
                  higherIsBetter: nil, precision: 1),
            .init(key: quietHoursKey, displayName: "Work hours on your quieter days",
                  unit: "h", value: out.lightMedianHours,
                  higherIsBetter: nil, precision: 1),
            .init(key: loadGapKey, displayName: "The gap between your busy and quiet days",
                  unit: "h", value: out.loadGapHours,
                  // A wider gap is a *better comparison*, not a better week —
                  // and there is no field for "better evidence", so this stays
                  // undirected rather than claiming the wrong good direction.
                  higherIsBetter: nil, precision: 1),
            .init(key: daysComparedKey, displayName: "Working days compared",
                  unit: "days", value: Double(out.workingDaysCompared),
                  higherIsBetter: true, precision: 0),
            // The statistic the dial is a rendering of, kept in SD because the
            // 0–100 above it is a curve and a curve throws away resolution at
            // both ends. `ScoreHistory` already trends the score; this is the
            // thing the score is *of*.
            .init(key: pooledKey, displayName: "How much your body differed on busy days",
                  unit: "SD", value: out.pooled, higherIsBetter: false, precision: 2),
        ]
    }

    /// The calendar quantities as factors, so they appear in "What goes into
    /// this" and in "How this is weighted" rather than only inside a sentence.
    public static func calendarFactors(_ out: Output) -> [ScoreFactor] {
        let id = { (key: String) in DerivedSeriesID(.workImpact, key) }
        return [
            ScoreFactor.producedFigure(
                id(loadGapKey), name: "The gap this comparison rests on",
                detail: String(format: "%.1f h more work on the busy half — %.1f h against %.1f h. This gap decides which day goes in which group; it carries no share of the number, because the number is how much your *body* differed, not how much your calendar did.",
                               out.loadGapHours, out.heavyMedianHours, out.lightMedianHours)),
            ScoreFactor.producedFigure(
                id(busyHoursKey), name: "Work hours on your busier days",
                detail: String(format: "%.1f h, median. Charted here and in the Data tab; not scored, because this card measures the difference between two kinds of day rather than judging either one.",
                               out.heavyMedianHours)),
            ScoreFactor.producedFigure(
                id(quietHoursKey), name: "Work hours on your quieter days",
                detail: String(format: "%.1f h, median. The side everything above is measured against.",
                               out.lightMedianHours)),
            ScoreFactor.producedFigure(
                id(daysComparedKey), name: "Working days compared",
                detail: "\(out.workingDaysCompared) — \(out.heavyDays) busy against \(out.lightDays) quiet. Context rather than a share: a comparison resting on \(minimumDaysPerHalf * 2) days is not the same evidence as one resting on forty, and nothing else on this card tells you which you have."),
        ]
    }
}

/// **What crossing time zones costs, measured on the reader's own body.**
public enum TravelDrainModel {

    /// Days after a zone change treated as the disrupted stretch.
    public static let recoveryDays = 4
    /// Trips needed before anything is said. **Two, minimum** — one trip is an
    /// anecdote, and a card that turns a single flight into a finding is the
    /// thing the substance card was refused for.
    public static let minimumTrips = 2

    public struct Output: Sendable, Equatable {
        public let trips: Int
        /// Signed so positive is the unwelcome direction, per channel.
        public let channels: [WorkImpactModel.Channel]
        public let score: Double
        public let pooled: Double
        public let contributions: [MetricContribution]
        /// The zones seen, for the card to name.
        public let zones: [String]
        /// **Days actually inside a recovery window** — the union of them, not
        /// `trips × recoveryDays`. Two trips four days apart overlap, and the
        /// difference between the two figures is the difference between what was
        /// compared and what a reader would assume was compared.
        public let disruptedDays: Int
    }

    public static func evaluate(events: [CalendarEvent],
                                samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let changes = CalendarModel.timeZoneChanges(events, calendar: calendar)
        guard changes.count >= minimumTrips else { return nil }

        // Days inside a recovery window after any change.
        var disrupted = Set<Date>()
        for change in changes {
            for offset in 0..<recoveryDays {
                if let day = calendar.date(byAdding: .day, value: offset, to: change.day) {
                    disrupted.insert(calendar.startOfDay(for: day))
                }
            }
        }

        var channels: [WorkImpactModel.Channel] = []
        for entry in WorkImpactModel.watched {
            let daily = VitalReader.dailySeries(entry.metric, from: samples, now: now,
                                                calendar: calendar)
            let after = daily.filter { disrupted.contains($0.date) }.map(\.value)
            let ordinary = daily.filter { !disrupted.contains($0.date) }.map(\.value)
            guard after.count >= minimumTrips * 2, ordinary.count >= 14,
                  let afterMean = Baseline.mean(after),
                  let ordinaryMean = Baseline.mean(ordinary),
                  let spread = Baseline.robustScale(ordinary), spread > 0
            else { continue }
            let raw = (afterMean - ordinaryMean) / spread
            channels.append(WorkImpactModel.Channel(
                metric: entry.metric, onHeavyDays: afterMean, onLightDays: ordinaryMean,
                towardWorse: entry.higherIsWorse ? raw : -raw))
        }
        guard channels.count >= 2 else { return nil }

        let pooled = channels.reduce(0) { $0 + $1.towardWorse } / Double(channels.count)
        let contributions = channels.map { channel in
            MetricContribution(
                metric: channel.metric,
                higherIsBetter: !WorkImpactModel.watched
                    .first { $0.metric == channel.metric }!.higherIsWorse,
                weight: 1 / Double(channels.count),
                detail: String(format: "%@ ran %@ against %@ in the %d days after a time-zone change",
                               channel.metric.displayName,
                               MetricValueFormatter.string(channel.onHeavyDays, channel.metric),
                               MetricValueFormatter.string(channel.onLightDays, channel.metric),
                               recoveryDays),
                componentScore: WorkImpactModel.score(pooled: channel.towardWorse))
        }

        return Output(trips: changes.count, channels: channels.sorted { $0.towardWorse > $1.towardWorse },
                      score: WorkImpactModel.score(pooled: pooled), pooled: pooled,
                      contributions: contributions,
                      zones: Array(Set(changes.map(\.zone))).sorted(),
                      disruptedDays: disrupted.count)
    }

    // MARK: - What the calendar contributes here
    //
    // The same shape as work impact and the same verdict, for the same reason:
    // the calendar decides which days are compared and the score is a curve over
    // how much the *body* differed between them, so these quantities are the
    // card's independent variable rather than terms in its sum. Weight 0, both
    // sections, and a series each.
    //
    // Deliberately **not** emitted here: the per-channel means either side of a
    // trip. They are `MetricContribution.detail` already, and each is the mean of
    // one metric over a set of days — a bare restatement, which under the
    // reader's own qualifier ("unless that was just directly derived from one
    // other data point") must not become a second name for a number the Data tab
    // already holds.

    static let tripsKey = "timeZoneChanges"
    static let disruptedDaysKey = "disruptedDays"
    static let pooledKey = "bodyDifferencePooled"

    public static func derivedOutputs(_ out: Output) -> [DerivedOutput] {
        [
            .init(key: tripsKey, displayName: "Time-zone changes found",
                  unit: "", value: Double(out.trips),
                  // More trips is more evidence and not a better life; the card
                  // says so out loud and the series must not disagree with it.
                  higherIsBetter: nil, precision: 0),
            .init(key: disruptedDaysKey, displayName: "Days inside a recovery window",
                  unit: "days", value: Double(out.disruptedDays),
                  higherIsBetter: nil, precision: 0),
            .init(key: pooledKey, displayName: "How much your body differed after a change",
                  unit: "SD", value: out.pooled, higherIsBetter: false, precision: 2),
        ]
    }

    public static func calendarFactors(_ out: Output) -> [ScoreFactor] {
        let id = { (key: String) in DerivedSeriesID(.travelDrain, key) }
        return [
            ScoreFactor.producedFigure(
                id(tripsKey), name: "Time-zone changes found",
                detail: "\(out.trips) across your calendar. This decides which days are compared and carries no share of the number — and \(out.trips) is a small number, which is the caveat this card leads with rather than hides."),
            ScoreFactor.producedFigure(
                id(disruptedDaysKey), name: "Days inside a recovery window",
                detail: "\(out.disruptedDays) — the \(recoveryDays) days after each change, counted once where two trips overlap. Everything above is measured on these days against every other day."),
        ]
    }
}

// MARK: - The cards

/// **Work impact** — backlog #16.
///
/// Its inputs are the calendar and the body, and the calendar is not `samples`,
/// so it is bound at construction and rebound on every recompute — the same
/// device `SubstanceImpactInsight` uses for the substance log, and for the same
/// reason: `InsightEngine` carries samples and a profile and nothing else.
public struct WorkImpactInsight: InsightModel {
    public let id: InsightID = .workImpact
    public let title = "Work impact"

    public let events: [CalendarEvent]
    public let judgements: [CalendarEventJudgement]

    public init(events: [CalendarEvent] = [], judgements: [CalendarEventJudgement] = []) {
        self.events = events
        self.judgements = judgements
    }

    public var candidateMetrics: [MetricType] { WorkImpactModel.watched.map(\.metric) }
    public var requirements: [GroundingRequirement] { [] }
    /// The calendar is construction state, not `samples`.
    public var readsOnlySamples: Bool { false }

    /// Identity (B7 H1), because it decides whose OOO block a working day
    /// contains — the input that most directly moves this card's load figures.
    /// `.offeredOnly`, so it is findable here and never nagged for. Travel
    /// drain deliberately does **not** offer it: that model reads time-zone
    /// changes and no classifications, and a card offering an input its model
    /// ignores would be claiming a sensitivity it does not have.
    ///
    /// ⚠️ H6 — this model reading the holiday *ledger* ("you have not had
    /// leave in N months") is deliberately not wired yet; it changes the score
    /// and needs a `modelVersion` bump, per the fitness-v2 precedent.
    public var contributions: [ContributionRoute] { [.readerIdentity] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let out = WorkImpactModel.evaluate(events: events, judgements: judgements,
                                                 samples: samples, now: now) else {
            return invitingInput(
                id, title,
                action: "Connect your calendar",
                message: "This compares your body on your busier working days against your quieter ones — resting heart rate, variability and sleep, each read on the night *after* the day, because a meeting cannot change the sleep before it. It needs your calendar connected and about \(WorkImpactModel.minimumDaysPerHalf) working days of each.")
        }

        var drivers: [InsightDriver] = [
            InsightDriver(
                text: String(format: "Your busier working days carry about %.1f hours of work against %.1f on the quieter ones — %d days against %d.",
                             out.heavyMedianHours, out.lightMedianHours,
                             out.heavyDays, out.lightDays),
                isNotable: false)
        ]
        for channel in out.channels {
            drivers.append(InsightDriver(text: WorkImpactModel.sentence(channel),
                                         isNotable: channel.towardWorse >= 0.5))
        }
        // ⚠️ The caveat that makes the whole comparison legitimate.
        drivers.append(.routine("Only working days are compared, on both sides. A busy-versus-quiet comparison that included weekends would mostly be measuring the weekend — more sleep, later mornings, no meetings — and would report that work wrecks your recovery when what it found is that Saturday exists."))
        drivers.append(.routine("An hour is not an hour here: a formal meeting in a room counts for more than blocked focus time, and a reminder counts for nothing. Those weightings are the app's stated assumption, not a measurement — correct any event on the list and this recomputes."))

        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: headline(out), score: out.score,
            confidence: out.channels.count >= 3 ? .moderate : .low,
            explanation: "Your body on your busier working days against the same body on your quieter ones, over the last \(WorkImpactModel.windowDays) days. Working days only, on both sides, and every signal read on the night after the day it is judging.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: out.contributions,
            weighting: .weightedAverage,
            // The calendar, finally declared where the reader looks for what a
            // card reads — see `WorkImpactModel.calendarFactors`.
            otherFactors: WorkImpactModel.calendarFactors(out),
            derivedOutputs: WorkImpactModel.derivedOutputs(out))
    }

    private func headline(_ out: WorkImpactModel.Output) -> String {
        switch out.pooled {
        case ..<0.3: return "Busy days look like quiet ones"
        case 0.3..<0.8: return "A little more strain on busy days"
        case 0.8..<1.5: return "Busy days cost you"
        default: return "Busy days cost you a lot"
        }
    }
}

/// **Travel drain** — backlog #15, and the card the reader asked after by name.
public struct TravelDrainInsight: InsightModel {
    public let id: InsightID = .travelDrain
    public let title = "Travel drain"

    public let events: [CalendarEvent]

    public init(events: [CalendarEvent] = []) { self.events = events }

    public var candidateMetrics: [MetricType] { WorkImpactModel.watched.map(\.metric) }
    public var requirements: [GroundingRequirement] { [] }
    /// The calendar is construction state, not `samples`.
    public var readsOnlySamples: Bool { false }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let out = TravelDrainModel.evaluate(events: events, samples: samples, now: now)
        else {
            return invitingInput(
                id, title,
                action: "Connect your calendar",
                message: "This reads the time zone on your calendar entries — the app captures no location and no time zone on any health reading, so a calendar entry is the only thing on your phone that knows you moved. It needs \(TravelDrainModel.minimumTrips) trips before it will say anything: one flight is an anecdote.")
        }

        var drivers: [InsightDriver] = [
            InsightDriver(
                text: "\(out.trips) time-zone changes found across your calendar, and the \(TravelDrainModel.recoveryDays) days after each compared with every other day.",
                isNotable: false)
        ]
        for channel in out.channels {
            drivers.append(InsightDriver(
                text: String(format: "%@ ran %@ after a change, against %@ otherwise — %.1f SD %@",
                             channel.metric.displayName,
                             MetricValueFormatter.string(channel.onHeavyDays, channel.metric),
                             MetricValueFormatter.string(channel.onLightDays, channel.metric),
                             abs(channel.towardWorse),
                             channel.towardWorse > 0 ? "the unwelcome way" : "the welcome way"),
                isNotable: channel.towardWorse >= 0.5))
        }
        drivers.append(.routine("⚠️ A time-zone change on a calendar is not proof of a flight — an entry set in another zone by hand looks identical. And \(out.trips) trips is a small number: this describes what happened around those, not what travel does to you in general."))
        if !out.zones.isEmpty {
            drivers.append(.routine("Zones seen: \(out.zones.joined(separator: ", "))."))
        }

        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: headline(out), score: out.score,
            confidence: out.trips >= 4 ? .moderate : .low,
            explanation: "What crossing time zones costs you, measured on your own body. The app records no location and no time zone on any health reading, so your calendar is the only thing on the phone that knows you moved — which is why this card needed the calendar before it could exist at all.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: out.contributions,
            weighting: .weightedAverage,
            otherFactors: TravelDrainModel.calendarFactors(out),
            derivedOutputs: TravelDrainModel.derivedOutputs(out))
    }

    private func headline(_ out: TravelDrainModel.Output) -> String {
        switch out.pooled {
        case ..<0.3: return "Travel barely shows"
        case 0.3..<0.8: return "A little drag after a trip"
        case 0.8..<1.5: return "Trips take something out of you"
        default: return "Trips take a lot out of you"
        }
    }
}
