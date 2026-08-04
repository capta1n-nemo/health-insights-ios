import XCTest
@testable import InsightKit

/// "Export my data" has to mean *all* of it — including whatever a future
/// connector brings. The old full export carried samples and the unmodelled
/// catalogue only, so the substance log, the medication regimen, its doses, the
/// side effects, the profile facts and every derived score were missing from the
/// one file a reader hands back.
final class HealthDataExportTests: XCTestCase {

    private func bundle(empty: Bool = false) -> HealthDataExport {
        let now = TestClock.now
        var profile = UserHealthProfile()
        profile.set(.init(kind: .totalCholesterol, value: 5.1, recordedAt: now))
        return HealthDataExport(
            generatedAt: now, build: "test",
            samples: empty ? [] : [.init(type: .bodyMass, value: 80, start: now, source: .withings)],
            unmodelled: empty ? [] : [.init(identifier: "oura.x", displayName: "X",
                                            value: 1.0, unit: "", start: now, source: .oura)],
            substances: empty ? [] : [.init(substance: .alcohol, timestamp: now)],
            medication: empty ? nil : .init(
                compound: "tirzepatide", brandName: "Mounjaro", startedOn: now,
                doses: [.init(takenAt: now, milligrams: 12.5, injectionSite: "Left Thigh",
                              isInferred: false, confirmedAt: nil)]),
            sideEffects: empty ? [] : [.init(name: "Nausea", severity: 3, date: now)],
            profile: profile,
            derivedScores: empty ? [] : [.init(
                card: "cardiovascularRisk", title: "Heart Attack & Stroke Risk",
                score: 72, primaryValue: 4.2, headline: "4.2%", confidence: "moderate",
                history: [.init(date: now, score: 72)])])
    }

    /// **Every nested optional survives being nil.**
    ///
    /// The top-level encoder was hand-written so the optional `medication`
    /// would emit an explicit null instead of vanishing, because "takes
    /// nothing" and "the exporter forgot" must be distinguishable. Every
    /// *nested* optional was left on the synthesised encoder, which uses
    /// `encodeIfPresent` — so an unconfirmed dose had no `confirmedAt` key at
    /// all, which is precisely the ambiguity the top-level fix removed.
    ///
    /// The guard that existed could not see it: its one fixture dose left
    /// `confirmedAt` nil and then asserted only on keys the fixture populated.
    /// This one builds a bundle in which **every nested optional is nil** and
    /// insists each key is still there. Canaried by reverting the encoders.
    func testNestedOptionalsAreWrittenAsNullRatherThanOmitted() throws {
        let now = TestClock.now
        let allNil = HealthDataExport(
            generatedAt: now, build: "test",
            samples: [], unmodelled: [], substances: [],
            medication: .init(compound: "tirzepatide", brandName: nil, startedOn: now,
                              doses: [.init(takenAt: now, milligrams: 5, injectionSite: nil,
                                            isInferred: true, confirmedAt: nil)]),
            sideEffects: [], profile: UserHealthProfile(),
            derivedScores: [.init(card: "sleep", title: "Sleep", score: nil,
                                  primaryValue: nil, headline: "No data yet",
                                  confidence: "low", history: [])])
        let json = try XCTUnwrap(String(data: allNil.json(), encoding: .utf8))
        for key in ["confirmedAt", "injectionSite", "brandName", "score", "primaryValue"] {
            XCTAssertTrue(json.contains("\"\(key)\""),
                          "\(key) disappears from the export when nil, so a missing value is indistinguishable from a forgotten field")
        }
    }

    /// A finished regimen is still the reader's data.
    ///
    /// `startMedication` deactivates every prior record and the export read
    /// only the active one, so switching compounds silently dropped the earlier
    /// course and every dose on it.
    func testPreviousRegimensAreExportedAlongsideTheActiveOne() throws {
        let now = TestClock.now
        let past = HealthDataExport.Medication(
            compound: "semaglutide", brandName: "Ozempic",
            startedOn: now.addingTimeInterval(-365 * 86_400),
            doses: [.init(takenAt: now.addingTimeInterval(-300 * 86_400), milligrams: 1.0,
                          injectionSite: nil, isInferred: false, confirmedAt: nil)])
        let export = HealthDataExport(
            generatedAt: now, build: "test", samples: [], unmodelled: [], substances: [],
            medication: nil, previousMedication: [past], sideEffects: [],
            profile: UserHealthProfile(), derivedScores: [])
        let json = try XCTUnwrap(String(data: export.json(), encoding: .utf8))
        XCTAssertTrue(json.contains("semaglutide"),
                      "a regimen the reader has finished is missing from their own export")
        XCTAssertTrue(json.contains("\"previousMedication\""))
    }

    /// The key is present even with no history, so an empty array can never be
    /// mistaken for a field the exporter dropped.
    func testThePreviousMedicationKeyIsPresentWhenThereIsNone() throws {
        let json = try XCTUnwrap(String(data: bundle(empty: true).json(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"previousMedication\""))
    }

    /// **The rule.** Every kind of data the app holds names a key in the export,
    /// and that key is really in the encoded JSON — a switch that merely named
    /// one would still let the payload go out without it.
    func testEveryDataDomainHasAKeyThatIsActuallyInTheJSON() throws {
        let json = try XCTUnwrap(String(data: bundle().json(), encoding: .utf8))
        for domain in DataDomain.allCases {
            let key = HealthDataExport.exportKey(for: domain)
            XCTAssertTrue(json.contains("\"\(key)\""),
                          "\(domain.rawValue) claims the export key \"\(key)\", "
                              + "which is not in the exported JSON")
        }
    }

    /// The things that are not a `DataDomain` but that every number rests on.
    func testTheProfileAndDerivedScoresAreExportedToo() throws {
        let json = try XCTUnwrap(String(data: bundle().json(), encoding: .utf8))
        for key in HealthDataExport.additionalKeys {
            XCTAssertTrue(json.contains("\"\(key)\""), "missing \"\(key)\"")
        }
    }

    /// An empty phone still exports every key, so a reader sharing a fresh
    /// install produces a file with the same shape — "absent" and "empty" have
    /// to be distinguishable by whoever reads it.
    func testAnEmptyBundleStillCarriesEveryKey() throws {
        let json = try XCTUnwrap(String(data: bundle(empty: true).json(), encoding: .utf8))
        for domain in DataDomain.allCases {
            let key = HealthDataExport.exportKey(for: domain)
            XCTAssertTrue(json.contains("\"\(key)\""), "\(key) vanishes when empty")
        }
    }

    /// The distinctions that matter downstream must survive the round trip: an
    /// inferred dose is not a logged one, and a derived score is not a
    /// measurement.
    func testTheInferredFlagAndDerivedScoresSurvive() throws {
        let json = try XCTUnwrap(String(data: bundle().json(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"isInferred\""))
        XCTAssertTrue(json.contains("\"derivedScores\""))
        XCTAssertTrue(json.contains("\"primaryValue\""),
                      "a card's own units — a risk % — are not its 0–100 dial")
        XCTAssertTrue(json.contains("\"schemaVersion\""))
    }
}
