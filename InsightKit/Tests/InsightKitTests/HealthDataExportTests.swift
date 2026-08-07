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

    // MARK: - Populated, not merely present

    /// Everything the app can hold, all at once — the fixture the check below
    /// needs, because "the key is in the JSON" is satisfied by `[]`.
    private func fullyPopulated() -> HealthDataExport {
        let now = TestClock.now
        var profile = UserHealthProfile()
        profile.set(.init(kind: .totalCholesterol, value: 5.1, recordedAt: now))

        var store = DerivedSeriesStore()
        let spec = DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "fitnessAge"),
                                     displayName: "Fitness age", unit: "years",
                                     producedBy: .fitness, kind: .modelOutput,
                                     higherIsBetter: false, precision: 1)
        store.record(spec, value: 33.5, on: now)
        store.record(spec, value: 33.2, on: now.addingTimeInterval(-86_400))

        return HealthDataExport(
            generatedAt: now, build: "test",
            samples: [.init(type: .bodyMass, value: 80, start: now, source: .withings)],
            unmodelled: [.init(identifier: "oura.x", displayName: "X", value: 1.0,
                               unit: "", start: now, source: .oura)],
            substances: [.init(substance: .alcohol, timestamp: now)],
            medication: .init(compound: "tirzepatide", brandName: "Mounjaro", startedOn: now,
                              doses: [.init(takenAt: now, milligrams: 12.5,
                                            injectionSite: "Left Thigh",
                                            isInferred: false, confirmedAt: nil)]),
            previousMedication: [.init(compound: "semaglutide", brandName: "Ozempic",
                                       startedOn: now.addingTimeInterval(-365 * 86_400),
                                       doses: [])],
            sideEffects: [.init(name: "Nausea", severity: 3, date: now)],
            symptoms: [.init(type: .headache, severity: .moderate, date: now,
                             source: .appleHealth)],
            bodyScans: [.init(id: UUID(), capturedAt: now, mode: .tape, parserVersion: 1,
                              measurements: BodyMeasurements([.init(site: .waist,
                                                                    centimetres: 88)]),
                              conditions: ScanConditions(clothing: .formFitting),
                              retainedAssets: [])],
            profile: profile,
            derivedScores: [.init(card: "cardiovascularRisk", title: "Heart Attack & Stroke Risk",
                                  score: 72, primaryValue: 4.2, headline: "4.2%",
                                  confidence: "moderate", history: [.init(date: now, score: 72)])],
            cycles: [CycleDay(day: now, flow: .medium)],
            holidays: [.init(firstDay: now, lastDay: now.addingTimeInterval(6 * 86_400),
                             label: "Leave", source: "entered")],
            generatedInsights: HealthDataExport.derivedSeries(from: store))
    }

    /// **The check the D39 defect asked for.** `testEveryDataDomainHasAKeyThat
    /// IsActuallyInTheJSON` proves a domain *names* a key that exists; an empty
    /// array satisfies it, which is how logged bleeding days exported as `[]`
    /// for a day without a single test noticing. This one decodes the payload
    /// and insists the key carries something on a phone that holds everything.
    ///
    /// ⚠️ **It cannot speak for `calendarEvents`**, which deliberately shares
    /// the `unmodelled` key and emits nothing — event titles are the most
    /// identifying strings this app holds. The calendar reaches the file through
    /// `holidays` (dates only) and through `generatedInsights` (the quantities
    /// its cards derive), and both of those *are* checked here.
    ///
    /// ⚠️ **It still cannot see the caller.** The gap D39 lived in is a
    /// defaulted argument the app target forgot to pass, and the app target has
    /// no test host. `scripts/verify.sh` holds that half.
    func testEveryDataDomainsKeyIsPopulatedOnAFullyPopulatedExport() throws {
        let object = try JSONSerialization.jsonObject(with: fullyPopulated().json())
        let payload = try XCTUnwrap(object as? [String: Any])

        for domain in DataDomain.allCases {
            let key = HealthDataExport.exportKey(for: domain)
            let value = try XCTUnwrap(payload[key], "\(domain.rawValue) names missing key \"\(key)\"")
            if let array = value as? [Any] {
                XCTAssertFalse(array.isEmpty,
                               "\(domain.rawValue) exports \"\(key)\": [] on a phone that holds "
                                   + "one of everything — the key is present and the data is not")
            } else if let dictionary = value as? [String: Any] {
                XCTAssertFalse(dictionary.isEmpty, "\(domain.rawValue) exports an empty \"\(key)\"")
            } else {
                XCTAssertFalse(value is NSNull, "\(domain.rawValue) exports \"\(key)\": null")
            }
        }
    }

    /// **Derived series export.** They used to map to `samples` on the argument
    /// that they replay from it — true on the phone that still has the raw data,
    /// false of a server-side pool, which is the only place the reader's norms
    /// can be built. `docs/norms-and-telemetry.md`.
    func testGeneratedInsightsCarryTheirSpecAndEveryDatedValue() throws {
        let json = try XCTUnwrap(String(data: fullyPopulated().json(), encoding: .utf8))
        XCTAssertEqual(HealthDataExport.exportKey(for: .generatedInsights), "generatedInsights",
                       "derived series are back to sharing the samples key — see the reversal note")
        XCTAssertTrue(json.contains("\"generatedInsights\""))
        XCTAssertTrue(json.contains("fitness.fitnessAge"), "the series id is what makes it poolable")
        XCTAssertTrue(json.contains("\"modelOutput\""), "the kind says it is derived, not measured")
        XCTAssertTrue(json.contains("33.5"), "the values did not travel")
        XCTAssertTrue(json.contains("33.2"), "only the latest value travelled — a series is its history")
    }

    /// A derived series with no direction — a departure in SD, where neither way
    /// is the good one — must say so rather than lose the field.
    func testANilHigherIsBetterIsWrittenAsNull() throws {
        var store = DerivedSeriesStore()
        store.record(DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "vo2.departure"),
                                       displayName: "VO2 — from your normal", unit: "SD",
                                       producedBy: .fitness, kind: .componentDeparture,
                                       higherIsBetter: nil, precision: 2),
                     value: -0.4, on: TestClock.now)
        let export = HealthDataExport(
            generatedAt: TestClock.now, build: "test", samples: [], unmodelled: [],
            substances: [], medication: nil, sideEffects: [],
            profile: UserHealthProfile(), derivedScores: [],
            generatedInsights: HealthDataExport.derivedSeries(from: store))
        let json = try XCTUnwrap(String(data: export.json(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"higherIsBetter\""))
    }

    // MARK: - The round trip, actually taken

    /// **Everything, out and back.**
    ///
    /// Until 2026-08-07 every assertion in this file was `json.contains("key")`
    /// — including one titled "must survive the round trip" that never decoded.
    /// A substring cannot see a shape, and a shape is what went wrong: on
    /// 2026-08-05 an importer lost all four sections of a real file because
    /// `UserHealthProfile.inputs` does not encode as the object everyone
    /// assumed. The encode side was word-perfect throughout.
    ///
    /// Compared as whole values rather than field by field, deliberately: a
    /// field added to `HealthDataExport` next month is compared by this test
    /// without anyone remembering to add it, which is the difference between
    /// closing an instance and closing the category. It is also why
    /// `Equatable` was added to the type.
    func testTheWholeExportSurvivesADecode() throws {
        let original = fullyPopulated()
        let decoded = try HealthDataExport.decoded(from: original.json())

        // Named first so a failure says *which* section moved, then the whole
        // value so a new one cannot be added without being compared.
        XCTAssertEqual(decoded.samples, original.samples)
        XCTAssertEqual(decoded.unmodelled, original.unmodelled)
        XCTAssertEqual(decoded.substances, original.substances)
        XCTAssertEqual(decoded.medication, original.medication)
        XCTAssertEqual(decoded.previousMedication, original.previousMedication)
        XCTAssertEqual(decoded.sideEffects, original.sideEffects)
        XCTAssertEqual(decoded.symptoms, original.symptoms)
        XCTAssertEqual(decoded.bodyScans, original.bodyScans)
        XCTAssertEqual(decoded.profile, original.profile)
        XCTAssertEqual(decoded.derivedScores, original.derivedScores)
        XCTAssertEqual(decoded.cycles, original.cycles)
        XCTAssertEqual(decoded.holidays, original.holidays)
        XCTAssertEqual(decoded.generatedInsights, original.generatedInsights)
        XCTAssertEqual(decoded.schemaVersion, HealthDataExport.schemaVersion)
        XCTAssertEqual(decoded, original)
    }

    /// **The exact shape that broke the importer, pinned.**
    ///
    /// `UserHealthProfile.inputs` is `[GroundingKind: GroundingInput]`, and
    /// Swift encodes a dictionary whose key is neither `String` nor `Int` as an
    /// **alternating key/value array**, not an object. Every hand-rolled reader
    /// of this file will assume otherwise, so the shape is asserted here rather
    /// than left as folklore — and the assertion is in the failing direction: if
    /// `GroundingKind` ever gains `CodingKeyRepresentable`, the payload becomes
    /// an object, every such reader breaks again, and this test says so.
    func testTheProfileEncodesAsAnAlternatingArrayAndStillDecodes() throws {
        let original = fullyPopulated()
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: original.json()) as? [String: Any])
        let profile = try XCTUnwrap(payload["profile"] as? [String: Any],
                                    "profile is no longer a keyed object")
        let inputs = try XCTUnwrap(profile["inputs"],
                                   "the profile's own facts are missing from the file")
        XCTAssertNotNil(inputs as? [Any],
                        "`inputs` is no longer an alternating key/value array — every "
                        + "reader of this file that assumed an object has just broken, "
                        + "and the 2026-08-05 import defect is the shape of what happens")
        XCTAssertNil(inputs as? [String: Any])

        // And the thing that matters: it comes back.
        let decoded = try HealthDataExport.decoded(from: original.json())
        XCTAssertEqual(decoded.profile.value(.totalCholesterol), 5.1)
        XCTAssertEqual(decoded.profile.inputs.count, original.profile.inputs.count)
    }

    /// A fresh install's file must decode too — the empty case is the one a
    /// reader is most likely to hand back first, and `[]` vs absent is the
    /// distinction the hand-written encoders exist to keep.
    func testAnEmptyExportSurvivesADecode() throws {
        let original = bundle(empty: true)
        let decoded = try HealthDataExport.decoded(from: original.json())
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.medication, "an explicit null must read back as nil, not as a throw")
        XCTAssertTrue(decoded.samples.isEmpty)
        XCTAssertTrue(decoded.previousMedication.isEmpty)
    }

    /// The nulls the encoders were hand-written to produce have to read back as
    /// nils. An explicit `null` that throws on decode is no better than a
    /// missing key.
    func testExplicitNullsDecodeAsNils() throws {
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
        let decoded = try HealthDataExport.decoded(from: allNil.json())
        let dose = try XCTUnwrap(decoded.medication?.doses.first)
        XCTAssertNil(dose.confirmedAt)
        XCTAssertNil(dose.injectionSite)
        XCTAssertTrue(dose.isInferred, "an inferred dose must not read back as a logged one")
        XCTAssertNil(decoded.medication?.brandName)
        XCTAssertNil(decoded.derivedScores.first?.score)
        XCTAssertNil(decoded.derivedScores.first?.primaryValue)
        XCTAssertEqual(decoded, allNil)
    }

    /// Dates are written as ISO-8601 without fractional seconds, so the file
    /// carries whole seconds and a re-read instant is truncated. Stated as a
    /// test because it is a property of the file that a reader pooling these
    /// needs to know, and because it is the one place whole-value equality
    /// above could quietly stop meaning what it says.
    func testDatesRoundTripToTheSecond() throws {
        let odd = TestClock.now.addingTimeInterval(0.75)
        let export = HealthDataExport(
            generatedAt: odd, build: "test", samples: [], unmodelled: [], substances: [],
            medication: nil, sideEffects: [], profile: UserHealthProfile(), derivedScores: [])
        let decoded = try HealthDataExport.decoded(from: export.json())
        XCTAssertEqual(decoded.generatedAt.timeIntervalSince1970,
                       TestClock.now.timeIntervalSince1970, accuracy: 1e-9,
                       "sub-second precision is not in the file; if that changes, say so here")
    }

    /// The distinctions that matter downstream must survive the round trip: an
    /// inferred dose is not a logged one, and a derived score is not a
    /// measurement.
    ///
    /// Kept as an encode-side key check — the decode half of the claim its
    /// title makes is `testExplicitNullsDecodeAsNils` above, which is where it
    /// should have been all along.
    func testTheInferredFlagAndDerivedScoresSurvive() throws {
        let json = try XCTUnwrap(String(data: bundle().json(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"isInferred\""))
        XCTAssertTrue(json.contains("\"derivedScores\""))
        XCTAssertTrue(json.contains("\"primaryValue\""),
                      "a card's own units — a risk % — are not its 0–100 dial")
        XCTAssertTrue(json.contains("\"schemaVersion\""))
    }
}
