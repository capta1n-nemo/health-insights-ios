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
            // not what this card is about.
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
                      zones: Array(Set(changes.map(\.zone))).sorted())
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
            weighting: .weightedAverage)
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
            weighting: .weightedAverage)
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
