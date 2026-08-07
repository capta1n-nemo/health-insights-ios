import XCTest
@testable import InsightKit

/// Roadmap #18. Four different answers to "what age does this body look like",
/// each on a different card, with no way to see that they disagree.
///
/// The competitive scan is the reason this is worth building and the reason it
/// is built this way: Whoop sells a "WHOOP Age", Oura prints a cardiovascular
/// age, and **neither publishes what its number is worth**. These pin the two
/// rules that make the difference — relay rather than merge, and print the
/// error or say plainly that there isn't one.
final class AgeComparisonTests: XCTestCase {

    private let now = TestClock.now

    private func vascularSamples(_ value: Double) -> [HealthMetricSample] {
        (0..<20).map { day in
            HealthMetricSample(type: .vascularAge, value: value,
                               start: now.addingTimeInterval(-Double(day) * 86_400),
                               source: .oura)
        }
    }

    // MARK: - Relay, never merge

    /// **The rule the whole section rests on.** Averaging four estimates into
    /// one house number invents a precision none of them has, so every estimate
    /// stays its own row and names whoever computed it.
    func testEveryEstimateNamesWhoComputedIt() {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 46, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male,
            samples: vascularSamples(32), now: now, calendar: TestClock.utc)

        XCTAssertGreaterThanOrEqual(estimates.count, 3)
        for estimate in estimates {
            XCTAssertFalse(estimate.attribution.isEmpty,
                           "\(estimate.label) was reported with nobody's name on it")
        }
        // The vendor's number carries the vendor's name, not the app's.
        let vascular = estimates.first { $0.label == "Vascular age" }
        XCTAssertEqual(vascular?.attribution, "Oura")
        XCTAssertEqual(vascular?.years, 32)
    }

    /// ⚠️ **A relayed number must not read as the app's own.** Oura publishes a
    /// cardiovascular age with no error at all, and saying that plainly is the
    /// most useful sentence available about it.
    func testAVendorNumberWithNoPublishedErrorSaysSo() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: vascularSamples(32), now: now, calendar: TestClock.utc)
        let vascular = try XCTUnwrap(estimates.first { $0.label == "Vascular age" })

        XCTAssertNil(vascular.uncertainty.years,
                     "an error was invented for a number the vendor publishes bare")
        XCTAssertTrue(vascular.uncertainty.note.contains("without an error"))
        XCTAssertTrue(vascular.uncertainty.note.contains("Oura"))
    }

    // MARK: - The errors, which are derived rather than cited

    /// The app's own fitness age carries an error it can actually justify: the
    /// norm table it inverts moves a known number of years per mL/kg·min, so a
    /// VO₂max error converts straight into an age error.
    func testTheFitnessAgeErrorIsDerivedFromTheTableItInverts() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 46, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male, samples: [], now: now, calendar: TestClock.utc)
        let fitness = try XCTUnwrap(estimates.first { $0.label == "Fitness age" })
        let years = try XCTUnwrap(fitness.uncertainty.years)

        // The male table runs 48 → 32 mL/kg·min across 25 → 65 years: 2.5 years
        // per unit, so a ±3.5 VO₂max is roughly ±9 years.
        XCTAssertEqual(AgeComparison.vo2YearsPerUnit(sex: .male), 2.5, accuracy: 0.01)
        XCTAssertEqual(years, 9, accuracy: 0.5)
        XCTAssertTrue(fitness.uncertainty.note.contains("mL/kg·min"),
                      "the error was printed without saying where it came from")
    }

    /// ⚠️ **An honest "we cannot say" beats an invented number.** Where only one
    /// risk equation covers the reader's age there is nothing to measure the
    /// heart age against, and the section says that rather than printing a
    /// figure with no basis.
    func testAnUnmeasurableErrorIsStatedAsUnmeasurableRatherThanGuessed() {
        let single = HeartAgeModel.Output(
            chronologicalAge: 40,
            readings: [.init(engine: .score2, heartAge: 48, excessYears: 8,
                             isCapped: false, riskPercent: 4, optimalRiskPercent: 2)])
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: single, sex: .male,
            samples: [], now: now, calendar: TestClock.utc)
        let heart = estimates.first { $0.label == "Heart age" }

        XCTAssertNil(heart?.uncertainty.years)
        XCTAssertTrue(heart?.uncertainty.note.contains("nothing to measure") ?? false)
    }

    // MARK: - The finding

    /// **When they disagree by more than their errors allow, that is the
    /// finding** — and it is more useful than any single number here, because it
    /// tells the reader how much to trust the idea of a biological age at all.
    func testAWideDisagreementIsReportedAsTheFinding() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 55, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male,
            samples: vascularSamples(62), now: now, calendar: TestClock.utc)
        let text = try XCTUnwrap(AgeComparison.disagreement(estimates))

        XCTAssertTrue(text.contains("disagree"))
        XCTAssertTrue(text.lowercased().contains("biological age"),
                      "the finding did not say what the disagreement means")
    }

    /// And two estimates inside their own error bars are **not** disagreeing —
    /// they are the same answer measured twice. Saying otherwise would make the
    /// loudest sentence on the section the one that fires most often.
    func testEstimatesInsideTheirOwnErrorAreNotCalledADisagreement() {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 44, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male,
            samples: vascularSamples(43), now: now, calendar: TestClock.utc)
        XCTAssertNil(AgeComparison.disagreement(estimates))
    }

    /// Your real age is not an estimate and must never widen the spread.
    func testYourRealAgeIsNotCountedAsAnEstimate() throws {
        let estimates = AgeComparison.estimates(
            chronological: 20,
            fitness: FitnessAgeModel.evaluate(vo2: 40, sex: .male, chronologicalAge: 20),
            heart: nil, sex: .male,
            samples: vascularSamples(45), now: now, calendar: TestClock.utc)
        let spread = try XCTUnwrap(AgeComparison.spread(estimates))
        let guesses = estimates.filter { $0.label != "Your age" }.map(\.years)
        let expected = try XCTUnwrap(guesses.max()) - (try XCTUnwrap(guesses.min()))
        XCTAssertEqual(spread, expected, accuracy: 0.001)
    }
}

/// **Every age estimate from every source, plus this app's own** — the reader's
/// request, 2026-08-06: *"I wanted it to take all the age estimates from all the
/// sources, and also build our own age estimate."*
///
/// Both halves of that turned out to be missing, and the first was a defect
/// rather than an omission.
final class AgeComparisonAllSourcesTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// A vascular age from each of two devices, as a reader with both would have.
    private func twoVendors() -> [HealthMetricSample] {
        (0..<20).flatMap { day -> [HealthMetricSample] in
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            return [
                HealthMetricSample(type: .vascularAge, value: 34, start: date,
                                   end: date, source: .oura),
                HealthMetricSample(type: .vascularAge, value: 47, start: date,
                                   end: date, source: .withings),
            ]
        }
    }

    /// ⚠️ **The defect.** The section relayed vascular age through
    /// `VitalReader.reading`, which picks ONE instrument by freshness and
    /// history and never blends. That is right for a vital — a chart of "your
    /// resting heart rate" must be one device's series — and exactly wrong here,
    /// because **the subject of this section is that instruments disagree**. A
    /// reader with two vascular ages saw one of them, on the one screen built to
    /// show the difference.
    func testEveryVendorGetsItsOwnRowRatherThanOneWinning() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: twoVendors(), now: now, calendar: utc)

        let vascular = estimates.filter { $0.label.hasPrefix("Vascular age") }
        XCTAssertEqual(vascular.count, 2,
                       "one vendor won and the other was never mentioned")
        let attributions = Set(vascular.map(\.attribution))
        XCTAssertEqual(attributions.count, 2, "both rows must name their own device")
        // And each row is labelled by device, so two "Vascular age" rows are
        // not indistinguishable.
        XCTAssertEqual(Set(vascular.map(\.label)).count, 2)
    }

    /// With one vendor the label stays plain — a device suffix on a single row
    /// is noise, and this is the state most readers are in.
    func testASingleVendorKeepsThePlainLabel() throws {
        let single = (0..<20).map { day in
            HealthMetricSample(type: .vascularAge, value: 34,
                               start: now.addingTimeInterval(-Double(day) * 86_400),
                               source: .oura)
        }
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: single, now: now, calendar: utc)
        XCTAssertEqual(estimates.filter { $0.label == "Vascular age" }.count, 1)
    }

    /// **This app's own biological age joins the list**, and it is the only row
    /// whose error was derived rather than assumed or absent.
    func testOurOwnBiologicalAgeAppearsWithADerivedError() throws {
        var profile = UserHealthProfile()
        let dob = now.addingTimeInterval(-45 * 365.2425 * 86_400)
        profile.set(.init(kind: .dateOfBirth, value: dob.timeIntervalSince1970, recordedAt: now))
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))

        var samples: [HealthMetricSample] = []
        for metric in [MetricType.vo2Max, .heartRateVariabilityRMSSD,
                       .bloodPressureSystolic, .bodyFatPercentage] {
            guard let value = BiologicalAgeModel.expected(metric, age: 45, sex: .male)
            else { continue }
            samples += (0..<200).map { day in
                let date = now.addingTimeInterval(-Double(day) * 86_400)
                return HealthMetricSample(type: metric, value: value, start: date,
                                          end: date, source: .appleHealth)
            }
        }
        let biological = try XCTUnwrap(BiologicalAgeModel.evaluate(
            samples: samples, profile: profile, now: now, calendar: utc))

        let estimates = AgeComparison.estimates(
            chronological: 45, fitness: nil, heart: nil, sex: .male,
            samples: samples, biological: biological, now: now, calendar: utc)

        let ours = try XCTUnwrap(estimates.first { $0.label == "Biological age" })
        XCTAssertTrue(ours.attribution.hasPrefix("This app"), ours.attribution)
        guard case .derived = ours.uncertainty else {
            return XCTFail("our own estimate must carry a derived error, got \(ours.uncertainty)")
        }
        XCTAssertNotNil(ours.uncertainty.years)
    }

    /// ⚠️ **Relay, never merge — still.** Adding rows must not add a combined
    /// one: averaging several ages into a house number invents a precision none
    /// of them has, and it is the rule the whole section rests on.
    func testNothingIsMergedIntoAConsensusRow() {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: twoVendors(), now: now, calendar: utc)
        for banned in ["consensus", "combined", "average", "overall", "blended"] {
            XCTAssertFalse(estimates.contains { $0.label.lowercased().contains(banned) },
                           "a merged row appeared: \(banned)")
        }
        // Two vendors 13 years apart must still read as a disagreement rather
        // than being quietly reconciled.
        XCTAssertEqual(AgeComparison.spread(estimates) ?? 0, 13, accuracy: 0.001)
    }
}

/// **Backlog D21 — "all the sources" was two-thirds true.**
///
/// The vascular row stopped picking a winner on 2026-08-06. The app's *own* two
/// ages did not: both arrived here already collapsed to one instrument by
/// `VitalReader.reading` inside `HeartAgeAnalyser`, and the reader's export
/// carries **four VO₂max source ids and four systolic ones**.
///
/// That is the section committing the exact offence it exists to expose — a
/// screen whose subject is that instruments disagree, manufacturing agreement by
/// silently choosing one. It matters numerically as well as in principle: two
/// wrist VO₂max estimates differing by 6 mL/kg·min are fifteen years of fitness
/// age apart, which is wider than the ±9 the row prints.
final class AgeComparisonAppOwnSourcesTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func samples(_ metric: MetricType,
                         _ readings: [(MetricSource, Double)],
                         days: Int = 20) -> [HealthMetricSample] {
        (0..<days).flatMap { day -> [HealthMetricSample] in
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            return readings.map {
                HealthMetricSample(type: metric, value: $0.1, start: date, end: date,
                                   source: $0.0)
            }
        }
    }

    private func subject(systolic: Double = 130) -> HeartAgeModel.Subject {
        HeartAgeModel.Subject(sex: .male, race: .whiteOrOther, region: .low,
                              systolicBP: systolic, totalCholesterolMmol: 5.2,
                              hdlCholesterolMmol: 1.3, isSmoker: false,
                              hasDiabetes: false, treatedForBP: false)
    }

    // MARK: - Fitness age

    /// ⚠️ **The defect.** One VO₂max won and the other three were never
    /// mentioned, on the one screen built to show the difference.
    func testEveryVO2MaxSourceGetsItsOwnFitnessAge() throws {
        let estimates = AgeComparison.estimates(
            chronological: 50, fitness: nil, heart: nil, sex: .male,
            samples: samples(.vo2Max, [(.appleHealth, 46), (.oura, 38)]),
            now: now, calendar: utc)

        let rows = estimates.filter { $0.label.hasPrefix("Fitness age") }
        XCTAssertEqual(rows.count, 2, "one instrument won and the other vanished")
        XCTAssertEqual(Set(rows.map(\.label)).count, 2, "both rows must name their own device")
        XCTAssertEqual(Set(rows.map(\.id)).count, 2, "duplicate ids drop a row in SwiftUI")
        // Still the app's own estimate — the strip tints these apart from a
        // relayed vendor number on exactly this prefix.
        for row in rows {
            XCTAssertTrue(row.attribution.hasPrefix("This app"), row.attribution)
        }
        // And they genuinely disagree by more than the row's own stated error,
        // which is the whole reason hiding one was a defect rather than tidiness.
        let years = rows.map(\.years)
        let stated = try XCTUnwrap(rows.first?.uncertainty.years)
        XCTAssertGreaterThan(try XCTUnwrap(years.max()) - (try XCTUnwrap(years.min())),
                             stated)
    }

    /// With one instrument the label stays plain — a device suffix on a single
    /// row is noise, and this is the state most readers are in.
    func testASingleVO2MaxSourceKeepsThePlainLabel() {
        let estimates = AgeComparison.estimates(
            chronological: 50, fitness: nil, heart: nil, sex: .male,
            samples: samples(.vo2Max, [(.appleHealth, 46)]), now: now, calendar: utc)
        XCTAssertEqual(estimates.filter { $0.label == "Fitness age" }.count, 1)
    }

    /// **The app's own rows carry a date now too.** A fitness age built from a
    /// VO₂max nobody has refreshed since last winter sits beside one from last
    /// week; without the date the gap between them reads as physiology when it
    /// is partly just time.
    func testAnAppRowFromAQuietInstrumentSaysHowOldItIs() throws {
        let stale = (0..<10).map { day -> HealthMetricSample in
            let date = now.addingTimeInterval(-Double(300 + day) * 86_400)
            return HealthMetricSample(type: .vo2Max, value: 38, start: date, end: date,
                                      source: .oura)
        }
        let estimates = AgeComparison.estimates(
            chronological: 50, fitness: nil, heart: nil, sex: .male,
            samples: stale, now: now, calendar: utc)
        let row = try XCTUnwrap(estimates.first { $0.label.hasPrefix("Fitness age") })
        XCTAssertNotNil(row.staleness(now: now),
                        "a ten-month-old reading was presented as current")
    }

    // MARK: - Heart age

    /// The same defect on the other half: four systolic sources, one row.
    ///
    /// Only the blood pressure varies between these rows. Cholesterol, smoking
    /// and diabetes are facts about the person rather than readings off a
    /// device, so holding them fixed is what makes the spread here attributable
    /// to the instruments.
    func testEverySystolicSourceGetsItsOwnHeartAge() {
        let estimates = AgeComparison.estimates(
            chronological: 55, fitness: nil, heart: nil, sex: .male,
            samples: samples(.bloodPressureSystolic,
                             [(.manual, 118), (.withings, 148)]),
            heartSubject: subject(), now: now, calendar: utc)

        let rows = estimates.filter { $0.label.hasPrefix("Heart age") }
        XCTAssertEqual(rows.count, 2, "one cuff won and the other was never mentioned")
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
        // The higher pressure must produce the older heart — otherwise the rows
        // are not actually being solved from their own instrument's number.
        let byLabel = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0.years) })
        let low = try? XCTUnwrap(byLabel.first { $0.key.contains("Manual") }?.value)
        let high = try? XCTUnwrap(byLabel.first { $0.key.contains("Withings") }?.value)
        XCTAssertLessThan(low ?? 0, high ?? 0)
    }

    /// **The reader's own cuff needs no special case.** `DataStore` mirrors every
    /// entered cuff reading into a `.bloodPressureSystolic` sample under
    /// `MetricSource.manual`, so the per-source breakdown already carries it —
    /// and a hand-written "the reading you entered" row would have printed it
    /// twice, which on a section about disagreement reads as two instruments
    /// agreeing perfectly.
    func testTheEnteredCuffIsOneSourceAndNotTwoRows() {
        let estimates = AgeComparison.estimates(
            chronological: 55, fitness: nil, heart: nil, sex: .male,
            samples: samples(.bloodPressureSystolic, [(.manual, 130)]),
            heartSubject: subject(), now: now, calendar: utc)
        XCTAssertEqual(estimates.filter { $0.label.hasPrefix("Heart age") }.count, 1)
    }

    /// A caller with no subject to re-solve from still gets its row rather than
    /// losing it — the fallback that keeps this change from being a regression
    /// for anything that computed an age elsewhere.
    func testACallerWithNoSubjectKeepsTheSingleRowItPassedIn() throws {
        let output = try XCTUnwrap(HeartAgeModel.evaluate(subject: subject(systolic: 150),
                                                          age: 55))
        let estimates = AgeComparison.estimates(
            chronological: 55, fitness: nil, heart: output, sex: .male,
            samples: [], now: now, calendar: utc)
        XCTAssertEqual(estimates.filter { $0.label == "Heart age" }.count, 1)
    }

    /// ⚠️ **Relay, never merge — still.** More rows must not become a house
    /// average, and the widened spread has to survive into the finding.
    func testMoreRowsStillNeverProduceAConsensusRow() {
        let estimates = AgeComparison.estimates(
            chronological: 50, fitness: nil, heart: nil, sex: .male,
            samples: samples(.vo2Max, [(.appleHealth, 46), (.oura, 38)]),
            now: now, calendar: utc)
        for banned in ["consensus", "combined", "average", "overall", "blended"] {
            XCTAssertFalse(estimates.contains { $0.label.lowercased().contains(banned) },
                           "a merged row appeared: \(banned)")
        }
    }
}

/// The two defects the scouting pass found in the multi-source change itself.
///
/// Both are about the same trade: the old code **filtered** relayed readings on
/// freshness and the new code carries their **date** instead. Filtering hid a
/// real estimate; not filtering would have presented a year-old one as current.
final class AgeComparisonFreshnessTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func vascular(daysAgo: Int, source: MetricSource = .oura) -> [HealthMetricSample] {
        (0..<10).map { offset in
            let date = now.addingTimeInterval(-Double(daysAgo + offset) * 86_400)
            return HealthMetricSample(type: .vascularAge, value: 34, start: date,
                                      end: date, source: source)
        }
    }

    /// ⚠️ **The live defect.** The vendor row was read through
    /// `VitalReader.reading`, whose default window is 36 hours — so a reader
    /// whose ring had not synced since yesterday lost the only non-app estimate
    /// on the section, while the card above it went on printing the same
    /// vendor's number from a sixty-day window. Two windows, one card, one
    /// number.
    func testAVendorRowSurvivesARingThatHasNotSyncedSinceYesterday() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: vascular(daysAgo: 4), now: now, calendar: utc)
        XCTAssertTrue(estimates.contains { $0.label.hasPrefix("Vascular age") },
                      "a four-day-old vendor reading vanished from the section")
    }

    /// And the opposite fault, which dropping the filter would have introduced:
    /// `latest` is the newest raw sample with no window at all, so a device that
    /// stopped a year ago would read as current. It is shown **with its age**.
    func testAVendorRowThatStoppedAYearAgoSaysSoRatherThanReadingAsCurrent() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: vascular(daysAgo: 400), now: now, calendar: utc)
        let row = try XCTUnwrap(estimates.first { $0.label.hasPrefix("Vascular age") })
        let stale = try XCTUnwrap(row.staleness(now: now),
                                  "a year-old reading was presented as current")
        XCTAssertTrue(stale.lowercased().contains("year"), stale)
    }

    /// A recent reading says nothing — the note is a finding, not decoration.
    func testAFreshVendorRowCarriesNoStalenessNote() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: vascular(daysAgo: 1), now: now, calendar: utc)
        let row = try XCTUnwrap(estimates.first { $0.label.hasPrefix("Vascular age") })
        XCTAssertNil(row.staleness(now: now))
    }

    /// ⚠️ **Two devices with the same display name must not collide.** `id` was
    /// `label`, which is fine while every row is a different kind of age and
    /// breaks the moment two devices report the same kind — SwiftUI silently
    /// drops a duplicate id, losing exactly the row this work exists to add.
    func testTwoSourcesSharingADisplayNameKeepDistinctIdentities() {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: vascular(daysAgo: 1, source: .oura)
                + vascular(daysAgo: 2, source: .withings),
            now: now, calendar: utc)
        let ids = estimates.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "two rows shared an id and one would be dropped")
    }
}
