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
public enum LabAnalyteCatalog {

    /// One catalogued analyte and everything needed to read it off a report.
    public struct Entry: Sendable {
        public let key: String
        public let displayName: String
        public let canonicalUnit: String
        public let groundingKind: GroundingKind?
        /// Lower-cased labels, **longest first at match time**, so
        /// "HDL cholesterol" is never consumed by the bare "cholesterol".
        public let synonyms: [String]
        /// Units this analyte is reported in, mapped to a multiplier that
        /// converts into `canonicalUnit`. The canonical unit maps to 1.
        public let unitFactors: [String: Double]
        /// The widest value that could honestly have been printed, in the
        /// canonical unit. Anything outside is treated as a misread.
        public let plausible: ClosedRange<Double>
        /// What this analyte is about, for grouping on the data page.
        public let panel: LabPanel

        public var analyte: LabAnalyte {
            LabAnalyte(key: key, displayName: displayName,
                       canonicalUnit: canonicalUnit,
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

        // ---- Liver.
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
        Entry(key: "white_cell_count", displayName: "White cell count",
              canonicalUnit: "10^9/L", groundingKind: nil,
              synonyms: ["white blood cell count", "white cell count", "leucocytes",
                         "leukocytes", "wbc", "wcc"],
              unitFactors: ["10^9/l": 1, "x10^9/l": 1, "10*9/l": 1, "10e9/l": 1,
                            "k/ul": 1, "/ul": 0.001],
              plausible: 0.1...300, panel: .haematology),
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
              plausible: 0.05...120, panel: .hormones)
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
        let normalised = " " + label.lowercased()
            .map { ch -> Character in
                if ch.isLetter || ch.isNumber || ch == "/" || ch == ":" || ch == "-"
                    || ch == "+" || ch == "(" || ch == ")" { return ch }
                return " "
            }
            .reduce(into: "") { acc, ch in
                if ch == " " && acc.last == " " { return }
                acc.append(ch)
            } + " "

        for (synonym, entry) in synonymIndex where normalised.contains(" \(synonym) ")
            || normalised.contains(" \(synonym)(") {
            return entry
        }
        return nil
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
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lipids: return "Lipids"
        case .glycaemic: return "Glucose & HbA1c"
        case .renal: return "Kidneys & electrolytes"
        case .liver: return "Liver"
        case .thyroid: return "Thyroid"
        case .haematology: return "Blood count & vitamins"
        case .inflammation: return "Inflammation & other"
        case .hormones: return "Hormones"
        case .other: return "Not recognised"
        }
    }
}

public extension LabAnalyte {
    /// The panel this analyte belongs to.
    var panel: LabPanel {
        LabAnalyteCatalog.entry(forKey: key)?.panel ?? .other
    }
}
