import Foundation

/// "Improve Your Health" — the one greenfield item on the feedback list.
///
/// The hard part is not generating suggestions, it is refusing to generate the
/// wrong ones. This app is not a medical device and does not give medical
/// advice, so a suggestion here is only ever one of three factual things:
///
/// 1. **Something the user's own data already shows.** `VO2Trajectory` set the
///    precedent — "in weeks where your active energy was above X, your cardio
///    fitness averaged Y against Z in your lighter weeks. That's your own
///    history, not a rule." This generalises that, and it is the strongest kind
///    because the evidence is the person in front of you.
/// 2. **A fact the app is missing.** "Log a cuff reading and Blood Pressure
///    starts scoring" is a statement about the software, not about the body.
/// 3. **A signal sitting away from its own baseline**, named without being
///    explained. Saying resting heart rate has been running high is reporting;
///    saying why, or what to do about it, would not be.
///
/// General population evidence — "adults should get 150 minutes of exercise a
/// week" — is deliberately absent. It is true, it is not about this person, and
/// the moment the app starts dispensing it the framing stops being descriptive.
public struct Suggestion: Sendable, Equatable, Identifiable {

    /// What the suggestion rests on. Also the primary sort key: an observation
    /// about this person outranks a gap in the app's inputs, which outranks a
    /// signal merely being off.
    public enum Basis: String, Sendable, Comparable {
        /// Several independent signals leaning the same way at once.
        ///
        /// Ranked above everything else because it is the best-founded thing
        /// this app can say. One signal off baseline is an ordinary Tuesday and
        /// sits at the bottom of this list for exactly that reason; four of them
        /// agreeing is a different claim resting on independent evidence, and it
        /// is also the only one that is *time-critical* — a lever drawn from
        /// three months of history will still be true next week.
        case convergingSignals
        /// Drawn from a contrast in the user's own history.
        case yourOwnData
        /// A missing or stale grounding fact that would make an insight work.
        case unlockAnInsight
        /// A measured signal away from its own baseline.
        case signalOffBaseline

        private var rank: Int {
            switch self {
            case .convergingSignals: return 0
            case .yourOwnData: return 1
            case .unlockAnInsight: return 2
            case .signalOffBaseline: return 3
            }
        }
        public static func < (a: Basis, b: Basis) -> Bool { a.rank < b.rank }
    }

    public let id: String
    /// The short line. Never an instruction — a description of what was found.
    public let title: String
    /// The evidence, in the user's own numbers wherever there are any.
    public let detail: String
    public let basis: Basis
    /// Which card this came from, so the row can navigate there.
    public let insight: InsightID?
    public let metric: MetricType?
    /// 0–1, the sort key *within* a basis. How strongly the evidence supports it
    /// — not how important the app thinks it is.
    public let strength: Double

    public init(id: String, title: String, detail: String, basis: Basis,
                insight: InsightID? = nil, metric: MetricType? = nil,
                strength: Double) {
        self.id = id
        self.title = title
        self.detail = detail
        self.basis = basis
        self.insight = insight
        self.metric = metric
        self.strength = strength
    }
}

public enum SuggestionEngine {

    /// How many to show. Past a handful this stops being a list of findings and
    /// starts being a to-do list, which is a different and less honest thing.
    public static let defaultLimit = 5

    /// Everything worth surfacing, strongest evidence first.
    public static func suggestions(results: [InsightResult],
                                   samples: [HealthMetricSample],
                                   profile: UserHealthProfile,
                                   substanceEvents: [SubstanceEvent] = [],
                                   /// Which inputs the reader has ever used.
                                   /// Anything `promptsWhenNeverUsed` and absent
                                   /// from this earns a dismissible row.
                                   usedInputs: Set<InputKind> = Set(InputKind.allCases),
                                   /// When the reader last measured themselves.
                                   /// Nil means never, which this list leaves to
                                   /// `unusedInputs` — see `bodyScanDue`.
                                   lastBodyScan: Date? = nil,
                                   /// How many flagged events are waiting for an
                                   /// answer — backlog P32. Named for the
                                   /// quantity rather than for the row it feeds,
                                   /// which also keeps it from shadowing
                                   /// `eventsAwaitingReview(count:)` below.
                                   pendingEventCount: Int = 0,
                                   /// What the app is allowed to observe about
                                   /// place. **The reader's own condition on
                                   /// building the location feature at all** —
                                   /// see `locationPermission` below. Defaults
                                   /// to `.always` so no existing caller starts
                                   /// emitting a permission row it never asked
                                   /// for.
                                   locationAccess: LocationAccess = .always,
                                   now: Date = Date(),
                                   calendar: Calendar = .current,
                                   limit: Int = defaultLimit) -> [Suggestion] {
        let watch = HealthWatchModel.evaluate(samples: samples, now: now, calendar: calendar)

        var out: [Suggestion] = []
        out += convergence(watch)
        out += personalLevers(samples: samples, profile: profile, now: now, calendar: calendar)
        out += overnightCharge(samples: samples, now: now, calendar: calendar)
        out += substanceResponse(events: substanceEvents, samples: samples, now: now)
        out += unlocks(results: results, profile: profile, now: now)
        out += unusedInputs(used: usedInputs)
        out += eventsAwaitingReview(count: pendingEventCount)
        out += locationPermission(access: locationAccess)
        out += bodyScanDue(lastScan: lastBodyScan, now: now, calendar: calendar)
        // A signal named in the convergence row must not appear again three
        // rows further down as a lone departure. The same reading twice, once
        // as part of a pattern and once as an isolated fact, reads as two
        // findings and is one.
        out += departures(samples: samples, now: now, calendar: calendar,
                          excluding: Set(convergenceCovers(watch)))

        return out
            .sorted { a, b in
                a.basis == b.basis ? a.strength > b.strength : a.basis < b.basis
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 0. Several signals leaning together

    /// Health Watch's finding, promoted to the top of this list.
    ///
    /// `SuggestionEngine` predates the card, so the strongest observation the
    /// app makes was the one thing this list could not say. It is not restated
    /// from the card's prose — the card's phrasing is written for a card — but
    /// recomputed from the same model, which is the only way the two can be
    /// guaranteed to agree about how many signals are leaning.
    ///
    /// Two is the floor, and that is the whole point: one signal off baseline is
    /// already covered by `departures` below, at the *bottom* of the ranking,
    /// and promoting a single reading to the top would destroy the distinction
    /// the card exists to draw.
    static func convergence(_ watch: HealthWatchModel.Output?) -> [Suggestion] {
        guard let watch else { return [] }
        let leaning = watch.leaning.sorted { abs($0.zScore) > abs($1.zScore) }
        guard leaning.count >= 2 else { return [] }

        let named = list(leaning.map { $0.metric.inSentence })
        return [Suggestion(
            id: "converging-\(leaning.count)",
            title: "\(leaning.count) signals are leaning the same way",
            detail: "\(named.capitalizedFirst) have all moved in the direction an immune response pushes them, over the last \(HealthWatchModel.recentDays) days against a fortnight that ended before they started. Individually each is inside the noise; together they are a pattern. An observation about your own numbers, not a diagnosis — if you feel unwell, that is the better information.",
            basis: .convergingSignals,
            insight: .readiness,
            metric: leaning.first?.metric,
            // The card's own score, read as concern. It already accumulates
            // votes rather than taking the worst, so it is the right scale here.
            strength: Swift.min(1, Swift.max(0, (100 - watch.score) / 100)))]
    }

    /// Which metrics the convergence row already speaks for. Empty whenever no
    /// convergence row is emitted, so nothing is suppressed on its behalf.
    static func convergenceCovers(_ watch: HealthWatchModel.Output?) -> [MetricType] {
        guard let watch, watch.leaning.count >= 2 else { return [] }
        return watch.leaning.map(\.metric)
    }

    /// "a, b and c" — hand-rolled rather than `ListFormatter`, which is not in
    /// Foundation on Linux and would take this package off the platforms its
    /// tests run on.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    // MARK: - 1. The user's own history

    /// The busier-versus-lighter-weeks contrast `VO2Trajectory` already computes.
    ///
    /// Re-derived here rather than plumbed through `InsightResult`, because the
    /// contrast is a structured finding and `drivers` are strings — parsing a
    /// sentence back into numbers would be the wrong direction of travel.
    static func personalLevers(samples: [HealthMetricSample], profile: UserHealthProfile,
                               now: Date, calendar: Calendar) -> [Suggestion] {
        guard let age = profile.age(asOf: now), let sex = profile.sex,
              let trajectory = VO2Trajectory.evaluate(samples: samples, age: age, sex: sex,
                                                      now: now, calendar: calendar),
              let volume = trajectory.volume, volume.difference > 0 else { return [] }

        // The size of the contrast, against a full point of VO₂max as the scale
        // at which a difference is worth mentioning at all.
        let strength = Swift.min(1, volume.difference / 2)
        return [Suggestion(
            id: "volume-\(volume.metric.rawValue)",
            title: "Your busier weeks track higher cardio fitness",
            detail: String(format: "In weeks where your %@ was above %.0f %@, your cardio fitness averaged %.1f — against %.1f in your lighter weeks, across %d weeks of your own history. An association in your data, not a rule.",
                           volume.metric.inSentence, volume.medianWeekly,
                           volume.metric.unit, volume.vo2WhenBusier,
                           volume.vo2WhenLighter, volume.weeksCompared),
            basis: .yourOwnData,
            insight: .fitness,
            metric: volume.metric,
            strength: strength)]
    }

    /// Energy's own contrast: how this week's mornings compare with the user's
    /// best week of the last quarter.
    ///
    /// Deliberately the *morning charge* rather than sleep hours. Charge is
    /// sleep length and overnight autonomic recovery together, so it separates
    /// "seven hours that worked" from "seven hours that didn't" — a distinction
    /// a duration series cannot express, and the reason this is Energy's
    /// suggestion rather than Sleep Debt's.
    ///
    /// Against the user's own best week, not against 100: the ceiling of the
    /// model is not a target anybody should be measured against, and their own
    /// good week demonstrably is reachable — they reached it.
    static func overnightCharge(samples: [HealthMetricSample], now: Date,
                                calendar: Calendar) -> [Suggestion] {
        let series = EnergyModel.morningChargeSeries(samples: samples, days: 90,
                                                     now: now, calendar: calendar)
        guard let contrast = EnergyModel.weekContrast(series, now: now),
              contrast.shortfall >= minimumChargeShortfall else { return [] }

        return [Suggestion(
            id: "morning-charge",
            title: "Your mornings have been starting lower than usual",
            detail: String(format: "Energy has charged to %.0f overnight on average this week, against %.0f in your best week of the last three months — %d nights each. Charge is sleep length and overnight recovery together, which is why two seven-hour nights can start you in different places. Your own range, not a target.",
                           contrast.recent, contrast.best,
                           Swift.min(contrast.recentNights, contrast.bestNights)),
            basis: .yourOwnData,
            insight: .energy,
            metric: .sleepDurationHours,
            // A full standard deviation of overnight recovery is eight points;
            // three of those is as large as this contrast realistically gets.
            strength: Swift.min(1, contrast.shortfall / (3 * EnergyModel.recoveryPointsPerSD)))]
    }

    /// How far below their own best week a person has to be starting before it
    /// is worth saying. One standard deviation of overnight recovery — below
    /// that this is reporting the week-to-week wobble of the model itself.
    static let minimumChargeShortfall = EnergyModel.recoveryPointsPerSD

    /// The strongest thing the substance log has to say about this person.
    ///
    /// The log was a data source for exactly one card and one chart shading.
    /// Everything else in the app — the pattern finder, the deep dive, this —
    /// was blind to it, which is a strange property for the only input the user
    /// enters by hand.
    ///
    /// It qualifies as `.yourOwnData` for the same reason the volume contrast
    /// does: it is a comparison between two sets of this person's own nights,
    /// with the counts stated. It is emphatically not advice — the sentence
    /// reports what the nights after a log looked like against the nights after
    /// nothing, and stops there.
    static func substanceResponse(events: [SubstanceEvent],
                                  samples: [HealthMetricSample],
                                  now: Date) -> [Suggestion] {
        guard !events.isEmpty else { return [] }
        let analysis = SubstanceResponseAnalyzer.analyze(events: events, samples: samples,
                                                         now: now)
        // The clearest adverse effect, by how large it is against the clean
        // nights' own spread — the same standard the rest of this file uses, and
        // the reason a 2 bpm shift in a steady signal can outrank a 5 bpm shift
        // in a noisy one.
        guard let effect = analysis.effects
            .filter({ $0.isAdverse })
            .compactMap({ effect -> (SubstanceResponseAnalyzer.MetricEffect, Double)? in
                effect.effectSize.map { (effect, $0) }
            })
            .filter({ $0.1 >= minimumSubstanceEffectSize
                        && abs($0.0.deltaPercent) >= minimumSubstanceChangePercent })
            .max(by: { $0.1 < $1.1 })?.0 else { return [] }

        let direction = effect.deltaAbsolute > 0 ? "higher" : "lower"
        return [Suggestion(
            id: "substance-\(effect.metric.rawValue)",
            title: "\(effect.metric.displayName) reads differently after you log something",
            detail: String(format: "In the %d nights following a log, your %@ averaged %@ — %@ than the %@ across %d nights with nothing logged. Your own two sets of nights, not a claim about cause.",
                           effect.affectedNights, effect.metric.inSentence,
                           MetricValueFormatter.detailedString(effect.afterUse, effect.metric),
                           direction,
                           MetricValueFormatter.detailedString(effect.baseline, effect.metric),
                           effect.baselineNights),
            basis: .yourOwnData,
            insight: .substanceImpact,
            metric: effect.metric,
            // A full standard deviation of the clean nights is a strong finding;
            // two is as strong as this evidence gets.
            strength: Swift.min(1, (effect.effectSize ?? 0) / 2))]
    }

    /// How far apart the two sets of nights must be before this is worth saying,
    /// in clean-night standard deviations. Below half an SD the two
    /// distributions are the same distribution.
    static let minimumSubstanceEffectSize = 0.5

    /// And how far apart in the metric's own units, as a share of the baseline.
    ///
    /// A standardised threshold alone is not enough, and the failure is easy to
    /// miss: someone whose clean nights sit in a very tight band gets a tiny
    /// divisor, so a fifth of a beat per minute clears half a standard deviation
    /// and the app announces a finding about a difference no sensor can resolve.
    ///
    /// Three percent — a couple of bpm on a resting heart rate — is roughly
    /// where consumer optical measurement stops being able to tell two numbers
    /// apart. The same shape as the ±5 mmHg floor on blood-pressure drift and
    /// the two-point floor on a score change: a relative test needs an absolute
    /// companion, because a small enough denominator makes anything significant.
    static let minimumSubstanceChangePercent = 3.0

    // MARK: - 2. Facts the app is missing

    /// A grounding gap is a statement about the software, which is why it can be
    /// phrased as something to do without becoming advice.
    ///
    /// Ranked by how many cards the fact unblocks, so one blood-pressure reading
    /// — which feeds Blood Pressure, Heart Age and Cardiovascular Risk — leads
    /// over an ethnicity field that refines one.
    ///
    /// **Missing and stale are worded differently**, and that distinction
    /// arrived here from the Today banner this replaced: `unmetRequirements` is
    /// "not satisfied", which is *either* never entered or entered and gone out
    /// of date. Telling someone to "add your cholesterol" when they added it
    /// last year reads as the app having lost it.
    static func unlocks(results: [InsightResult],
                        profile: UserHealthProfile,
                        now: Date) -> [Suggestion] {
        var blockedBy: [GroundingKind: (mandatory: Bool, insights: [InsightID])] = [:]
        for result in results {
            for requirement in result.unmetRequirements {
                var entry = blockedBy[requirement.kind] ?? (false, [])
                entry.mandatory = entry.mandatory || requirement.isMandatory
                entry.insights.append(result.id)
                blockedBy[requirement.kind] = entry
            }
        }
        // Which cards have no number at all — the ones a missing fact is actually
        // costing something.
        let unscored = Set(results.filter { $0.score == nil }.map(\.id))

        return blockedBy.map { kind, entry in
            let blocked = entry.insights
            let names = blocked.count == 1
                ? "one insight" : "\(blocked.count) insights"
            let costsAScore = blocked.contains { unscored.contains($0) }
            // Mandatory-and-blocking a scoreless card is the strongest case;
            // an optional refinement is the weakest.
            let strength = (entry.mandatory ? 0.6 : 0.2)
                + (costsAScore ? 0.3 : 0)
                + Swift.min(0.1, Double(blocked.count) * 0.03)
            // Unmet with a value on file means the value went out of date —
            // the same test `requirementStatuses` uses to call it `.stale`.
            let isStale = profile.input(kind).map { !$0.isFresh(asOf: now) } ?? false
            let noun = kind.displayName.lowercased()
            return Suggestion(
                // One id per kind, whichever it is. A dismissal survives the
                // fact going missing → satisfied → stale only if the suggestion
                // keeps being made across that, and it does not: `unlocks`
                // emits nothing while it is satisfied, which is exactly when
                // `pruneResolvedSuggestions` clears the dismissal.
                id: "grounding-\(kind.rawValue)",
                title: isStale ? "Update your \(noun)" : "Add your \(noun)",
                detail: detail(names: names, costsAScore: costsAScore, isStale: isStale),
                basis: .unlockAnInsight,
                insight: blocked.first,
                metric: nil,
                strength: Swift.min(1, strength))
        }
    }

    /// **An input the reader has never used, once, dismissibly.**
    ///
    /// The fourth clause of the user's rule: *"if it's missing, or hasn't been
    /// added for the first time, it goes into the improve your health
    /// recommendation that can be dismissed"* — and the fifth follows from it
    /// for free, because Today already renders the top suggestion with a
    /// dismiss control and Insights renders the whole list.
    ///
    /// Only `promptsWhenNeverUsed` kinds, which is deliberately the short list.
    /// The profile facts and the cuff reading are prompted *per fact* by
    /// `unlocks` above, which knows which card each is blocking; a second,
    /// vaguer row would be the same nudge carrying less. And nobody is asked to
    /// record a side effect they have not had.
    ///
    /// **Weakest of the unlock rows on purpose.** A grounding fact that is
    /// costing a card its score is a stronger claim than "here is a feature you
    /// have not tried", and the ranking has to keep saying so.
    static func unusedInputs(used: Set<InputKind>) -> [Suggestion] {
        InputKind.allCases
            .filter { $0.promptsWhenNeverUsed && !used.contains($0) }
            .map { kind in
                Suggestion(
                    // Stable per kind, so a dismissal survives — and
                    // `pruneResolvedSuggestions` clears it the moment the input
                    // is used, because this stops emitting then.
                    id: "input-\(kind.rawValue)",
                    title: "Try \(kind.title.lowercased())",
                    detail: kind.detail,
                    basis: .unlockAnInsight,
                    insight: nil, metric: nil,
                    strength: 0.15)
            }
    }

    /// **Questions the app has asked and nobody has answered** — backlog P32.
    ///
    /// A row about the reader's own data rather than about a feature they have
    /// not tried, which is why it does not go through `unusedInputs`: it carries
    /// a count and names something that actually happened. `.unlockAnInsight`
    /// rather than `.yourOwnData` all the same — the finding is that the app has
    /// a gap in what it knows, not that it has learnt something about the
    /// reader. That ordering keeps it below every convergence and every
    /// personal-history contrast, which is right: an unanswered question is
    /// never more urgent than four signals leaning the same way.
    ///
    /// **One row for the whole queue**, deliberately. A row per pending event
    /// would push everything else off Today the first busy week, and this list
    /// is capped at five.
    static func eventsAwaitingReview(count: Int) -> [Suggestion] {
        guard count > 0 else { return [] }
        let events = count == 1 ? "1 flagged moment" : "\(count) flagged moments"
        return [Suggestion(
            // Stable across counts, so waving it away once does not have to be
            // done again the moment a second event arrives — the dismissal is
            // about the prompt, not about a particular tally.
            id: "flagged-events-awaiting",
            title: "\(events) waiting for you",
            detail: "Your heart rate ran high with nothing moving to explain it. The app has a guess and it is often wrong — telling it what was actually going on is the only way it gets better, and it keeps its guess and your answer apart so it can show you how often it's right.",
            basis: .unlockAnInsight,
            insight: nil, metric: nil,
            // Above `unusedInputs` (0.15) because something measurable actually
            // happened, and below every grounding gap for the reason those
            // outrank everything here: a card that cannot produce a number is a
            // stronger claim than a question going unanswered. More waiting
            // nudges it up, saturating at ten so a long absence cannot dominate.
            strength: Swift.min(0.45, 0.20 + 0.025 * Double(count)))]
    }

    /// **The dismissible row the reader made a condition of building any of
    /// this** — backlog Q6.
    ///
    /// Their ruling was *"just build the whole thing"* with two conditions
    /// attached: an onboarding step that explains why **before** the system
    /// prompt, and *"a dismissible front-page suggestion when the permission is
    /// absent"*. This is the second. The first is `OnboardingView`'s location
    /// step, and neither is optional — the prompt without the explanation is not
    /// what was approved.
    ///
    /// ⚠️ **Silent unless asking could change something.** `.denied` emits
    /// nothing: iOS will not show the prompt again, so a row the reader cannot
    /// act on is a nag, and this app's whole ranking exists to avoid being one.
    /// The feed still says what it is missing (`LocationAccess.sentence`) — that
    /// is transparency on a screen they opened, which is a different thing from
    /// a prompt on a screen they did not.
    ///
    /// ⚠️ **It never says the feature needs location.** It does not: events are
    /// flagged from vitals alone and the whole feed works without it. Claiming
    /// otherwise to win a permission is how apps get their permissions, and it
    /// is not how this one will.
    static func locationPermission(access: LocationAccess) -> [Suggestion] {
        guard access.isWorthAsking else { return [] }
        return [Suggestion(
            id: "location-for-flagged-events",
            title: "Add a place to your flagged moments",
            detail: "When the app flags a stretch it can't explain, knowing roughly where you were often jogs the memory. It uses the coarsest thing iOS offers — arrivals at places you stop, rounded to a few hundred metres — keeps a rough position only until you answer, and never builds a location history. Everything works without it; you just won't get the map.",
            basis: .unlockAnInsight,
            insight: nil, metric: nil,
            // The weakest row in the list, below even "a feature you haven't
            // tried". It asks for a permission rather than reporting a finding,
            // and this app does not let a permission ask outrank anything about
            // the reader's own data.
            strength: 0.10)]
    }

    /// **The body-scan interval, finally said out loud.**
    ///
    /// `BodyScanCadence` has been built and tested since the scan engine landed
    /// and nothing called it, so the app knew when the next measurement was due
    /// and had no way to mention it. This is that way. The wording is the
    /// cadence type's own — a reminder and a Settings row disagreeing about how
    /// overdue something is would be two answers to one question.
    ///
    /// **Never scanned is deliberately not this clause's business.** That is
    /// what `unusedInputs` covers: `.bodyMeasurements` prompts while it has
    /// never been used, and two rows about the same missing measurement is the
    /// duplication the ranking exists to avoid. So this needs a last scan to
    /// have an opinion at all, and `.current` says nothing — a reminder that
    /// appears every day stops being one.
    ///
    /// **The id carries the state, which is the opposite of `unlocks`'s rule**,
    /// and for a reason those two do not share: a dismissal lasts thirty days
    /// and the interval *is* thirty days, so one stable id would let a
    /// dismissal at day 25 swallow the whole of the next cycle. Overdue is also
    /// a stronger claim than due-soon rather than a restatement of it, and
    /// earns the right to be made once.
    static func bodyScanDue(lastScan: Date?, now: Date, calendar: Calendar) -> [Suggestion] {
        guard let lastScan,
              let prompt = BodyScanCadence.prompt(lastScan: lastScan, now: now,
                                                  calendar: calendar) else { return [] }
        let state = BodyScanCadence.state(lastScan: lastScan, now: now, calendar: calendar)
        let overdueBy = -(BodyScanCadence.daysUntilDue(lastScan: lastScan, now: now,
                                                       calendar: calendar) ?? 0)
        // Below every grounding gap that costs a card its score, and above "a
        // feature you have not tried". Overdue climbs with the size of the hole
        // it is reporting and stops climbing at one whole interval late, past
        // which more days do not make it a different finding.
        let strength = state == .overdue
            ? 0.3 + 0.3 * Swift.min(1, Double(overdueBy) / Double(BodyScanCadence.intervalDays))
            : 0.18
        return [Suggestion(id: "body-scan-\(state.rawValue)",
                           title: prompt.title,
                           detail: prompt.detail,
                           basis: .unlockAnInsight,
                           insight: .bodyComposition,
                           metric: nil,
                           strength: strength)]
    }

    /// Four sentences over two independent questions — is it costing a score,
    /// and is the value absent or merely old. Written out rather than assembled
    /// from clauses, because "One insight can't produce a score without it. Your
    /// last one is out of date." is two sentences fighting over which is the
    /// point.
    static func detail(names: String, costsAScore: Bool, isStale: Bool) -> String {
        switch (isStale, costsAScore) {
        case (false, true):
            return "\(names.capitalizedFirst) can't produce a score without it."
        case (false, false):
            return "\(names.capitalizedFirst) would get more accurate with it."
        case (true, true):
            return "Your last one is too old to rely on, and \(names) can't "
                + "produce a score without a current reading."
        case (true, false):
            return "Your last one is out of date — \(names) would get more "
                + "accurate with a fresh reading."
        }
    }

    // MARK: - 3. Signals away from their own baseline

    /// Named, not explained. This reports that a signal has moved; it does not
    /// say why, and it does not say what to do — both of which would be claims
    /// this app has no standing to make.
    static func departures(samples: [HealthMetricSample], now: Date,
                           calendar: Calendar,
                           excluding covered: Set<MetricType> = []) -> [Suggestion] {
        let scan = VitalSignsCheck.evaluate(samples: samples, now: now, calendar: calendar)
        return scan.unusual.compactMap { reading in
            guard !covered.contains(reading.metric) else { return nil }
            guard let z = reading.zScore, abs(z) >= VitalSignsCheck.unusualZ else { return nil }
            let direction = z > 0 ? "above" : "below"
            return Suggestion(
                id: "departure-\(reading.metric.rawValue)",
                title: "\(reading.metric.displayName) is \(direction) your usual range",
                detail: String(format: "%@ against a baseline of %@, measured %@. Worth keeping an eye on — this is your own pattern, not a diagnosis.",
                               MetricValueFormatter.detailedString(reading.value, reading.metric),
                               reading.baseline.map {
                                   MetricValueFormatter.detailedString($0, reading.metric)
                               } ?? "your recent average",
                               reading.sourceName),
                basis: .signalOffBaseline,
                insight: .readiness,
                metric: reading.metric,
                // Two SDs is the floor for appearing here at all; four is as
                // strong as this evidence gets.
                strength: Swift.min(1, abs(z) / 4))
        }
    }
}
