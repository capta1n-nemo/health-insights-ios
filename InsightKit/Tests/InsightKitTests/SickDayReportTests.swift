import XCTest
@testable import InsightKit

private let reportNow = TestClock.now
private let reportCalendar = TestClock.utc

/// **What the reader said, and the per-day page built from it** — backlog
/// `B11-2`, `B11-8` and `B11-9`.
///
/// Every assertion here is a claim the evidence doc constrains
/// (`docs/illness-detection-evidence-2026-08-07.md`), and the two that matter
/// most are the ones about what the app is *not* allowed to do: it may not name
/// a kind of illness from readings alone, and it may never treat a quiet radar
/// as a reason to doubt what the reader recorded.
final class SickDayReportTests: XCTestCase {

    // MARK: - Fixtures

    private func nights(_ metric: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: TestClock.day(values.count - 1 - index)
                                   .addingTimeInterval(12 * 3600),
                               source: .oura)
        }
    }

    /// A perfectly ordinary forty days — nothing leaning, nothing accumulated.
    private func wellHistory(days: Int = 40) -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        func series(_ metric: MetricType, healthy: Double, jitter: Double) {
            samples += nights(metric, (0..<days).map {
                healthy + Double($0 % 3) * jitter - jitter
            })
        }
        series(.restingHeartRate, healthy: 55, jitter: 1.2)
        series(.heartRateVariabilityRMSSD, healthy: 46, jitter: 2.5)
        series(.skinTemperatureDeviation, healthy: 0, jitter: 0.12)
        series(.respiratoryRate, healthy: 14, jitter: 0.3)
        return samples
    }

    private func tag(_ type: SymptomType, _ severity: SymptomSeverity = .moderate,
                     daysAgo: Int = 0) -> SymptomEvent {
        SymptomEvent(type: type, severity: severity, date: TestClock.day(daysAgo),
                     source: .appleHealth)
    }

    private func ledger(_ severity: CalendarEventClassification.SickSeverity?,
                        daysAgo: Int = 0) -> SickDayLedger {
        SickDayLedger(entered: [
            .init(firstDay: TestClock.day(daysAgo), lastDay: TestClock.day(daysAgo),
                  label: nil, severity: severity, source: .entered)
        ], calendar: reportCalendar)
    }

    private func radar(symptoms: [SymptomEvent] = [],
                       sickDays: SickDayLedger = SickDayLedger(),
                       sideEffects: [SymptomReconciliation.LoggedEffect] = [])
        -> SymptomRadarInsight {
        SymptomRadarInsight(symptoms: symptoms, medication: nil, sickDays: sickDays,
                            sideEffects: sideEffects, calendar: reportCalendar)
    }

    // MARK: - B11-8: the reported channel

    /// **The property that keeps the physiological calibration intact.** A day
    /// nothing was recorded on must score exactly what it scored before this
    /// channel existed — otherwise the stated false-alarm budget (about two
    /// alarming mornings a year) would silently have to be re-simulated.
    func testADayWithNothingRecordedScoresExactlyWhatItAlwaysDid() {
        let samples = wellHistory()
        let before = SymptomRadarModel.verdict(
            today: HealthWatchModel.evaluate(samples: samples, now: reportNow,
                                             calendar: reportCalendar)!,
            timeline: SymptomRadarModel.timeline(samples: samples, days: 30,
                                                 endingAt: reportNow,
                                                 calendar: reportCalendar))
        let after = radar().evaluate(samples: samples, profile: .init(), now: reportNow)
        XCTAssertEqual(after.score ?? 0, before.score, accuracy: 1e-9)
        XCTAssertFalse(before.isReaderReported)
    }

    /// The reader saying they were severely ill must not be met with "nothing
    /// stirring". This is the whole point of the channel and the one claim it
    /// makes: the card declines to contradict the only person who was there.
    func testASeverelyRecordedSickDayCannotBeCalledQuiet() {
        let result = radar(sickDays: ledger(.severe))
            .evaluate(samples: wellHistory(), profile: .init(), now: reportNow)
        XCTAssertNotEqual(result.headline, "Nothing stirring")
        XCTAssertEqual(result.score ?? 100, 50, accuracy: 1e-6,
                       "a stated severe illness is anchored on the strong-signs edge")
    }

    /// ⚠️ **A single non-specific symptom can never flag the card on its own.**
    /// `nonSpecificShare` is a half precisely so that even a severe headache
    /// stays under `someSignsExcess` — this card's founding argument (agreement
    /// is the finding) applied to the reader's words as well as their vitals.
    func testOneNonSpecificSymptomCannotFlagTheCardAlone() {
        let out = ReportedIllness.evaluate(
            day: TestClock.day(0), symptoms: [tag(.headache, .severe)],
            sickDays: SickDayLedger(), calendar: reportCalendar)
        XCTAssertLessThan(out.excess, HealthWatchModel.someSignsExcess)

        let result = radar(symptoms: [tag(.headache, .severe)])
            .evaluate(samples: wellHistory(), profile: .init(), now: reportNow)
        XCTAssertEqual(result.headline, "Nothing stirring")
    }

    /// An infection-like tag speaks at full strength; the same grade on a
    /// non-specific symptom speaks at half. The asymmetry is the evidence doc's
    /// finding about specificity, expressed as arithmetic.
    func testAnInfectionLikeTagOutweighsANonSpecificOneAtTheSameGrade() {
        let specific = ReportedIllness.tagExcess(tag(.fever, .severe))
        let vague = ReportedIllness.tagExcess(tag(.fatigue, .severe))
        XCTAssertEqual(specific, HealthWatchModel.strongSignsExcess, accuracy: 1e-9)
        XCTAssertEqual(vague, specific * ReportedIllness.nonSpecificShare, accuracy: 1e-9)
    }

    /// **The maximum, never the sum.** Three records of one illness are three
    /// views of one statement; adding them would put 6.6 on a scale whose strong
    /// band is 3.3.
    func testThreeRecordsOfOneIllnessDoNotAddUp() {
        let out = ReportedIllness.evaluate(
            day: TestClock.day(0),
            symptoms: [tag(.fever, .severe)],
            sickDays: ledger(.severe),
            sideEffects: [.init(name: "Coughing", severity: 9, date: TestClock.day(0))],
            calendar: reportCalendar)
        XCTAssertEqual(out.components.count, 3)
        XCTAssertEqual(out.excess, HealthWatchModel.strongSignsExcess, accuracy: 1e-9)
    }

    /// The side-effect log only speaks for the symptoms Health does not already
    /// hold — otherwise one statement would vote twice, which is the same
    /// double-count `collapsingDuplicates` refuses on the physiological side.
    func testTheSideEffectLogDoesNotRepeatWhatHealthAlreadyHolds() {
        let out = ReportedIllness.evaluate(
            day: TestClock.day(0),
            symptoms: [tag(.coughing, .moderate)],
            sickDays: SickDayLedger(),
            sideEffects: [.init(name: "Coughing", severity: 9, date: TestClock.day(0))],
            calendar: reportCalendar)
        XCTAssertNil(out.component(.sideEffectLog),
                     "the same symptom in both records is one statement, not two")
    }

    /// The reader's own log reaching the card at all is `B11-8`'s point — a hit
    /// rate built from one of two logs was reading half the evidence.
    func testASymptomOnlyInTheMedicationLogStillReachesTheCard() {
        let out = ReportedIllness.evaluate(
            day: TestClock.day(0), symptoms: [],
            sickDays: SickDayLedger(),
            sideEffects: [.init(name: "Fever", severity: 9, date: TestClock.day(0))],
            calendar: reportCalendar)
        XCTAssertEqual(out.excess, HealthWatchModel.strongSignsExcess, accuracy: 1e-9)
    }

    // MARK: - B11-8: the weightings

    /// The reader's rule: an input either carries a share or says on its own row
    /// why it doesn't. All three sources appear every day, whichever spoke.
    func testAllThreeReportedSourcesAppearInTheWeightingsEveryDay() {
        let quiet = radar().evaluate(samples: wellHistory(), profile: .init(),
                                     now: reportNow)
        let named = Set(quiet.unweightedFactors.map(\.name))
        for source in ReportedIllness.Source.allCases {
            XCTAssertTrue(named.contains(source.displayName),
                          "\(source) is missing from the weightings entirely")
        }
        for row in quiet.unweightedFactors {
            XCTAssertTrue(row.detail.contains(" — "), "\(row.name): \(row.detail)")
        }
    }

    /// On a day the reader recorded illness the row carries a real share, the
    /// measured signals give some of theirs up, and the whole still sums to one.
    func testARecordedSickDayTakesARealShareAndTheBarsStillSumToOne() {
        let result = radar(sickDays: ledger(.moderate))
            .evaluate(samples: wellHistory(), profile: .init(), now: reportNow)
        let weighted = result.weightedFactors
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        let sickRow = weighted.first { $0.name == ReportedIllness.Source.recordedSickDay.displayName }
        XCTAssertNotNil(sickRow)
        XCTAssertGreaterThan(sickRow?.weight ?? 0, 0)
    }

    /// ⚠️ On a perfectly ordinary morning the reader tagged a fever on, the
    /// measured signals carry **nothing** — `today.excess` is zero, and a bar
    /// saying they contributed half of that day's number would be an invention.
    func testOnAnOrdinaryMorningTheReaderReportedTheSignalsCarryNothing() {
        let result = radar(symptoms: [tag(.fever, .severe)])
            .evaluate(samples: wellHistory(), profile: .init(), now: reportNow)
        let metricWeight = result.contributors.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(metricWeight, 0, accuracy: 1e-9)
        XCTAssertEqual(result.weightedFactors.reduce(0) { $0 + $1.weight }, 1,
                       accuracy: 1e-9)
    }

    /// The card must say the number came from what the reader recorded, not
    /// print a physiological lead over a morning its own arithmetic did not
    /// make. This is the modelled-dressed-as-measured rule on this card.
    func testAReaderLedVerdictSaysSoInTheCopy() {
        let result = radar(sickDays: ledger(.severe))
            .evaluate(samples: wellHistory(), profile: .init(), now: reportNow)
        XCTAssertTrue(result.explanation.contains("what you recorded"),
                      result.explanation)
        XCTAssertFalse(result.explanation.contains("watched signals are leaning"),
                       "a reader-led number must not be explained as a reading")
    }

    /// The three reported series reach the Data tab as first-class derived data
    /// — backlog `B11-9` — and a silent day records a real zero rather than a
    /// gap, so the history stays readable.
    func testTheReportedSourcesAreDerivedSeriesEvenOnASilentDay() {
        let quiet = radar().evaluate(samples: wellHistory(), profile: .init(),
                                     now: reportNow)
        var store = DerivedSeriesStore()
        store.record(quiet, on: reportNow, calendar: reportCalendar)
        for source in ReportedIllness.Source.allCases {
            let id = DerivedSeriesID(.symptomRadar, source.seriesKey)
            XCTAssertEqual(store.value(id, on: reportNow, calendar: reportCalendar), 0,
                           "\(source) should record a zero, not vanish")
        }
    }

    /// `modelVersion` moves with the arithmetic, per the `fitness-v2`
    /// precedent — a score from before this change is not comparable with one
    /// from after it.
    func testTheModelVersionMovedWithTheChange() {
        XCTAssertEqual(InsightID.symptomRadar.modelVersion, "symptom-radar-v2")
    }

    // MARK: - B11-2: the estimate

    /// ⚠️ **Physiology alone never names a kind of illness.** The literature is
    /// explicit that the signal is non-specific systemic strain and detects no
    /// organ system at all; an estimator that read "respiratory" off a raised
    /// breathing rate would be inventing specificity nobody has measured.
    func testReadingsAloneNeverNameAKindOfIllness() {
        let samples = wellHistory()
        let history = SymptomRadarModel.history(over: SymptomRadarModel.timeline(
            samples: samples, days: 30, endingAt: reportNow, calendar: reportCalendar))
        let report = SickDayReport.build(day: TestClock.day(0), history: history,
                                         derived: DerivedSeriesStore(), symptoms: [],
                                         sickDays: SickDayLedger(),
                                         calendar: reportCalendar)
        XCTAssertEqual(report.estimate.assessment.kind, .unknown)
        XCTAssertNil(report.estimate.assessment.severity)
    }

    /// A tagged symptom names the kind; a recorded sick day with no named
    /// symptom says `.other` rather than guessing one.
    func testTheKindComesFromWhatWasReported() {
        let samples = wellHistory()
        let history = SymptomRadarModel.history(over: SymptomRadarModel.timeline(
            samples: samples, days: 30, endingAt: reportNow, calendar: reportCalendar))
        func kind(symptoms: [SymptomEvent], sickDays: SickDayLedger) -> IllnessKind {
            SickDayReport.build(day: TestClock.day(0), history: history,
                                derived: DerivedSeriesStore(), symptoms: symptoms,
                                sickDays: sickDays, calendar: reportCalendar)
                .estimate.assessment.kind
        }
        XCTAssertEqual(kind(symptoms: [tag(.coughing)], sickDays: SickDayLedger()),
                       .respiratory)
        XCTAssertEqual(kind(symptoms: [tag(.vomiting)], sickDays: SickDayLedger()),
                       .gastrointestinal)
        XCTAssertEqual(kind(symptoms: [tag(.fever)], sickDays: SickDayLedger()),
                       .feverish)
        XCTAssertEqual(kind(symptoms: [], sickDays: ledger(.moderate)), .other)
        // A vague symptom names nothing, even graded severe.
        XCTAssertEqual(kind(symptoms: [tag(.fatigue, .severe)], sickDays: SickDayLedger()),
                       .unknown)
    }

    /// The readings may suggest mild or moderate and never severe. Only the
    /// reader can say severe, and a 4–12% PPV detector saying it would be the
    /// overreach this whole feature is written against.
    func testMeasuredSeverityNeverReachesSevere() {
        // Every watched signal pinned at its cap in the concerning direction —
        // the loudest morning this model can produce.
        let signals = HealthWatchModel.watched.map { entry in
            HealthWatchModel.Signal(metric: entry.metric, recent: 1, reference: 0,
                                    zScore: entry.risingIsConcerning ? 6 : -6,
                                    isConcerning: true)
        }
        for count in 1...signals.count {
            let subset = Array(signals.prefix(count))
            guard let output = HealthWatchModel.output(fromEvaluated: subset) else { continue }
            let row = SymptomRadarModel.DayHistory(
                day: TestClock.day(0), output: output,
                accumulation: .init(statistic: SymptomRadarModel.Memory.accumulationCap,
                                    daysRunning: 20),
                status: output.status)
            XCTAssertNotEqual(IllnessEstimator.measuredGrade(history: row), .severe,
                              "readings must never grade somebody severely ill")
        }
    }

    /// ⚠️ Every estimate carries a non-empty uncertainty. The reader's standing
    /// instruction is the honest version, always; an estimate whose uncertainty
    /// is a view's responsibility is one that will be rendered without it.
    func testEveryEstimateStatesItsUncertainty() {
        let samples = wellHistory()
        let history = SymptomRadarModel.history(over: SymptomRadarModel.timeline(
            samples: samples, days: 30, endingAt: reportNow, calendar: reportCalendar))
        let cases: [([SymptomEvent], SickDayLedger)] = [
            ([], SickDayLedger()),
            ([tag(.fever, .severe)], SickDayLedger()),
            ([], ledger(.mild)),
            ([tag(.fatigue)], ledger(.severe)),
        ]
        for (symptoms, sick) in cases {
            let report = SickDayReport.build(day: TestClock.day(0), history: history,
                                             derived: DerivedSeriesStore(),
                                             symptoms: symptoms, sickDays: sick,
                                             calendar: reportCalendar)
            XCTAssertFalse(report.estimate.uncertainty.isEmpty)
            XCTAssertFalse(report.estimate.basis.isEmpty)
            XCTAssertFalse(report.templateSummary.isEmpty)
        }
    }

    /// A day outside the replay's span is "nothing was judged" and says so —
    /// never a green morning nobody measured.
    func testADayWithNothingWornIsNotAQuietDay() {
        let report = SickDayReport.build(day: TestClock.day(500), history: [],
                                         derived: DerivedSeriesStore(), symptoms: [],
                                         sickDays: SickDayLedger(),
                                         calendar: reportCalendar)
        XCTAssertFalse(report.wasJudged)
        XCTAssertNil(report.score)
        XCTAssertTrue(report.templateSummary.contains("Nothing was judged"),
                      report.templateSummary)
    }

    /// The contributing-sources list is a lookup in `DerivedSeriesStore` on the
    /// day being shown — never `latest`, which would let last week's figure
    /// stand in for this one.
    func testTheContributingSourcesAreReadOnTheDayBeingShown() {
        var store = DerivedSeriesStore()
        let spec = DerivedSeriesSpec(id: DerivedSeriesID(.readiness, "example"),
                                     displayName: "Example", unit: "",
                                     producedBy: .readiness, kind: .modelOutput)
        store.record(spec, value: 7, on: TestClock.day(3), calendar: reportCalendar)
        store.record(spec, value: 9, on: TestClock.day(0), calendar: reportCalendar)
        let report = SickDayReport.build(day: TestClock.day(3), history: [],
                                         derived: store, symptoms: [],
                                         sickDays: SickDayLedger(),
                                         calendar: reportCalendar)
        XCTAssertEqual(report.derived.first?.value, 7)
    }

    /// The fact sheet handed to the on-device model names no symptom. A prompt
    /// is a place a health fact can leak, and this repo's rule is the shape of a
    /// finding, never the reading.
    func testTheFactSheetNamesNoSymptom() {
        let samples = wellHistory()
        let history = SymptomRadarModel.history(over: SymptomRadarModel.timeline(
            samples: samples, days: 30, endingAt: reportNow, calendar: reportCalendar))
        let report = SickDayReport.build(day: TestClock.day(0), history: history,
                                         derived: DerivedSeriesStore(),
                                         symptoms: [tag(.coughing, .severe)],
                                         sickDays: SickDayLedger(),
                                         calendar: reportCalendar)
        let sheet = report.factSheet.lowercased()
        for name in SymptomType.allCases.map({ $0.title.lowercased() }) {
            XCTAssertFalse(sheet.contains(name), "the prompt named \(name)")
        }
    }

    // MARK: - B11-2: correcting it

    /// The guess, the answer and the snapshot stay in three fields — the
    /// `CalendarEventJudgement` design, and the reason the app can ever say how
    /// often it was right.
    func testACorrectionNeverOverwritesTheGuess() {
        let estimate = IllnessEstimate(
            assessment: IllnessAssessment(kind: .feverish, severity: .mild),
            basis: ["because"], uncertainty: "not a verdict",
            artifact: IllnessArtifact(physiologicalExcess: 2, accumulatedStatistic: 1,
                                      reportedExcess: 0, leaningSignals: 2,
                                      wasJudged: true))
        let judgement = IllnessJudgement(day: TestClock.day(1), estimate: estimate)
            .reviewed(correction: IllnessAssessment(kind: .respiratory, severity: .severe),
                      confirmed: false, at: reportNow)
        XCTAssertEqual(judgement.estimate.assessment.kind, .feverish)
        XCTAssertEqual(judgement.effective.kind, .respiratory)
        XCTAssertTrue(judgement.wasCorrected)
        XCTAssertEqual(judgement.estimate.artifact.leaningSignals, 2)
    }

    /// "Confirmed correct" is a label; "not yet looked at" is not. Treating them
    /// as one inflates any accuracy figure the app ever computes.
    func testAnUnansweredEstimateIsNotASilentSuccess() {
        let estimate = IllnessEstimate(
            assessment: .notIll, basis: ["because"], uncertainty: "not a verdict",
            artifact: IllnessArtifact(physiologicalExcess: 0, accumulatedStatistic: 0,
                                      reportedExcess: 0, leaningSignals: 0,
                                      wasJudged: true))
        let unanswered = (0..<10).map {
            IllnessJudgement(day: TestClock.day($0), estimate: estimate)
        }
        let accuracy = IllnessAccuracy.over(unanswered)
        XCTAssertEqual(accuracy.answered, 0)
        XCTAssertNil(accuracy.rate)
    }

    /// A rate needs a stated floor of answers rather than a fraction of three
    /// days — this card is the last place in the app that should print noise
    /// with a percent sign.
    func testAHitRateNeedsEnoughAnswersToMeanAnything() {
        let estimate = IllnessEstimate(
            assessment: .notIll, basis: ["because"], uncertainty: "not a verdict",
            artifact: IllnessArtifact(physiologicalExcess: 0, accumulatedStatistic: 0,
                                      reportedExcess: 0, leaningSignals: 0,
                                      wasJudged: true))
        func answered(_ count: Int) -> [IllnessJudgement] {
            (0..<count).map {
                IllnessJudgement(day: TestClock.day($0), estimate: estimate)
                    .reviewed(correction: nil, confirmed: true, at: reportNow)
            }
        }
        XCTAssertNil(IllnessAccuracy.over(answered(IllnessAccuracy.minimumAnswers - 1)).rate)
        XCTAssertEqual(IllnessAccuracy.over(answered(IllnessAccuracy.minimumAnswers)).rate, 1)
    }

    /// The reader can say "not ill", and nothing in this app treats that as an
    /// argument with their body. `.unknown` is the app's word for its own
    /// ignorance and is deliberately not offered to them.
    func testTheReaderCanSayNotIllAndIsNeverOfferedTheAppsOwnIgnorance() {
        XCTAssertTrue(IllnessKind.correctable.contains(.notIll))
        XCTAssertFalse(IllnessKind.correctable.contains(.unknown))
    }
}
