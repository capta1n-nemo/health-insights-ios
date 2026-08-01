import Foundation

/// Sleep: last night, and the pattern behind it.
///
/// One card from three. Sleep Quality scored the *night*, Sleep Debt scored how
/// far *behind* you were, and Sleep Regularity scored *when* you went to bed —
/// three cards all reading `sleepDurationHours` and each answering a third of
/// one question.
///
/// **The maths was kept.** `SleepDebtModel` and `CircadianConsistencyModel` are
/// unchanged and still have their own tests; this card calls them as components,
/// exactly as it already called `VitalReader` and `Baseline`.
///
/// Consistency and regularity are deliberately **both** here and are not the
/// same thing: consistency is the spread of how *long* you sleep, regularity the
/// spread of *when* you start. A shift worker with an iron seven hours has one
/// and not the other.
public struct SleepInsight: InsightModel {
    public let id: InsightID = .sleep
    public let title = "Sleep"
    public init() {}
    public var requirements: [GroundingRequirement] { [] }
    /// `sleepOnset` arrives with the regularity component. The two absolute
    /// temperatures are new: the card already read the *deviation*, but Whoop
    /// and Oura report absolutes too and nothing was reading them — a night's
    /// absolute skin temperature is the same evidence in a different unit, and
    /// on a device that reports only the absolute it was the whole signal.
    public var candidateMetrics: [MetricType] {
        [.sleepDurationHours, .sleepOnset, .sleepEfficiency, .sleepDeepMinutes,
         .sleepRemMinutes, .oxygenSaturation, .respiratoryRate,
         .skinTemperatureDeviation, .skinTemperature, .bodyTemperature]
    }

    /// The share of a night the published figures put deep and REM sleep at,
    /// combined.
    ///
    /// Deep is roughly 13–23% of a night and REM 20–25%, so together they
    /// account for something like a third to a half of it. Scored as a *share*
    /// rather than in minutes, and that is the whole point: a fixed minute
    /// target tells a six-hour sleeper their perfectly normal proportions are
    /// abnormal, when what they have is a duration problem the duration term is
    /// already scoring. Charging them twice for one night would be the
    /// double-counting this app has had to unpick before.
    static let restorativeShareLow = 0.33
    static let restorativeShareHigh = 0.55

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        // One value per night, de-duplicated across devices. Previously this read
        // raw samples, so a nap counted as a night and a second source counted
        // the same night twice — which is what drove the consistency score to
        // zero: the spread it measured was fragmentation, not sleep.
        guard let sleepReading = VitalReader.reading(.sleepDurationHours, from: samples,
                                                     now: now, freshWithin: 36 * 3600) else {
            return notReady(id, title, "Connect a sleep source (Oura, Whoop or Apple Health) to see your sleep quality.")
        }
        let lastNight = sleepReading.value
        let durationScore = Self.durationScore(lastNight)
        // A night older than the freshness window is still worth showing, but it
        // is not "last night" and the card shouldn't imply it is.
        let nightsAgo = Swift.max(0, Int((now.timeIntervalSince(sleepReading.date) / 86_400).rounded(.down)))
        let nightLabel = sleepReading.isFresh ? "Last night"
            : "Last recorded night (\(nightsAgo) days ago)"

        let nightly = VitalReader.dailyValues(.sleepDurationHours, from: samples,
                                              days: 14, now: now)
        // Needs a few nights before night-to-night spread means anything; below
        // that it's a neutral figure rather than a damning one.
        let consistencyScore: Double = nightly.count >= 4
            ? (Baseline.standardDeviation(nightly).map { max(0, 100 - $0 * 40) } ?? 60)
            : 60

        // The night's respiratory rate, not the last ten minutes. Wearables
        // report a nightly figure, but daytime readings land in the same series
        // and `last` was picking whichever arrived most recently — often a
        // waking measurement that says nothing about the night.
        let respReading = VitalReader.reading(.respiratoryRate, from: samples, now: now)
        let respScore: Double = {
            guard let dev = respReading?.zScore else { return 75 }
            return max(0, 90 - min(60, abs(dev) * 20))
        }()

        // Overnight blood oxygen. Saturation dipping through the night is the
        // clearest non-invasive marker of disrupted breathing during sleep, and
        // it was being collected and ignored. Neutral 75 when absent, so nights
        // without a reading aren't penalised.
        let spo2Reading = VitalReader.reading(.oxygenSaturation, from: samples, now: now)
        let oxygenScore: Double = {
            guard let latest = spo2Reading?.value else { return 75 }
            switch latest {
            case 96...: return 100
            case 94..<96: return 82
            case 92..<94: return 60
            default: return 35
            }
        }()

        // Skin temperature away from baseline disturbs sleep and marks the
        // night an illness or a heavy drink starts.
        //
        // **Read from whichever unit the device reports.** Oura and Whoop send a
        // nightly *deviation*; others send only the absolute, and a departure
        // from this person's own baseline is the same evidence either way. Both
        // absolutes have been declared inputs of this card since the merge and
        // neither was read, so on a device reporting only an absolute the
        // temperature term silently took its neutral 75 — and the two metrics
        // charted on no card at all, because the overlay draws contributors.
        let tempSignal: (metric: MetricType, departure: Double, detail: String)? = {
            if let deviation = VitalReader.reading(.skinTemperatureDeviation,
                                                   from: samples, now: now) {
                return (.skinTemperatureDeviation, deviation.value,
                        String(format: "%+.1f °C vs your baseline", deviation.value))
            }
            for metric in [MetricType.skinTemperature, .bodyTemperature] {
                guard let reading = VitalReader.reading(metric, from: samples, now: now),
                      let baseline = reading.baseline else { continue }
                let departure = reading.value - baseline
                return (metric, departure,
                        String(format: "%.1f °C, %+.1f from your normal",
                               reading.value, departure))
            }
            return nil
        }()
        let tempScore: Double = {
            guard let dev = tempSignal?.departure else { return 75 }
            return max(20, 95 - min(70, abs(dev) * 55))
        }()

        // How much of the time in bed was actually spent asleep. Oura, Whoop and
        // Apple all report the pieces and the parser discarded them, so this
        // card scored a night by its length and its breathing while the
        // composition of that night sat unread in the same payload.
        let efficiencyReading = VitalReader.reading(.sleepEfficiency, from: samples,
                                                    now: now, freshWithin: 36 * 3600)
        let efficiencyScore: Double = {
            guard let value = efficiencyReading?.value else { return 75 }
            switch value {
            case 90...: return 100
            case 85..<90: return 88
            case 80..<85: return 68
            case 75..<80: return 50
            default: return 30
            }
        }()

        // Deep and REM as a share of the night, never as a minute target.
        let deepReading = VitalReader.reading(.sleepDeepMinutes, from: samples,
                                              now: now, freshWithin: 36 * 3600)
        let remReading = VitalReader.reading(.sleepRemMinutes, from: samples,
                                             now: now, freshWithin: 36 * 3600)
        let restorativeShare: Double? = {
            guard lastNight > 0, deepReading != nil || remReading != nil else { return nil }
            let minutes = (deepReading?.value ?? 0) + (remReading?.value ?? 0)
            return minutes / (lastNight * 60)
        }()
        let restorativeScore: Double = {
            guard let share = restorativeShare else { return 75 }
            if share >= Self.restorativeShareLow && share <= Self.restorativeShareHigh {
                return 100
            }
            // Distance outside the band, in percentage points of the night. Ten
            // points outside is a materially different night; the band's own
            // width is what sets the scale.
            let outside = share < Self.restorativeShareLow
                ? Self.restorativeShareLow - share : share - Self.restorativeShareHigh
            return Swift.max(30, 100 - outside * 100 * 4)
        }()

        // MARK: The two components this card absorbed

        // How far behind you are, against a need learned from your own nights.
        // Neutral 75 until there are enough nights to say, matching how every
        // other absent component here behaves.
        let debt = SleepDebtModel.evaluate(samples: samples, now: now)
        let debtScore = debt.map { SleepDebtModel.score(debtHours: $0.debtHours) } ?? 75

        // When you go to bed, not how long for. Scores the *spread* and never
        // the hour — chronotype is largely constitutional and shift work is a
        // job, and there is a test sweeping three very different bedtimes to
        // keep it that way.
        // `now:` matters and its absence would be silent. `ScoreHistory.replay`
        // reconstructs a past day by handing the model that day as `now`; a
        // component defaulting to the real present would read a window that the
        // replayed samples do not reach, contribute its neutral 75 to every
        // replayed day, and quietly flatten the history.
        let regularity = CircadianConsistencyModel.evaluate(samples: samples, now: now)
        let regularityScore = regularity.map {
            CircadianConsistencyModel.score(spreadHours: $0.spreadHours)
        } ?? 75

        // Duration keeps the largest share — nothing about a night's
        // composition rescues four hours of it. The two absorbed terms are
        // funded out of duration and the weakest evidence here, rather than by
        // inflating the total: debt is duration measured against a need, and
        // regularity is the one thing on this card that is not about duration at
        // all, which is why it earns more than the breathing terms.
        //
        // These must sum to 1, and every weight repeated in `contributors`
        // below must equal its coefficient here. They drifted apart once
        // already when the stage breakdown was added.
        let score = durationScore * 0.30 + debtScore * 0.12
            + consistencyScore * 0.10 + regularityScore * 0.10
            + efficiencyScore * 0.13 + restorativeScore * 0.10
            + oxygenScore * 0.07 + respScore * 0.05 + tempScore * 0.03
        let band = Self.band(score)
        // Each line classified by the sub-score behind it, so the detail card
        // leads with whatever cost the night its marks.
        var drivers = [
            InsightDriver.component(nightLabel + String(format: ": %.1f h", lastNight),
                                    score: durationScore),
            InsightDriver.component("Consistency: \(Int(consistencyScore))/100",
                                    score: consistencyScore)
        ]
        if let debt {
            drivers.append(.component(
                debt.debtHours < 1
                    ? String(format: "Sleep debt: clear, against a need of %.1f h", debt.needHours)
                    : String(format: "Sleep debt: %.1f h behind a need of %.1f h — about %d night%@ of an extra hour to clear",
                             debt.debtHours, debt.needHours, debt.nightsToClear,
                             debt.nightsToClear == 1 ? "" : "s"),
                score: debtScore))
        }
        if let regularity {
            var line = String(format: "Bedtime: %@, varying by about %.1f h",
                              MetricValueFormatter.string(regularity.typicalOnset, .sleepOnset),
                              regularity.spreadHours)
            if let jetlag = regularity.socialJetlagHours, abs(jetlag) >= 0.5 {
                line += String(format: " (weekends %.1f h %@)", abs(jetlag),
                               jetlag > 0 ? "later" : "earlier")
            }
            drivers.append(.component(line, score: regularityScore))
        }
        if let latest = efficiencyReading?.value {
            drivers.append(.component(String(format: "Efficiency: %.0f%% of your time in bed asleep", latest),
                                      score: efficiencyScore))
        }
        if let share = restorativeShare {
            let deep = deepReading.map { String(format: "%.0f min deep", $0.value) }
            let rem = remReading.map { String(format: "%.0f min REM", $0.value) }
            let parts = [deep, rem].compactMap { $0 }.joined(separator: ", ")
            drivers.append(.component(String(format: "Deep and REM: %.0f%% of the night (%@)",
                                             share * 100, parts),
                                      score: restorativeScore))
        }
        if let latest = respReading?.value {
            drivers.append(.component(String(format: "Respiratory rate: %.0f br/min", latest),
                                      score: respScore))
        }
        if let latest = spo2Reading?.value {
            drivers.append(.component(String(format: "Blood oxygen: %.0f%%%@", latest,
                                             latest < 94 ? " — lower than a settled night usually looks" : ""),
                                      score: oxygenScore))
        }
        if let tempSignal {
            drivers.append(.component("\(tempSignal.metric.displayName): \(tempSignal.detail)",
                                      score: tempScore))
        }

        // Only metrics that actually had a reading become contributions — the
        // neutral 75s above are placeholders for absent data, not measurements,
        // and charting them would draw a line out of nothing.
        //
        // Seven components, six metrics: consistency is the night-to-night
        // spread *of the sleep series itself*, not a separate measurement, so it
        // shares sleep's line rather than inventing one of its own. Its weight is
        // folded into sleep's and the detail names it, so the 15% isn't
        // unaccounted for.
        //
        // Every weight here must equal the coefficient applied above. They are
        // two statements of one number — the score uses the coefficient, the
        // detail chart uses this — and they drifted apart once already when the
        // terms were rebalanced to make room for the stage breakdown.
        // Duration carries its own term, the consistency term (the spread of
        // this same series) and the debt term (this same series against a
        // learned need) — three coefficients, one measurement, so one line.
        var contributors = [MetricContribution(
            metric: .sleepDurationHours, higherIsBetter: true, weight: 0.52,
            detail: String(format: "%.1f h · consistency %d/100%@",
                           lastNight, Int(consistencyScore),
                           debt.map { String(format: " · %.1f h behind", $0.debtHours) } ?? ""))]
        if let regularity {
            contributors.append(.init(
                metric: .sleepOnset, higherIsBetter: nil, weight: 0.10,
                detail: String(format: "%@ ± %.1f h",
                               MetricValueFormatter.string(regularity.typicalOnset, .sleepOnset),
                               regularity.spreadHours)))
        }
        if let latest = efficiencyReading?.value {
            contributors.append(.init(metric: .sleepEfficiency, higherIsBetter: true,
                                      weight: 0.13, detail: String(format: "%.0f%%", latest)))
        }
        if let latest = deepReading?.value {
            contributors.append(.init(metric: .sleepDeepMinutes, higherIsBetter: nil,
                                      weight: 0.05, detail: String(format: "%.0f min", latest)))
        }
        if let latest = remReading?.value {
            contributors.append(.init(metric: .sleepRemMinutes, higherIsBetter: nil,
                                      weight: 0.05, detail: String(format: "%.0f min", latest)))
        }
        if let latest = spo2Reading?.value {
            contributors.append(.init(metric: .oxygenSaturation, higherIsBetter: true,
                                      weight: 0.07, detail: String(format: "%.0f%%", latest)))
        }
        if let latest = respReading?.value {
            contributors.append(.init(metric: .respiratoryRate, higherIsBetter: false,
                                      weight: 0.05, detail: String(format: "%.0f br/min", latest)))
        }
        if let tempSignal {
            contributors.append(.init(metric: tempSignal.metric, higherIsBetter: nil,
                                      weight: 0.03, detail: tempSignal.detail))
        }

        // A stale night can't buy high confidence however long the history is.
        let confidence: InsightConfidence = (nightly.count >= 5 && sleepReading.isFresh)
            ? .high : .moderate
        return InsightResult(
            id: id, title: title, primaryValue: score, headline: band, score: score,
            confidence: confidence,
            explanation: "Sleep quality \(Int(score.rounded()))/100 (\(band)) — from last night's \(String(format: "%.1f", lastNight)) hours, how much of your time in bed was actually asleep, how much of the night was deep or REM, how consistent your recent nights are, and your breathing, blood oxygen and skin temperature through it. Deep and REM are scored as a *share* of the night rather than in minutes, so a short sleeper isn't charged twice for one short night.",
            driverLines: drivers.filter { $0.isNotable == true } + drivers.filter { $0.isNotable != true },
            unmetRequirements: [], contributors: contributors,
            weighting: .weightedAverage)
    }

    static func durationScore(_ h: Double) -> Double {
        switch h {
        case 7.5...9: return 100
        case 7..<7.5, 9..<9.5: return 85
        case 6..<7, 9.5..<10: return 65
        case 5..<6: return 45
        default: return 30
        }
    }
    static func band(_ s: Double) -> String {
        switch s { case 80...: return "Excellent"; case 65..<80: return "Good"
        case 50..<65: return "Fair"; default: return "Poor" }
    }
}
