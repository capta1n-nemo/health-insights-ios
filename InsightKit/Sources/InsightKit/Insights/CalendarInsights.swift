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
///
/// ## ⚠️ The card scores two things now, not one (backlog D41, 2026-08-06)
///
/// Earlier the same day this card's number was purely *response*: a curve over
/// how much resting heart rate, HRV and sleep differed between busy and quiet
/// working days. The calendar quantities that decide which day lands in which
/// half were declared at weight 0, each row saying it defined the comparison
/// rather than dividing the number. That was an accurate description of the
/// arithmetic — and the reader overruled the arithmetic:
///
/// > *"I want all inputs to carry at least some weight, thats the entire point.
/// > If i have had 10 meetings in a day, how would that not leave me impacted
/// > and drained?"*
///
/// The card is called **work impact** — impact *on you* — so it now scores
/// **exposure** (how much work there actually was) beside **response** (how
/// much the body differed), and both carry real shares. See
/// `WorkImpactModel.Quadrant` for how the four combinations are kept
/// distinguishable, which is the part that is easy to get wrong.
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

    /// **What the four combinations of load and response actually mean.**
    ///
    /// ⚠️ **This is the trap in scoring exposure at all, and it is worth
    /// stating before the arithmetic.** Once the calendar carries a share, the
    /// obvious blend — heavy calendar drags the number down, tired body drags
    /// it down — gets two of the four quadrants badly wrong:
    ///
    /// - **A heavy fortnight your body did not notice is not the same thing as
    ///   a quiet one.** It is *you handling it*, which is genuinely good news,
    ///   and a card that scored it identically to a fortnight with nothing in
    ///   the diary would be unable to say the one encouraging thing it knows.
    /// - **A large bodily difference across a calendar with almost no contrast
    ///   is not work impact.** The two halves of the split barely differ, so
    ///   whatever moved resting heart rate moved it for some other reason, and
    ///   naming work is a confident wrong answer.
    ///
    /// So the blend is not symmetric. Exposure carries a fixed, bounded share;
    /// the **response's** share rises with the contrast (`gapRatio`), because the
    /// contrast is exactly how much authority the body comparison has to speak
    /// about *work*. The quadrant is then stated out loud, in the headline and
    /// in a driver line, rather than left for the reader to infer from a dial.
    public enum Quadrant: String, Sendable, Equatable, CaseIterable {
        /// Heavy load, and the body shows it. The card's worst reading.
        case carrying
        /// Heavy load, and the body is steady. Good news, and it is said.
        case absorbing
        /// Light load, and the body differs anyway — so it is not the calendar.
        case unexplained
        /// Light load, steady body. A quiet stretch.
        case quiet
    }

    /// One working day, as this card reads it.
    ///
    /// The meeting count rides along with the hours because the reader's own
    /// framing of the question is a count — *"if i have had 10 meetings in a
    /// day"* — and an hour of load is not something anybody can picture.
    public struct DayLoad: Sendable, Equatable {
        /// Weighted load hours: an in-person formal meeting costs more than the
        /// same hour of blocked focus time. The app's stated assumption.
        public let hours: Double
        /// Actual meetings, unweighted. For the copy, never for the score.
        public let meetings: Int
    }

    public struct Output: Sendable, Equatable {
        public let channels: [Channel]
        public let heavyDays: Int
        public let lightDays: Int
        /// Median load on the heavy half, in hours.
        public let heavyMedianHours: Double
        public let lightMedianHours: Double
        /// **The unit everything on the calendar side is measured in**: the
        /// reader's own typical working day. It is the median the split is made
        /// at, so it is already what "busy *for them*" means on this card.
        ///
        /// ⚠️ **Not an SD, and the first version of this used one.** A robust
        /// scale is the app's usual yardstick and it is the wrong one here: over
        /// a load distribution with evenly spaced levels the MAD is itself
        /// proportional to the gap, so the ratio came out at the same number for
        /// a calendar of 1/3/6-hour days and one of 3/3.5/4-hour days — a
        /// statistic that could not tell those apart is not measuring exposure.
        /// It can also be exactly zero, which the SD fallback papered over.
        public let typicalDayHours: Double
        /// The heaviest single working day in the window, and what was on it.
        public let peakHours: Double
        public let peakMeetings: Int
        /// Median meetings on a day in the heavy half.
        public let busyMedianMeetings: Double
        public let score: Double
        /// Weighted mean departure, in SDs of the reader's own spread.
        public let pooled: Double
        /// The share the body comparison ended up carrying, after the contrast
        /// scaled it. Stored rather than recomputed so the copy and the
        /// arithmetic cannot disagree.
        public let responseShare: Double
        public let contributions: [MetricContribution]
        /// The calendar's own weighted rows. **Not `producedFigure`s any
        /// more** — every one of them divides the number.
        public let factors: [ScoreFactor]

        /// **The card's independent variable, in one number.**
        ///
        /// How much busier the busy half actually was. A comparison across a
        /// twenty-minute gap and one across five hours produce the same kind of
        /// answer and are not the same evidence, and until 2026-08-06 nothing on
        /// this card said which it had — and until D41 landed, nothing scored it
        /// either.
        public var loadGapHours: Double { heavyMedianHours - lightMedianHours }

        /// The gap as a multiple of a typical working day of theirs. **Their own
        /// busy weeks against their own quiet ones, and nobody else's.**
        public var gapRatio: Double {
            typicalDayHours > 0 ? loadGapHours / typicalDayHours : 0
        }

        /// How far above a typical working day the heaviest one stood, as a
        /// multiple of it. 1.0 means the worst day carried twice a normal one.
        public var peakRatio: Double {
            typicalDayHours > 0
                ? Swift.max(0, (peakHours - typicalDayHours) / typicalDayHours) : 0
        }

        /// The two exposure facets as one number, for the quadrant and for the
        /// series. Not itself scored — the facets are scored separately, so
        /// each carries its own row.
        public var exposureLevel: Double {
            gapFacetWeight * gapRatio + peakFacetWeight * peakRatio
        }

        public var quadrant: Quadrant {
            let heavy = exposureLevel >= heavyExposureLevel
            let responded = pooled >= notableResponse
            switch (heavy, responded) {
            case (true, true): return .carrying
            case (true, false): return .absorbing
            case (false, true): return .unexplained
            case (false, false): return .quiet
            }
        }

        /// Working days on both sides of the split.
        public var workingDaysCompared: Int { heavyDays + lightDays }
    }

    /// Load and meeting count per working day, from the classified events.
    ///
    /// Weekends are excluded here rather than filtered later, so nothing
    /// downstream can accidentally reintroduce them.
    public static func workingDayProfile(events: [CalendarEvent],
                                         judgements: [CalendarEventJudgement],
                                         now: Date = Date(),
                                         calendar: Calendar = .current) -> [Date: DayLoad] {
        let byID = Dictionary(uniqueKeysWithValues: judgements.map { ($0.eventID, $0.effective) })
        let cutoff = calendar.date(byAdding: .day, value: -windowDays,
                                   to: calendar.startOfDay(for: now)) ?? now
        var hours: [Date: Double] = [:]
        var meetings: [Date: Int] = [:]
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
            hours[day, default: 0] += classification.loadHours
            if classification.occasion == .meeting { meetings[day, default: 0] += 1 }
        }
        return hours.reduce(into: [:]) { out, entry in
            out[entry.key] = DayLoad(hours: entry.value, meetings: meetings[entry.key] ?? 0)
        }
    }

    /// Load per working day. The half of `workingDayProfile` most callers want.
    public static func workingDayLoad(events: [CalendarEvent],
                                      judgements: [CalendarEventJudgement],
                                      now: Date = Date(),
                                      calendar: Calendar = .current) -> [Date: Double] {
        workingDayProfile(events: events, judgements: judgements,
                          now: now, calendar: calendar).mapValues(\.hours)
    }

    public static func evaluate(events: [CalendarEvent],
                                judgements: [CalendarEventJudgement],
                                samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let profile = workingDayProfile(events: events, judgements: judgements,
                                        now: now, calendar: calendar)
        guard profile.count >= minimumDaysPerHalf * 2 else { return nil }
        let load = profile.mapValues(\.hours)

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

        let heavySorted = heavy.compactMap { load[$0] }.sorted()
        let lightSorted = light.compactMap { load[$0] }.sorted()
        let heavyMedian = heavySorted[heavySorted.count / 2]
        let lightMedian = lightSorted[lightSorted.count / 2]

        // ⚠️ **The scale exposure is measured on, and the one decision in this
        // whole change that could have gone wrong quietly.**
        //
        // There is no published norm for meeting hours — that is the entire
        // point of `docs/norms-and-telemetry.md` — so an external band would be
        // a number somebody here invented, dressed as clinical guidance. The
        // reader's own **typical working day** is real, is theirs, and is
        // already what "busy for them" means in the median split three lines
        // above. Every exposure row's copy says which it is.
        //
        // The median can be zero — a reader whose work calendar is mostly
        // reminders — so the mean stands in, which is positive whenever
        // anything at all carried load, and the heavy half above guarantees
        // that. The guard is here so a future change to the split cannot
        // reintroduce a divide-by-zero silently.
        let typicalDay = median > 0 ? median : (Baseline.mean(sorted) ?? 0)
        guard typicalDay > 0 else { return nil }

        let peak = profile.values.max { $0.hours < $1.hours }
        let peakHours = peak?.hours ?? heavyMedian
        let peakMeetings = peak?.meetings ?? 0
        let busyMeetings = Baseline.median(heavy.compactMap { profile[$0]?.meetings }
            .map(Double.init)) ?? 0

        let gapRatio = (heavyMedian - lightMedian) / typicalDay
        let peakRatio = max(0, (peakHours - typicalDay) / typicalDay)

        // **Exposure and response, as shares of one number.** The response's
        // share rises with the contrast; see `Quadrant` for why the blend is
        // deliberately asymmetric.
        let metricShare = responseShare(gapRatio: gapRatio)
        let metricTerms = channels.map { channel in
            ScoreBlend.Term(
                metric: channel.metric,
                higherIsBetter: !watched.first { $0.metric == channel.metric }!.higherIsWorse,
                score: responseScore(towardWorse: channel.towardWorse),
                weight: 1, detail: sentence(channel))
        }
        let factorTerms = exposureTerms(
            gapRatio: gapRatio, peakRatio: peakRatio,
            heavyMedian: heavyMedian, lightMedian: lightMedian,
            typicalDay: typicalDay, peakHours: peakHours, peakMeetings: peakMeetings)
        guard let blended = ScoreBlend.blend(metrics: metricTerms, factors: factorTerms,
                                             metricShare: metricShare)
        else { return nil }

        return Output(
            channels: channels.sorted { $0.towardWorse > $1.towardWorse },
            heavyDays: heavy.count, lightDays: light.count,
            heavyMedianHours: heavyMedian,
            lightMedianHours: lightMedian,
            typicalDayHours: typicalDay,
            peakHours: peakHours, peakMeetings: peakMeetings,
            busyMedianMeetings: busyMeetings,
            score: blended.score, pooled: pooled,
            responseShare: metricShare,
            contributions: blended.contributions,
            factors: blended.factors)
    }

    // MARK: - The two components, and how much of the number each carries

    /// **How much of the number the body comparison carries at full contrast**,
    /// with the calendar carrying the rest.
    ///
    /// Response leads, because a measured difference in the reader's own body is
    /// stronger evidence about *impact* than a count of hours can ever be. It
    /// does not lead by so much that the calendar is decorative, which is what
    /// the reader overruled.
    public static let responseShareAtFullContrast = 0.65
    /// …and the floor it falls to when the two halves barely differ.
    ///
    /// Not zero. A body difference across a flat calendar is still a real
    /// measurement — it is only the *attribution to work* that collapses, and
    /// the card says which it is rather than dropping the rows.
    public static let responseShareAtNoContrast = 0.30

    /// Within the calendar's share: the gap is a median over a dozen days on
    /// each side and the peak is one day, so the steadier facet leads.
    public static let gapFacetWeight = 0.6
    public static let peakFacetWeight = 0.4

    /// Exposure at or above this — in multiples of the reader's own typical
    /// working day — is a heavy stretch *for them*. Used only to name the
    /// quadrant; the score itself is a curve with no step in it.
    public static let heavyExposureLevel = 0.75
    /// The pooled departure at which the body has said something. The same 0.5
    /// this card already uses to mark a channel notable.
    public static let notableResponse = 0.5

    /// The body comparison's share, as a function of how far apart the two
    /// halves of the split actually are.
    ///
    /// ⚠️ **The gap does two jobs here and that is deliberate.** It is real work
    /// the reader carried — so it is scored, as an exposure row — *and* it is
    /// the width of the comparison the body rows rest on, so it sets how much
    /// those rows are believed. Those are different uses of one measurement,
    /// not the same evidence counted twice: no part of the gap's own score is
    /// added to the response's, and no part of the response's is added to the
    /// gap's.
    public static func responseShare(gapRatio: Double) -> Double {
        ScoreCurve.through([(0, responseShareAtNoContrast), (0.5, 0.48),
                            (1.0, responseShareAtFullContrast)], at: gapRatio)
    }

    /// One exposure facet's 0–100, from its size as a multiple of the reader's
    /// own typical working day.
    ///
    /// ⚠️ **The floor is 30 and not 0.** A calendar on its own is never a health
    /// catastrophe; what can take this card to the floor is the body, and it
    /// reaches it through the response rows. A curve that let a diary alone
    /// score zero would be the substance card's old defect in a new place.
    public static func exposureScore(level: Double) -> Double {
        ScoreCurve.through([(0, 95), (0.5, 80), (1.0, 66), (2.0, 48), (3.5, 30)],
                           at: level)
    }

    /// One body channel's 0–100. Unchanged from the curve this card has always
    /// scored its components with — only its *share* moved.
    public static func responseScore(towardWorse: Double) -> Double {
        ScoreCurve.through([(-1.5, 95), (0, 78), (0.75, 55), (1.5, 35), (3, 18)],
                           at: towardWorse)
    }

    public static func score(pooled: Double) -> Double {
        ScoreCurve.through([(-1.5, 95), (-0.5, 85), (0, 78),
                            (0.75, 55), (1.5, 35), (3, 18)], at: pooled)
    }

    // MARK: - Saying which of the four it is

    /// The headline, from the quadrant rather than from the dial.
    ///
    /// ⚠️ **Four distinguishable sentences, and the test pins that they stay
    /// distinguishable.** Before D41 all four came off `pooled` alone, so a
    /// heavy fortnight the reader absorbed and a fortnight with nothing in the
    /// diary both read *"Busy days look like quiet ones"* — which is true of the
    /// body and useless to somebody who had just worked sixty hours.
    public static func headline(_ out: Output) -> String {
        switch out.quadrant {
        case .carrying:
            return out.pooled >= 1.2 ? "A heavy stretch, and it is costing you"
                                     : "A heavy stretch, and you are feeling it"
        case .absorbing:
            return "A heavy stretch, and you are carrying it well"
        case .unexplained:
            return "Your body is off, and it is not your calendar"
        case .quiet:
            return "A light stretch, and your body agrees"
        }
    }

    /// The quadrant said out loud, as the card's first driver line.
    public static func quadrantLine(_ out: Output) -> String {
        let load = String(format: "%.1f h against %.1f h",
                          out.heavyMedianHours, out.lightMedianHours)
        switch out.quadrant {
        case .carrying:
            return "Your busy working days are heavy for you — \(load) — and your body is showing it on the nights after them. That combination is what this card is for, and it is the one reading here that means something is worth changing."
        case .absorbing:
            return "Your busy working days are heavy for you — \(load) — and your body is not showing it: resting heart rate, variability and sleep look much the same after a heavy day as after a quiet one. That is genuinely good news and it is not the same thing as an empty diary. The load still counts for something here, because the hours were still yours."
        case .unexplained:
            return "Your body differs between these two groups of days, but your calendar barely does — \(load). Whatever is moving resting heart rate, variability or sleep, this card cannot honestly call it work: there is not enough difference between your busy and quiet days for work to be the explanation."
        case .quiet:
            return "A light stretch by your own standards — \(load) — and your body agrees: nothing separates the busier days from the quieter ones."
        }
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

    // MARK: - What the calendar contributes, as shares of the number
    //
    // **The reader's complaint, 2026-08-06, and it was exactly right:** *"The
    // work impact card... 'What's changed' and 'what goes into this' will only
    // still just show Resting Heart Rate, HRV and sleep duration.... how is that
    // possible, the entire point of this card is to take into consideration work
    // impact, where is that on these sections?"*
    //
    // The first answer declared the calendar quantities at **weight 0**, each
    // row saying it defined the comparison rather than dividing the number. That
    // was true of the arithmetic as it then stood, and the reader overruled the
    // arithmetic hours later:
    //
    // > *"I want all inputs to carry at least some weight, thats the entire
    // > point. If i have had 10 meetings in a day, how would that not leave me
    // > impacted and drained?"*
    //
    // ## What replaced the zeros
    //
    // Two exposure rows, both scored, both carrying a share:
    //
    // | Row | What it is | Scored against |
    // | --- | --- | --- |
    // | The gap | how much more work the busy half carried | the reader's own spread |
    // | The heaviest day | the worst single working day | the reader's own typical day |
    //
    // ⚠️ **Neither is scored against a population norm, and the copy on both
    // says so.** No published band for meeting hours exists — that is
    // `docs/norms-and-telemetry.md`'s whole point — so inventing one would be a
    // number from this repo wearing clinical clothes. The reader's own
    // distribution is real, is theirs, and is what "busy *for you*" already
    // means everywhere else on this card, including the median split itself.
    //
    // The three descriptive quantities that used to hold weight-0 rows — the two
    // halves' medians and the day count — keep their **series**, so nothing in
    // the Data tab orphans, and their values now appear inside the weighted
    // rows' own detail and in the drivers. There is no longer any calendar row
    // claiming it merely defines the comparison, because that is no longer true.
    //
    // ## ⚠️ What scoring against your own distribution cannot see, stated once
    //
    // Both facets are ratios to the reader's own spread, so they are **scale
    // invariant**: triple every meeting in the calendar and neither number
    // moves. A genuinely relentless diary — heavy every single day — therefore
    // reads *light* here, because nothing stands out against anything.
    //
    // That is the price of refusing to invent a band, and it is the right price:
    // the alternative is a threshold from this repo presented as guidance. The
    // card says it out loud in a driver line rather than hiding it. The real fix
    // is time, not a constant — `workExposure` is recorded as a series from
    // today, so a later revision can score this fortnight's load against the
    // reader's own trailing year, which is still their own distribution and is
    // *not* scale invariant. Backlog it there rather than reaching for an
    // eight-hour day here.

    static let busyHoursKey = "meetingHoursBusyDays"
    static let quietHoursKey = "meetingHoursQuietDays"
    static let loadGapKey = "meetingHoursGap"
    static let daysComparedKey = "workingDaysCompared"
    static let pooledKey = "bodyDifferencePooled"
    // New with D41. Keys are baked into stored ids — renaming one orphans its
    // history — so they are declared here and treated like a `modelVersion`.
    static let peakHoursKey = "heaviestWorkingDayHours"
    static let peakMeetingsKey = "meetingsOnHeaviestDay"
    static let exposureKey = "workExposure"

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
                  // ⚠️ **Directed now, and it was `nil` before D41.** While the
                  // gap only chose the two groups, "a wider gap is better
                  // evidence" was the only true statement about it and there is
                  // no field for that. It is scored as load now — more extra
                  // work on your busy half costs points — so the series has to
                  // shade the same way the row does.
                  higherIsBetter: false, precision: 1),
            .init(key: daysComparedKey, displayName: "Working days compared",
                  unit: "days", value: Double(out.workingDaysCompared),
                  higherIsBetter: true, precision: 0),
            .init(key: peakHoursKey, displayName: "Your heaviest working day",
                  unit: "h", value: out.peakHours, higherIsBetter: false, precision: 1),
            .init(key: peakMeetingsKey, displayName: "Meetings on your heaviest day",
                  unit: "", value: Double(out.peakMeetings),
                  higherIsBetter: false, precision: 0),
            // The exposure statistic the two rows above are curves of, kept as
            // the raw multiple for the reason `pooled` is kept in SD: a 0–100
            // is a curve and a curve throws away resolution at both ends.
            .init(key: exposureKey, displayName: "How heavy your work was, for you",
                  unit: "× a typical day", value: out.exposureLevel,
                  higherIsBetter: false, precision: 2),
            // The statistic the response half is a rendering of. `ScoreHistory`
            // already trends the score; this is the thing that half is *of*.
            .init(key: pooledKey, displayName: "How much your body differed on busy days",
                  unit: "SD", value: out.pooled, higherIsBetter: false, precision: 2),
        ]
    }

    /// The two exposure rows, as blend terms.
    ///
    /// Separate from `evaluate` only so the copy is readable; it is called from
    /// exactly one place and the weights it states are relative — `ScoreBlend`
    /// renormalises them into the calendar's share.
    static func exposureTerms(gapRatio: Double, peakRatio: Double,
                              heavyMedian: Double, lightMedian: Double,
                              typicalDay: Double, peakHours: Double,
                              peakMeetings: Int) -> [ScoreBlend.FactorTerm] {
        let ownRange = String(format: "Measured against your own typical working day of %.1f h, because no published norm for meeting hours exists to measure it against — this says heavy for you, never heavy.",
                              typicalDay)
        let meetings = peakMeetings > 0
            ? ", across \(peakMeetings) meeting\(peakMeetings == 1 ? "" : "s")"
            : ""
        return [
            .init(id: DerivedSeriesID(.workImpact, loadGapKey),
                  name: "The gap between your busy and quiet working days",
                  score: exposureScore(level: gapRatio), weight: gapFacetWeight,
                  detail: String(format: "%.1f h more work on the busy half — %.1f h against %.1f h, which is %.2f× a typical working day of yours in extra load alone. That work is real time you spent, so it carries a share. %@",
                                 heavyMedian - lightMedian, heavyMedian, lightMedian,
                                 gapRatio, ownRange)),
            .init(id: DerivedSeriesID(.workImpact, peakHoursKey),
                  name: "Your heaviest working day",
                  score: exposureScore(level: peakRatio), weight: peakFacetWeight,
                  detail: String(format: "%.1f h of work load%@ — %.2f× a typical working day of yours, on top of it. One day is thinner evidence than a fortnight of them, which is why this carries the smaller of the two calendar shares. %@",
                                 peakHours, meetings, peakRatio, ownRange)),
        ]
    }

    /// The calendar's weighted rows, for "What goes into this" and "How this is
    /// weighted".
    ///
    /// Computed in `evaluate` alongside the score rather than rebuilt here: the
    /// shares and the number have to come out of one blend, or the section can
    /// state proportions that do not account for the dial above them.
    public static func calendarFactors(_ out: Output) -> [ScoreFactor] { out.factors }
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
    // ⚠️ **These stay at weight 0, and work impact's D41 rewrite deliberately
    // did not come here. Decided 2026-08-06; `travel-drain-v1` is unchanged.**
    //
    // Work impact now scores exposure because "how much work there was" is a
    // *load* — hours the reader actually spent — and more of it is plausibly
    // more drain, which is exactly what the reader said. The equivalent figure
    // here is a **count of time-zone changes**, and it is not the same kind of
    // quantity:
    //
    // 1. **Scoring it would say more trips is worse health**, on this reader's
    //    own body, from a count with no measured response attached. The card
    //    already leads with the opposite caveat — *"N trips is a small
    //    number"* — and a share under that sentence would contradict it.
    // 2. **There is nothing to score it against.** Work impact scores exposure
    //    against the reader's own spread of working-day load, forty-odd
    //    observations deep. Two to four trips is not a distribution, and the
    //    only alternative reference would be a band somebody here invented.
    // 3. **A time-zone change is not even established as a flight** — an entry
    //    set in another zone by hand looks identical — so the count is softer
    //    evidence than the calendar load work impact reads.
    //
    // So these remain the card's independent variable, each row saying so, and
    // the model version does not move because the arithmetic did not. If trip
    // count ever earns a share it needs its own brief and `travel-drain-v2`.
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

        // ⚠️ **The quadrant leads, and it is the whole point of D41.** The dial
        // alone cannot distinguish "you carried a lot and it cost you" from
        // "you carried a lot and took it well" from "something is costing you
        // and it isn't work" — and all three are ordinary months.
        var drivers: [InsightDriver] = [.notable(WorkImpactModel.quadrantLine(out))]
        drivers.append(InsightDriver(
            text: String(format: "Your busier working days carry about %.1f hours of work against %.1f on the quieter ones — %d days against %d, and your heaviest single day ran to %.1f h%@.",
                         out.heavyMedianHours, out.lightMedianHours,
                         out.heavyDays, out.lightDays, out.peakHours,
                         out.peakMeetings > 0 ? " across \(out.peakMeetings) meetings" : ""),
            isNotable: false))
        for channel in out.channels {
            drivers.append(InsightDriver(text: WorkImpactModel.sentence(channel),
                                         isNotable: channel.towardWorse >= WorkImpactModel.notableResponse))
        }
        drivers.append(.routine(String(format: "How the number divides: your calendar carries %d%% of it and your body the other %d%%. That split is not fixed — the further apart your busy and quiet days are, the more your body's side is allowed to say, because a difference measured across two groups of days that barely differ is not evidence about work.",
                                       Int(((1 - out.responseShare) * 100).rounded()),
                                       Int((out.responseShare * 100).rounded()))))
        drivers.append(.routine(String(format: "The calendar side is scored against your own range and nothing else — a typical working day of yours carries %.1f h. There is no published norm for how many hours of meetings is too many, so there is nothing here pretending to be one. ⚠️ The cost of that honesty: if every one of your days is heavy, there is nothing for a heavy day to stand out against, and this side of the card will read light. It answers \"heavy for you\", never \"heavy\".",
                                       out.typicalDayHours)))
        // ⚠️ The caveat that makes the whole comparison legitimate.
        drivers.append(.routine("Only working days are compared, on both sides. A busy-versus-quiet comparison that included weekends would mostly be measuring the weekend — more sleep, later mornings, no meetings — and would report that work wrecks your recovery when what it found is that Saturday exists."))
        drivers.append(.routine("An hour is not an hour here: a formal meeting in a room counts for more than blocked focus time, and a reminder counts for nothing. Those weightings are the app's stated assumption, not a measurement — correct any event on the list and this recomputes."))

        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: WorkImpactModel.headline(out), score: out.score,
            // Thin contrast is thin evidence about work whatever the body did,
            // so it caps the confidence as well as the response's share.
            confidence: out.channels.count >= 3 && out.gapRatio >= 0.5 ? .moderate : .low,
            explanation: "How much work there was, and what your body did about it — two things, both scored. The calendar side is how much heavier your busy working days were than your quiet ones, measured against your own range rather than anybody's norm. The body side is resting heart rate, variability and sleep on the nights after those days, over the last \(WorkImpactModel.windowDays) days. Working days only, on both sides.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: out.contributions,
            weighting: .weightedAverage,
            // The calendar, carrying a share at last — see
            // `WorkImpactModel.exposureTerms`.
            otherFactors: WorkImpactModel.calendarFactors(out),
            derivedOutputs: WorkImpactModel.derivedOutputs(out))
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
