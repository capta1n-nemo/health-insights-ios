import XCTest
@testable import InsightKit

/// "View & add" now shows a grounded summary and no preview of its own contents,
/// on every route. What can be wrong is the state: a green seal beside a figure
/// that says something is missing, or a progress bar next to a finished one.
final class ContributionSummaryTests: XCTestCase {

    // MARK: - Grounded and the figure cannot disagree

    /// The whole point of the figure is to be the short version of the seal.
    /// Sweeping every reachable pair is what stops them drifting.
    func testFactsAreGroundedExactlyWhenTheFigureSaysTheyAre() {
        for total in 0...6 {
            for set in 0...total {
                let summary = ContributionSummary.facts(set: set, of: total)
                XCTAssertEqual(summary.figure, "\(set) of \(total) set")
                XCTAssertEqual(summary.isGrounded, total > 0 && set == total,
                               "set \(set) of \(total)")
            }
        }
    }

    /// A bar that is already full says nothing the seal has not said. It must be
    /// absent once grounded, and present with a real fraction before that.
    func testTheProgressBarOnlyExistsWhileThereIsSomethingLeftToFill() throws {
        XCTAssertNil(ContributionSummary.facts(set: 4, of: 4).progress)
        XCTAssertNil(ContributionSummary.facts(set: 0, of: 0).progress)
        XCTAssertEqual(try XCTUnwrap(ContributionSummary.facts(set: 1, of: 4).progress),
                       0.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ContributionSummary.facts(set: 3, of: 4).progress),
                       0.75, accuracy: 1e-9)
    }

    /// Nothing asked for is not the same as everything given. A card whose model
    /// declares no requirements must not show a green seal it did not earn.
    func testAskingForNothingIsNotGrounded() {
        XCTAssertFalse(ContributionSummary.facts(set: 0, of: 0).isGrounded)
    }

    func testTheGuidanceCountsWhatIsActuallyMissing() {
        XCTAssertTrue(ContributionSummary.facts(set: 2, of: 5).guidance
            .hasPrefix("3 still to give"))
        XCTAssertTrue(ContributionSummary.facts(set: 5, of: 5).guidance
            .hasPrefix("All set"))
    }

    /// The button changes its verb once there is nothing left to add — the
    /// section is still worth opening to correct a value that was mistyped,
    /// which is the reason "View & add" replaced "Add these for a better
    /// estimate" in the first place.
    func testAGroundedCardStillOffersAWayIn() {
        XCTAssertEqual(ContributionSummary.facts(set: 5, of: 5).addLabel, "View your details")
        XCTAssertEqual(ContributionSummary.facts(set: 1, of: 5).addLabel, "Add your details")
    }

    /// Two controls for one destination is the thing this section exists to
    /// remove. A route gets a second control only when there is a screen beyond
    /// its own entry sheet: blood pressure's dated history and calibration
    /// detail, and medication's dose and side-effect history.
    func testOnlyARouteWithSomewhereFurtherToGoOffersALink() {
        XCTAssertNil(ContributionSummary.facts(set: 2, of: 5).detailLabel)
        XCTAssertNil(ContributionSummary.substances(logged: 9).detailLabel)
        XCTAssertNil(ContributionSummary.fileImport(lastReceived: "yesterday").detailLabel)
        XCTAssertNotNil(ContributionSummary
            .bloodPressure(.init(totalReadings: 4, recentReadings: 2)).detailLabel)
        XCTAssertNotNil(ContributionSummary
            .medication(hasRegimen: true, doses: 3, sideEffects: 0).detailLabel)
    }

    // MARK: - Medication

    /// The history link exists exactly while there is history — and it survives
    /// the odd corner where side effects arrived in an import before any dose
    /// was logged.
    func testTheMedicationLinkIsWordedForWhatExists() {
        XCTAssertNil(ContributionSummary
            .medication(hasRegimen: false, doses: 0, sideEffects: 0).detailLabel)
        XCTAssertNil(ContributionSummary
            .medication(hasRegimen: true, doses: 0, sideEffects: 0).detailLabel)
        XCTAssertEqual(ContributionSummary
            .medication(hasRegimen: true, doses: 1, sideEffects: 0).detailLabel,
            "All 1 dose and side effects")
        XCTAssertEqual(ContributionSummary
            .medication(hasRegimen: true, doses: 24, sideEffects: 2).detailLabel,
            "All 24 doses and side effects")
        XCTAssertEqual(ContributionSummary
            .medication(hasRegimen: true, doses: 0, sideEffects: 2).detailLabel,
            "All 2 side effects")
    }

    // MARK: - File import

    /// The route reads its state from the phrase the caller formatted: a figure
    /// while a file has arrived, an invitation while none has.
    func testFileImportIsGroundedOnceAFileHasArrived() {
        let never = ContributionSummary.fileImport(lastReceived: nil)
        XCTAssertFalse(never.isGrounded)
        XCTAssertEqual(never.figure, "None yet")
        XCTAssertNil(never.progress)

        let received = ContributionSummary.fileImport(lastReceived: "2 days ago")
        XCTAssertTrue(received.isGrounded)
        XCTAssertEqual(received.figure, "2 days ago")
        XCTAssertTrue(received.guidance.contains("2 days ago"))
        XCTAssertNil(received.progress)
    }

    // MARK: - Blood pressure defers rather than re-deciding

    /// There must not be a second opinion on whether blood pressure is
    /// calibrated. `CalibrationStatus` owns the five-then-two rule and the
    /// sentence; this only reads them.
    func testBloodPressureTakesItsAnswerFromTheCalibrationStatus() {
        for recent in 0...7 {
            let status = BloodPressureEstimator.CalibrationStatus(
                totalReadings: recent, recentReadings: recent)
            let summary = ContributionSummary.bloodPressure(status)
            XCTAssertEqual(summary.isGrounded, status.isGrounded, "\(recent) readings")
            XCTAssertEqual(summary.guidance, status.guidance)
            XCTAssertEqual(summary.figure, "\(recent) in 30 days")
        }
    }

    func testTheBloodPressureBarTracksItsOwnTarget() throws {
        let two = BloodPressureEstimator.CalibrationStatus(totalReadings: 2, recentReadings: 2)
        XCTAssertEqual(try XCTUnwrap(ContributionSummary.bloodPressure(two).progress),
                       Double(2) / Double(two.required), accuracy: 1e-9)

        let plenty = BloodPressureEstimator.CalibrationStatus(
            totalReadings: 20, recentReadings: 20)
        XCTAssertTrue(plenty.isGrounded)
        XCTAssertNil(ContributionSummary.bloodPressure(plenty).progress)
    }

    /// The link's words carry the count, so it has to survive being singular
    /// and being absent.
    func testTheBloodPressureLinkIsWordedForItsOwnCount() {
        let one = BloodPressureEstimator.CalibrationStatus(totalReadings: 1, recentReadings: 1)
        XCTAssertEqual(ContributionSummary.bloodPressure(one).detailLabel,
                       "All 1 reading and calibration detail")

        let many = BloodPressureEstimator.CalibrationStatus(totalReadings: 9, recentReadings: 2)
        XCTAssertEqual(ContributionSummary.bloodPressure(many).detailLabel,
                       "All 9 readings and calibration detail")

        let none = BloodPressureEstimator.CalibrationStatus(totalReadings: 0, recentReadings: 0)
        XCTAssertEqual(ContributionSummary.bloodPressure(none).detailLabel,
                       "Readings and calibration detail")
    }

    // MARK: - Substances

    /// A log has no target. Grounded means only "there is something here", and
    /// the section must not invent a requirement the model never stated.
    func testALogIsGroundedOnceItHasAnything() {
        XCTAssertFalse(ContributionSummary.substances(logged: 0).isGrounded)
        XCTAssertTrue(ContributionSummary.substances(logged: 1).isGrounded)
        XCTAssertNil(ContributionSummary.substances(logged: 0).progress)
        XCTAssertNil(ContributionSummary.substances(logged: 40).progress)
    }

    func testTheLogFigureAndItsIrregularPlural() {
        XCTAssertEqual(ContributionSummary.substances(logged: 0).figure, "None yet")
        XCTAssertEqual(ContributionSummary.substances(logged: 3).figure, "3 logged")
        XCTAssertTrue(ContributionSummary.substances(logged: 1).guidance
            .hasPrefix("1 entry recorded"))
        XCTAssertTrue(ContributionSummary.substances(logged: 6).guidance
            .hasPrefix("6 entries recorded"))
    }

    /// The privacy sentence is load-bearing on this route and must not be lost
    /// when the inline list of entries goes.
    func testTheLogKeepsSayingItIsPrivate() {
        for count in [0, 1, 12] {
            let guidance = ContributionSummary.substances(logged: count).guidance.lowercased()
            XCTAssertTrue(guidance.contains("private") || guidance.contains("on-device")
                          || guidance.contains("compare"),
                          "route lost its reassurance at \(count) entries")
        }
        XCTAssertTrue(ContributionSummary.substances(logged: 2).guidance
            .contains("no amounts"))
    }

    // MARK: - Symptom tags

    /// The radar's route: grounded once anything is tagged, and a recorded
    /// absence is surfaced as its own count — a real answer, never an
    /// occurrence, which is `SymptomSeverity.isPresent`'s distinction held at
    /// the summary level.
    func testSymptomTagsAreGroundedOnceAnythingIsTagged() {
        let none = ContributionSummary.symptoms(tagged: 0, recordedAbsences: 0)
        XCTAssertFalse(none.isGrounded)
        XCTAssertEqual(none.figure, "None yet")
        XCTAssertNil(none.progress)
        XCTAssertNil(none.detailLabel)

        let some = ContributionSummary.symptoms(tagged: 3, recordedAbsences: 0)
        XCTAssertTrue(some.isGrounded)
        XCTAssertEqual(some.figure, "3 tagged")
        XCTAssertEqual(some.detailLabel, "All 3 symptom entries")

        // Absences alone are history worth seeing but not grounding: the radar
        // grades against having something, and "I did not have this" is a
        // different gift.
        let absences = ContributionSummary.symptoms(tagged: 0, recordedAbsences: 2)
        XCTAssertFalse(absences.isGrounded)
        XCTAssertEqual(absences.figure, "0 tagged · 2 marked absent")
        XCTAssertEqual(absences.detailLabel, "All 2 symptom entries")
    }

    func testSymptomGuidanceSendsTheReaderToAppleHealth() {
        for summary in [ContributionSummary.symptoms(tagged: 0, recordedAbsences: 0),
                        .symptoms(tagged: 4, recordedAbsences: 1)] {
            XCTAssertTrue(summary.guidance.contains("Apple Health"), summary.guidance)
            XCTAssertTrue(summary.guidance.contains("recorded absence"), summary.guidance)
            XCTAssertEqual(summary.addLabel, "Open Apple Health")
        }
    }

    // MARK: - Body measurements

    /// Grounded is a waist, not a full set — `BuildAssessmentModel` moves off BMI
    /// the moment it has one, and a summary that waited for hips and neck would
    /// call a card ungrounded while it was already scoring on the better
    /// instrument.
    func testBodyMeasurementsAreGroundedOnAWaistAlone() {
        let waistOnly = ContributionSummary.bodyMeasurements(
            sitesMeasured: 1, hasWaist: true, lastMeasured: "3 days ago", isOverdue: false)
        XCTAssertTrue(waistOnly.isGrounded)
        XCTAssertEqual(waistOnly.figure, "1 measurement")
        XCTAssertNil(waistOnly.progress)

        // Sites without the one that counts is not grounded, however many there are.
        let noWaist = ContributionSummary.bodyMeasurements(
            sitesMeasured: 4, hasWaist: false, lastMeasured: "3 days ago", isOverdue: false)
        XCTAssertFalse(noWaist.isGrounded)
        XCTAssertEqual(noWaist.figure, "4 measurements")
        XCTAssertTrue(noWaist.guidance.contains("waist"), noWaist.guidance)

        let nothing = ContributionSummary.bodyMeasurements(
            sitesMeasured: 0, hasWaist: false, lastMeasured: nil, isOverdue: false)
        XCTAssertFalse(nothing.isGrounded)
        XCTAssertEqual(nothing.figure, "Nothing measured yet")
        XCTAssertEqual(nothing.addLabel, "Add measurements")
        XCTAssertNil(nothing.detailLabel)
    }

    /// Overdue changes what the sentence asks for without changing the seal —
    /// a stale waist still feeds the score, so it must not be reported as
    /// missing.
    func testAnOverdueMeasurementStillCounts() {
        let overdue = ContributionSummary.bodyMeasurements(
            sitesMeasured: 3, hasWaist: true, lastMeasured: "7 weeks ago", isOverdue: true)
        XCTAssertTrue(overdue.isGrounded)
        XCTAssertTrue(overdue.guidance.contains("7 weeks ago"), overdue.guidance)
        XCTAssertTrue(overdue.guidance.contains("once a month"), overdue.guidance)
        XCTAssertEqual(overdue.addLabel, "Measure again")
        XCTAssertEqual(overdue.detailLabel, "All measurements")

        let fresh = ContributionSummary.bodyMeasurements(
            sitesMeasured: 3, hasWaist: true, lastMeasured: "yesterday", isOverdue: false)
        XCTAssertTrue(fresh.guidance.contains("yesterday"), fresh.guidance)
        XCTAssertFalse(fresh.guidance.contains("once a month"), fresh.guidance)
    }

    // MARK: - Screen time

    /// The one route besides facts and blood pressure with a real target, so it
    /// is the one whose bar can disagree with its seal.
    func testScreenTimeIsGroundedOnlyOnceTheSleepModelCanContrast() throws {
        for days in 0...16 {
            let summary = ContributionSummary.screenTime(
                daysRecorded: days, needed: 14, lastEntered: days == 0 ? nil : "yesterday")
            XCTAssertEqual(summary.isGrounded, days >= 14, "\(days) days")
            if days >= 14 {
                XCTAssertNil(summary.progress, "\(days) days")
            } else {
                XCTAssertEqual(try XCTUnwrap(summary.progress),
                               Double(days) / 14, accuracy: 1e-9, "\(days) days")
            }
        }
    }

    func testScreenTimeSaysWhyItCannotBeReadAutomatically() {
        let none = ContributionSummary.screenTime(daysRecorded: 0, needed: 14, lastEntered: nil)
        XCTAssertEqual(none.figure, "None yet")
        XCTAssertEqual(none.addLabel, "Add a day")
        XCTAssertTrue(none.guidance.contains("Screen Time"), none.guidance)

        let partway = ContributionSummary.screenTime(
            daysRecorded: 5, needed: 14, lastEntered: "yesterday")
        XCTAssertEqual(partway.figure, "5 days")
        XCTAssertTrue(partway.guidance.hasPrefix("5 of 14 days needed"), partway.guidance)

        let one = ContributionSummary.screenTime(
            daysRecorded: 1, needed: 14, lastEntered: "yesterday")
        XCTAssertEqual(one.figure, "1 day")

        let enough = ContributionSummary.screenTime(
            daysRecorded: 30, needed: 14, lastEntered: "today")
        XCTAssertTrue(enough.guidance.contains("last today"), enough.guidance)
        // An association, never a cause — the standing rule for this contrast.
        XCTAssertTrue(enough.guidance.contains("association"), enough.guidance)
        XCTAssertNil(enough.detailLabel)
    }

    // MARK: - Reader identity

    /// A name alone answers the name-in-title question and emails alone answer
    /// the organiser one, so either is grounding on its own.
    func testReaderIdentityIsGroundedOnEitherHalf() {
        let empty = ContributionSummary.readerIdentity(name: nil, emails: 0)
        XCTAssertFalse(empty.isGrounded)
        XCTAssertEqual(empty.figure, "Not set")
        XCTAssertEqual(empty.addLabel, "Add your name & emails")

        // An empty string is not a name — the sheet can hand back "".
        XCTAssertFalse(ContributionSummary.readerIdentity(name: "", emails: 0).isGrounded)
        XCTAssertEqual(ContributionSummary.readerIdentity(name: "", emails: 0).figure, "Not set")

        let named = ContributionSummary.readerIdentity(name: "Alex", emails: 0)
        XCTAssertTrue(named.isGrounded)
        XCTAssertEqual(named.figure, "Alex")

        let emailsOnly = ContributionSummary.readerIdentity(name: nil, emails: 1)
        XCTAssertTrue(emailsOnly.isGrounded)
        XCTAssertEqual(emailsOnly.figure, "1 email")
        XCTAssertEqual(ContributionSummary.readerIdentity(name: "", emails: 3).figure, "3 emails")

        // The reassurance is the reason the reader hands over a name at all.
        for summary in [empty, named, emailsOnly] {
            XCTAssertTrue(summary.guidance.contains("never exported"), summary.guidance)
            XCTAssertNil(summary.progress)
            XCTAssertNil(summary.detailLabel)
        }
    }

    // MARK: - Shape, across every route

    /// The sweeps below claim "across every route". They are only worth that
    /// sentence while this list *is* the set of routes — which is what
    /// `testTheSweepExaminesEveryRouteThatExists` checks against the source,
    /// rather than against whatever was shipped the day this was written.
    ///
    /// Keyed by factory name for exactly that reason: the census compares these
    /// keys to the `public static func` declarations in `ContributionSummary`,
    /// so a new route fails here instead of being silently excluded. (Before
    /// 2026-08-07 this was a bare array and two shipped routes —
    /// `bodyMeasurements` and `screenTime` — appeared in no test in the repo;
    /// `readerIdentity` had joined them by the time it was fixed. The
    /// CardVisibilityTests closed-set lesson, one door over.)
    private static let routes: [(name: String, cases: [ContributionSummary])] = [
        ("facts", [.facts(set: 0, of: 3), .facts(set: 3, of: 3)]),
        ("substances", [.substances(logged: 0), .substances(logged: 5)]),
        ("bloodPressure", [.bloodPressure(.init(totalReadings: 0, recentReadings: 0)),
                           .bloodPressure(.init(totalReadings: 9, recentReadings: 9))]),
        ("medication", [.medication(hasRegimen: false, doses: 0, sideEffects: 0),
                        .medication(hasRegimen: true, doses: 24, sideEffects: 2)]),
        ("bodyType", [.bodyType(estimated: nil, override: nil),
                      .bodyType(estimated: "Mesomorph", override: nil),
                      .bodyType(estimated: "Mesomorph", override: "Endomorph")]),
        ("fileImport", [.fileImport(lastReceived: nil),
                        .fileImport(lastReceived: "yesterday")]),
        ("symptoms", [.symptoms(tagged: 0, recordedAbsences: 0),
                      .symptoms(tagged: 5, recordedAbsences: 2)]),
        ("bodyMeasurements", [
            .bodyMeasurements(sitesMeasured: 0, hasWaist: false,
                              lastMeasured: nil, isOverdue: false),
            .bodyMeasurements(sitesMeasured: 4, hasWaist: false,
                              lastMeasured: "9 weeks ago", isOverdue: true),
            .bodyMeasurements(sitesMeasured: 6, hasWaist: true,
                              lastMeasured: "yesterday", isOverdue: false)]),
        ("screenTime", [.screenTime(daysRecorded: 0, needed: 14, lastEntered: nil),
                        .screenTime(daysRecorded: 5, needed: 14, lastEntered: "yesterday"),
                        .screenTime(daysRecorded: 30, needed: 14, lastEntered: "today")]),
        ("readerIdentity", [.readerIdentity(name: nil, emails: 0),
                            .readerIdentity(name: "", emails: 2),
                            .readerIdentity(name: "Alex", emails: 1)])
    ]

    private var all: [ContributionSummary] { Self.routes.flatMap(\.cases) }

    /// **The set being swept must be the set that exists.**
    ///
    /// Read against the type's own source rather than a second hand-written
    /// list, because a second hand-written list is the defect: `all` covered
    /// seven of ten factories for weeks and all three sweeps below reported
    /// success over the seven.
    func testTheSweepExaminesEveryRouteThatExists() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // InsightKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // InsightKit
            .appendingPathComponent("Sources")
            .appendingPathComponent("InsightKit")
            .appendingPathComponent("Presentation")
            .appendingPathComponent("ContributionSummary.swift")
        // Deliberately a failure and not an XCTSkip: a census that can quietly
        // stop running is the thing it was written to prevent.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "cannot find ContributionSummary.swift at \(source.path) — "
                      + "if the file moved, move this path with it")
        let text = try String(contentsOf: source, encoding: .utf8)

        var declared: Set<String> = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("public static func ") else { continue }
            let rest = trimmed.dropFirst("public static func ".count)
            let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { declared.insert(String(name)) }
        }

        XCTAssertGreaterThanOrEqual(declared.count, 10,
                                    "only found \(declared.count) route factories — the "
                                    + "parse above has stopped matching the source")
        let swept = Set(Self.routes.map(\.name))
        XCTAssertEqual(swept, declared,
                       "a route is not in the sweep: missing \(declared.subtracting(swept)), "
                       + "stale \(swept.subtracting(declared))")
        XCTAssertEqual(Self.routes.count, swept.count, "a route name is listed twice")
    }

    /// Every route has a header figure, a sentence and exactly one prominent way
    /// in — that is the anatomy, and it did not hold before: the grounding-facts
    /// route had no button at all, and its rows were the only way to reach a
    /// value.
    func testEveryRouteOffersAWayIn() {
        for summary in all {
            XCTAssertFalse(summary.addLabel.isEmpty)
            XCTAssertFalse(summary.figure.isEmpty)
            XCTAssertFalse(summary.guidance.isEmpty)
            XCTAssertNotEqual(summary.detailLabel, "")
        }
    }

    func testAGroundedRouteNeverShowsABar() {
        for summary in all where summary.isGrounded {
            XCTAssertNil(summary.progress)
        }
    }

    func testABarIsAlwaysAFraction() {
        for summary in all {
            guard let progress = summary.progress else { continue }
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
        }
    }
}
