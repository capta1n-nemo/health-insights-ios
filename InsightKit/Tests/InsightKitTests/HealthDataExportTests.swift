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

    // MARK: - The four that were in no key at all (backlog Q10)

    /// A bundle carrying one of each of Q10's four fields.
    ///
    /// Separate from `fullyPopulated()` on purpose, and that is a compromise
    /// rather than a design: another agent was editing this file at the same
    /// time and additive edits merge, shared helpers don't. **`fullyPopulated()`
    /// leaves all four of these empty and therefore under-claims its name** —
    /// folding them in is a one-line-each follow-up worth doing once these two
    /// branches have met, and it would put them under
    /// `testEveryDataDomainsKeyIsPopulatedOnAFullyPopulatedExport`'s sibling
    /// checks.
    private func withLedgers() -> HealthDataExport {
        let now = TestClock.now
        let cohort = Cohort(sex: "male", ageBand: "40-49",
                            ethnicity: "white_or_other", region: "low")
        return HealthDataExport(
            generatedAt: now, build: "test", samples: [], unmodelled: [],
            substances: [], medication: nil, sideEffects: [],
            profile: UserHealthProfile(), derivedScores: [],
            connections: [
                .init(integration: "oura", state: .connected, lastSync: now),
                // Connected but nothing has come back yet, and errored — the two
                // states whose nil `lastSync` the hand-written encoder exists for.
                .init(integration: "withings", state: .connected, lastSync: nil),
                .init(integration: "calendar", state: .error, lastSync: nil)],
            suggestionDismissals: [
                .init(suggestionID: "grounding-cuffSystolic", dismissedAt: now)],
            feedback: [.init(card: .sleep, rating: .inaccurate,
                             modelVersion: InsightID.sleep.modelVersion,
                             cohort: cohort, recordedAt: now)],
            predictionOutcomes: [
                .init(id: UUID(), insightID: .bloodPressure, metric: .bloodPressureSystolic,
                      predicted: 128, actual: 124, modelVersion: "bp-estimator-v2",
                      cohort: cohort, recordedAt: now)])
    }

    /// **The Q10 rule.** Four things the phone held were named by no export key
    /// at all: connection state, suggestion dismissals, the feedback ledger and
    /// prediction outcomes.
    ///
    /// None of them is a `DataDomain` — the Data tab shows none of them — so
    /// `exportKey(for:)` cannot speak for them and neither can the two tests
    /// that walk it. They live in `additionalKeys`, and this insists the keys
    /// are not merely present but carry something, which is the distinction the
    /// D39 defect was about: `"cycles": []` satisfied every check there was.
    ///
    /// The reader's standing rule 11 is why it matters more than it looks: *a
    /// quantity missing from the export is a quantity that can never become a
    /// norm* — this file is the only route from a phone to a server-side pool,
    /// and "it is recomputable" was tried as an exemption and reversed the same
    /// day (see `exportKey(for: .generatedInsights)`).
    func testTheFourQ10FieldsAreInTheExportAndCarrySomething() throws {
        let object = try JSONSerialization.jsonObject(with: withLedgers().json())
        let payload = try XCTUnwrap(object as? [String: Any])
        for key in ["connections", "suggestionDismissals", "feedback", "predictionOutcomes"] {
            XCTAssertTrue(HealthDataExport.additionalKeys.contains(key),
                          "\(key) is not in additionalKeys, so nothing walks it")
            let array = try XCTUnwrap(payload[key] as? [Any], "missing \"\(key)\"")
            XCTAssertFalse(array.isEmpty,
                           "\"\(key)\": [] on a phone that holds one of each — the key is "
                               + "present and the data is not")
        }
    }

    /// The keys survive an empty phone, so "nothing connected" reads differently
    /// from "the exporter dropped connections".
    func testTheFourQ10KeysArePresentWhenEmpty() throws {
        let json = try XCTUnwrap(String(data: bundle(empty: true).json(), encoding: .utf8))
        for key in ["connections", "suggestionDismissals", "feedback", "predictionOutcomes"] {
            XCTAssertTrue(json.contains("\"\(key)\""), "\(key) vanishes when empty")
        }
    }

    /// **The reader's one condition on Q10: *"do not include tokens."***
    ///
    /// `OAuthTokens` gave up `Codable` so a credential cannot be a stored
    /// property of anything `Encodable`, which closes the obvious route. This
    /// closes the second one: `IntegrationStatus.unavailable(reason:)` and
    /// `.error(String)` quote whatever the provider said, and a failed OAuth
    /// exchange is precisely where an access token appears inside a message
    /// nobody chose to export.
    ///
    /// So the assertion is on the *shape*: a connection has exactly three keys
    /// and its state is one of five closed values. A future edit that widened
    /// `state` to a `String` to "keep the error message for diagnostics" fails
    /// here, which is the edit this test exists to stop.
    func testAConnectionCanCarryNothingButItsIdStateAndLastSync() throws {
        let object = try JSONSerialization.jsonObject(with: withLedgers().json())
        let payload = try XCTUnwrap(object as? [String: Any])
        let connections = try XCTUnwrap(payload["connections"] as? [[String: Any]])
        XCTAssertFalse(connections.isEmpty)
        for connection in connections {
            XCTAssertEqual(Set(connection.keys), ["integration", "state", "lastSync"],
                           "a connection grew a field — if it holds free text from a "
                               + "provider it can hold a token")
            let state = try XCTUnwrap(connection["state"] as? String)
            XCTAssertNotNil(HealthDataExport.ConnectionState(rawValue: state),
                            "\"\(state)\" is not one of the closed states, so state is "
                                + "carrying free text")
        }
        // Connected-but-never-synced must say so rather than lose the key.
        let neverSynced = try XCTUnwrap(connections.first { $0["integration"] as? String == "withings" })
        XCTAssertTrue(neverSynced["lastSync"] is NSNull,
                      "a source connected but yet to deliver reads as though the exporter "
                          + "forgot to record when it last did")
    }

    /// A rating means nothing without the revision it was about and the cohort
    /// it came from, and a prediction outcome means nothing without both of its
    /// numbers.
    func testTheLedgersCarryWhatMakesThemInterpretable() throws {
        let json = try XCTUnwrap(String(data: withLedgers().json(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"inaccurate\""), "the rating itself did not travel")
        XCTAssertTrue(json.contains("sleep-v1"),
                      "a rating without its model version is not comparable with any other")
        XCTAssertTrue(json.contains("\"ageBand\""), "the cohort a rating was recorded under")
        XCTAssertTrue(json.contains("128"), "the predicted value")
        XCTAssertTrue(json.contains("124"), "the actual value — an outcome is the pair")
        XCTAssertTrue(json.contains("grounding-cuffSystolic"),
                      "a dismissal's id is what makes it mean the same suggestion later")
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
