import XCTest
@testable import InsightKit

/// Structural invariants of the analyte catalogue. Each one is a way a new
/// entry can be added that compiles, looks right, and quietly files values
/// under the wrong analyte or in the wrong unit.
final class LabAnalyteCatalogTests: XCTestCase {

    func testKeysAreUnique() {
        let keys = LabAnalyteCatalog.entries.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "two catalogue entries share a key")
    }

    /// Longest-first synonym matching is what stops "HDL cholesterol" being
    /// consumed by "cholesterol". If the index ever stops being sorted, the
    /// failure is a wrong number in a cardiovascular risk estimate.
    func testTheSynonymIndexIsSortedLongestFirst() {
        let lengths = LabAnalyteCatalog.synonymIndex.map(\.label.count)
        XCTAssertEqual(lengths, lengths.sorted(by: >))
    }

    /// Every entry must be able to store a value in its own canonical unit —
    /// an entry whose unit table omits its canonical unit converts nothing.
    func testEveryEntryCanConvertItsOwnCanonicalUnit() {
        for entry in LabAnalyteCatalog.entries {
            let converted = LabAnalyteCatalog.convert(1, from: entry.canonicalUnit, for: entry)
            XCTAssertNotNil(converted, "\(entry.key) cannot convert its own canonical unit")
        }
    }

    /// A plausible range that excludes the middle of the reference interval
    /// would reject every real value for that analyte.
    func testPlausibleRangesAreNotDegenerate() {
        for entry in LabAnalyteCatalog.entries {
            XCTAssertLessThan(entry.plausible.lowerBound, entry.plausible.upperBound,
                              "\(entry.key) has an empty plausible range")
        }
    }

    /// A label the catalogue does not know must not be silently forced onto one
    /// it does — that is the whole point of `isKnown`.
    func testAnUnknownLabelDoesNotMatch() {
        XCTAssertNil(LabAnalyteCatalog.match(label: "Anti-Mullerian Hormone"))
        XCTAssertFalse(LabAnalyte.unknown(label: "Anti-Mullerian Hormone", unit: nil).isKnown)
    }

    func testTheMicroSignAndGreekMuNormaliseTogether() {
        XCTAssertEqual(LabAnalyteCatalog.normaliseUnit("µmol/L"),
                       LabAnalyteCatalog.normaliseUnit("μmol/L"))
    }

    /// An uncatalogued analyte's key is namespaced, so it can never collide
    /// with a catalogued one that is added later under the same words.
    func testUnknownAnalyteKeysAreNamespaced() {
        XCTAssertTrue(LabAnalyte.unknown(label: "HbA1c", unit: nil).key.hasPrefix("other."))
    }

    /// ⚠️ An analyte that fills a grounding fact feeds SCORE2 and ASCVD. Only
    /// the two lipids may, and a third arriving by accident would change a
    /// cardiovascular risk estimate with nothing in the UI saying so.
    func testOnlyTheTwoLipidsFillGroundingFacts() {
        let grounded = LabAnalyteCatalog.entries.compactMap(\.groundingKind)
        XCTAssertEqual(Set(grounded), [.totalCholesterol, .hdlCholesterol])
    }

    // MARK: - The 2026-08-09 corpus: synonyms that can eat each other

    /// ⚠️ **The pair this catalogue is most likely to get wrong.** Hepatitis B
    /// surface *antigen* and surface *antibody* differ by two letters at the end
    /// of a twenty-seven character label, sit one line under each other on the
    /// report, and mean opposite things: antigen Negative is no active
    /// infection, antibody Negative is no immunity. Filing either as the other
    /// tells the reader the opposite of what their laboratory said.
    func testHepatitisBSurfaceAntibodyAndAntigenAreNeverEachOther() {
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Hepatitis B surface antigen")?.key,
                       "hep_b_surface_antigen")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Hepatitis B surface antibody")?.key,
                       "hep_b_surface_antibody")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HBsAg")?.key, "hep_b_surface_antigen")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HBsAb")?.key, "hep_b_surface_antibody")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Anti-HBs")?.key, "hep_b_surface_antibody")
        // And neither may absorb the third hepatitis B result on the same panel.
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Hepatitis B core antibody")?.key,
                       "hep_b_core_antibody")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Anti-HBc")?.key, "hep_b_core_antibody")
        // A label naming neither finding must match nothing rather than guess.
        XCTAssertNil(LabAnalyteCatalog.match(label: "Hepatitis B serology"))
    }

    /// ⚠️ A corrected calcium is *calculated* from albumin; the total calcium it
    /// is calculated from is printed on the line above it and is a different
    /// number. Both are catalogued since 2026-08-09 — an Australian CMP prints
    /// the pair, and until the bare word had an entry the measured total started
    /// its own trend under the laboratory's label — so this now has to hold in
    /// **both** directions: neither label may reach the other's key.
    /// "Albumin corrected calcium" must not fall to albumin either, which is the
    /// longest-first sort doing its job.
    func testACorrectedCalciumIsNeverABareCalcium() {
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Corrected calcium")?.key,
                       "corrected_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium (corrected)")?.key,
                       "corrected_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium (Corrected)")?.key,
                       "corrected_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Albumin corrected calcium")?.key,
                       "corrected_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium corrected")?.key,
                       "corrected_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Adjusted calcium")?.key,
                       "corrected_calcium")
        // ...and the direction that only exists now the bare word is catalogued.
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium")?.key, "calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Serum calcium")?.key, "calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Total calcium")?.key, "calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium (total)")?.key, "calcium")
    }

    /// ⚠️ **The row that makes the bare "calcium" synonym safe to have.** An
    /// ionised calcium is a different fraction at about half the number, and
    /// "Calcium (ionised)" contains "calcium" — so without an entry of its own a
    /// blood-gas ionised calcium would be filed on the total's trend, which is
    /// the silent version of the mistake the corrected pair is guarded against.
    func testAnIonisedCalciumIsNeverATotalCalcium() {
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Ionised calcium")?.key,
                       "ionised_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium (ionised)")?.key,
                       "ionised_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium (ionized)")?.key,
                       "ionised_calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Free calcium")?.key,
                       "ionised_calcium")
        // And it may not steal either of the other two.
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Calcium")?.key, "calcium")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Corrected calcium")?.key,
                       "corrected_calcium")
    }

    /// Every synonym must find its own entry back.
    ///
    /// Two failures this catches, both silent: a synonym that duplicates one on
    /// another entry (whichever sorts first wins, and `sorted` is not stable, so
    /// the loser is filed under the winner at random), and a synonym written
    /// with punctuation `match(label:)` strips — "h. pylori antigen" can never
    /// match any label at all, and nothing else in the suite would notice.
    func testEverySynonymMatchesItsOwnEntry() {
        for entry in LabAnalyteCatalog.entries {
            for synonym in entry.synonyms {
                XCTAssertEqual(LabAnalyteCatalog.match(label: synonym)?.key, entry.key,
                               "\(entry.key): the synonym \"\(synonym)\" does not find its own entry")
            }
        }
    }

    /// The additions must not have taken a label that already belonged to
    /// someone. Each of these is one new synonym away from breaking: transferrin
    /// contains no ferritin but "transferrin saturation" contains "transferrin",
    /// "alk phos" and "phosphate" are one report line apart, and the two lipids
    /// underneath still feed a cardiovascular risk estimate.
    func testTheNewSynonymsDoNotStealAnOlderLabel() {
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Total cholesterol")?.key,
                       "total_cholesterol")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HDL cholesterol")?.key,
                       "hdl_cholesterol")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Serum ferritin")?.key, "ferritin")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Transferrin")?.key, "transferrin")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Transferrin saturation")?.key,
                       "transferrin_saturation")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Alk. Phos.")?.key, "alp")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Alkaline phosphatase")?.key, "alp")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Phosphate")?.key, "phosphate")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Albumin")?.key, "albumin")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "White cell count")?.key,
                       "white_cell_count")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Red cell count")?.key,
                       "red_cell_count")
    }

    /// ⚠️ The same organism reported by a different method is a different
    /// finding — IgG says the reader met it once, DNA says it is replicating
    /// now — so every nucleic-acid synonym carries its method and no bare
    /// organism name is catalogued. A screen must not swallow a viral load
    /// either: one is a word, the other a number in copies/mL.
    func testTheSameOrganismByAnotherMethodDoesNotMatch() {
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HSV 1 DNA")?.key, "hsv1_dna")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HSV-2 DNA")?.key, "hsv2_dna")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Herpes simplex virus 2 DNA")?.key,
                       "hsv2_dna")
        XCTAssertNil(LabAnalyteCatalog.match(label: "HSV IgG"))
        XCTAssertNil(LabAnalyteCatalog.match(label: "Varicella zoster IgG"))
        XCTAssertNil(LabAnalyteCatalog.match(label: "HIV RNA quantitative"))
        XCTAssertNil(LabAnalyteCatalog.match(label: "Chlamydia pneumoniae IgG"))
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Chlamydia trachomatis NAT")?.key,
                       "chlamydia_trachomatis_nat")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HIV Ag/Ab")?.key, "hiv_ag_ab")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "H. pylori antigen")?.key,
                       "h_pylori_faecal_antigen")
    }

    // MARK: - The two axes the corpus added

    /// A catalogued analyte may not be filed under "Not recognised" — the panel
    /// is a claim about what the app knows, and for a row in this table the
    /// claim is false by construction.
    func testNoCataloguedAnalyteIsFiledAsNotRecognised() {
        for entry in LabAnalyteCatalog.entries {
            XCTAssertNotEqual(entry.panel, .other, "\(entry.key) is catalogued and unplaced")
        }
    }

    /// ⚠️ `.protected` is about who else can read the screen, not about how bad
    /// a result is. Every serology and STI analyte carries it; an entry added to
    /// `.infection` without it would be one the app is willing to draw unasked.
    func testEveryInfectionAnalyteIsProtected() {
        let infection = LabAnalyteCatalog.entries.filter { $0.panel == .infection }
        XCTAssertEqual(infection.count, 14)
        for entry in infection {
            XCTAssertEqual(entry.sensitivity, .protected, "\(entry.key) is disclosable")
        }
        XCTAssertEqual(LabAnalyteCatalog.entry(forKey: "hiv_ag_ab")?.analyte.sensitivity,
                       .protected)
        // The default holds for everything that predates the axis.
        XCTAssertEqual(LabAnalyteCatalog.entry(forKey: "hba1c")?.sensitivity, .ordinary)
        // ⚠️ And for an analyte the catalogue has never met, which is a
        // limitation the caller has to know about rather than a judgement.
        XCTAssertEqual(LabAnalyte.unknown(label: "HIV viral load", unit: nil).sensitivity,
                       .ordinary)
    }

    /// A qualitative analyte carries no unit and no magnitude, and both must
    /// travel together: an empty canonical unit is how this file says
    /// "reported as a word", so a number that happens to be printed bare — the
    /// haemolysis index — must not be mistaken for one.
    func testAQualitativeEntryCarriesNoUnitAndNoMagnitude() {
        for entry in LabAnalyteCatalog.entries where entry.isQualitative {
            XCTAssertTrue(entry.canonicalUnit.isEmpty, "\(entry.key)")
            XCTAssertTrue(entry.unitFactors.isEmpty, "\(entry.key)")
            XCTAssertNil(entry.analyte.canonicalUnit, "\(entry.key)")
            XCTAssertEqual(entry.form, .word, "\(entry.key)")
            // Nothing a report can print is inside it, which is what marks a
            // stray serology index doubtful instead of storing it as a result.
            XCTAssertFalse(entry.plausible.contains(0), "\(entry.key)")
            XCTAssertFalse(entry.plausible.contains(1), "\(entry.key)")
            XCTAssertFalse(entry.plausible.contains(1000), "\(entry.key)")
        }
        // Thirteen, not the fourteen this test pinned before 2026-08-09: the
        // hepatitis B surface antibody left the word-only set for `.either`.
        XCTAssertEqual(LabAnalyteCatalog.entries.filter(\.isQualitative).count, 13)

        let haemolysis = LabAnalyteCatalog.entry(forKey: "haemolysis_index")
        XCTAssertEqual(haemolysis?.isQualitative, false)
        XCTAssertEqual(haemolysis?.analyte.canonicalUnit, "index")

        // A unit printed beside a word is never honoured — a signal-to-cutoff
        // index is not the finding, and converting one would store it as if it
        // were.
        let hiv = LabAnalyteCatalog.entry(forKey: "hiv_ag_ab")!
        XCTAssertNil(LabAnalyteCatalog.convert(0.06, from: "S/CO", for: hiv))
    }

    // MARK: - The dual form

    /// ⚠️ **The one combination `Entry.form` reads silently and wrongly**: the
    /// word flag set on an entry with no canonical unit is `.word` whatever the
    /// author meant, so its unit table and plausible range would never be
    /// consulted again. Nothing in the type can stop that being written, which is
    /// why it is pinned here — the same job `testEverySynonymMatchesItsOwnEntry`
    /// does for a synonym nothing can match.
    func testADualFormEntryDeclaresBothAUnitAndAWord() {
        for entry in LabAnalyteCatalog.entries where entry.alsoReportedAsWord {
            XCTAssertFalse(entry.canonicalUnit.isEmpty,
                           "\(entry.key) claims a word form with no unit to be the other half of")
            XCTAssertEqual(entry.form, .either, "\(entry.key)")
            XCTAssertFalse(entry.unitFactors.isEmpty, "\(entry.key)")
            // A real range, not the `noMagnitude` sentinel: a dual-form analyte's
            // number is a measurement and has to be sizeable.
            XCTAssertNotEqual(entry.plausible, LabAnalyteCatalog.Entry.noMagnitude,
                              "\(entry.key)")
            XCTAssertFalse(entry.isQualitative, "\(entry.key)")
        }
        // The three forms partition the catalogue: every entry is exactly one.
        for entry in LabAnalyteCatalog.entries {
            switch entry.form {
            case .word: XCTAssertTrue(entry.canonicalUnit.isEmpty, "\(entry.key)")
            case .measurement, .either: XCTAssertFalse(entry.canonicalUnit.isEmpty, "\(entry.key)")
            }
        }
    }

    /// ⚠️ **The reader's own report prints this test both ways.** `HepB surface
    /// antibody Negative` is a word and `HepB surface antibody <5 IU/L` is a
    /// censored titre, and the titre is what the report's own comment reasons
    /// about — *not immune (HBsAb <10 IU/L)*. Held as word-only, the titre was
    /// `unitUnrecognised` and doubtful; held as a measurement, the word was
    /// dropped. mIU/mL and IU/L are the same quantity by arithmetic, and a report
    /// printing the American spelling must not come back doubtful for it.
    func testHepatitisBSurfaceAntibodyIsPrintedBothAsAWordAndAsATitre() {
        let entry = LabAnalyteCatalog.entry(forKey: "hep_b_surface_antibody")!
        XCTAssertEqual(entry.form, .either)
        XCTAssertEqual(entry.analyte.canonicalUnit, "IU/L")
        XCTAssertEqual(LabAnalyteCatalog.convert(142, from: "IU/L", for: entry), 142)
        XCTAssertEqual(LabAnalyteCatalog.convert(142, from: "mIU/mL", for: entry), 142)
        XCTAssertEqual(LabAnalyteCatalog.convert(142, from: "U/L", for: entry), 142)
        // Still refused rather than guessed at, the same as any other entry.
        XCTAssertNil(LabAnalyteCatalog.convert(142, from: "copies/mL", for: entry))
        // ⚠️ It is the only one. Every other serology row prints a number that is
        // *not* the finding — a signal-to-cutoff index, a Ct, a viral load — and
        // `noMagnitude` is what keeps that number from being stored as a result.
        XCTAssertEqual(LabAnalyteCatalog.entries.filter { $0.form == .either }.map(\.key),
                       ["hep_b_surface_antibody"])
        XCTAssertEqual(LabAnalyteCatalog.entry(forKey: "hep_a_igg")?.form, .word)
        XCTAssertEqual(LabAnalyteCatalog.entry(forKey: "hep_b_surface_antigen")?.form, .word)
    }

    // MARK: - Labels that missed their entry by spelling

    /// ⚠️ **Three labels off the reader's own reports matched nothing**, so each
    /// started a second trend beside the catalogued analyte it *is*. None of the
    /// three is an unusual name — they are the ordinary spellings of tests the
    /// catalogue already had, and a synonym list is only as good as the shapes it
    /// was written against.
    func testTheThreeCorpusLabelsThatMissedTheirEntryBySpelling() {
        // "HepB" is one word: a synonym written "hep b" cannot match it, because
        // normalisation collapses punctuation to spaces and never splits a word.
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HepB surface antibody")?.key,
                       "hep_b_surface_antibody")
        // "Ag", not "antigen" — and only ever behind the organism's name.
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Faecal H. pylori Ag (ChLIA)")?.key,
                       "h_pylori_faecal_antigen")
        // A spaced slash, which every synonym in the file writes closed up.
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HIV 1 / 2 total antibody")?.key,
                       "hiv_ag_ab")

        // ⚠️ None of the three may have bought its match by taking a label that
        // belonged to something else. The hepatitis B pair is two letters apart
        // and means opposite things; "ag" is two letters that also open an anion
        // gap and an HIV screen.
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HepB surface antigen")?.key,
                       "hep_b_surface_antigen")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HepB core antibody")?.key,
                       "hep_b_core_antibody")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Anion gap")?.key, "anion_gap")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "HIV Ag/Ab")?.key, "hiv_ag_ab")
        XCTAssertNil(LabAnalyteCatalog.match(label: "Faecal occult blood"))
    }

    /// ⚠️ The slash fix is in the normaliser rather than in each synonym, so it
    /// has to leave every closed-up spelling exactly where it was — and it opens
    /// the full stop's twin hazard: a synonym written with a spaced slash can
    /// never match anything. `testEverySynonymMatchesItsOwnEntry` is what catches
    /// that one; this is the half that pins the labels.
    func testASpacedSlashInALabelFindsTheSameEntryAsAClosedOne() {
        for label in ["HIV 1/2 total antibody", "HIV 1 / 2 total antibody",
                      "HIV 1 /2 total antibody", "HIV 1/ 2 total antibody"] {
            XCTAssertEqual(LabAnalyteCatalog.match(label: label)?.key, "hiv_ag_ab", label)
        }
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Cholesterol / HDL ratio")?.key,
                       "cholesterol_hdl_ratio")
        XCTAssertEqual(LabAnalyteCatalog.match(label: "Cholesterol/HDL ratio")?.key,
                       "cholesterol_hdl_ratio")
        // A label that is only a slash away from a real analyte still matches
        // nothing rather than the nearest thing.
        XCTAssertNil(LabAnalyteCatalog.match(label: "HIV 1 / 2 RNA quantitative"))
    }
}
