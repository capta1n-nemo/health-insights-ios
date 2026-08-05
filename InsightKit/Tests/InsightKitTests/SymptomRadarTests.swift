import XCTest
@testable import InsightKit

private let radarNow = TestClock.now
private let radarCalendar = TestClock.utc

/// The symptom radar: `HealthWatchModel` rendered as its own card, graded
/// against the reader's own tags. The shaping constraint throughout is the
/// best published validation of this approach — 43% sensitivity at 95%
/// specificity — which forbids the green tick: quiet must say what quiet
/// misses, and the card must keep score against the reader's tags out loud.
final class SymptomRadarTests: XCTestCase {

    // MARK: - Fixtures

    /// Mirrors `nightly` in NewCardTests.swift — one sample per day, midday,
    /// oldest first.
    private func nights(_ metric: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: TestClock.day(values.count - 1 - index),
                               source: .oura)
        }
    }

    /// Mirrors `HealthWatchTests.history(illDays:)` (NewCardTests.swift:116) —
    /// same four metrics, same bases, jitter and shape — generalised to place
    /// the ill stretch anywhere, so the timeline, episode and ledger tests can
    /// build months with illnesses in the middle. Documented as a copy: the
    /// shipped assertions there (`history()` scores > 95, `illDays: 3` scores
    /// < 50, a lone outlier scores 55) are what the expectations below lean on.
    private func history(days: Int = 40,
                         illWindows: [ClosedRange<Int>] = []) -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        func series(_ metric: MetricType, healthy: Double, ill: Double, jitter: Double) {
            let values = (0..<days).map { index -> Double in
                let daysAgo = days - 1 - index
                let base = illWindows.contains { $0.contains(daysAgo) } ? ill : healthy
                return base + Double(index % 3) * jitter - jitter
            }
            samples += nights(metric, values)
        }
        series(.restingHeartRate, healthy: 55, ill: 62, jitter: 1.2)
        series(.heartRateVariabilityRMSSD, healthy: 46, ill: 32, jitter: 2.5)
        series(.skinTemperatureDeviation, healthy: 0, ill: 0.9, jitter: 0.12)
        series(.respiratoryRate, healthy: 14, ill: 16.5, jitter: 0.3)
        return samples
    }

    private func history(illDays: Int) -> [HealthMetricSample] {
        history(illWindows: illDays > 0 ? [0...(illDays - 1)] : [])
    }

    /// The single-outlier fixture from
    /// `HealthWatchTests.testOneSignalAloneBarelyMovesTheScore`: resting heart
    /// rate genuinely high for three days, everything else settled. Weight 0.9
    /// fully leaned → score exactly 55.
    private func singleOutlier() -> [HealthMetricSample] {
        var samples = history(illDays: 0)
        samples.removeAll { $0.type == .restingHeartRate }
        samples += nights(.restingHeartRate, (0..<40).map { index in
            index >= 37 ? 78 : 55 + Double(index % 3) * 1.2 - 1.2
        })
        return samples
    }

    private func radar(symptoms: [SymptomEvent] = [],
                       medication: MedicationSchedule? = nil) -> SymptomRadarInsight {
        SymptomRadarInsight(symptoms: symptoms, medication: medication,
                            calendar: radarCalendar)
    }

    private func tag(_ type: SymptomType, _ severity: SymptomSeverity = .moderate,
                     daysAgo: Int = 0) -> SymptomEvent {
        SymptomEvent(type: type, severity: severity, date: TestClock.day(daysAgo),
                     source: .appleHealth)
    }

    private func dose(_ milligrams: Double, daysAgo: Int,
                      inferred: Bool = false) -> AdministeredDose {
        AdministeredDose(takenAt: TestClock.day(daysAgo), milligrams: milligrams,
                         isInferred: inferred)
    }

    private func joinedDrivers(_ result: InsightResult) -> String {
        result.drivers.joined(separator: " ")
    }

    // MARK: - Timeline

    /// The timeline is a sliding replay of `evaluate`, day by day — this pins
    /// the shared-window refactor and any hidden `now`-dependence in the daily
    /// series fetch.
    func testTimelineAgreesWithEvaluateDayByDay() throws {
        let samples = history(illDays: 3)
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 10,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        XCTAssertEqual(timeline.count, 10)
        XCTAssertEqual(timeline.last?.day, radarCalendar.startOfDay(for: radarNow))
        XCTAssertEqual(timeline.last?.output,
                       HealthWatchModel.evaluate(samples: samples, now: radarNow,
                                                 calendar: radarCalendar))
        for back in [2, 5] {
            let day = radarCalendar.date(byAdding: .day, value: -back,
                                         to: radarCalendar.startOfDay(for: radarNow))!
            let endOfDay = radarCalendar.date(byAdding: .day, value: 1, to: day)!
            let snapshot = try XCTUnwrap(timeline.first { $0.day == day })
            XCTAssertEqual(snapshot.output,
                           HealthWatchModel.evaluate(samples: samples, now: endOfDay,
                                                     calendar: radarCalendar),
                           "day \(back) back disagrees with a live evaluation at its end")
        }
    }

    // MARK: - Status bands

    func testStatusBands() throws {
        let quiet = try XCTUnwrap(HealthWatchModel.evaluate(
            samples: history(illDays: 0), now: radarNow, calendar: radarCalendar))
        XCTAssertGreaterThan(quiet.score, 95)
        XCTAssertEqual(quiet.status, .quiet)

        let strong = try XCTUnwrap(HealthWatchModel.evaluate(
            samples: history(illDays: 3), now: radarNow, calendar: radarCalendar))
        XCTAssertLessThan(strong.score, 50)
        XCTAssertEqual(strong.status, .strongSigns)

        let one = try XCTUnwrap(HealthWatchModel.evaluate(
            samples: singleOutlier(), now: radarNow, calendar: radarCalendar))
        XCTAssertEqual(one.leaning.count, 1)
        XCTAssertEqual(one.status, .someSigns,
                       "exactly one leaning signal can never reach strongSigns")
        // The other half of that sentence, and it needs its own gate: this
        // fixture is a resting heart rate 23 bpm above the reader's own normal
        // with everything else settled. The joint statistic is *right* that one
        // channel does not make a convergence — it scores \(one.score) — but
        // "nothing stirring" would be a false answer to a heart rate like that.
        XCTAssertGreaterThan(one.score, 85,
                             "the agreement statistic should be relaxed here")
        XCTAssertNotEqual(one.status, .quiet,
                          "one signal 23 bpm out was reported as nothing stirring")
    }

    // MARK: - The 2026-08-05 defect, from both ends

    /// **The reader's own bug report.** *"My heart rate is still elevated, my
    /// HRV is still down … why am I now back at 99%?"*
    ///
    /// Four signals all leaning the illness way at z ≈ 0.95 scored **exactly
    /// 100** — "Nothing stirring" — because the score opened with
    /// `guard signal.isLeaning` and threw everything under z = 1.0 away. A body
    /// does not know where the threshold is.
    func testSignalsJustUnderTheLeaningBarStillCount() {
        func signals(at z: Double) -> [HealthWatchModel.Signal] {
            [(.skinTemperatureDeviation, true), (.restingHeartRate, true),
             (.respiratoryRate, true), (.oxygenSaturation, false)]
                .map { (metric: MetricType, rising: Bool) in
                    HealthWatchModel.Signal(metric: metric, recent: 0, reference: 0,
                                            zScore: rising ? z : -z, isConcerning: true)
                }
        }
        let justUnder = HealthWatchModel.score(signals(at: 0.95))
        let nothing = HealthWatchModel.score(signals(at: 0))

        XCTAssertLessThan(justUnder, 95,
                          "four signals all leaning at z = 0.95 scored \(justUnder) — the reader's bug")
        XCTAssertLessThan(justUnder, nothing)
        // For the record, so the next reader of this file has the figure: this
        // day used to score **exactly 100** and now scores about 90. It is not
        // 50, and it should not be — four channels 0.95 SD out is around the
        // 85th percentile of an ordinary week, which is a slightly-off day
        // rather than a finding.
        //
        // ⚠️ **That is the whole of what this fix buys, and it is not all of
        // what the reader asked for.** Their day-after complaint is about
        // *memory* — a departure that has lasted two days should not be judged
        // as though today were the first time. That is the accumulation half,
        // tracked separately.
        XCTAssertGreaterThan(justUnder, 80)
    }

    /// **The other end of the same defect.** Measured before the fix: one signal
    /// at z = 3.0 scored 55 while four at z = 1.2 scored 64 — the precise
    /// opposite of what `HealthWatchModel.score`'s own doc comment claimed, and
    /// the opposite of what this card is for. Agreement is the finding.
    func testFourSignalsAgreeingWorryItMoreThanOneShouting() {
        func signal(_ metric: MetricType, _ z: Double,
                    concerning: Bool) -> HealthWatchModel.Signal {
            .init(metric: metric, recent: 0, reference: 0, zScore: z,
                  isConcerning: concerning)
        }
        let four = [signal(.skinTemperatureDeviation, 1.2, concerning: true),
                    signal(.restingHeartRate, 1.2, concerning: true),
                    signal(.respiratoryRate, 1.2, concerning: true),
                    signal(.oxygenSaturation, -1.2, concerning: true)]
        let oneShouting = [signal(.skinTemperatureDeviation, 0.1, concerning: false),
                           signal(.restingHeartRate, 3.0, concerning: true),
                           signal(.respiratoryRate, 0.1, concerning: false),
                           signal(.oxygenSaturation, -0.1, concerning: false)]

        XCTAssertLessThan(HealthWatchModel.score(four),
                          HealthWatchModel.score(oneShouting),
                          "one signal shouting outranked four agreeing")
    }

    /// The score has to be continuous *through* the old threshold, or the fix
    /// has only moved the cliff.
    func testTheScoreHasNoCliffAtTheOldThreshold() {
        func score(at z: Double) -> Double {
            HealthWatchModel.score([
                .init(metric: .skinTemperatureDeviation, recent: 0, reference: 0,
                      zScore: z, isConcerning: true),
                .init(metric: .restingHeartRate, recent: 0, reference: 0,
                      zScore: z, isConcerning: true),
                .init(metric: .respiratoryRate, recent: 0, reference: 0,
                      zScore: z, isConcerning: true)])
        }
        var previous = score(at: 0)
        for step in 1...4000 {
            let value = score(at: Double(step) / 1000)
            XCTAssertLessThan(abs(value - previous), 1.0,
                              "a jump of more than a point at z = \(Double(step) / 1000)")
            previous = value
        }
    }

    /// ⚠️ **The band edges claim a false-alarm budget, so measure it.**
    /// `strongSigns` is anchored on the 99.45th percentile of the null — about
    /// two alarming mornings a year on a body that is perfectly well, against
    /// the ninety-seven that six signals each at 95% specificity would give if
    /// they were simply OR'd together.
    ///
    /// **This test has already earned its place.** The first version of `excess`
    /// assumed independent channels; this measured the real rate at 5.3% —
    /// nineteen mornings a year — and the spread grew an equicorrelation term
    /// the same hour.
    ///
    /// Run at three dependences, because 0.3 is an assumption and the cost of it
    /// being wrong belongs in a number rather than in a worry.
    func testTheFalseAlarmBudgetIsWhatTheBandsClaim() {
        // A fixed sequence rather than a random one: a calibration test that
        // fails once a fortnight is a test nobody trusts.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func uniform() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 1_000_000) / 1_000_000 + 1e-9
        }
        func normal() -> Double {
            (-2 * Foundation.log(uniform())).squareRoot()
                * Foundation.cos(2 * .pi * uniform())
        }

        let metrics: [(MetricType, Bool)] = [
            (.skinTemperatureDeviation, true), (.restingHeartRate, true),
            (.respiratoryRate, true), (.oxygenSaturation, false)]

        // The budget at the design assumption, and what it costs to be wrong in
        // either direction. Measured, then written down.
        let budget: [(dependence: Double, allowed: Double)] = [
            (0.0, 0.004),   // channels genuinely independent — better than designed
            (0.3, 0.008),   // the assumption: ~2 alarming mornings a year
            (0.5, 0.025),   // half again as dependent: ~6 a year, a degradation
        ]

        for (correlation, allowed) in budget {
            var alarms = 0
            let trials = 40_000
            for _ in 0..<trials {
                let common = normal()
                let signals = metrics.map { metric, rising -> HealthWatchModel.Signal in
                    let z = correlation.squareRoot() * common
                        + (1 - correlation).squareRoot() * normal()
                    return HealthWatchModel.Signal(
                        metric: metric, recent: 0, reference: 0,
                        zScore: rising ? z : -z, isConcerning: z > 0)
                }
                // Through `output(fromEvaluated:)` rather than `score` directly,
                // so the same-basis collapse and the two-signal gate are both in
                // the measurement. Respiratory rate and oxygen saturation are one
                // family and do collapse — the real morning has three channels,
                // not four, and a budget measured on four would be flattering.
                if HealthWatchModel.output(fromEvaluated: signals)?.status == .strongSigns {
                    alarms += 1
                }
            }
            let rate = Double(alarms) / Double(trials)
            XCTAssertLessThan(rate, allowed,
                              "at dependence \(correlation) the strong band fires on \(rate * 100)% of well days — about \(Int((rate * 365).rounded())) mornings a year")
        }
    }

    /// The structural claim behind the bands, now stated as a rule rather than
    /// left emergent: `strongSigns` needs two signals leaning, because one
    /// dramatic number is never the finding. Swept over every timeline day of
    /// every fixture.
    func testStrongSignsRequiresAgreement() {
        for fixture in [history(illDays: 0), history(illDays: 3),
                        history(illDays: 6), singleOutlier()] {
            for snapshot in SymptomRadarModel.timeline(samples: fixture, days: 30,
                                                       endingAt: radarNow,
                                                       calendar: radarCalendar) {
                guard let output = snapshot.output,
                      output.status == .strongSigns else { continue }
                XCTAssertGreaterThanOrEqual(output.leaning.count, 2,
                                            "strongSigns with a lone vote on \(snapshot.day)")
            }
        }
    }

    // MARK: - Episodes (#35: the episode, not just the onset)

    func testEpisodeHasStartPeakAndRecoveries() throws {
        // Ill days 9 through 4 ago, recovered since. The trailing recent
        // window keeps the flags alive one day past the ill stretch (the
        // reference window's own contamination then damps the z), so the last
        // flag lands exactly three days ago: today is quiet and the episode is
        // closed but recent — the recap state.
        let samples = history(days: 60, illWindows: [4...9])
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 30,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        let episodes = SymptomRadarModel.episodes(in: timeline, calendar: radarCalendar)
        XCTAssertEqual(episodes.count, 1, "one ill stretch should cut one episode")
        let episode = try XCTUnwrap(episodes.first)
        XCTAssertLessThan(episode.start, episode.end)
        XCTAssertTrue((episode.start...episode.end).contains(episode.peakDay))
        XCTAssertFalse(episode.leaningMetrics.isEmpty)
        XCTAssertGreaterThanOrEqual(episode.peakLeaningCount, 2)
        for metric in episode.leaningMetrics {
            let recovery = try XCTUnwrap(episode.recoveries[metric],
                                         "\(metric) never returned to baseline")
            XCTAssertGreaterThan(recovery, episode.peakDay,
                                 "recovery must follow the peak")
        }

        // And the quiet card recaps it rather than going silent — the Whoop
        // criticism this feature exists to answer.
        let result = radar().evaluate(samples: samples, profile: .init(), now: radarNow)
        XCTAssertEqual(result.headline, "Nothing stirring")
        XCTAssertTrue(result.drivers.contains { $0.contains("Settled:") },
                      "\(result.drivers)")
    }

    /// The peak rule itself — "the flag day with the lowest score, the
    /// earliest on a tie" — pinned against synthetic snapshots with known
    /// scores. `testEpisodeHasStartPeakAndRecoveries` only asserts properties
    /// any in-episode day satisfies, so replacing the rule with `group.first`
    /// passed the whole suite (mutation verified, 2026-08-04); this fails it.
    func testEpisodePeakIsTheLowestScoreDayEarliestOnATie() throws {
        func snapshot(daysAgo: Int, score: Double,
                      leaning: Int) -> SymptomRadarModel.DaySnapshot {
            let metrics: [MetricType] = [.skinTemperatureDeviation,
                                         .restingHeartRate, .respiratoryRate,
                                         .oxygenSaturation]
            let signals = metrics.enumerated().map { index, metric in
                HealthWatchModel.Signal(metric: metric, recent: 0, reference: 0,
                                        zScore: index < leaning ? 1.5 : 0,
                                        isConcerning: index < leaning)
            }
            return .init(day: radarCalendar.startOfDay(for: TestClock.day(daysAgo)),
                         output: .init(signals: signals, score: score))
        }

        // Flags on days 5…2 ago; day 3 is the unique deepest.
        let timeline = [snapshot(daysAgo: 6, score: 95, leaning: 0),
                        snapshot(daysAgo: 5, score: 70, leaning: 2),
                        snapshot(daysAgo: 4, score: 60, leaning: 2),
                        snapshot(daysAgo: 3, score: 40, leaning: 3),
                        snapshot(daysAgo: 2, score: 70, leaning: 2),
                        snapshot(daysAgo: 1, score: 95, leaning: 0)]
        let episode = try XCTUnwrap(
            SymptomRadarModel.episodes(in: timeline, calendar: radarCalendar).first)
        XCTAssertEqual(episode.peakDay,
                       radarCalendar.startOfDay(for: TestClock.day(3)))
        XCTAssertEqual(episode.peakScore, 40)
        XCTAssertEqual(episode.peakLeaningCount, 3)

        // Two days equally deep: the earliest wins the tie.
        let tied = [snapshot(daysAgo: 5, score: 70, leaning: 2),
                    snapshot(daysAgo: 4, score: 40, leaning: 3),
                    snapshot(daysAgo: 3, score: 40, leaning: 3),
                    snapshot(daysAgo: 2, score: 70, leaning: 2)]
        let tiedEpisode = try XCTUnwrap(
            SymptomRadarModel.episodes(in: tied, calendar: radarCalendar).first)
        XCTAssertEqual(tiedEpisode.peakDay,
                       radarCalendar.startOfDay(for: TestClock.day(4)),
                       "equal scores: the earliest flag day is the peak")
    }

    /// A graded real fixture: ill days 0…5 at a moderate lean with days 1…3
    /// markedly deeper, so yesterday — the one day whose whole recent window
    /// is deep — is the unique peak, and the on-card "hardest so far" driver
    /// must name its weekday. Deviations are sized in units of the reference
    /// spread (jitter × √(14/20), the sample deviation of seven each of
    /// base−j, base, base+j) to keep every z in the unsaturated 1…2 band —
    /// at the shipped fixture's z ≈ 7 every deep day floors at score 0 and
    /// the peak is undefined by score.
    func testHardestSoFarDriverNamesThePeakWeekday() throws {
        var samples: [HealthMetricSample] = []
        func series(_ metric: MetricType, healthy: Double, jitter: Double,
                    rising: Bool) {
            let spread = jitter * (14.0 / 20.0).squareRoot()
            let sign = rising ? 1.0 : -1.0
            samples += nights(metric, (0..<40).map { index in
                let daysAgo = 39 - index
                let lean: Double
                switch daysAgo {
                case 1...3: lean = 1.7
                case 0...5: lean = 1.2
                default: lean = 0
                }
                return healthy + sign * lean * spread
                    + Double(index % 3) * jitter - jitter
            })
        }
        series(.restingHeartRate, healthy: 55, jitter: 1.2, rising: true)
        series(.heartRateVariabilityRMSSD, healthy: 46, jitter: 2.5, rising: false)
        series(.skinTemperatureDeviation, healthy: 0, jitter: 0.12, rising: true)
        series(.respiratoryRate, healthy: 14, jitter: 0.3, rising: true)

        let timeline = SymptomRadarModel.timeline(samples: samples, days: 30,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        let episode = try XCTUnwrap(
            SymptomRadarModel.episodes(in: timeline, calendar: radarCalendar).last)
        XCTAssertEqual(episode.peakDay,
                       radarCalendar.startOfDay(for: TestClock.day(1)),
                       "the only day whose whole window is deep must be the peak")
        XCTAssertEqual(episode.peakLeaningCount, 3)

        let result = radar().evaluate(samples: samples, profile: .init(),
                                      now: radarNow)
        let weekday = radarCalendar.standaloneWeekdaySymbols[
            radarCalendar.component(.weekday, from: TestClock.day(1)) - 1]
        XCTAssertTrue(result.drivers.contains {
            $0.contains("hardest so far \(weekday)")
                && $0.contains("3 signals leaning")
        }, "\(result.drivers)")
    }

    func testDayCountAppearsInHeadline() {
        let result = radar().evaluate(samples: history(illDays: 3),
                                      profile: .init(), now: radarNow)
        // Three ill days: the recent window first crosses the leaning
        // threshold two days ago, so today is day 3 of the stretch.
        XCTAssertEqual(result.headline, "Strong signs — day 3")
    }

    // MARK: - The dose cases (#34: never call a dose reaction an infection)

    func testAGIClusterInsideTheDoseWindowNamesTheDose() {
        let schedule = MedicationSchedule(
            compound: .tirzepatide,
            doses: [dose(5, daysAgo: 8), dose(7.5, daysAgo: 1)])
        let tags = [tag(.nausea, .moderate, daysAgo: 0),
                    tag(.fatigue, .mild, daysAgo: 1)]
        let samples = history(illDays: 3)
        let result = radar(symptoms: tags, medication: schedule)
            .evaluate(samples: samples, profile: .init(), now: radarNow)
        let joined = joinedDrivers(result)

        XCTAssertTrue(joined.contains("tirzepatide"), joined)
        XCTAssertTrue(joined.contains("7.5"), joined)
        XCTAssertTrue(joined.contains("stepping up from 5"), joined)
        XCTAssertTrue(joined.contains("nausea"), joined)
        XCTAssertTrue(joined.contains("likelier explanation"), joined)
        // The neutral lead replaced the illness one…
        XCTAssertFalse(joined.contains("before an illness announces itself"), joined)
        // …but alongside, never instead of: the score and the signal lines
        // are untouched by the reader's medication.
        let unbound = radar().evaluate(samples: samples, profile: .init(), now: radarNow)
        XCTAssertEqual(result.score, unbound.score)
        XCTAssertEqual(result.primaryValue, unbound.primaryValue)
        XCTAssertTrue(result.drivers.contains { $0.contains("— leaning") },
                      "the per-signal lines must still render: \(result.drivers)")
    }

    func testFeverWithoutADoseKeepsTheIllnessWording() {
        let result = radar(symptoms: [tag(.fever, .moderate, daysAgo: 0)])
            .evaluate(samples: history(illDays: 3), profile: .init(), now: radarNow)
        let joined = joinedDrivers(result)
        XCTAssertTrue(joined.contains("before an illness announces itself"), joined)
        XCTAssertTrue(joined.contains("You tagged fever"), joined)
    }

    func testFeverBesideADoseIsNeverDoseExplained() {
        let schedule = MedicationSchedule(compound: .tirzepatide,
                                          doses: [dose(7.5, daysAgo: 1)])
        let result = radar(symptoms: [tag(.fever, .moderate, daysAgo: 0),
                                      tag(.nausea, .moderate, daysAgo: 0)],
                           medication: schedule)
            .evaluate(samples: history(illDays: 3), profile: .init(), now: radarNow)
        let joined = joinedDrivers(result)
        XCTAssertTrue(joined.contains("not a known tirzepatide effect"), joined)
        XCTAssertTrue(joined.contains("before an illness announces itself"),
                      "an infection-like tag keeps the illness lead: \(joined)")
    }

    /// The mirror image of #34: a GI tag that *predates* the dose cannot be
    /// the dose's effect, and calling it one suppresses a warning — nausea
    /// tagged two days before this morning's dose is early gastroenteritis
    /// until proven otherwise, and the old branch said "tagged nausea since",
    /// a temporally impossible attribution (fixed 2026-08-04, the same
    /// `gap >= 0` rule `doseCovers` always applied in the ledger).
    func testAGITagPredatingTheDoseKeepsTheIllnessLead() {
        let schedule = MedicationSchedule(compound: .tirzepatide,
                                          doses: [dose(5, daysAgo: 0)])
        let result = radar(symptoms: [tag(.nausea, .moderate, daysAgo: 2),
                                      tag(.nausea, .mild, daysAgo: 1)],
                           medication: schedule)
            .evaluate(samples: history(illDays: 3), profile: .init(), now: radarNow)
        let joined = joinedDrivers(result)
        XCTAssertTrue(joined.contains("before an illness announces itself"),
                      "pre-dose tags must keep the illness lead: \(joined)")
        XCTAssertFalse(joined.contains("likelier explanation"), joined)
        // The dose is still named — the overlap note survives the fall-through.
        XCTAssertTrue(joined.contains("Dose days can move these same signals"),
                      joined)
    }

    /// A recorded absence is a real answer and must count as *no* tag — it
    /// neither triggers the confounder table nor confirms an episode
    /// (`SymptomSeverity.isPresent`'s contract, held at the radar level).
    func testARecordedAbsenceNeitherConfirmsNorTriggersConfounders() {
        let schedule = MedicationSchedule(compound: .tirzepatide,
                                          doses: [dose(7.5, daysAgo: 1)])
        let absent = [tag(.nausea, .notPresent, daysAgo: 0)]
        let result = radar(symptoms: absent, medication: schedule)
            .evaluate(samples: history(illDays: 3), profile: .init(), now: radarNow)
        let joined = joinedDrivers(result)
        XCTAssertFalse(joined.contains("likelier explanation"),
                       "a recorded absence of nausea must not read as nausea: \(joined)")
        XCTAssertTrue(joined.contains("before an illness announces itself"), joined)

        // And in the ledger: an absence cannot confirm an episode.
        let samples = history(days: 100, illWindows: [27...30])
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 90,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        let notPresent = SymptomRadarModel.ledger(
            timeline: timeline, symptoms: [tag(.coughing, .notPresent, daysAgo: 26)],
            medication: nil, now: radarNow, calendar: radarCalendar)
        XCTAssertEqual(notPresent.hits, 0)
        XCTAssertEqual(notPresent.unconfirmed, 1)
        let present = SymptomRadarModel.ledger(
            timeline: timeline, symptoms: [tag(.coughing, .moderate, daysAgo: 26)],
            medication: nil, now: radarNow, calendar: radarCalendar)
        XCTAssertEqual(present.hits, 1)
    }

    // MARK: - The ledger (#36: the card grades itself)

    func testLedgerCountsHitUnconfirmedAndMiss() {
        // (a) an ill stretch a month ago, coughing tagged right after → hit;
        // (b) an ill stretch a fortnight ago, nothing tagged → unconfirmed;
        // (c) fever tagged twice six weeks ago with quiet vitals → miss.
        let samples = history(days: 100, illWindows: [27...30, 13...15])
        let tags = [tag(.coughing, .moderate, daysAgo: 26),
                    tag(.fever, .moderate, daysAgo: 45),
                    tag(.fever, .mild, daysAgo: 44)]
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 90,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        let ledger = SymptomRadarModel.ledger(timeline: timeline, symptoms: tags,
                                              medication: nil, now: radarNow,
                                              calendar: radarCalendar)
        XCTAssertEqual(ledger.hits, 1)
        XCTAssertEqual(ledger.unconfirmed, 1)
        XCTAssertEqual(ledger.misses, 1)
        XCTAssertEqual(ledger.pending, 0)
        XCTAssertGreaterThan(ledger.gradedDays, 30)
    }

    /// An ongoing stretch is not accused of silence: its confirmation window
    /// is still open, so it is pending, never unconfirmed.
    func testAnOngoingStretchIsPendingNotAccused() {
        let samples = history(days: 100, illWindows: [1...3, 13...15])
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 90,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        let ledger = SymptomRadarModel.ledger(timeline: timeline, symptoms: [],
                                              medication: nil, now: radarNow,
                                              calendar: radarCalendar)
        XCTAssertEqual(ledger.pending, 1)
        XCTAssertEqual(ledger.unconfirmed, 1)
        XCTAssertEqual(ledger.hits, 0)
    }

    /// A nausea-only tag inside a dose window cannot confirm an episode on its
    /// own — the dose already explains it. The identical tag with no dose can.
    func testADoseExplainedTagDoesNotCountAsAHit() {
        let samples = history(days: 100, illWindows: [27...30])
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 90,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        let nausea = [tag(.nausea, .moderate, daysAgo: 26)]
        let schedule = MedicationSchedule(compound: .tirzepatide,
                                          doses: [dose(5, daysAgo: 28)])
        let explained = SymptomRadarModel.ledger(timeline: timeline, symptoms: nausea,
                                                 medication: schedule, now: radarNow,
                                                 calendar: radarCalendar)
        XCTAssertEqual(explained.hits, 0, "a dose-window nausea is not a confirmation")
        XCTAssertEqual(explained.unconfirmed, 1)
        let unexplained = SymptomRadarModel.ledger(timeline: timeline, symptoms: nausea,
                                                   medication: nil, now: radarNow,
                                                   calendar: radarCalendar)
        XCTAssertEqual(unexplained.hits, 1, "the same tag with no dose confirms")
    }

    /// A tag type this reader logs on most days confirms nothing: daily hot
    /// flushes would otherwise "confirm" every stretch the radar ever flags,
    /// and a 100% hit rate built that way carries zero information — the
    /// readers most likely to have dense tag streams are exactly the ones the
    /// ledger would flatter (fixed 2026-08-04). The identical tag logged only
    /// around the episode still counts.
    func testAChronicTagCannotConfirmAnEpisode() {
        let samples = history(days: 100, illWindows: [27...30])
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 90,
                                                  endingAt: radarNow,
                                                  calendar: radarCalendar)
        let daily = (0..<90).map { tag(.hotFlashes, .mild, daysAgo: $0) }
        let chronic = SymptomRadarModel.ledger(timeline: timeline, symptoms: daily,
                                               medication: nil, now: radarNow,
                                               calendar: radarCalendar)
        XCTAssertEqual(chronic.hits, 0, "a tag present most days is not a signal")
        XCTAssertEqual(chronic.unconfirmed, 1)

        let sparse = SymptomRadarModel.ledger(
            timeline: timeline, symptoms: [tag(.hotFlashes, .mild, daysAgo: 28)],
            medication: nil, now: radarNow, calendar: radarCalendar)
        XCTAssertEqual(sparse.hits, 1,
                       "the same tag logged occasionally still confirms")
    }

    /// Replay honesty: evaluated at a past `now`, the ledger must not see tags
    /// dated after it — and the geometry makes the clip load-bearing. The
    /// episode's confirmation window extends past `now` and a tag sits one day
    /// after `now` inside it: with the clip the episode is pending, without it
    /// that tag flips it to a hit, so `with == without` detects the clip's
    /// removal. (The first version placed the tag 15 days after the only
    /// episode's window, so the ledger was byte-identical with or without the
    /// clip and the test was vacuous — mutation verified, 2026-08-04.)
    func testLedgerNeverReadsPastNow() {
        let past = TestClock.day(20)
        let samples = history(days: 100, illWindows: [21...24])
        let timeline = SymptomRadarModel.timeline(samples: samples, days: 90,
                                                  endingAt: past,
                                                  calendar: radarCalendar)
        let futureTags = [tag(.coughing, .moderate, daysAgo: 19),  // 1 day after `past`
                          tag(.coughing, .moderate, daysAgo: 5)]   // 15 days after
        let with = SymptomRadarModel.ledger(timeline: timeline, symptoms: futureTags,
                                            medication: nil, now: past,
                                            calendar: radarCalendar)
        let without = SymptomRadarModel.ledger(timeline: timeline, symptoms: [],
                                               medication: nil, now: past,
                                               calendar: radarCalendar)
        XCTAssertEqual(with, without, "a tag from the future reached a past grade")
        XCTAssertEqual(with.hits, 0)
        XCTAssertEqual(with.pending, 1,
                       "the stretch is on the books with its window still open")
        XCTAssertGreaterThan(with.flags, 0,
                             "the stretch itself should still be on the books")
    }

    // MARK: - Copy guardrails

    /// The radar's own version of the never-diagnose sweep — it additionally
    /// bans the word "infection" outright (the study line says "illnesses").
    func testItNeverDiagnoses() {
        let schedule = MedicationSchedule(
            compound: .tirzepatide,
            doses: [dose(5, daysAgo: 8), dose(7.5, daysAgo: 1)])
        let quiet = radar().evaluate(samples: history(illDays: 0),
                                     profile: .init(), now: radarNow)
        let flagged = radar(symptoms: [tag(.fever, .moderate, daysAgo: 0)])
            .evaluate(samples: history(illDays: 3), profile: .init(), now: radarNow)
        let doseFlagged = radar(symptoms: [tag(.nausea, .moderate, daysAgo: 0)],
                                medication: schedule)
            .evaluate(samples: history(illDays: 3), profile: .init(), now: radarNow)
        let empty = radar().evaluate(samples: [], profile: .init(), now: radarNow)

        for result in [quiet, flagged, doseFlagged, empty] {
            let text = (result.explanation + " "
                + result.drivers.joined(separator: " ")).lowercased()
            for banned in ["you have ", "you are ill", "you should", "diagnosis of",
                           "suggests you", "virus", "infection"] {
                XCTAssertFalse(text.contains(banned),
                               "\(result.headline) diagnosed (\"\(banned)\"): \(text)")
            }
        }
        for result in [flagged, doseFlagged] {
            XCTAssertTrue(result.drivers.joined().contains("not a diagnosis"),
                          "the disclaimer must travel with the finding")
        }
        XCTAssertTrue(quiet.explanation.contains("43%"),
                      "quiet must say what quiet misses")
    }

    /// #32 pinned to the pixel that matters: the Today preview shows
    /// `drivers.first`, so the quiet card's first driver *is* the 43% line.
    func testQuietLeadsWithTheHonestyLine() throws {
        let result = radar().evaluate(samples: history(illDays: 0),
                                      profile: .init(), now: radarNow)
        XCTAssertEqual(result.headline, "Nothing stirring")
        let first = try XCTUnwrap(result.drivers.first)
        XCTAssertTrue(first.contains("43%"), first)
        XCTAssertTrue(first.contains("not an all-clear"), first)
    }

    /// Quiet admits one genuinely leaning signal — score >= 85 is concern
    /// <= 0.3, which a lone SpO2 at z ≈ −1.5 (weight 0.5) satisfies — and the
    /// radar web draws that dot past the inner ring. The explanation printed
    /// above it must not claim "None of your watched signals is leaning": the
    /// falsity was visible on the same page (fixed 2026-08-04).
    func testQuietWithOneLeaningSignalSaysSoInsteadOfNone() throws {
        var samples: [HealthMetricSample] = []
        samples += nights(.restingHeartRate, (0..<40).map { index in
            55 + Double(index % 3) * 1.2 - 1.2
        })
        // Reference at 97 with the usual jitter; the last four days flat at
        // 96.5 → recent mean 96.5, z ≈ −1.49: leaning, but concern ≈ 0.25.
        samples += nights(.oxygenSaturation, (0..<40).map { index in
            let daysAgo = 39 - index
            return daysAgo <= 3 ? 96.5 : 97 + Double(index % 3) * 0.4 - 0.4
        })
        let watch = try XCTUnwrap(HealthWatchModel.evaluate(
            samples: samples, now: radarNow, calendar: radarCalendar))
        XCTAssertEqual(watch.status, .quiet,
                       "fixture drifted: this must be a quiet day (score \(watch.score))")
        XCTAssertEqual(watch.leaning.map(\.metric), [.oxygenSaturation],
                       "fixture drifted: exactly one signal must lean")

        let result = radar().evaluate(samples: samples, profile: .init(),
                                      now: radarNow)
        XCTAssertEqual(result.headline, "Nothing stirring")
        XCTAssertFalse(result.explanation.contains("None of your watched signals"),
                       result.explanation)
        XCTAssertTrue(result.explanation.contains("Only one signal — Blood Oxygen"),
                      result.explanation)
        XCTAssertTrue(result.explanation.contains("43%"),
                      "the honesty line must survive the new lead")
    }

    // MARK: - Empty states

    func testEmptyStateInvitesWearingTheWatch() {
        let result = radar().evaluate(samples: [], profile: .init(), now: radarNow)
        XCTAssertTrue(result.invitesInput)
        XCTAssertEqual(result.headline, "Wear your watch to sleep")
        XCTAssertNil(result.score)
        XCTAssertTrue(result.isWorthShowing)
    }

    func testStaleDataAwaitsSync() {
        // A real baseline whose newest reading is three days old: a sync gap,
        // not a fresh install — the two get opposite sentences.
        let stale = history(illDays: 0).filter { $0.start <= TestClock.day(3) }
        let result = radar().evaluate(samples: stale, profile: .init(), now: radarNow)
        XCTAssertTrue(result.isAwaitingTodaysData)
        XCTAssertEqual(result.headline, "Waiting for today's sync")
        XCTAssertNil(result.score)
        XCTAssertFalse(result.invitesInput)
    }

    // MARK: - Attribution

    /// Contributors carry the vote: each surviving signal's watched weight over
    /// the surviving total, and a collapse loser rides at zero with the reason
    /// on its own row.
    func testContributorsCarryTheVoteWeightsAndSumToOne() throws {
        let result = radar().evaluate(samples: history(illDays: 0),
                                      profile: .init(), now: radarNow)
        XCTAssertEqual(result.weighting, .accumulative)

        // Four metrics in the fixture; resting HR and rMSSD share the
        // beat-to-beat basis, so three vote and one is discounted.
        XCTAssertEqual(result.contributors.count, 4)
        XCTAssertEqual(Set(result.contributors.map(\.metric)),
                       [.restingHeartRate, .heartRateVariabilityRMSSD,
                        .skinTemperatureDeviation, .respiratoryRate])
        let weighted = result.contributors.filter { $0.weight > 0 }
        XCTAssertEqual(weighted.count, 3)
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)

        let temp = try XCTUnwrap(result.contributors.first {
            $0.metric == .skinTemperatureDeviation
        })
        XCTAssertEqual(temp.weight, 1.0 / 2.7, accuracy: 1e-9)
        XCTAssertEqual(temp.higherIsBetter, false)
        let resp = try XCTUnwrap(result.contributors.first {
            $0.metric == .respiratoryRate
        })
        XCTAssertEqual(resp.weight, 0.8 / 2.7, accuracy: 1e-9)
        XCTAssertEqual(resp.higherIsBetter, false)

        // One of the beat-to-beat pair votes at 0.9 of 2.7; the other says why
        // it carries nothing — "counted once" is not "not looked at".
        let pair = result.contributors.filter {
            [.restingHeartRate, .heartRateVariabilityRMSSD].contains($0.metric)
        }
        XCTAssertEqual(pair.filter { $0.weight > 0 }.count, 1)
        XCTAssertEqual(try XCTUnwrap(pair.first { $0.weight > 0 }).weight,
                       0.9 / 2.7, accuracy: 1e-9)
        let discounted = try XCTUnwrap(pair.first { $0.weight == 0 })
        XCTAssertTrue(discounted.detail.contains(" — counted once with"),
                      discounted.detail)
        XCTAssertEqual(result.contributors.first {
            $0.metric == .heartRateVariabilityRMSSD
        }?.higherIsBetter, true)
        XCTAssertEqual(result.contributors.first {
            $0.metric == .restingHeartRate
        }?.higherIsBetter, false)
    }

    // MARK: - Registration and plumbing

    /// `withSymptoms` replaces rather than appends, so the app can apply it on
    /// every recompute without compounding — the `withSubstanceLog` contract.
    func testWithSymptomsRebindsIdempotently() throws {
        let tags1 = [tag(.headache, .mild, daysAgo: 1)]
        let tags2 = [tag(.fever, .moderate, daysAgo: 0)]
        let engine = InsightEngine()
            .withSymptoms(tags1, medication: nil)
            .withSymptoms(tags2, medication: nil)
        XCTAssertEqual(engine.models.count, InsightEngine().models.count)
        XCTAssertEqual(engine.models.filter { $0 is SymptomRadarInsight }.count, 1)
        let bound = try XCTUnwrap(engine.models
            .compactMap { $0 as? SymptomRadarInsight }.first)
        XCTAssertEqual(bound.symptoms, tags2)
    }

    /// The cadence switch has a `default:` and fails silently onto the wrong
    /// tab — this is the pin that keeps the radar on Today.
    func testRadarIsRegisteredOnToday() {
        XCTAssertEqual(InsightID.symptomRadar.cadence, .daily)
    }
}
