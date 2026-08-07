import Foundation

/// **Social battery** — backlog B9-1, scoped by the reader on 2026-08-07.
///
/// The model is `SocialBatteryModel`; read its note first, because the three
/// design decisions that keep this from being a second Work impact card live
/// there. This file is the card: what it says, in what order, and what it
/// refuses to say.
///
/// ## Its inputs are the calendar and the body
///
/// The calendar is not `samples`, so it is bound at construction and rebound on
/// every recompute by `InsightEngine.withCalendar` — the same device
/// `WorkImpactInsight`, `TravelDrainInsight` and `SubstanceImpactInsight` use,
/// and for the same reason: the engine carries samples and a profile and nothing
/// else.
///
/// ## ⚠️ The one thing this card will not do
///
/// It will not print a battery percentage. See
/// `SocialBatteryModel.capacityRefusal` — the reader asked for capacity
/// remaining today, and the honest answer is the three facts underneath it plus
/// the reason there is no number. Energy's reservoir constants were chosen in
/// this repo rather than measured (the open `B19` problem), and borrowing them
/// here would have produced the most reassuring figure on the card and the least
/// true one.
public struct SocialBatteryInsight: InsightModel {
    public let id: InsightID = .socialBattery
    public let title = "Social battery"

    public let events: [CalendarEvent]
    public let judgements: [CalendarEventJudgement]

    public init(events: [CalendarEvent] = [], judgements: [CalendarEventJudgement] = []) {
        self.events = events
        self.judgements = judgements
    }

    public var candidateMetrics: [MetricType] { SocialBatteryModel.watched.map(\.metric) }
    public var requirements: [GroundingRequirement] { [] }
    /// The calendar is construction state, not `samples`.
    public var readsOnlySamples: Bool { false }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        let what = "This reads how much of your time went on other people — meetings with a size, in person or remote, work and personal alike — and what your body did on the nights after those days."
        let out: SocialBatteryModel.Output
        switch SocialBatteryModel.analyse(events: events, judgements: judgements,
                                          samples: samples, now: now) {
        case .ready(let value):
            out = value
        case .noCalendar:
            return invitingInput(
                id, title,
                action: "Connect your calendar",
                message: "\(what) It needs your calendar connected and about \(SocialBatteryModel.minimumDaysPerHalf * 2) days of it.")
        case .waiting(let gate):
            // Never the "connect your calendar" invitation on this branch — the
            // calendar is plainly connected here, we are holding events. That
            // was a defect the reader found on the travel card on 2026-08-07.
            return waitingOn(id, title, gate: gate, context: what)
        }

        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: SocialBatteryModel.headline(out),
            // The second figure is today, because the reader asked what is left
            // *today* and the eight-week score cannot answer that.
            subheadline: subheadline(out),
            score: out.score,
            // Thin contrast is thin evidence about company whatever the body
            // did, and an interval that spans zero is thinner still.
            confidence: confidence(out),
            explanation: "How much of your time went on other people, and what your body did about it — both of those are scored here. The calendar side is how much busier your busier days for company were than your quieter ones, measured against your own range rather than anybody's norm. The body side is resting heart rate, variability and sleep on the nights after those days, over the last \(SocialBatteryModel.windowDays) days. ⚠️ Whether more company counts for or against you here is not assumed: it is read off your own nights, and while your data cannot say, this card says so rather than guessing.",
            driverLines: drivers(out),
            unmetRequirements: [],
            contributors: out.contributions,
            weighting: .weightedAverage,
            otherFactors: SocialBatteryModel.calendarFactors(out)
                + SocialBatteryModel.producedFigures(out),
            derivedOutputs: SocialBatteryModel.derivedOutputs(out))
    }

    private func subheadline(_ out: SocialBatteryModel.Output) -> String? {
        guard let today = out.today else { return nil }
        guard today.totalHours > 0 else { return "Nothing with other people in today's diary" }
        return String(format: "Today: %.1f h of company%@",
                      today.totalHours,
                      today.aheadHours > 0
                          ? String(format: ", %.1f h still ahead", today.aheadHours) : "")
    }

    /// ⚠️ **Three gates, not one.** A card whose whole claim is "this is what
    /// company does to *you*" must not read as confident while the interval
    /// around its central finding contains zero.
    private func confidence(_ out: SocialBatteryModel.Output) -> InsightConfidence {
        guard out.overall.channels.count >= 3,
              out.contactGapRatio >= 0.5,
              out.overall.isDistinguishableFromZero else { return .low }
        return .moderate
    }

    private func drivers(_ out: SocialBatteryModel.Output) -> [InsightDriver] {
        var drivers: [InsightDriver] = [.notable(SocialBatteryModel.quadrantLine(out))]

        // Framing 3 leads the rest, because it is the novel one and because it
        // is what decides how the calendar rows above are scored.
        drivers.append(InsightDriver(
            text: "Does company restore you or drain you? " + SocialBatteryModel.restorationPhrase(out) + ".",
            isNotable: out.overall.isDistinguishableFromZero))
        for finding in out.findings {
            drivers.append(InsightDriver(
                text: SocialBatteryModel.kindSentence(finding),
                isNotable: finding.verdict == .drains))
        }

        // Framing 2 — today, with the refusal attached to it rather than buried.
        drivers.append(.routine(SocialBatteryModel.todaySentence(out)))
        drivers.append(.routine(SocialBatteryModel.todayPrecedentSentence(out)))
        drivers.append(.routine(SocialBatteryModel.capacityRefusal))

        // Framing 1's own numbers.
        drivers.append(InsightDriver(
            text: String(format: "Your busier days for company carry about %.1f hours of it against %.1f on the quieter ones — %d days against %d — and your busiest single day ran to %.1f h%@.",
                         out.heavyMedianHours, out.lightMedianHours,
                         out.heavyDays, out.lightDays, out.peakHours,
                         out.peakPeople > 0 ? " across at least \(out.peakPeople) people" : ""),
            isNotable: false))
        for channel in out.overall.channels {
            drivers.append(InsightDriver(
                text: SocialBatteryModel.sentence(channel),
                isNotable: channel.towardWorse >= SocialBatteryModel.notableResponse))
        }

        drivers.append(.routine(String(format: "How the number divides: your calendar carries %d%% of it and your body the other %d%%. That split is not fixed — the further apart your busier and quieter days for company are, the more your body's side is allowed to say, because a difference measured across two groups of days that barely differ is not evidence about company.",
                                       Int(((1 - out.responseShare) * 100).rounded()),
                                       Int((out.responseShare * 100).rounded()))))

        // ⚠️ The caveat that makes the comparison legitimate, and it is the one
        // thing this card does differently from Work impact.
        drivers.append(.routine(stratificationLine(out)))
        drivers.append(.routine("⚠️ Company and work overlap: a day with six meetings is both. Nothing here separates the people from the work on a working day, so read the busy-versus-quiet finding as being about your days, not about human beings. The line that *is* about people rather than about work is the one above about contact you chose — personal and casual contact only."))
        drivers.append(.routine(String(format: "The calendar side is scored against your own range and nothing else — a typical day of yours carries %.1f h of company. There is no published norm for how much company is too much, so there is nothing here pretending to be one. ⚠️ The cost of that honesty: if every one of your days is full of people, there is nothing for a full day to stand out against, and this side of the card will read light. It answers \"busy for you\", never \"busy\".",
                                       out.typicalDayHours)))
        drivers.append(.routine("An hour is not an hour here: a formal meeting in a room counts for more than the same hour on a video call, an all-day banner counts for nothing, and a reminder counts for nothing. Those weightings are the app's stated assumption, not a measurement — correct any event on the list below and this recomputes."))
        drivers.append(.routine("⚠️ Every range on this card is worked out as if resting heart rate, variability and sleep move independently, and they do not — so the true range is wider than the one printed. Where a verdict here is close, treat it as closer."))
        if out.peopleCoverage < 1 {
            drivers.append(.routine(String(format: "Only %.0f%% of your days with meetings say how many people were in them, so every headcount here is a floor rather than a total. Your app never stores who — only how many.",
                                           out.peopleCoverage * 100)))
        }

        return drivers.filter { $0.isNotable == true }
            + drivers.filter { $0.isNotable != true }
    }

    private func stratificationLine(_ out: SocialBatteryModel.Output) -> String {
        let used = out.strata.map(\.title).joined(separator: " and ")
        let base = "Busy days are compared with quiet days inside weekdays and weekends separately, and the two comparisons are then pooled. A single busy-versus-quiet split would mostly be measuring the weekend — more sleep, later mornings, different drinking — and would report that company wrecks your recovery when what it found is that Saturday exists. Splitting inside each block instead is what lets your personal life stay in this card at all, which is the whole difference between this and the work card."
        guard !out.droppedStrata.isEmpty else {
            return base + " Compared here: \(used.isEmpty ? "nothing yet" : used.lowercased())."
        }
        let dropped = out.droppedStrata.map(\.title).joined(separator: " and ")
        return base + " \(dropped) had too few days — or too little variation — to split, so they are left out entirely rather than folded in, which would reintroduce exactly the confound above. Compared here: \(used.isEmpty ? "nothing yet" : used.lowercased())."
    }
}
