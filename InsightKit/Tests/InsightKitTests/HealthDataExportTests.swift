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
            // Q8 / B3-25. ⚠️ **Two ingredients on purpose, and only one of them
            // declares an amount** — a stack whose every line is a number is not
            // the shape that ships, and the proprietary-blend case is the one
            // whose encoding could silently become a nought.
            supplements: [SupplementEntry(
                product: SupplementProduct(
                    name: "Daily multivitamin",
                    brand: "Test",
                    servingDescription: "2 capsules",
                    ingredients: [
                        SupplementIngredient(
                            nutrient: .zinc, labelText: "Zinc (as citrate)",
                            amount: .stated(.init(value: 15, unit: .milligrams))),
                        SupplementIngredient(
                            nutrient: .selenium, labelText: "Selenium",
                            amount: .withinProprietaryBlend(
                                blendName: "Antioxidant Blend",
                                blendTotal: .init(value: 250, unit: .milligrams))),
                    ],
                    // ⚠️ Stamped rather than defaulted. `addedAt` defaults to
                    // `Date()`, whose sub-second precision `.iso8601` truncates
                    // — so a defaulted fixture fails the round-trip comparison
                    // for a reason that has nothing to do with this type.
                    addedAt: now),
                servingsPerDay: 1, startedOn: now.addingTimeInterval(-30 * 86_400))],
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
            // D50. A phone holding one of everything holds a calendar event, and
            // this fixture is what `testEveryDataDomainsKeyIsPopulated…` reads —
            // so the key cannot be present-and-empty here. ⚠️ The tier gate that
            // decides whether it travels lives in `DataExportView`, which no
            // InsightKit test can reach; this pins only that the type carries it.
            calendarEvents: [CalendarEvent(
                id: "evt-1", start: now, end: now.addingTimeInterval(3600),
                isAllDay: false, timeZoneIdentifier: "Australia/Sydney",
                calendarName: "Work", kind: .timed, title: "Quarterly review",
                location: "Level 3", hasVideoLink: false,
                organizerIsReader: true, attendeeCount: 4)],
            // §B11-4. A detected spell, so `label` is nil exactly as the ledger
            // produces it — the fixture has to hold the shape that actually
            // ships, or the encoder's nil handling goes untested.
            sickDays: [.init(firstDay: now.addingTimeInterval(-10 * 86_400),
                             lastDay: now.addingTimeInterval(-8 * 86_400),
                             label: nil, severity: "moderate", source: "detected")],
            // §B11-2. One **corrected** day rather than a confirmed one, for the
            // reason the flagged-event fixture below gives: a guess and an
            // answer that disagree is the shape that actually carries
            // information, and it is the only shape in which the correction
            // fields can be seen to travel at all.
            illnessAnswers: [HealthDataExport.IllnessAnswer(
                IllnessJudgement(
                    day: now.addingTimeInterval(-9 * 86_400),
                    estimate: IllnessEstimate(
                        assessment: IllnessAssessment(kind: .feverish, severity: .mild),
                        basis: ["Two overnight signals were leaning."],
                        uncertainty: "A prompt, not a finding.",
                        artifact: IllnessArtifact(physiologicalExcess: 2.4,
                                                  accumulatedStatistic: 1.8,
                                                  reportedExcess: 0,
                                                  leaningSignals: 2, wasJudged: true)))
                    .reviewed(correction: IllnessAssessment(kind: .respiratory,
                                                            severity: .moderate),
                              confirmed: false, at: now))],
            generatedInsights: HealthDataExport.derivedSeries(from: store),
            // §B12. One custom Oura tag, classified — the fixture holds a name
            // the lexicon has never seen, because a fixed lookup table is
            // exactly what the reader said would not scale.
            tags: [HealthTag(name: "Kayaking", code: nil, date: now, source: .oura,
                             mapping: TagLexicon.classify(name: "Kayaking"))],
            // P32. One flagged moment the reader answered — and **corrected**,
            // so the fixture holds the shape that actually carries information:
            // a guess and an answer that disagree. Built through the judgement
            // initialiser rather than by hand, which is the route the app uses
            // and the one that would break if the artifact stopped travelling
            // with the guess.
            flaggedEvents: [Self.answeredFlaggedEvent(at: now)]
                .compactMap { HealthDataExport.FlaggedEventExport($0) },
            // Q7. A machine-read value rather than a typed one, deliberately:
            // the fixture has to hold the shape that carries `evidence`, or the
            // one field that distinguishes an OCR'd number from a typed one
            // goes untested in the file.
            labResults: [LabResult(
                analyte: LabAnalyteCatalog.entry(forKey: "hba1c")!.analyte,
                value: 38, unit: "mmol/mol",
                referenceRange: LabReferenceRange(low: 20, high: 41,
                                                  printed: "20 - 41"),
                collectedAt: now, collectedAtIsExact: true, source: .pdf,
                evidence: LabExtractionEvidence(
                    rawLabel: "HbA1c", rawValueText: "38",
                    rawLine: "HbA1c   38 mmol/mol   (20 - 41)",
                    method: .deterministic,
                    checks: [.unitRecognised("mmol/mol"), .plausibleMagnitude,
                             .insidePrintedRange]),
                isConfirmedByReader: true)],
            // I7. With a printed finding *and* its provenance, because the
            // attribution is the part that must never travel without the
            // quotation — a classification in a file with nobody's name on it
            // reads as this app's own, and this app produces none.
            ecgRecords: [ECGRecord(recordedAt: now, recordedAtIsExact: true,
                                   source: .pdf, leads: .singleLead,
                                   durationSeconds: 30,
                                   printedAverageHeartRate: 62,
                                   deviceDescription: "Apple Watch",
                                   printedFinding: "Sinus Rhythm",
                                   findingProvenance: .recordingDevice,
                                   readerNote: nil, pageCount: 1,
                                   attachmentFileName: "ecg-1.pdf",
                                   transcription: nil)],
            reports: .init(inventory: "# Inventory\nbodyMass · 1 reading",
                           cardOutputs: "# Cards\ncardiovascularRisk 72",
                           modelInternals: "# Internals\nbaseline n=1",
                           diagnostics: "[2026-08-07] OK · Sync: imported 1"),
            improvements: HealthDataExport.Improvements.build(
                tier: .full,
                judgements: [Self.correctedJudgement(at: now)],
                outcomes: []))
    }

    /// One flagged moment the reader answered, with all three layers — the
    /// app's guess, their correction, and the snapshot it guessed against.
    ///
    /// It carries a `note` and a `.usual` place deliberately: the export row
    /// built from it must show neither, and a fixture with nothing to omit
    /// cannot demonstrate that.
    private static func answeredFlaggedEvent(at now: Date) -> FlaggedEventJudgement {
        let start = now.addingTimeInterval(-3 * 3600)
        let event = FlaggedEvent(
            id: "restingHeartRateElevation-1",
            start: start, end: start.addingTimeInterval(1800),
            trigger: .restingHeartRateElevation,
            evidence: FlagEvidence(peak: 104, typical: 66, spread: 6,
                                   referenceDays: 28, stepsInWindow: 0, sampleCount: 6),
            place: PlaceContext(familiarity: .usual,
                                coordinate: CoarseCoordinate(rounding: -33.86,
                                                             longitude: 151.2),
                                capture: .visit, capturedAt: start),
            candidates: [CauseCandidate(cause: .intimacy, weight: 0.3, basis: .timeOfDay)])
        return FlaggedEventJudgement(pending: event)
            .reviewed(correction: .stress, note: "row with the landlord",
                      confirmed: false, at: now)
    }

    /// One reviewed calendar event with all three layers — the app's guess, the
    /// reader's correction, and the artifact it judged.
    private static func correctedJudgement(at now: Date) -> CalendarEventJudgement {
        CalendarEventJudgement(
            eventID: "evt-1",
            classification: .init(context: .work, occasion: .meeting,
                                  presence: .inPerson, formality: .formal, hours: 1.5),
            correction: .init(context: .personal, occasion: .meeting,
                              presence: .inPerson, formality: .casual, hours: 1.5),
            isConfirmed: true, reviewedAt: now,
            artifact: .init(title: "Quarterly review with Northwind",
                            location: "Level 3, 200 Example St", attendeeCount: 6,
                            durationHours: 1.5, isAllDay: false, calendarName: "Work",
                            hasVideoLink: true, organizerIsReader: false,
                            capturedAt: now))
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
        XCTAssertEqual(decoded.reports, original.reports)
        XCTAssertEqual(decoded.improvements, original.improvements)
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

    // MARK: - One export, containing everything (backlog B20)

    /// **The four side files are really in the one file.**
    ///
    /// Settings ▸ Export my data offered five surfaces until 2026-08-07 and the
    /// reader wanted one — *"just have one export option that contains
    /// everything. This should also include troubleshooting, and the data &
    /// model improvements."* Collapsing the buttons is the easy half; this is
    /// the half that can silently not happen, because a `Reports` of four empty
    /// strings encodes to four present keys and looks identical.
    func testTheFourProseReportsTravelInsideTheOneFile() throws {
        let object = try JSONSerialization.jsonObject(with: fullyPopulated().json())
        let payload = try XCTUnwrap(object as? [String: Any])
        let reports = try XCTUnwrap(payload["reports"] as? [String: Any],
                                    "the folded-in reports are not in the export at all")
        for key in ["inventory", "cardOutputs", "modelInternals", "diagnostics"] {
            let text = try XCTUnwrap(reports[key] as? String, "missing report \"\(key)\"")
            XCTAssertFalse(text.isEmpty,
                           "\"\(key)\": \"\" on a bundle that was handed one — the key is "
                               + "present and the report is not, which is the D39 shape")
        }
    }

    /// An empty phone still carries all four keys, so "this build had nothing to
    /// say" reads differently from "the exporter dropped the reports".
    func testTheReportKeysArePresentWhenEmpty() throws {
        let json = try XCTUnwrap(String(data: bundle(empty: true).json(), encoding: .utf8))
        for key in ["reports", "inventory", "cardOutputs", "modelInternals", "diagnostics"] {
            XCTAssertTrue(json.contains("\"\(key)\""), "\(key) vanishes when empty")
        }
    }

    // MARK: - The correction record reaches the export (backlog R4)

    /// **All three layers, in the file.** The guess, the correction, and the
    /// artifact that was judged.
    ///
    /// `R3` shipped the three-layer record itself and nothing carried it into an
    /// export — the reader's *"there is no way to export Data and model
    /// improvement data"*. Two layers alone make a tally: the app can say it was
    /// wrong fourteen times and nothing about what it was wrong *about*.
    func testTheCorrectionRecordCarriesGuessCorrectionAndArtifact() throws {
        let json = try XCTUnwrap(String(data: fullyPopulated().json(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"improvements\""))
        XCTAssertTrue(json.contains("\"work\""), "the app's guess did not travel")
        XCTAssertTrue(json.contains("\"personal\""), "the reader's correction did not travel")
        XCTAssertTrue(json.contains("Quarterly review with Northwind"),
                      "the artifact did not travel, so the record is a tally rather "
                          + "than a training pair")
        XCTAssertTrue(json.contains("Level 3, 200 Example St"))
    }

    /// The export honours the reader's own two-tier ruling (`R5`) rather than
    /// inventing a second answer to a question they have already answered.
    ///
    /// Under `.metadataOnly` the before/after move survives whole — it is a
    /// change between cases of a closed enum the app defined — and every word
    /// the reader's calendar holds is gone.
    func testMetadataOnlyStripsTheArtifactsWordsFromTheExport() throws {
        let now = TestClock.now
        let export = HealthDataExport(
            generatedAt: now, build: "test", samples: [], unmodelled: [],
            substances: [], medication: nil, sideEffects: [],
            profile: UserHealthProfile(), derivedScores: [],
            improvements: HealthDataExport.Improvements.build(
                tier: .metadataOnly,
                judgements: [Self.correctedJudgement(at: now)],
                outcomes: []))
        let json = try XCTUnwrap(String(data: export.json(), encoding: .utf8))
        XCTAssertFalse(json.contains("Quarterly review with Northwind"),
                       "an event's title left the phone under a tier the reader set to "
                           + "carry no content")
        XCTAssertFalse(json.contains("Level 3, 200 Example St"))
        XCTAssertTrue(json.contains("\"metadataOnly\""))
        XCTAssertTrue(json.contains("\"personal\""),
                      "the correction itself is a move between app categories and is the "
                          + "whole substance of the metadata tier")
    }

    /// **Both tiers off is a refusal, not an absence**, and the file has to say
    /// which. An empty `corrections` array with no tier beside it reads exactly
    /// like a person who has never corrected anything.
    func testBothTiersOffIsRecordedAsANullTierRatherThanAnEmptyList() throws {
        let now = TestClock.now
        let improvements = HealthDataExport.Improvements.build(
            tier: nil, judgements: [Self.correctedJudgement(at: now)], outcomes: [])
        XCTAssertNil(improvements.tier)
        XCTAssertTrue(improvements.corrections.isEmpty)

        let export = HealthDataExport(
            generatedAt: now, build: "test", samples: [], unmodelled: [],
            substances: [], medication: nil, sideEffects: [],
            profile: UserHealthProfile(), derivedScores: [],
            improvements: improvements)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: export.json()) as? [String: Any])
        let section = try XCTUnwrap(payload["improvements"] as? [String: Any])
        XCTAssertTrue(section["tier"] is NSNull,
                      "the tier key vanished, so \"both switched off\" is indistinguishable "
                          + "from \"nothing has ever been corrected\"")
    }

    /// An unreviewed judgement is not a correction, and shipping it as one would
    /// inflate any accuracy figure computed downstream.
    func testAnUnreviewedJudgementIsNotExportedAsACorrection() {
        let now = TestClock.now
        let untouched = CalendarEventJudgement(
            eventID: "evt-2",
            classification: .init(context: .work, occasion: .meeting,
                                  presence: .inPerson, formality: .formal, hours: 1))
        let improvements = HealthDataExport.Improvements.build(
            tier: .full, judgements: [untouched, Self.correctedJudgement(at: now)],
            outcomes: [])
        XCTAssertEqual(improvements.corrections.count, 1,
                       "an event nobody has looked at was exported as a correction")
    }

    /// Newest first, and undated rows last rather than at the top — a correction
    /// record with no order is a set of anecdotes.
    func testCorrectionsAreOrderedNewestFirstWithUndatedRowsLast() {
        let now = TestClock.now
        let older = CalendarEventJudgement(
            eventID: "old",
            classification: .init(context: .work, occasion: .meeting,
                                  presence: .inPerson, formality: .formal, hours: 1),
            isConfirmed: true, reviewedAt: now.addingTimeInterval(-86_400))
        let undated = CalendarEventJudgement(
            eventID: "undated",
            classification: .init(context: .work, occasion: .meeting,
                                  presence: .inPerson, formality: .formal, hours: 1),
            isConfirmed: true, reviewedAt: nil)
        let improvements = HealthDataExport.Improvements.build(
            tier: .full, judgements: [older, undated, Self.correctedJudgement(at: now)],
            outcomes: [])
        XCTAssertEqual(improvements.corrections.map(\.recordedAt),
                       [now, now.addingTimeInterval(-86_400), nil])
    }

    /// Prediction outcomes reach the improvement section too — the reader's own
    /// example for the metadata tier is one of these, not a calendar event.
    func testEstimateErrorsAreCorrectionsAsWell() throws {
        let now = TestClock.now
        let outcome = PredictionOutcome(
            id: UUID(), insightID: .bloodPressure, metric: .bloodPressureSystolic,
            predicted: 131, actual: 118, modelVersion: "bp-estimator-v2",
            cohort: Cohort(sex: "male", ageBand: "40-49",
                           ethnicity: "white_or_other", region: "low"),
            recordedAt: now)
        let improvements = HealthDataExport.Improvements.build(
            tier: .metadataOnly, judgements: [], outcomes: [outcome])
        let correction = try XCTUnwrap(improvements.corrections.first)
        XCTAssertEqual(correction.record.kind, .estimateError)
        XCTAssertTrue(correction.record.readings.isEmpty,
                      "an absolute reading travelled under the metadata tier")
        XCTAssertEqual(correction.summary, correction.record.summary,
                       "the stored sentence and the shaped record disagree, so the file "
                           + "says something the payload does not")
    }

    /// **The credential rule, restated over the new keys.** `improvements`
    /// carries an app-shaped record and `reports` carries rendered prose, and
    /// neither may become a route for a token — the reader's one condition on
    /// this file.
    func testTheNewSectionsCarryNoCredentialShapedField() throws {
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: fullyPopulated().json()) as? [String: Any])
        let section = try XCTUnwrap(payload["improvements"] as? [String: Any])
        XCTAssertEqual(Set(section.keys), ["tier", "corrections"],
                       "the improvement section grew a field — a free-text field here is "
                           + "where a provider's error body, and with it a token, arrives")
        let tier = try XCTUnwrap(section["tier"] as? String)
        XCTAssertNotNil(SharingTier(rawValue: tier),
                        "\"\(tier)\" is not a closed tier value, so tier carries free text")
    }

    // MARK: - The calendar is the one tier-conditional key (D50)

    /// ⚠️ **The reader's ruling, 2026-08-07:** *"if they have full sharing your
    /// corrections enabled, it will be enabled for that future feature (server)
    /// and the export."*
    ///
    /// So `calendarEvents` carries the whole calendar at `.full` and nothing at
    /// any other tier. **The key is present either way** — an empty array says
    /// "you have this turned off", where an absent key would say "this app does
    /// not export calendars", and those are different sentences.
    ///
    /// The gate itself lives in `DataExportView`, which no InsightKit test can
    /// reach; what this pins is that the *type* carries what it is handed and
    /// re-decides nothing.
    func testTheCalendarKeyIsAlwaysPresentAndCarriesWhatItIsHanded() throws {
        let now = TestClock.now
        let event = CalendarEvent(id: "evt-1", start: now, end: now.addingTimeInterval(3600),
                                  isAllDay: false, timeZoneIdentifier: "Australia/Sydney",
                                  calendarName: "Work", kind: .timed,
                                  title: "Quarterly review", location: "Level 3",
                                  hasVideoLink: false, organizerIsReader: true,
                                  attendeeCount: 4)

        let withCalendar = try HealthDataExport.decoded(from: bundle().json())
        XCTAssertNotNil(withCalendar.calendarEvents,
                        "the key must exist so an empty one reads as 'turned off'")

        let full = HealthDataExport(
            generatedAt: now, build: "test", samples: [], unmodelled: [], substances: [],
            medication: nil, sideEffects: [], profile: UserHealthProfile(),
            derivedScores: [], calendarEvents: [event])
        let decoded = try HealthDataExport.decoded(from: full.json())
        XCTAssertEqual(decoded.calendarEvents.count, 1)
        XCTAssertEqual(decoded.calendarEvents.first?.title, "Quarterly review",
                       "at .full the words travel — that is what the reader ruled")

        let off = HealthDataExport(
            generatedAt: now, build: "test", samples: [], unmodelled: [], substances: [],
            medication: nil, sideEffects: [], profile: UserHealthProfile(),
            derivedScores: [], calendarEvents: [])
        XCTAssertTrue(try HealthDataExport.decoded(from: off.json()).calendarEvents.isEmpty)
        XCTAssertTrue(String(decoding: try off.json(), as: UTF8.self).contains("calendarEvents"),
                      "the key stays in the file even when empty")
    }
}
