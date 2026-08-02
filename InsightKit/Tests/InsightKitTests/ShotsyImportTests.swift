import XCTest
@testable import InsightKit

/// Every fixture here is copied from the shape of the user's own Shotsy export
/// (version 2, 144 days, 21 shots), because the format is not what a
/// description of it would suggest and the units are actively hostile.
final class ShotsyImportTests: XCTestCase {

    private func payload(days: String = "[]", schedules: String = "[]") -> Data {
        Data("""
        {"exportDate":1785661508,"exportVersion":2,
         "days":\(days),"schedules":\(schedules),
         "medicationTypeInjectionSiteRotation":[]}
        """.utf8)
    }

    // MARK: - Recognising the file

    func testARandomJSONFileIsRefused() {
        XCTAssertThrowsError(try ShotsyImport.parse(Data(#"{"hello":"world"}"#.utf8))) {
            XCTAssertEqual($0 as? ShotsyImport.Failure, .notAShotsyExport)
        }
    }

    func testSomethingThatIsNotJSONIsRefused() {
        XCTAssertThrowsError(try ShotsyImport.parse(Data("not json".utf8))) {
            XCTAssertEqual($0 as? ShotsyImport.Failure, .notJSON)
        }
    }

    func testTheExportStampIsRead() throws {
        let result = try ShotsyImport.parse(payload())
        XCTAssertEqual(result.exportVersion, 2)
        XCTAssertEqual(result.exportedAt, Date(timeIntervalSince1970: 1_785_661_508))
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Shots

    private let oneShotDay = """
    [{"1771232400":{"shots":[{
      "id":"9FAE4A21-5445-422A-B4CF-2F6D55A94817",
      "dosageID":"A6834B3E-DA61-6E0B-25BC-0A824268E840",
      "medicationName":"Mounjaro","painLevel":1,"dosageStrength":2.5,
      "taken":true,"medicationID":"30000000-0000-0000-0002-000000000000",
      "deliveryMethod":"injection","injectionSite":"Stomach - Lower Right",
      "timestamp":1771232400,
      "injectionSiteID":"20000000-0000-0000-0000-000000000006"}]}}]
    """

    func testAShotIsReadWholeFromInsideItsDay() throws {
        let result = try ShotsyImport.parse(payload(days: oneShotDay))
        XCTAssertEqual(result.doses.count, 1)
        let dose = try XCTUnwrap(result.doses.first)
        XCTAssertEqual(dose.milligrams, 2.5)
        XCTAssertEqual(dose.medicationName, "Mounjaro")
        XCTAssertEqual(dose.injectionSite, "Stomach - Lower Right")
        XCTAssertEqual(dose.painLevel, 1)
        XCTAssertTrue(dose.wasTaken)
        XCTAssertEqual(dose.takenAt, Date(timeIntervalSince1970: 1_771_232_400))
    }

    /// A backup is a set, not a stream. Sharing the same export twice must not
    /// produce two injections.
    func testTheSameShotTwiceIsOneInjection() throws {
        let twice = "[\(oneShotDay.dropFirst().dropLast()),\(oneShotDay.dropFirst().dropLast())]"
        let result = try ShotsyImport.parse(payload(days: twice))
        XCTAssertEqual(result.doses.count, 1)
    }

    /// Shotsy stores planned shots alongside taken ones, and a missing flag
    /// means taken — reading it the other way silently drops real injections.
    func testAMissingTakenFlagCountsAsTaken() throws {
        let days = """
        [{"1771232400":{"shots":[{"id":"A","dosageStrength":5,"timestamp":1771232400}]}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertTrue(try XCTUnwrap(result.doses.first).wasTaken)
    }

    // MARK: - The units, which are the whole risk

    /// **Body fat arrives in parts per million.** 331890.03 is 33.19 %, and
    /// imported raw it would render as a body fat of three hundred thousand
    /// percent.
    func testBodyFatIsConvertedFromPartsPerMillion() throws {
        let days = """
        [{"1767156643":{"Body Fat":{"value":331890.02990722656,"unit":"ppm",
          "date":"2025-12-31T04:50:43Z","id":"CA4B3725","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        let sample = try XCTUnwrap(result.samples.first { $0.type == .bodyFatPercentage })
        XCTAssertEqual(sample.value, 33.189, accuracy: 0.01)
    }

    /// The declared unit is the authority, not the kind — so a future export
    /// that switches to percent is not divided by ten thousand.
    func testADeclaredPercentIsTakenAtFaceValue() throws {
        let days = """
        [{"1767156643":{"Body Fat":{"value":33.19,"unit":"%",
          "date":"2025-12-31T04:50:43Z","id":"X","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(try XCTUnwrap(result.samples.first).value, 33.19, accuracy: 0.001)
    }

    /// A unitless fraction is the other honest reading, and magnitude tells
    /// them apart: nobody is 0.33 % fat.
    func testAUnitlessFractionIsReadAsAFraction() throws {
        let days = """
        [{"1767156643":{"Body Fat":{"value":0.33,
          "date":"2025-12-31T04:50:43Z","id":"X","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(try XCTUnwrap(result.samples.first).value, 33, accuracy: 0.001)
    }

    func testWeightAndLeanMassComeThroughInKilograms() throws {
        let days = """
        [{"1755784800":{
          "Weight":{"value":122.66,"unit":"kg","date":"2025-08-22T09:53:01Z","id":"W","source":"health-kit"},
          "Lean Mass":{"value":82.71,"unit":"kg","date":"2025-08-22T09:53:01Z","id":"L","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(try XCTUnwrap(result.samples.first { $0.type == .bodyMass }).value,
                       122.66, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(result.samples.first { $0.type == .leanBodyMass }).value,
                       82.71, accuracy: 0.01)
    }

    /// Exercise arrives in seconds; this app's metric is minutes.
    func testExerciseIsConvertedFromSeconds() throws {
        let days = """
        [{"1762426740":{"Exercise":{"value":1800,"unit":"s",
          "date":"2025-11-06T10:59:00Z","id":"E","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(try XCTUnwrap(result.samples.first).value, 30, accuracy: 0.001)
    }

    /// Nutrition is in the file and has no home yet. It must be reported as
    /// unmapped rather than dropped silently — the TDEE module is blocked on
    /// exactly this data.
    func testNutritionIsReportedAsUnmappedRatherThanDiscarded() throws {
        let days = """
        [{"1771232400":{
          "Calories":{"value":5460872.83,"unit":"J","date":"2026-02-17T09:14:00Z","id":"C","source":"health-kit"},
          "Protein":{"value":0.0438,"unit":"kg","date":"2026-02-17T09:14:00Z","id":"P","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertTrue(result.samples.isEmpty)
        XCTAssertEqual(result.unmappedKinds, ["Calories", "Protein"])
        // And the conversions are written down for when they do get a home.
        XCTAssertNotNil(ShotsyUnit.pendingNutritionKinds["Calories"])
        XCTAssertEqual(5_460_872.83 * ShotsyUnit.joulesToKilocalories, 1305, accuracy: 1)
        XCTAssertEqual(0.0438 * ShotsyUnit.kilogramsToGrams, 43.8, accuracy: 0.1)
    }

    // MARK: - Schedule and side effects

    func testTheLiveScheduleIsTheMostRecentlyStarted() throws {
        let schedules = """
        [{"recurrenceDays":7,"medicationName":"Mounjaro","startDate":1785146400,
          "dosageStrength":12.5,"deliveryMethod":"injection","id":"A","source":"user"},
         {"recurrenceDays":7,"medicationName":"Mounjaro","startDate":1770000000,
          "dosageStrength":7.5,"deliveryMethod":"injection","id":"B","source":"user"}]
        """
        let result = try ShotsyImport.parse(payload(schedules: schedules))
        let schedule = try XCTUnwrap(result.schedule)
        XCTAssertEqual(schedule.milligrams, 12.5, "the newer schedule is the live one")
        XCTAssertEqual(schedule.everyDays, 7)
    }

    func testSideEffectsAreReadOnceRatherThanTwice() throws {
        // The file carries both `sideEffectRecords` and a lossier `sideEffects`
        // summary of the same facts. Merging both would double every one.
        let days = """
        [{"1772928000":{
          "sideEffectRecords":[{"id":"S","sideEffectID":"10000000","name":"Fatigue",
            "severity":7,"date":"2026-03-08T01:00:00Z"}],
          "sideEffects":{"Fatigue":7}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(result.sideEffects.count, 1)
        let effect = try XCTUnwrap(result.sideEffects.first)
        XCTAssertEqual(effect.name, "Fatigue")
        XCTAssertEqual(effect.severity, 7)
    }

    // MARK: - Hygiene

    func testDecimalCommasAndStringNumbersSurvive() {
        XCTAssertEqual(ShotsyImport.numeric("2,5"), 2.5)
        XCTAssertEqual(ShotsyImport.numeric("12.5"), 12.5)
        XCTAssertEqual(ShotsyImport.numeric(7), 7)
        XCTAssertNil(ShotsyImport.numeric("not a number"))
    }

    func testInjectionSitesAreTrimmedAndEmptyOnesDropped() {
        XCTAssertEqual(ShotsyImport.cleanedSite("  Stomach - Lower Right "),
                       "Stomach - Lower Right")
        XCTAssertNil(ShotsyImport.cleanedSite("   "))
        XCTAssertNil(ShotsyImport.cleanedSite(nil))
    }

    func testBothISOVariantsParse() {
        XCTAssertNotNil(ShotsyImport.isoDate("2025-08-22T09:53:01Z"))
        XCTAssertNotNil(ShotsyImport.isoDate("2025-08-22T09:53:01.271Z"))
        XCTAssertNil(ShotsyImport.isoDate("22/08/2025"))
    }

    /// A malformed row must cost that row and nothing else — an import of 144
    /// days should not be lost to one bad entry.
    func testOneBadRowDoesNotLoseTheImport() throws {
        let days = """
        [{"1771232400":{"shots":[
           {"id":"good","dosageStrength":5,"timestamp":1771232400},
           {"medicationName":"missing everything"}]}},
         {"1755784800":{"Weight":{"value":"nonsense","unit":"kg",
           "date":"2025-08-22T09:53:01Z","id":"W","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(result.doses.count, 1)
        XCTAssertTrue(result.samples.isEmpty)
    }

    func testEverythingComesBackInTimeOrder() throws {
        let days = """
        [{"2":{"shots":[{"id":"late","dosageStrength":5,"timestamp":2000}]}},
         {"1":{"shots":[{"id":"early","dosageStrength":5,"timestamp":1000}]}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(result.doses.map(\.id), ["early", "late"])
    }

    /// Imported readings carry their own source, so a reader can see which
    /// weigh-ins came from the tracker and `MultiSource` keeps them separate.
    func testImportedSamplesAreAttributedToShotsy() throws {
        let days = """
        [{"1755784800":{"Weight":{"value":122.66,"unit":"kg",
          "date":"2025-08-22T09:53:01Z","id":"W","source":"health-kit"}}}]
        """
        let result = try ShotsyImport.parse(payload(days: days))
        XCTAssertEqual(try XCTUnwrap(result.samples.first).source.id, MetricSource.shotsy.id)
    }
}
