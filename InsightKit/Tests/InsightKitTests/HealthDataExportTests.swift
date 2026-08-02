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
