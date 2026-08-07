import XCTest
@testable import InsightKit

private let cal = TestClock.utc

/// What the app is willing to interrupt somebody for, and — more of these
/// assertions than not — what it refuses to.
///
/// The refusals are the substance of Q11. Notifications are the loudest surface
/// this app has, and three of the repo's standing rules land on them at once:
/// **this app does not nag**, **a detector is never the good news**, and
/// **modelled is never dressed as measured**. Every one of those is a sentence
/// somebody could write into a trigger without noticing, so each has a test.
final class NotificationTriggerTests: XCTestCase {

    // MARK: - Fixtures

    private func signal(_ metric: MetricType, z: Double,
                        concerning: Bool = true) -> HealthWatchModel.Signal {
        HealthWatchModel.Signal(metric: metric, recent: 0, reference: 0,
                                zScore: z, isConcerning: concerning)
    }

    private func verdict(_ status: SymptomRadarStatus, score: Double = 45,
                         leaning: [MetricType] = [.restingHeartRate, .heartRateVariabilityRMSSD],
                         carried: Bool = false) -> SymptomRadarModel.Verdict {
        let signals = leaning.map { signal($0, z: 2.0) }
        return SymptomRadarModel.Verdict(
            today: .init(signals: signals, score: score),
            accumulation: .none, score: score, status: status,
            isCarriedForward: carried)
    }

    private func episode(startDaysAgo: Int, endDaysAgo: Int,
                         metrics: [MetricType] = [.restingHeartRate]) -> SymptomRadarModel.SymptomRadarEpisode {
        SymptomRadarModel.SymptomRadarEpisode(
            start: cal.startOfDay(for: TestClock.day(startDaysAgo)),
            end: cal.startOfDay(for: TestClock.day(endDaysAgo)),
            peakDay: cal.startOfDay(for: TestClock.day(endDaysAgo)),
            peakScore: 40, peakLeaningCount: metrics.count,
            leaningMetrics: metrics, recoveries: [:])
    }

    private func card(_ id: InsightID, score: Double?, headline: String = "Good") -> InsightResult {
        InsightResult(id: id, title: "Readiness", primaryValue: score, headline: headline,
                      score: score, confidence: .high, explanation: "",
                      drivers: [], unmetRequirements: [])
    }

    private func inputs(_ build: (inout NotificationInputs) -> Void) -> NotificationInputs {
        var input = NotificationInputs(now: TestClock.now, calendar: cal)
        build(&input)
        return input
    }

    private func fire(_ input: NotificationInputs,
                      ledger: NotificationLedger = NotificationLedger()) -> [HealthNotification] {
        NotificationTriggers.candidates(input, ledger: ledger)
    }

    // MARK: - 1. Symptoms — the reader's own ask

    func testAStepTowardsSignsNotifies() {
        let out = fire(inputs {
            $0.radar = verdict(.someSigns)
            $0.previousRadarStatus = .quiet
        })
        let symptom = out.first { $0.kind == .symptomsDetected }
        XCTAssertNotNil(symptom)
        XCTAssertTrue(symptom?.body.contains("not a diagnosis") == true,
                      "modelled is never dressed as measured")
    }

    /// ⚠️ **A detector is never the good news.** The radar at 100 means nothing
    /// was *detected*, which is not a claim about the reader's health — so
    /// there is no path from any status back to quiet that sends anything.
    func testReturningToQuietNotifiesNothing() {
        for previous in [SymptomRadarStatus.someSigns, .strongSigns] {
            let out = fire(inputs {
                $0.radar = verdict(.quiet, score: 100, leaning: [])
                $0.previousRadarStatus = previous
            })
            XCTAssertTrue(out.filter { $0.kind == .symptomsDetected }.isEmpty,
                          "a step down from \(previous) must send nothing")
        }
    }

    func testTheSameStatusOnASecondDayDoesNotNotifyAgain() {
        let out = fire(inputs {
            $0.radar = verdict(.someSigns)
            $0.previousRadarStatus = .someSigns
        })
        XCTAssertTrue(out.filter { $0.kind == .symptomsDetected }.isEmpty)
    }

    /// A fresh install has no previous status, and must not open with a symptom
    /// alert on the strength of its first evaluation.
    func testAFirstEverEvaluationNotifiesNothing() {
        let out = fire(inputs {
            $0.radar = verdict(.strongSigns)
            $0.previousRadarStatus = nil
        })
        XCTAssertTrue(out.filter { $0.kind == .symptomsDetected }.isEmpty)
    }

    /// A day the watch could not evaluate is silence, not quiet. It must
    /// neither raise a flag nor be able to end one.
    func testADayTheWatchCouldNotEvaluateIsNotAQuietDay() {
        let out = fire(inputs {
            $0.radar = nil
            $0.previousRadarStatus = .quiet
        })
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - 2 & 3. A stretch opening and closing

    func testAStretchStartingTodayNotifies() {
        let out = fire(inputs { $0.episodes = [episode(startDaysAgo: 0, endDaysAgo: 0)] })
        XCTAssertEqual(out.filter { $0.kind == .radarEpisodeOpened }.count, 1)
    }

    func testAnOldStretchIsNotAnnouncedAsNew() {
        let out = fire(inputs { $0.episodes = [episode(startDaysAgo: 20, endDaysAgo: 18)] })
        XCTAssertTrue(out.filter { $0.kind == .radarEpisodeOpened }.isEmpty)
    }

    /// ⚠️ **An ending is only news to somebody who heard the beginning.**
    /// Announcing the end of a stretch that was never reported would be the app
    /// taking credit for a detection it kept to itself.
    func testAStretchEndIsNotReportedWhenTheStartNeverWas() {
        let out = fire(inputs {
            $0.episodes = [episode(startDaysAgo: 10, endDaysAgo: 6)]
            $0.radar = verdict(.quiet, score: 96, leaning: [])
            $0.previousRadarStatus = .quiet
        })
        XCTAssertTrue(out.filter { $0.kind == .radarEpisodeClosed }.isEmpty)
    }

    func testAStretchEndIsReportedWhenTheStartWas() {
        let ended = episode(startDaysAgo: 10, endDaysAgo: 6)
        var ledger = NotificationLedger()
        ledger.record(HealthNotification(
            kind: .radarEpisodeOpened,
            fingerprint: "open|\(NotificationTriggers.day(ended.start, cal))",
            title: "", body: ""), at: TestClock.day(10))

        let out = fire(inputs {
            $0.episodes = [ended]
            $0.radar = verdict(.quiet, score: 96, leaning: [])
            $0.previousRadarStatus = .quiet
        }, ledger: ledger)

        let close = out.first { $0.kind == .radarEpisodeClosed }
        XCTAssertNotNil(close)
        // ⚠️ Never congratulation. The claim is about the readings; how the
        // reader feels is theirs to judge, and this is the one kind here that
        // could plausibly have been written the other way.
        XCTAssertTrue(close?.body.contains("how you feel is your own to judge") == true)
        for word in ["well again", "recovered", "congratulations", "great news", "healthy"] {
            XCTAssertFalse((close.map { $0.title + " " + $0.body } ?? "")
                .localizedCaseInsensitiveContains(word),
                           "an ending is an observation about the signals, not a verdict on the reader (\(word))")
        }
    }

    /// One quiet morning mid-illness must not be announced as a recovery — the
    /// same three-day tolerance `SymptomRadarModel.episodes` joins across.
    func testAStretchThatOnlyJustEndedIsNotReportedYet() {
        let ended = episode(startDaysAgo: 6, endDaysAgo: 1)
        var ledger = NotificationLedger()
        ledger.record(HealthNotification(
            kind: .radarEpisodeOpened,
            fingerprint: "open|\(NotificationTriggers.day(ended.start, cal))",
            title: "", body: ""), at: TestClock.day(6))

        let out = fire(inputs {
            $0.episodes = [ended]
            $0.radar = verdict(.quiet, score: 96, leaning: [])
            $0.previousRadarStatus = .quiet
        }, ledger: ledger)
        XCTAssertTrue(out.filter { $0.kind == .radarEpisodeClosed }.isEmpty)
    }

    /// Still flagged today beats any claim the timeline makes about an ending.
    func testAStretchIsNotClosedWhileTodayIsStillFlagged() {
        let ended = episode(startDaysAgo: 10, endDaysAgo: 6)
        var ledger = NotificationLedger()
        ledger.record(HealthNotification(
            kind: .radarEpisodeOpened,
            fingerprint: "open|\(NotificationTriggers.day(ended.start, cal))",
            title: "", body: ""), at: TestClock.day(10))

        let out = fire(inputs {
            $0.episodes = [ended]
            $0.radar = verdict(.someSigns)
            $0.previousRadarStatus = .someSigns
        }, ledger: ledger)
        XCTAssertTrue(out.filter { $0.kind == .radarEpisodeClosed }.isEmpty)
    }

    // MARK: - 4. A source that has stopped syncing

    func testAConnectedSourceThatHasBroughtNothingBackForTwoDaysNotifies() {
        let out = fire(inputs {
            $0.connectors = [ConnectorSnapshot(id: "oura", displayName: "Oura",
                                               isConnected: true,
                                               lastSuccessfulSync: TestClock.day(3))]
        })
        XCTAssertEqual(out.filter { $0.kind == .connectorStalled }.count, 1)
    }

    /// A ring that spent one night on charge has not failed at anything.
    func testASourceThatMissedOneDayIsNotStalled() {
        let out = fire(inputs {
            $0.connectors = [ConnectorSnapshot(id: "oura", displayName: "Oura",
                                               isConnected: true,
                                               lastSuccessfulSync: TestClock.hours(20))]
        })
        XCTAssertTrue(out.isEmpty)
    }

    /// A source connected minutes ago has not stalled — it has not been asked.
    func testASourceThatHasNeverSyncedIsNotStalled() {
        let out = fire(inputs {
            $0.connectors = [ConnectorSnapshot(id: "withings", displayName: "Withings",
                                               isConnected: true, lastSuccessfulSync: nil)]
        })
        XCTAssertTrue(out.isEmpty)
    }

    func testADisconnectedSourceIsNotNagged() {
        let out = fire(inputs {
            $0.connectors = [ConnectorSnapshot(id: "whoop", displayName: "Whoop",
                                               isConnected: false,
                                               lastSuccessfulSync: TestClock.day(40))]
        })
        XCTAssertTrue(out.isEmpty)
    }

    /// The fingerprint carries the last successful sync, not today — so one
    /// stall is one notification however often the background pass sees it.
    func testAStallFingerprintIsStableAcrossEvaluations() {
        let connector = ConnectorSnapshot(id: "oura", displayName: "Oura",
                                          isConnected: true,
                                          lastSuccessfulSync: TestClock.day(5))
        let today = fire(inputs { $0.connectors = [connector] }).first { $0.kind == .connectorStalled }
        var later = NotificationInputs(now: TestClock.now.addingTimeInterval(4 * 86_400),
                                       calendar: cal)
        later.connectors = [connector]
        let tomorrow = fire(later).first { $0.kind == .connectorStalled }
        XCTAssertEqual(today?.id, tomorrow?.id)
    }

    // MARK: - 5. A grounding fact going stale

    func testAMandatoryFactThatHasLapsedNotifies() {
        let out = fire(inputs {
            $0.renewals = [GroundingRenewal(kind: .totalCholesterol, state: .stale,
                                            recordedAt: TestClock.day(400),
                                            expiresAt: TestClock.day(30),
                                            isMandatory: true)]
        })
        XCTAssertEqual(out.filter { $0.kind == .groundingFactStale }.count, 1)
    }

    /// Advance warning is a Grounding-screen row, not an interruption.
    func testAFactMerelyExpiringSoonNotifiesNothing() {
        let out = fire(inputs {
            $0.renewals = [GroundingRenewal(kind: .totalCholesterol, state: .expiringSoon,
                                            recordedAt: TestClock.day(300),
                                            expiresAt: TestClock.hours(-200),
                                            isMandatory: true)]
        })
        XCTAssertTrue(out.isEmpty)
    }

    /// An optional fact improves an estimate. Asking for one is an invitation,
    /// and invitations belong on Today.
    func testAnOptionalFactGoingStaleNotifiesNothing() {
        let out = fire(inputs {
            $0.renewals = [GroundingRenewal(kind: .totalCholesterol, state: .stale,
                                            recordedAt: TestClock.day(400),
                                            expiresAt: TestClock.day(30),
                                            isMandatory: false)]
        })
        XCTAssertTrue(out.isEmpty)
    }

    /// A fact that was never recorded is not a fact that went stale.
    func testAMissingFactIsNeverReportedAsStale() {
        let out = fire(inputs {
            $0.renewals = [GroundingRenewal(kind: .totalCholesterol, state: .missing,
                                            recordedAt: nil, expiresAt: nil,
                                            isMandatory: true)]
        })
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - 6. A card changing majorly

    func testAFullBandMoveNotifies() {
        let out = fire(inputs {
            $0.results = [card(.readiness, score: 45)]
            $0.previousCards = [.readiness: CardSnapshot(score: 72, confidence: .high,
                                                         at: TestClock.day(1))]
        })
        XCTAssertEqual(out.filter { $0.kind == .cardChangedMajorly }.count, 1)
    }

    /// A card resting on a band boundary crosses it most days it wobbles. The
    /// floor is what stops that becoming a daily notification.
    func testABoundaryWobbleIsNotAMajorChange() {
        let out = fire(inputs {
            $0.results = [card(.readiness, score: 60.4)]
            $0.previousCards = [.readiness: CardSnapshot(score: 59.6, confidence: .high,
                                                         at: TestClock.day(1))]
        })
        XCTAssertTrue(out.isEmpty)
    }

    /// A big move that stays inside one band is not a different answer.
    func testALargeMoveInsideOneBandIsNotAMajorChange() {
        let out = fire(inputs {
            $0.results = [card(.readiness, score: 79)]
            $0.previousCards = [.readiness: CardSnapshot(score: 61, confidence: .high,
                                                         at: TestClock.day(1))]
        })
        XCTAssertTrue(out.isEmpty)
    }

    /// A sync that moves four cards is one notification, not four. The rest are
    /// on Today, which is where a list of changes belongs.
    func testOnlyTheBiggestCardMoveIsSent() {
        let out = fire(inputs {
            $0.results = [card(.readiness, score: 45), card(.sleep, score: 30),
                          card(.energy, score: 55)]
            $0.previousCards = [
                .readiness: CardSnapshot(score: 72, confidence: .high, at: TestClock.day(1)),
                .sleep: CardSnapshot(score: 90, confidence: .high, at: TestClock.day(1)),
                .energy: CardSnapshot(score: 75, confidence: .high, at: TestClock.day(1))]
        })
        let changes = out.filter { $0.kind == .cardChangedMajorly }
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.insight, .sleep, "60 points beats 27 and 20")
    }

    /// A wearable that has not synced yet takes a card's number away every
    /// morning and gives it back by lunchtime. `isAwaitingTodaysData` renders
    /// that calmly on the card; a notification about it would be an alarm about
    /// nothing.
    func testACardLosingOrGainingItsNumberIsNotAMajorChange() {
        let lost = fire(inputs {
            $0.results = [card(.readiness, score: nil, headline: "Waiting for today")]
            $0.previousCards = [.readiness: CardSnapshot(score: 72, confidence: .high,
                                                         at: TestClock.day(1))]
        })
        XCTAssertTrue(lost.isEmpty)

        let gained = fire(inputs {
            $0.results = [card(.readiness, score: 72)]
            $0.previousCards = [.readiness: CardSnapshot(score: nil, confidence: .low,
                                                         at: TestClock.day(1))]
        })
        XCTAssertTrue(gained.isEmpty)
    }

    // MARK: - 7. The next body scan

    func testAnOverdueScanNotifiesSomebodyWhoScans() {
        let out = fire(inputs { $0.lastBodyScan = TestClock.day(45) })
        XCTAssertEqual(out.filter { $0.kind == .bodyScanDue }.count, 1)
    }

    /// ⚠️ Never scanned is an invitation to try a feature, and
    /// `SuggestionEngine` already ranks those below every grounding gap. A
    /// notification is louder than every row in that list.
    func testSomebodyWhoHasNeverScannedIsNotNotified() {
        let out = fire(inputs { $0.lastBodyScan = nil })
        XCTAssertTrue(out.isEmpty)
    }

    func testAScanInsideTheIntervalNotifiesNothing() {
        let out = fire(inputs { $0.lastBodyScan = TestClock.day(10) })
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - The whole pass

    /// An ordinary day, with everything current, must produce nothing at all.
    /// This is the assertion that fails first if somebody adds a trigger whose
    /// resting state is "fire".
    func testAnOrdinaryDayProducesNothing() {
        let out = fire(inputs {
            $0.radar = verdict(.quiet, score: 97, leaning: [])
            $0.previousRadarStatus = .quiet
            $0.results = [card(.readiness, score: 72)]
            $0.previousCards = [.readiness: CardSnapshot(score: 70, confidence: .high,
                                                         at: TestClock.day(1))]
            $0.renewals = [GroundingRenewal(kind: .totalCholesterol, state: .current,
                                            recordedAt: TestClock.day(30),
                                            expiresAt: TestClock.day(-300),
                                            isMandatory: true)]
            $0.lastBodyScan = TestClock.day(4)
            $0.connectors = [ConnectorSnapshot(id: "oura", displayName: "Oura",
                                               isConnected: true,
                                               lastSuccessfulSync: TestClock.hours(6))]
        })
        XCTAssertTrue(out.isEmpty, "produced: \(out.map(\.kind))")
    }

    /// Every kind has to be reachable, or a settings row promises something
    /// that can never happen.
    func testEveryKindHasATriggerThatCanProduceIt() {
        var produced = Set<HealthNotificationKind>()

        produced.formUnion(fire(inputs {
            $0.radar = verdict(.strongSigns)
            $0.previousRadarStatus = .quiet
            $0.episodes = [episode(startDaysAgo: 0, endDaysAgo: 0)]
            $0.results = [card(.readiness, score: 45)]
            $0.previousCards = [.readiness: CardSnapshot(score: 72, confidence: .high,
                                                         at: TestClock.day(1))]
            $0.renewals = [GroundingRenewal(kind: .totalCholesterol, state: .stale,
                                            recordedAt: TestClock.day(400),
                                            expiresAt: TestClock.day(30),
                                            isMandatory: true)]
            $0.lastBodyScan = TestClock.day(45)
            $0.connectors = [ConnectorSnapshot(id: "oura", displayName: "Oura",
                                               isConnected: true,
                                               lastSuccessfulSync: TestClock.day(4))]
        }).map(\.kind))

        let ended = episode(startDaysAgo: 10, endDaysAgo: 6)
        var ledger = NotificationLedger()
        ledger.record(HealthNotification(
            kind: .radarEpisodeOpened,
            fingerprint: "open|\(NotificationTriggers.day(ended.start, cal))",
            title: "", body: ""), at: TestClock.day(10))
        produced.formUnion(fire(inputs {
            $0.episodes = [ended]
            $0.radar = verdict(.quiet, score: 96, leaning: [])
            $0.previousRadarStatus = .quiet
        }, ledger: ledger).map(\.kind))

        XCTAssertEqual(produced, Set(HealthNotificationKind.allCases))
    }

    /// Fingerprints must not depend on the phone's language, or a reader who
    /// changes region gets every past finding announced again.
    func testFingerprintsAreLocaleIndependent() {
        var french = cal
        french.locale = Locale(identifier: "fr_FR")
        let a = NotificationTriggers.day(TestClock.now, cal)
        let b = NotificationTriggers.day(TestClock.now, french)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 10)
    }
}
