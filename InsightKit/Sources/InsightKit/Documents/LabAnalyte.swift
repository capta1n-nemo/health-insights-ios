import Foundation

/// **One thing a blood test measured.**
///
/// Backlog `Q7` / `I6`. Until 2026-08-07 this app could read exactly two
/// analytes — total and HDL cholesterol — because those are the two the
/// cardiovascular models ask for as *grounding facts*. Everything else on a
/// pathology report was thrown away at the parser.
///
/// The reader, asked whether bloods should be typed or photographed:
/// *"both? What do you mean? We should be able to accept all of these."* The
/// same answer applies one level down — a report that prints thirty analytes
/// should not be reduced to two because two are the ones a card happens to
/// score.
///
/// ## Why this is a struct with a `key`, not an enum
///
/// Every other vocabulary in this app is a closed enum (`MetricType`,
/// `DataDomain`, `InputKind`) precisely so a new member cannot be forgotten at
/// a surface. **This one cannot be**, and the difference is the point of `I6`:
/// the set of analytes is open. A private clinic's panel, a research assay, a
/// veterinary-style micronutrient screen — none of them are enumerable in
/// advance, and an enum with an `.other(String)` case would have every switch
/// in the app fall into that case and do nothing useful.
///
/// So the closed part is `LabAnalyteCatalog` — the analytes the app knows the
/// units, conversions and plausible ranges for — and the open part is any
/// `LabAnalyte` constructed from a label the catalogue did not recognise.
/// `isKnown` says which you are holding, and nothing pretends the second kind
/// carries the same certainty as the first.
public struct LabAnalyte: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// Stable, lower-snake identity. Derived from the display name for an
    /// unknown analyte, hard-coded for a catalogued one so a rename of the
    /// display string does not orphan stored results.
    public let key: String
    /// What the reader sees. For an unknown analyte this is the label as the
    /// report printed it, tidied but not reworded — the app has no better name
    /// for it than the one the laboratory used.
    public let displayName: String
    /// The unit this app stores the value in. `nil` for an unknown analyte:
    /// there is no canonical unit for something the app has never met, so the
    /// report's own unit is kept verbatim and never converted.
    public let canonicalUnit: String?
    /// The grounding fact this analyte can fill, if any. Only lipids today.
    public let groundingKind: GroundingKind?
    /// Whether `LabAnalyteCatalog` recognised it.
    ///
    /// ⚠️ **Read this before trusting a range check.** An unknown analyte has
    /// no plausible range, so `LabValueCheck.plausibility` cannot run on it and
    /// the only cross-check left is the reference interval the report printed
    /// beside the number. That is a weaker guard, and the UI says so.
    public let isKnown: Bool

    public init(key: String, displayName: String, canonicalUnit: String?,
                groundingKind: GroundingKind? = nil, isKnown: Bool) {
        self.key = key
        self.displayName = displayName
        self.canonicalUnit = canonicalUnit
        self.groundingKind = groundingKind
        self.isKnown = isKnown
    }

    public var id: String { key }

    /// An analyte the catalogue does not know, named by the report itself.
    ///
    /// The display name is trimmed and title-cased only where the source was
    /// clearly shouting (`ALL CAPS` labels are common on printouts); anything
    /// with mixed case is left exactly as printed. Renaming a laboratory's
    /// analyte is how "Free T3" quietly becomes something the reader cannot
    /// match against their own paperwork.
    public static func unknown(label: String, unit: String?) -> LabAnalyte {
        let tidy = LabAnalyte.tidyLabel(label)
        return LabAnalyte(key: "other." + LabAnalyte.normaliseKey(tidy),
                          displayName: tidy,
                          canonicalUnit: unit,
                          groundingKind: nil,
                          isKnown: false)
    }

    /// Lower-snake, punctuation-free — the storage key.
    public static func normaliseKey(_ s: String) -> String {
        let mapped = s.lowercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        // Collapse runs of underscore, then strip the ends.
        var out = ""
        var lastWasUnderscore = false
        for ch in mapped {
            if ch == "_" {
                if !lastWasUnderscore { out.append(ch) }
                lastWasUnderscore = true
            } else {
                out.append(ch)
                lastWasUnderscore = false
            }
        }
        while out.hasPrefix("_") { out.removeFirst() }
        while out.hasSuffix("_") { out.removeLast() }
        return out
    }

    static func tidyLabel(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reports separate label from value with a colon or a run of dots.
        while let last = s.last, last == ":" || last == "." || last == "-" || last == "—" {
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        let letters = s.filter(\.isLetter)
        let isShouting = !letters.isEmpty && letters.allSatisfy(\.isUppercase) && letters.count > 3
        guard isShouting else { return s }
        return s.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                // Keep acronyms of three or fewer letters as they are: HDL, LDL,
                // TSH, ALT, GGT are how the reader's own paperwork reads.
                let letterCount = word.filter(\.isLetter).count
                if letterCount <= 3 { return String(word) }
                return word.prefix(1) + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

/// **How a laboratory prints this analyte's result** — and the discovery, on
/// 2026-08-09, that for some analytes the answer is *both*.
///
/// This file had two states and derived them from one field: an empty
/// `canonicalUnit` meant "reported as a word", anything else meant "reported as a
/// number". The reader's own report prints the same analyte both ways on the same
/// page:
///
/// ```
/// HepB surface antibody   Negative
/// HepB surface antibody   <5  IU/L
/// ```
///
/// Neither line is a layout quirk. A hepatitis B surface antibody is a
/// **protective titre** — the report's own comment reads *not immune (HBsAb <10
/// IU/L)*, which is a sentence about a number — and the word is what a different
/// laboratory prints when it applies that same cutoff for you. With two states one
/// of those two lines always had to be mishandled: as a word-only entry the titre
/// came back `unitUnrecognised` plus `implausibleMagnitude` and was marked *check
/// this one*, and as a measurement entry the word was refused outright by
/// `LabReportParser.qualitativeRow` and the line was dropped on the floor.
///
/// ⚠️ **`.either` is a property of the assay, not of the app's confidence**, and
/// it is declared per entry rather than inferred per line. Inferring it per line is
/// precisely how `Glucose 5.4 mmol/L Normal` becomes the word "Normal" — the
/// misread `qualitativeRow`'s catalogued-analyte guard exists to prevent.
///
/// ⚠️ **One analyte key can now hold both shapes over time.** A reader whose
/// laboratory changes assay has words and numbers under one key, so anything
/// plotting a series must filter on `LabValueShape.isChartable` rather than assume
/// the analyte's form decides it.
public enum LabReportedForm: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// A number with a unit, always. Almost everything in the catalogue.
    case measurement
    /// A word, always — *Negative*, *Not detected*, *Reactive*. No unit, and no
    /// number on the line is the finding.
    case word
    /// Either, depending on the laboratory and sometimes on the line.
    case either
}

// MARK: - The catalogue

/// **The analytes this app knows enough about to check.**
///
/// "Knows enough" means three specific things, and each one is a guard that an
/// unknown analyte does not get:
///
/// 1. **Synonyms** — the label a laboratory prints varies ("HbA1c",
///    "Haemoglobin A1c", "Glycated haemoglobin"). Without them a value is filed
///    three times under three names and no trend exists.
/// 2. **A canonical unit and its conversions** — mg/dL and mmol/L differ by a
///    factor of 38.67 for cholesterol and 18 for glucose. Storing whichever the
///    report happened to print is how two results a year apart become a cliff.
/// 3. **A plausible range** — not a reference range, and the distinction
///    matters. A reference range says what is *normal*; this says what is
///    *physically possible to have been printed*. A total cholesterol of 0.02
///    or 400 mmol/L is a misread, not a finding, and `LabValueCheck` uses this
///    to say so.
///
/// ⚠️ **A plausible range is deliberately very wide.** It exists to catch a
/// decimal point OCR'd in the wrong place, never to comment on the reader's
/// health. Narrowing one so it "looks more clinical" would turn a data-quality
/// guard into an unlicensed opinion, which is the line this app does not cross.
///
/// ## A fourth thing, 2026-08-09: some analytes have no number at all
///
/// Fourteen entries below are serology or nucleic-acid tests, and their result
/// is a word — *Negative*, *Not detected*, *Reactive*; `LabValue` models that.
/// They carry no canonical unit and no magnitude, and `Entry.isQualitative`
/// says so.
///
/// ⚠️ **An empty `canonicalUnit` is how "no unit" is expressed**, so an analyte
/// that *is* a number must never be given one. `haemolysis_index` is printed
/// bare by the laboratory and still carries the pseudo-unit `index` for exactly
/// this reason — the same trick `Cholesterol : HDL ratio` already uses.
///
/// ## And a fifth: one of those fourteen is printed **both** ways
///
/// The reader's own report prints `HepB surface antibody` as a word on one line
/// and as `<5 IU/L` on another, and the titre is the half that answers the
/// question the test was ordered for. `LabReportedForm` is the third state that
/// buys, `Entry.form` derives it, and `hep_b_surface_antibody` is the one entry
/// that carries it — see the ⚠️ block on that entry for why the other thirteen
/// serology rows do **not**, which is a stronger claim than "nobody has checked".
public enum LabAnalyteCatalog {

    /// One catalogued analyte and everything needed to read it off a report.
    public struct Entry: Sendable {
        public let key: String
        public let displayName: String
        /// The unit this app stores the analyte in — **empty for an analyte the
        /// laboratory reports as a word**, because a word is in no unit. See
        /// `isQualitative`.
        public let canonicalUnit: String
        public let groundingKind: GroundingKind?
        /// Lower-cased labels, **longest first at match time**, so
        /// "HDL cholesterol" is never consumed by the bare "cholesterol".
        ///
        /// ⚠️ Written as `normaliseLabel` leaves a label: punctuation other than
        /// `/ : - + ( )` becomes a space, runs of space collapse, and a slash
        /// closes up against its neighbours. So a synonym carrying a full stop —
        /// "h. pylori" — or a spaced slash — "hiv 1 / 2" — can never match
        /// anything at all, and
        /// `LabAnalyteCatalogTests.testEverySynonymMatchesItsOwnEntry` is what
        /// catches both.
        public let synonyms: [String]
        /// Units this analyte is reported in, mapped to a multiplier that
        /// converts into `canonicalUnit`. The canonical unit maps to 1. Empty
        /// for a qualitative analyte, which converts nothing.
        public let unitFactors: [String: Double]
        /// The widest value that could honestly have been printed, in the
        /// canonical unit. Anything outside is treated as a misread.
        public let plausible: ClosedRange<Double>
        /// What this analyte is about, for grouping on the data page.
        public let panel: LabPanel
        /// Who else might read this off the screen. `.ordinary` unless stated,
        /// so every entry that predates the axis is unchanged by it.
        public let sensitivity: LabSensitivity
        /// Whether a laboratory **also** prints this analyte as a word, on an
        /// entry that otherwise carries a unit and a real magnitude.
        ///
        /// ⚠️ **Meaningless on an entry with no canonical unit**, which is
        /// already `.word` whatever this says — nothing reads this property
        /// directly except `form`, and
        /// `LabAnalyteCatalogTests.testADualFormEntryDeclaresBothAUnitAndAWord`
        /// is what stops the two being set into a contradiction.
        public let alsoReportedAsWord: Bool

        public init(key: String, displayName: String, canonicalUnit: String,
                    groundingKind: GroundingKind? = nil, synonyms: [String],
                    unitFactors: [String: Double], plausible: ClosedRange<Double>,
                    panel: LabPanel, sensitivity: LabSensitivity = .ordinary,
                    alsoReportedAsWord: Bool = false) {
            self.key = key
            self.displayName = displayName
            self.canonicalUnit = canonicalUnit
            self.groundingKind = groundingKind
            self.synonyms = synonyms
            self.unitFactors = unitFactors
            self.plausible = plausible
            self.panel = panel
            self.sensitivity = sensitivity
            self.alsoReportedAsWord = alsoReportedAsWord
        }

        /// Which of the three shapes a report may print for this analyte.
        ///
        /// **Derived, never declared twice.** The canonical unit already says
        /// whether a number is possible and `alsoReportedAsWord` says whether a
        /// word is; a third stored field repeating the answer is a field that can
        /// disagree with the two it summarises.
        public var form: LabReportedForm {
            if canonicalUnit.isEmpty { return .word }
            return alsoReportedAsWord ? .either : .measurement
        }

        /// Whether the laboratory reports this analyte as a word **and nothing
        /// else**. Derived from the absent canonical unit rather than declared
        /// beside it, so the two cannot disagree.
        ///
        /// ⚠️ **This is not "can this be a word".** A `.either` analyte answers
        /// `false` here and still reads *Negative* off a real report. Ask `form`
        /// when the question is what a line may say; ask this one only when the
        /// question is whether a number means anything at all — conversion, and
        /// the plausible range.
        public var isQualitative: Bool { form == .word }

        /// The plausible range for an analyte that has no magnitude.
        ///
        /// ⚠️ **Nothing a report can print falls inside it, and that is the
        /// point.** A qualitative result is a word; any number lifted off one of
        /// these lines is a signal-to-cutoff index, a titre or a specimen
        /// number, never a measurement of the finding. Failing the magnitude
        /// check marks the row doubtful (`LabValueCheck.isFailure`) instead of
        /// filing a number that reads like a result.
        ///
        /// A range rather than `nil` because `LabReportParser` and
        /// `LabModelVerifier` both read `plausible` unconditionally, and a bound
        /// below every printable number is the honest way to say "no number
        /// belongs here" without making those two call sites optional.
        public static let noMagnitude: ClosedRange<Double> = -2 ... -1

        /// A catalogued analyte the laboratory reports as a word.
        ///
        /// The factory exists so the three things that must travel together —
        /// no unit, no unit table, no magnitude — cannot be given separately and
        /// half-forgotten. `sensitivity` defaults to `.protected` because every
        /// qualitative analyte catalogued so far is a serology or STI result;
        /// over-protecting a bowel-screen antigen is a smaller mistake than
        /// under-protecting an HIV one, and the direction of that trade is the
        /// whole reason `LabSensitivity` exists.
        static func qualitative(key: String, displayName: String,
                                synonyms: [String], panel: LabPanel,
                                sensitivity: LabSensitivity = .protected) -> Entry {
            Entry(key: key, displayName: displayName, canonicalUnit: "",
                  groundingKind: nil, synonyms: synonyms, unitFactors: [:],
                  plausible: noMagnitude, panel: panel, sensitivity: sensitivity)
        }

        /// A catalogued analyte a laboratory prints **either** way.
        ///
        /// Everything a measurement entry needs — a unit, a table to convert into
        /// it, and a real plausible range — plus the flag, because a dual-form
        /// entry that kept `noMagnitude` would mark every genuine titre
        /// implausible, and one that kept an empty unit table would mark every
        /// genuine unit unrecognised. The factory names the intent at the call
        /// site; the combination it cannot express — the flag with no unit, which
        /// `form` silently reads as `.word` — is held by a test, the same way
        /// every other invariant in this catalogue is.
        ///
        /// `sensitivity` defaults to `.protected` for the reason the qualitative
        /// factory does: what has been dual-form so far is serology.
        static func dualForm(key: String, displayName: String, canonicalUnit: String,
                             synonyms: [String], unitFactors: [String: Double],
                             plausible: ClosedRange<Double>, panel: LabPanel,
                             sensitivity: LabSensitivity = .protected) -> Entry {
            Entry(key: key, displayName: displayName, canonicalUnit: canonicalUnit,
                  groundingKind: nil, synonyms: synonyms, unitFactors: unitFactors,
                  plausible: plausible, panel: panel, sensitivity: sensitivity,
                  alsoReportedAsWord: true)
        }

        public var analyte: LabAnalyte {
            LabAnalyte(key: key, displayName: displayName,
                       canonicalUnit: isQualitative ? nil : canonicalUnit,
                       groundingKind: groundingKind, isKnown: true)
        }
    }

    /// mmol/L per mg/dL, cholesterol and its fractions.
    static let cholesterolFactor = 38.67
    /// mmol/L per mg/dL, triglycerides (a different molecular weight, and
    /// getting this wrong by reusing the cholesterol factor is a real and
    /// silent 2.3x error).
    static let triglycerideFactor = 88.57
    /// mmol/L per mg/dL, glucose.
    static let glucoseFactor = 18.02

    public static let entries: [Entry] = [
        // ---- Lipids. The floor the reader named, and the two that already
        // feed SCORE2 and ASCVD as grounding facts.
        Entry(key: "total_cholesterol", displayName: "Total cholesterol",
              canonicalUnit: "mmol/L", groundingKind: .totalCholesterol,
              synonyms: ["total cholesterol", "cholesterol total", "serum cholesterol",
                         "chol total", "total chol", "cholesterol"],
              unitFactors: ["mmol/l": 1, "mg/dl": 1 / cholesterolFactor],
              plausible: 0.5...25, panel: .lipids),
        Entry(key: "hdl_cholesterol", displayName: "HDL cholesterol",
              canonicalUnit: "mmol/L", groundingKind: .hdlCholesterol,
              synonyms: ["hdl cholesterol", "cholesterol hdl", "hdl-c", "hdl chol", "hdl"],
              unitFactors: ["mmol/l": 1, "mg/dl": 1 / cholesterolFactor],
              plausible: 0.1...6, panel: .lipids),
        Entry(key: "ldl_cholesterol", displayName: "LDL cholesterol",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["ldl cholesterol", "cholesterol ldl", "ldl-c", "ldl chol",
                         "ldl calculated", "ldl"],
              unitFactors: ["mmol/l": 1, "mg/dl": 1 / cholesterolFactor],
              plausible: 0.1...20, panel: .lipids),
        Entry(key: "non_hdl_cholesterol", displayName: "Non-HDL cholesterol",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["non hdl cholesterol", "non-hdl cholesterol", "non-hdl-c", "non hdl"],
              unitFactors: ["mmol/l": 1, "mg/dl": 1 / cholesterolFactor],
              plausible: 0.1...22, panel: .lipids),
        Entry(key: "triglycerides", displayName: "Triglycerides",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["triglycerides", "triglyceride", "trigs", "tg"],
              unitFactors: ["mmol/l": 1, "mg/dl": 1 / triglycerideFactor],
              plausible: 0.1...40, panel: .lipids),
        Entry(key: "cholesterol_hdl_ratio", displayName: "Cholesterol : HDL ratio",
              canonicalUnit: "ratio", groundingKind: nil,
              synonyms: ["cholesterol/hdl ratio", "chol/hdl ratio", "chol:hdl",
                         "cholesterol hdl ratio", "tc/hdl"],
              unitFactors: ["ratio": 1, "": 1],
              plausible: 0.5...30, panel: .lipids),

        // ---- Glycaemic. HbA1c is the other half of the floor.
        //
        // ⚠️ Two units in genuine parallel use and NOT interconvertible by a
        // constant: mmol/mol (IFCC) and % (DCCT/NGSP) are related by
        // % = mmol/mol / 10.929 + 2.15. A single multiplier would be wrong at
        // every value, so the conversion is handled specially in
        // `convert(_:from:for:)` and this table carries the canonical unit only.
        Entry(key: "hba1c", displayName: "HbA1c",
              canonicalUnit: "mmol/mol", groundingKind: nil,
              synonyms: ["hba1c", "haemoglobin a1c", "hemoglobin a1c",
                         "glycated haemoglobin", "glycated hemoglobin", "a1c"],
              unitFactors: ["mmol/mol": 1],
              plausible: 10...200, panel: .glycaemic),
        Entry(key: "glucose", displayName: "Glucose",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["fasting glucose", "glucose fasting", "plasma glucose",
                         "blood glucose", "glucose"],
              unitFactors: ["mmol/l": 1, "mg/dl": 1 / glucoseFactor],
              plausible: 0.5...60, panel: .glycaemic),

        // ---- Renal.
        Entry(key: "creatinine", displayName: "Creatinine",
              canonicalUnit: "umol/L", groundingKind: nil,
              synonyms: ["creatinine", "serum creatinine"],
              unitFactors: ["umol/l": 1, "µmol/l": 1, "mg/dl": 88.42],
              plausible: 10...2000, panel: .renal),
        Entry(key: "egfr", displayName: "eGFR",
              canonicalUnit: "mL/min/1.73m2", groundingKind: nil,
              synonyms: ["egfr", "estimated gfr", "gfr"],
              unitFactors: ["ml/min/1.73m2": 1, "ml/min": 1, "": 1],
              plausible: 1...200, panel: .renal),
        Entry(key: "urea", displayName: "Urea",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["urea", "blood urea nitrogen", "bun"],
              unitFactors: ["mmol/l": 1, "mg/dl": 0.357],
              plausible: 0.5...80, panel: .renal),
        Entry(key: "sodium", displayName: "Sodium",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["sodium", "na+", "serum sodium"],
              unitFactors: ["mmol/l": 1, "meq/l": 1],
              plausible: 90...190, panel: .renal),
        Entry(key: "potassium", displayName: "Potassium",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["potassium", "k+", "serum potassium"],
              unitFactors: ["mmol/l": 1, "meq/l": 1],
              plausible: 1...12, panel: .renal),

        // The rest of what an Australian "UEC" prints. Chloride and bicarbonate
        // are two thirds of the anion gap, which is catalogued beside them
        // rather than recomputed: the laboratory's gap is the one printed
        // against the reader's own reference interval, and a recomputed one
        // would silently disagree with the paper in their hand.
        Entry(key: "chloride", displayName: "Chloride",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["serum chloride", "chloride", "cl-"],
              unitFactors: ["mmol/l": 1, "meq/l": 1],
              plausible: 50...180, panel: .renal),
        Entry(key: "bicarbonate", displayName: "Bicarbonate",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["serum bicarbonate", "bicarbonate", "total co2",
                         "co2 total", "hco3"],
              unitFactors: ["mmol/l": 1, "meq/l": 1],
              plausible: 1...60, panel: .renal),
        // ⚠️ **No "ag" synonym.** Two letters that also open the serology half
        // of this catalogue: a report printing "HIV Ag Ab" without the slash
        // normalises to a label containing " ag ", and an HIV screen filed as an
        // electrolyte is not a rounding error.
        //
        // The lower bound is negative because a negative anion gap is a real
        // printed result (bromide, lithium, a paraprotein), not a misread.
        Entry(key: "anion_gap", displayName: "Anion gap",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["anion gap"],
              unitFactors: ["mmol/l": 1, "meq/l": 1],
              plausible: -20...60, panel: .renal),
        // ⚠️ No bare "phos". "Alk. Phos." normalises to "alk phos", which
        // longest-first would keep on ALP — but only for as long as ALP keeps
        // that synonym, and a phosphate row that depends on another entry's
        // spelling is one edit away from wrong.
        Entry(key: "phosphate", displayName: "Phosphate",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["inorganic phosphate", "serum phosphate", "phosphate"],
              // 10 / 30.97 — phosphorus, not phosphate, is what mg/dL counts.
              unitFactors: ["mmol/l": 1, "mg/dl": 0.3229],
              plausible: 0.05...10, panel: .renal),
        Entry(key: "magnesium", displayName: "Magnesium",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["serum magnesium", "magnesium", "mg++"],
              // Divalent: 1 mEq/L is half a mmol/L. 10 / 24.305 for mg/dL.
              unitFactors: ["mmol/l": 1, "meq/l": 0.5, "mg/dl": 0.4114],
              plausible: 0.05...10, panel: .renal),
        // ⚠️ **The three calciums, and the two ways they can eat each other.**
        //
        // A corrected calcium is a *calculated* number — total calcium adjusted
        // for albumin — and an Australian CMP prints it directly under the
        // measured total it was calculated from. On a low albumin the two differ
        // by a tenth of a mmol/L, which is a difference nothing downstream could
        // recover: a stored value cannot say which measurement it was.
        //
        // Until 2026-08-09 only the calculated one was catalogued and the bare
        // word was deliberately absent, so the reader's measured total arrived
        // under the laboratory's own label and started a second trend beside the
        // corrected one. It is now its own entry, which is what the comment this
        // replaces anticipated: the parenthesised and albumin-prefixed spellings
        // below were already carried "so that longest-first keeps this row even
        // if a later session does catalogue the bare word".
        //
        // ⚠️ **`calcium` as a synonym is what makes the third row necessary.**
        // "Calcium (ionised)" contains "calcium", and ionised calcium is a
        // different fraction at about half the number — only the longest-first
        // sort keeps a blood-gas ionised calcium off the total's trend. Cataloguing
        // it is the guard, not a separate ambition: without it the bare word is a
        // silent wrong match rather than an honest uncatalogued one.
        //
        // ⚠️ A 24-hour **urine** calcium matches the total's row too, and is
        // printed in mmol/day, which converts to nothing here — so it arrives
        // `unitUnrecognised` and doubtful. That is a flagged wrong analyte rather
        // than a silent one; `LabReportParser.Scan.specimen` is what a caller has
        // to read to do better than flagging it.
        Entry(key: "corrected_calcium", displayName: "Calcium (corrected)",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["albumin corrected calcium", "calcium (corrected)",
                         "corrected calcium", "calcium corrected",
                         "adjusted calcium", "calcium (adjusted)"],
              // 10 / 40.08.
              unitFactors: ["mmol/l": 1, "mg/dl": 0.2495],
              plausible: 0.5...6, panel: .renal),
        Entry(key: "calcium", displayName: "Calcium",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["calcium (total)", "total calcium", "calcium total",
                         "serum calcium", "calcium"],
              // 10 / 40.08, and mEq/L is halved: calcium is divalent, the same
              // trap magnesium carries two entries up.
              unitFactors: ["mmol/l": 1, "mg/dl": 0.2495, "meq/l": 0.5],
              plausible: 0.5...6, panel: .renal),
        Entry(key: "ionised_calcium", displayName: "Calcium (ionised)",
              canonicalUnit: "mmol/L", groundingKind: nil,
              synonyms: ["calcium (ionised)", "calcium (ionized)",
                         "ionised calcium", "ionized calcium",
                         "calcium ionised", "calcium ionized", "free calcium"],
              unitFactors: ["mmol/l": 1, "mg/dl": 0.2495, "meq/l": 0.5],
              // Roughly half the total, and the range is wide for the usual
              // reason: it catches a misplaced decimal point, not a finding.
              plausible: 0.1...4, panel: .renal),

        // ---- Liver and pancreas.
        Entry(key: "alt", displayName: "ALT",
              canonicalUnit: "U/L", groundingKind: nil,
              synonyms: ["alanine aminotransferase", "alanine transaminase", "alt", "sgpt"],
              unitFactors: ["u/l": 1, "iu/l": 1],
              plausible: 1...5000, panel: .liver),
        Entry(key: "ast", displayName: "AST",
              canonicalUnit: "U/L", groundingKind: nil,
              synonyms: ["aspartate aminotransferase", "aspartate transaminase", "ast", "sgot"],
              unitFactors: ["u/l": 1, "iu/l": 1],
              plausible: 1...5000, panel: .liver),
        Entry(key: "ggt", displayName: "GGT",
              canonicalUnit: "U/L", groundingKind: nil,
              synonyms: ["gamma gt", "gamma-gt", "gamma glutamyl transferase", "ggt"],
              unitFactors: ["u/l": 1, "iu/l": 1],
              plausible: 1...5000, panel: .liver),
        Entry(key: "alp", displayName: "Alkaline phosphatase",
              canonicalUnit: "U/L", groundingKind: nil,
              synonyms: ["alkaline phosphatase", "alk phos", "alp"],
              unitFactors: ["u/l": 1, "iu/l": 1],
              plausible: 1...3000, panel: .liver),
        Entry(key: "bilirubin", displayName: "Bilirubin (total)",
              canonicalUnit: "umol/L", groundingKind: nil,
              synonyms: ["total bilirubin", "bilirubin total", "bilirubin"],
              unitFactors: ["umol/l": 1, "µmol/l": 1, "mg/dl": 17.1],
              plausible: 1...800, panel: .liver),
        Entry(key: "albumin", displayName: "Albumin",
              canonicalUnit: "g/L", groundingKind: nil,
              synonyms: ["albumin", "serum albumin"],
              unitFactors: ["g/l": 1, "g/dl": 10],
              plausible: 5...80, panel: .liver),
        // Pancreatic, not hepatic — it sits here because it is printed on the
        // same panel and because `.liver` is now titled for both. The ceiling is
        // high on purpose: acute pancreatitis prints five figures, and a
        // plausible range that called one a misread would suppress the single
        // most urgent number a laboratory can send.
        Entry(key: "lipase", displayName: "Lipase",
              canonicalUnit: "U/L", groundingKind: nil,
              synonyms: ["serum lipase", "lipase"],
              unitFactors: ["u/l": 1, "iu/l": 1],
              plausible: 1...30000, panel: .liver),

        // ---- Thyroid.
        Entry(key: "tsh", displayName: "TSH",
              canonicalUnit: "mIU/L", groundingKind: nil,
              synonyms: ["thyroid stimulating hormone", "thyroid-stimulating hormone",
                         "tsh"],
              unitFactors: ["miu/l": 1, "uiu/ml": 1, "µiu/ml": 1, "mu/l": 1],
              plausible: 0.001...200, panel: .thyroid),
        Entry(key: "free_t4", displayName: "Free T4",
              canonicalUnit: "pmol/L", groundingKind: nil,
              synonyms: ["free thyroxine", "free t4", "ft4", "t4 free"],
              unitFactors: ["pmol/l": 1, "ng/dl": 12.87],
              plausible: 1...120, panel: .thyroid),
        Entry(key: "free_t3", displayName: "Free T3",
              canonicalUnit: "pmol/L", groundingKind: nil,
              synonyms: ["free triiodothyronine", "free t3", "ft3", "t3 free"],
              unitFactors: ["pmol/l": 1, "pg/ml": 1.536],
              plausible: 0.5...60, panel: .thyroid),

        // ---- Haematology.
        Entry(key: "haemoglobin", displayName: "Haemoglobin",
              canonicalUnit: "g/L", groundingKind: nil,
              synonyms: ["haemoglobin", "hemoglobin", "hgb", "hb"],
              unitFactors: ["g/l": 1, "g/dl": 10],
              plausible: 20...250, panel: .haematology),
        Entry(key: "haematocrit", displayName: "Haematocrit",
              canonicalUnit: "%", groundingKind: nil,
              synonyms: ["haematocrit", "hematocrit", "hct", "pcv"],
              unitFactors: ["%": 1, "l/l": 100, "": 1],
              plausible: 5...80, panel: .haematology),
        Entry(key: "mcv", displayName: "MCV",
              canonicalUnit: "fL", groundingKind: nil,
              synonyms: ["mean corpuscular volume", "mean cell volume", "mcv"],
              // A femtolitre and a cubic micron are the same volume.
              unitFactors: ["fl": 1, "um^3": 1, "um3": 1],
              plausible: 20...200, panel: .haematology),
        // ⚠️ **The only cell count in this catalogue that is not 10^9/L.** Red
        // cells are a thousand times commoner than white ones, so the report
        // prints 10^12/L; storing a red cell count against the white cell unit
        // reads as 4,700 where 4.7 was meant, and both numbers look like
        // something a blood count could say.
        Entry(key: "red_cell_count", displayName: "Red cell count",
              canonicalUnit: "10^12/L", groundingKind: nil,
              synonyms: ["red blood cell count", "red cell count", "erythrocytes",
                         "rbc", "rcc"],
              unitFactors: ["10^12/l": 1, "x10^12/l": 1, "10*12/l": 1, "10e12/l": 1,
                            "10^6/ul": 1, "m/ul": 1],
              plausible: 0...12, panel: .haematology),
        Entry(key: "white_cell_count", displayName: "White cell count",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["white blood cell count", "white cell count", "leucocytes",
                         "leukocytes", "wbc", "wcc"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 0.1...300, panel: .haematology),

        // The differential, as **absolute counts**.
        //
        // ⚠️ A differential line prints the percentage beside the absolute —
        // "Neutrophils 65 % 5.2" — and the plausible range cannot separate them,
        // because 65 is a perfectly possible neutrophil count in 10^9/L. The
        // unit token is the only discriminator there is, so `.unitMissing` on
        // one of these rows deserves more suspicion than on any other analyte
        // here, and none of the five carries a percentage in its unit table:
        // an unrecognised "%" is a stated failure, while a silent one is not.
        //
        // Every lower bound is zero because zero is printable and real —
        // agranulocytosis prints 0.0 neutrophils, and that is the result, not a
        // misread. The ceilings are leukaemic rather than ordinary for the same
        // reason the liver enzymes run to 5000.
        Entry(key: "neutrophils", displayName: "Neutrophils",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["absolute neutrophil count", "neutrophil count",
                         "neutrophils", "neutrophils absolute"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 0...200, panel: .haematology),
        Entry(key: "lymphocytes", displayName: "Lymphocytes",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["absolute lymphocyte count", "lymphocyte count",
                         "lymphocytes", "lymphocytes absolute"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 0...500, panel: .haematology),
        Entry(key: "monocytes", displayName: "Monocytes",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["absolute monocyte count", "monocyte count", "monocytes",
                         "monocytes absolute"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 0...100, panel: .haematology),
        Entry(key: "eosinophils", displayName: "Eosinophils",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["absolute eosinophil count", "eosinophil count",
                         "eosinophils", "eosinophils absolute"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 0...100, panel: .haematology),
        Entry(key: "basophils", displayName: "Basophils",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["absolute basophil count", "basophil count", "basophils",
                         "basophils absolute"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 0...50, panel: .haematology),
        Entry(key: "platelets", displayName: "Platelets",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["platelet count", "platelets", "plt"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 1...3000, panel: .haematology),
        Entry(key: "ferritin", displayName: "Ferritin",
              canonicalUnit: "ug/L", groundingKind: nil,
              synonyms: ["ferritin", "serum ferritin"],
              unitFactors: ["ug/l": 1, "µg/l": 1, "ng/ml": 1],
              plausible: 1...20000, panel: .haematology),

        // Iron studies, the rest of the block ferritin arrives in.
        //
        // ⚠️ "Transferrin saturation" **contains** "transferrin", which is the
        // HDL-under-cholesterol shape one panel over: only the longest-first
        // sort in `synonymIndex` keeps a percentage off the g/L row.
        //
        // Serum iron itself is deliberately absent. It was not in the corpus
        // this batch was measured against, and a unit table written from memory
        // is exactly the kind of entry that looks right and converts wrong.
        Entry(key: "transferrin", displayName: "Transferrin",
              canonicalUnit: "g/L", groundingKind: nil,
              synonyms: ["serum transferrin", "transferrin"],
              unitFactors: ["g/l": 1, "g/dl": 10, "mg/dl": 0.01],
              plausible: 0.1...10, panel: .haematology),
        Entry(key: "tibc", displayName: "TIBC",
              canonicalUnit: "umol/L", groundingKind: nil,
              synonyms: ["total iron binding capacity", "iron binding capacity",
                         "tibc"],
              // 1 µg/dL of iron-binding capacity is 0.179 µmol/L.
              unitFactors: ["umol/l": 1, "µmol/l": 1, "ug/dl": 0.179],
              plausible: 5...200, panel: .haematology),
        // The ceiling is above 100 on purpose: saturations of 100–110% are
        // printed in iron overload by assay imprecision, and calling a real
        // reading a misread is the failure this range exists to avoid.
        Entry(key: "transferrin_saturation", displayName: "Transferrin saturation",
              canonicalUnit: "%", groundingKind: nil,
              synonyms: ["transferrin saturation", "transferrin sat",
                         "iron saturation", "tsat"],
              unitFactors: ["%": 1, "": 1],
              plausible: 0...120, panel: .haematology),
        Entry(key: "vitamin_b12", displayName: "Vitamin B12",
              canonicalUnit: "pmol/L", groundingKind: nil,
              synonyms: ["vitamin b12", "vitamin b-12", "cobalamin", "b12"],
              unitFactors: ["pmol/l": 1, "ng/l": 0.738, "pg/ml": 0.738],
              plausible: 10...5000, panel: .haematology),
        Entry(key: "folate", displayName: "Folate",
              canonicalUnit: "nmol/L", groundingKind: nil,
              synonyms: ["serum folate", "folate", "folic acid"],
              unitFactors: ["nmol/l": 1, "ug/l": 2.266, "ng/ml": 2.266],
              plausible: 0.5...300, panel: .haematology),

        // ---- Inflammation and the rest.
        Entry(key: "crp", displayName: "CRP",
              canonicalUnit: "mg/L", groundingKind: nil,
              synonyms: ["c reactive protein", "c-reactive protein",
                         "high sensitivity crp", "hs-crp", "crp"],
              unitFactors: ["mg/l": 1, "mg/dl": 10],
              plausible: 0.05...600, panel: .inflammation),
        Entry(key: "vitamin_d", displayName: "Vitamin D",
              canonicalUnit: "nmol/L", groundingKind: nil,
              synonyms: ["25-hydroxy vitamin d", "25 oh vitamin d", "vitamin d",
                         "25(oh)d"],
              unitFactors: ["nmol/l": 1, "ng/ml": 2.496],
              plausible: 1...800, panel: .inflammation),
        Entry(key: "uric_acid", displayName: "Uric acid",
              canonicalUnit: "umol/L", groundingKind: nil,
              synonyms: ["uric acid", "urate", "serum urate"],
              unitFactors: ["umol/l": 1, "µmol/l": 1, "mg/dl": 59.48],
              plausible: 20...1500, panel: .inflammation),
        Entry(key: "testosterone", displayName: "Testosterone",
              canonicalUnit: "nmol/L", groundingKind: nil,
              synonyms: ["total testosterone", "testosterone"],
              unitFactors: ["nmol/l": 1, "ng/dl": 0.0347],
              plausible: 0.05...120, panel: .hormones),

        // ---- Specimen quality, which is not a finding about the reader at all.
        //
        // The haemolysis index describes the *sample*: it is the reason a
        // potassium or an LDH on the same report cannot be trusted. Catalogued
        // so that reason survives instead of being discarded at the parser, and
        // filed under `.inflammation` — whose title already carries "& other" —
        // rather than `.other`, which claims the app did not recognise it.
        //
        // ⚠️ Two conventions share the name and do not convert into each other:
        // an ordinal grade (0–4, printed "1+") and an analyser index in
        // free-haemoglobin units running to about a thousand. The range spans
        // both because the app cannot tell which it is holding — which is also
        // why this number must never be compared across reports.
        //
        // ⚠️ It is printed with no unit and still carries the pseudo-unit
        // `index`, because an empty `canonicalUnit` means *qualitative* in this
        // file and a haemolysis index is a number.
        Entry(key: "haemolysis_index", displayName: "Haemolysis index",
              canonicalUnit: "index", groundingKind: nil,
              synonyms: ["haemolysis index", "hemolysis index", "haemolytic index"],
              unitFactors: ["index": 1, "": 1],
              plausible: 0...2000, panel: .inflammation),

        // ---- Infection and immunity. Fourteen analytes the parser could read
        //      and had nowhere to put: every one is reported as a word, and
        //      every one was landing in `.other` — "Not recognised" — which is a
        //      claim about the app's knowledge and was false for all fourteen.
        //
        // Every entry here is `.protected`. Two rules hold the synonyms
        // together, and both are shipped defects waiting to happen rather than
        // tidiness:
        //
        // 1. **Every synonym carries its method.** The same organism is reported
        //    by serology *and* by nucleic-acid test, and they are different
        //    findings: "Varicella zoster IgG" says the reader met it once,
        //    "Varicella zoster DNA" says it is replicating now. A bare organism
        //    name files one as the other, so there are no bare organism names.
        // 2. **No synonym spans an opposite finding.** Hepatitis B surface
        //    *antigen* and surface *antibody* differ by two letters at the end
        //    and mean opposite things — `LabQualitativeOrdinal` carries the same
        //    warning for the words themselves. "hepatitis b surface" is
        //    deliberately absent so neither can absorb the other, and the same
        //    goes for "hsv" between HSV1 and HSV2.
        .qualitative(key: "hiv_ag_ab", displayName: "HIV antigen/antibody",
                     // ⚠️ No bare "hiv": an HIV RNA viral load is a number in
                     // copies/mL and would file as this screen's word.
                     //
                     // "total antibody" is the same screen under the spelling one
                     // of the reader's laboratories uses — `HIV 1 / 2 total
                     // antibody`, which matched nothing here and started its own
                     // trend beside this one. Both slash spellings collapse to
                     // one synonym because `match(label:)` now closes the spaces
                     // around a slash; see the ⚠️ on `normaliseLabel`.
                     synonyms: ["hiv 1/2 antigen/antibody", "hiv antibody/antigen",
                                "hiv antigen/antibody", "hiv 1/2 total antibody",
                                "hiv total antibody", "hiv ag/ab", "hiv ag ab",
                                "hiv screen", "hiv combo"],
                     panel: .infection),
        // ⚠️ **"HepB" is one word on the reader's report**, and a synonym written
        // "hep b" cannot match it: `match(label:)` collapses punctuation to
        // spaces but never splits a word. All three hepatitis B rows carry the
        // closed spelling for that reason — fixing only the antibody would leave
        // its two neighbours, printed in the same style on the same page, filed
        // as uncatalogued analytes beside a catalogued sibling.
        .qualitative(key: "hep_b_surface_antigen",
                     displayName: "Hepatitis B surface antigen",
                     synonyms: ["hepatitis b surface antigen", "hep b surface antigen",
                                "hepb surface antigen", "hbs antigen", "hbsag"],
                     panel: .infection),
        // ⚠️ **The one dual-form entry in this catalogue, and the reason
        // `LabReportedForm` exists.** The reader's report prints this test as
        // `Negative` on one line and `<5 IU/L` on another, and its own comment —
        // *not immune (HBsAb <10 IU/L)* — is a sentence about the number. Held as
        // a word it made every titre doubtful; held as a measurement it threw
        // every word away.
        //
        // ⚠️ **mIU/mL and IU/L are the same quantity**, by arithmetic rather than
        // by a measured factor: a milli-international-unit per millilitre is an
        // international unit per litre. Both are carried, and so is the bare
        // `U/L` some analysers print, because an unrecognised unit on a line the
        // reader can check at a glance is the false alarm this file spends its
        // length avoiding.
        //
        // ⚠️ **The other thirteen serology rows are deliberately not dual-form.**
        // Every one of them prints a number that is *not* the finding — a
        // signal-to-cutoff index beside a screen, a Ct value or a viral load
        // beside a nucleic-acid test — and `Entry.noMagnitude` is what stops that
        // number being stored as the result. Giving one of them a unit and a real
        // range would retire that guard for the sake of a titre nothing has
        // observed. The nearest miss is `hep_a_igg`, which some laboratories do
        // report in mIU/mL; it stays word-only until a report in the corpus shows
        // otherwise, on the same rule that keeps serum iron out of this file.
        .dualForm(key: "hep_b_surface_antibody",
                  displayName: "Hepatitis B surface antibody",
                  canonicalUnit: "IU/L",
                  synonyms: ["hepatitis b surface antibody", "hep b surface antibody",
                             "hepb surface antibody", "hbs antibody", "anti-hbs",
                             "hbsab"],
                  unitFactors: ["iu/l": 1, "miu/ml": 1, "u/l": 1],
                  // A titre after vaccination is reported on a dilution and runs
                  // into the thousands; zero is printable and real.
                  plausible: 0...100_000, panel: .infection),
        .qualitative(key: "hep_b_core_antibody",
                     displayName: "Hepatitis B core antibody",
                     synonyms: ["hepatitis b core antibody", "hep b core antibody",
                                "hepb core antibody", "hbc antibody", "anti-hbc",
                                "hbcab"],
                     panel: .infection),
        .qualitative(key: "hep_a_igg", displayName: "Hepatitis A IgG",
                     // IgG in every spelling: hepatitis A IgM is acute infection,
                     // IgG is past exposure or vaccination, and "hepatitis a
                     // antibody" alone does not say which was measured.
                     synonyms: ["hepatitis a antibody igg", "hepatitis a igg antibody",
                                "hepatitis a igg", "hep a igg", "hav igg"],
                     panel: .infection),
        .qualitative(key: "hep_c_igg", displayName: "Hepatitis C IgG",
                     synonyms: ["hepatitis c antibody", "hepatitis c igg",
                                "hep c antibody", "hcv antibody", "hcv igg",
                                "anti-hcv"],
                     panel: .infection),
        // ⚠️ The bare word is kept here — Australian reports print "Syphilis"
        // and nothing else — which puts an obligation on anyone adding RPR or
        // VDRL later: those are non-treponemal *titres*, a different result, and
        // they must arrive with synonyms longer than this one ("syphilis rpr")
        // or longest-first will hand their titre to this screen.
        .qualitative(key: "syphilis_treponemal",
                     displayName: "Syphilis (treponemal screen)",
                     synonyms: ["treponema pallidum antibody", "syphilis treponemal antibody",
                                "treponemal antibody", "syphilis serology",
                                "syphilis screen", "syphilis cmia", "syphilis eia",
                                "syphilis"],
                     panel: .infection),
        .qualitative(key: "chlamydia_trachomatis_nat",
                     displayName: "Chlamydia trachomatis (NAT)",
                     // ⚠️ No bare "chlamydia": C. pneumoniae is a respiratory
                     // serology and would land in the reader's STI results.
                     synonyms: ["chlamydia trachomatis nat", "chlamydia trachomatis pcr",
                                "chlamydia trachomatis dna", "chlamydia trachomatis"],
                     panel: .infection),
        .qualitative(key: "neisseria_gonorrhoeae_nat",
                     displayName: "Neisseria gonorrhoeae (NAT)",
                     synonyms: ["neisseria gonorrhoeae nat", "neisseria gonorrhoeae pcr",
                                "neisseria gonorrhoeae dna", "neisseria gonorrhoeae",
                                "n gonorrhoeae", "gonorrhoeae"],
                     panel: .infection),
        // ⚠️ HSV1 and HSV2 are the herpes edition of the hepatitis B pair: one
        // character apart, printed one under the other, opposite in what they
        // disclose. Three spellings each because "HSV 1", "HSV1" and "HSV-1" all
        // normalise differently — the space and the hyphen both survive
        // `match(label:)`.
        .qualitative(key: "hsv1_dna", displayName: "Herpes simplex 1 DNA",
                     synonyms: ["herpes simplex virus 1 dna", "herpes simplex 1 dna",
                                "hsv-1 dna", "hsv 1 dna", "hsv1 dna",
                                "hsv-1 pcr", "hsv 1 pcr", "hsv1 pcr"],
                     panel: .infection),
        .qualitative(key: "hsv2_dna", displayName: "Herpes simplex 2 DNA",
                     synonyms: ["herpes simplex virus 2 dna", "herpes simplex 2 dna",
                                "hsv-2 dna", "hsv 2 dna", "hsv2 dna",
                                "hsv-2 pcr", "hsv 2 pcr", "hsv2 pcr"],
                     panel: .infection),
        .qualitative(key: "vzv_dna", displayName: "Varicella zoster DNA",
                     synonyms: ["varicella zoster virus dna", "varicella zoster dna",
                                "varicella zoster pcr", "vzv dna", "vzv pcr"],
                     panel: .infection),
        .qualitative(key: "adenovirus_dna", displayName: "Adenovirus DNA",
                     synonyms: ["adenovirus dna", "adenovirus pcr", "adenovirus nat"],
                     panel: .infection),
        // ⚠️ Written without the full stop the laboratory prints: `match(label:)`
        // turns "H. pylori" into "h pylori", so a synonym carrying the dot could
        // never match anything at all — and would fail silently, which is the
        // whole reason `testEverySynonymMatchesItsOwnEntry` exists.
        //
        // ⚠️ **"Ag" is the spelling the reader's report actually uses** — `Faecal
        // H. pylori Ag (ChLIA)` — and every synonym here said "antigen", so the
        // line landed uncatalogued. The abbreviation is only ever carried behind
        // the organism's name: a bare "ag" synonym is what `anion_gap` two panels
        // up refuses to have, because "HIV Ag Ab" without its slash normalises to
        // a label containing " ag ".
        .qualitative(key: "h_pylori_faecal_antigen",
                     displayName: "H. pylori antigen (faecal)",
                     synonyms: ["helicobacter pylori faecal antigen",
                                "faecal helicobacter pylori antigen",
                                "helicobacter pylori antigen",
                                "faecal h pylori antigen", "h pylori faecal antigen",
                                "helicobacter pylori ag", "faecal h pylori ag",
                                "h pylori faecal ag", "h pylori antigen",
                                "h pylori ag"],
                     panel: .infection)
    ]

    /// Every synonym, longest first, paired with its entry.
    ///
    /// **Longest first is load-bearing.** "HDL cholesterol" contains
    /// "cholesterol"; matching in declaration order would file every HDL under
    /// total cholesterol — which is not a rounding error, it is the wrong
    /// analyte, and it flows straight into SCORE2 as a grounding fact.
    static let synonymIndex: [(label: String, entry: Entry)] = {
        var pairs: [(String, Entry)] = []
        for entry in entries {
            for synonym in entry.synonyms { pairs.append((synonym, entry)) }
        }
        return pairs.sorted { $0.0.count > $1.0.count }
    }()

    public static func entry(forKey key: String) -> Entry? {
        entries.first { $0.key == key }
    }

    /// The catalogued analyte a printed label names, or nil.
    ///
    /// Matches on the **whole label**, normalised: a report line reading
    /// "Serum HDL cholesterol level" should find HDL, but "cholesterol" inside
    /// the word "cholesterolaemia" should not. Word-boundary matching after
    /// punctuation is stripped gives both.
    public static func match(label: String) -> Entry? {
        let normalised = " " + normaliseLabel(label) + " "
        for (synonym, entry) in synonymIndex where normalised.contains(" \(synonym) ")
            || normalised.contains(" \(synonym)(") {
            return entry
        }
        return nil
    }

    /// A printed label reduced to the form synonyms are written in.
    ///
    /// Punctuation other than `/ : - + ( )` becomes a space and runs of space
    /// collapse, so "Alk. Phos." and "alk phos" are the same label.
    ///
    /// ⚠️ **A slash closes up around itself**, and that is a fix rather than
    /// tidiness: the reader's laboratory prints `HIV 1 / 2 total antibody` while
    /// every synonym in this file writes `hiv 1/2 …`, so the spaced form matched
    /// nothing and started its own trend. Doing it here rather than adding a
    /// second spelling to each synonym fixes the whole class at once — and the
    /// hazard it creates is the full stop's twin: **a synonym written with a
    /// spaced slash can now never match anything**, which
    /// `LabAnalyteCatalogTests.testEverySynonymMatchesItsOwnEntry` is what
    /// catches.
    ///
    /// The sentinel spaces are added by the caller *after* this runs, so a label
    /// ending in a slash cannot lose the boundary its match depends on.
    static func normaliseLabel(_ label: String) -> String {
        label.lowercased()
            .map { ch -> Character in
                if ch.isLetter || ch.isNumber || ch == "/" || ch == ":" || ch == "-"
                    || ch == "+" || ch == "(" || ch == ")" { return ch }
                return " "
            }
            .reduce(into: "") { acc, ch in
                if ch == " " && acc.last == " " { return }
                acc.append(ch)
            }
            .replacingOccurrences(of: " /", with: "/")
            .replacingOccurrences(of: "/ ", with: "/")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Convert a printed value into the entry's canonical unit.
    ///
    /// Returns nil when the unit is present but unrecognised — **deliberately
    /// not a silent pass-through.** A value in an unknown unit stored as though
    /// it were canonical is exactly the misread class this whole file exists to
    /// stop, and it is invisible afterwards: the number looks fine.
    ///
    /// A *missing* unit is a different case and is handled by the caller, which
    /// can fall back on the printed reference range — see
    /// `LabValueCheck.unitInference`.
    public static func convert(_ value: Double, from unit: String?,
                               for entry: Entry) -> Double? {
        // A word-only analyte is reported as a word, so **no unit is its
        // canonical unit** — and there is nothing to convert into. An absent
        // unit passes the number through untouched; anything printed as a unit
        // beside a word is not recognised, which is what keeps a signal-to-cutoff
        // index from being stored as though it were the finding.
        //
        // ⚠️ **`.either` does not come through here**, and must not: when a
        // dual-form analyte prints a number it prints a real titre in a real
        // unit, so it converts exactly like any other measurement. `isQualitative`
        // is `form == .word` for precisely this reason — see the ⚠️ on it.
        if entry.isQualitative {
            return (unit ?? "").isEmpty ? value : nil
        }
        guard let unit, !unit.isEmpty else { return nil }
        let key = normaliseUnit(unit)

        // HbA1c's two units are affine, not proportional. `% = mmol/mol/10.929
        // + 2.15`; a multiplier would be wrong at every single value.
        if entry.key == "hba1c" {
            if key == "mmol/mol" { return value }
            if key == "%" { return (value - 2.15) * 10.929 }
            return nil
        }
        guard let factor = entry.unitFactors[key] else { return nil }
        return value * factor
    }

    /// Lower-case, whitespace-free, micro-sign folded to `u`.
    public static func normaliseUnit(_ unit: String) -> String {
        unit.lowercased()
            .replacingOccurrences(of: "μ", with: "u")   // GREEK SMALL LETTER MU
            .replacingOccurrences(of: "µ", with: "u")   // MICRO SIGN
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "litre", with: "l")
            .replacingOccurrences(of: "liter", with: "l")
    }
}

/// What an analyte is about — the grouping the data page reads down.
///
/// Not a clinical taxonomy and not used to score anything: it exists so a
/// thirty-row report does not render as thirty ungrouped lines. An unknown
/// analyte is `.other`, which is honest — the app does not know what it is.
public enum LabPanel: String, Sendable, Codable, CaseIterable, Identifiable {
    case lipids
    case glycaemic
    case renal
    case liver
    case thyroid
    case haematology
    case inflammation
    case hormones
    /// Serology and nucleic-acid tests. Split out on 2026-08-09: fourteen
    /// catalogued analytes were rendering under "Not recognised", which says
    /// something about the app's knowledge and was untrue of all fourteen.
    case infection
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lipids: return "Lipids"
        case .glycaemic: return "Glucose & HbA1c"
        case .renal: return "Kidneys & electrolytes"
        // "& pancreas" since lipase joined it — a lipase filed under a heading
        // reading only "Liver" is a small lie on the one page whose job is to
        // show the reader their own record back unaltered.
        case .liver: return "Liver & pancreas"
        case .thyroid: return "Thyroid"
        case .haematology: return "Blood count & vitamins"
        case .inflammation: return "Inflammation & other"
        case .hormones: return "Hormones"
        case .infection: return "Infection & immunity"
        case .other: return "Not recognised"
        }
    }
}

/// **Who else might be holding the phone.**
///
/// ⚠️ **Not a clinical severity scale, and it must never be rendered as one.**
/// An HIV or herpes result is not a worse finding than a potassium; it is a
/// *disclosure*, and the person it gets disclosed to is whoever the reader hands
/// their phone to, or whoever is beside them on the train when a summary card
/// draws itself. A test the reader chose to have taken is not a result they
/// chose to tell anyone about, and a surface that renders one unasked makes that
/// choice on their behalf.
///
/// The axis exists so a surface can decide once — hold it behind a tap, keep it
/// off a widget, leave it out of a share sheet — rather than every surface
/// re-deciding from the analyte's name. Nothing here says a `.protected` result
/// is bad news: hepatitis B surface *antibody* Negative is the unwanted answer
/// while hepatitis B surface *antigen* Negative is the wanted one (the same
/// counter-example `LabQualitativeOrdinal` is built around), and neither is any
/// of the room's business.
public enum LabSensitivity: String, Sendable, Codable, CaseIterable {
    /// Everything that says nothing about the reader beyond their physiology.
    /// The default, because it is what most analytes are.
    case ordinary
    /// Serology, STI screens, and anything else whose **name alone** discloses
    /// something the reader may not have told the people around them. The name
    /// is the disclosure, not the value: "HIV Ag/Ab" on a lock screen has
    /// already said it, whatever the result turned out to be.
    case protected
}

public extension LabAnalyte {
    /// The panel this analyte belongs to.
    var panel: LabPanel {
        LabAnalyteCatalog.entry(forKey: key)?.panel ?? .other
    }

    /// How carefully this analyte should be put on a screen.
    ///
    /// ⚠️ An **uncatalogued** analyte answers `.ordinary`, and that is a
    /// limitation rather than a judgement: the catalogue is the only place this
    /// app knows anything about an analyte, so a private clinic's HIV viral load
    /// arrives here indistinguishable from a magnesium. A surface that wants to
    /// be careful about the unknown case has to say so itself — `isKnown` is
    /// what tells it which kind it is holding.
    var sensitivity: LabSensitivity {
        LabAnalyteCatalog.entry(forKey: key)?.sensitivity ?? .ordinary
    }
}
