import Foundation

/// **What a test result actually is** — which is a plain number far less often
/// than this app assumed until 2026-08-09.
///
/// `LabResult.value` was a `Double` because the two analytes the feature started
/// with — total and HDL cholesterol — are always numbers. Measured against a real
/// pathology corpus, roughly **two results in five are not**: a syphilis screen
/// reads *Negative*, a PCR reads *Not detected*, a hepatitis B surface antibody
/// reads *<5 IU/L*, and an iron study reads *Specimen unsuitable* with no value
/// at all. Each of those was previously either unstorable or — worse — storable
/// as a number that means something else.
///
/// ⚠️ **The failure this type exists to prevent is a censored bound becoming a
/// measurement.** An eGFR printed `>90` is not an eGFR of 90; it is a statement
/// that the assay stopped looking. Storing 90 makes a ceiling into a reading, and
/// nothing downstream can tell afterwards. `measuredNumber` is `nil` for
/// everything except `.quantitative` precisely so a risk model cannot take one by
/// accident — see `AppModel.saveLabResults`.
public enum LabValue: Sendable, Equatable, Hashable {
    /// A number the laboratory actually measured.
    case quantitative(Double)
    /// A bound, not a measurement: the true value lies beyond `magnitude`.
    case censored(LabCensorOperator, Double)
    /// A word rather than a number.
    case qualitative(LabQualitativeResult)
    /// The analyte was on the report and no value was produced. **Not the same as
    /// absent** — the reader was told a test failed, and that is a fact about
    /// their record worth keeping.
    case notMeasured(LabNotMeasuredReason)

    /// **The number, only when one was measured.**
    ///
    /// `nil` for censored, qualitative and not-measured results, deliberately and
    /// without exception. Every caller that feeds a card, a risk model or a
    /// grounding fact reads this one and no other.
    public var measuredNumber: Double? {
        if case .quantitative(let value) = self { return value }
        return nil
    }

    /// The number **printed**, including a censored bound.
    ///
    /// For display, and for placing a point on an axis where the alternative is
    /// dropping it. Never for arithmetic that assumes a measurement: a series
    /// mean over a censored value is wrong in a direction nobody can recover.
    public var magnitude: Double? {
        switch self {
        case .quantitative(let value): return value
        case .censored(_, let value): return value
        case .qualitative, .notMeasured: return nil
        }
    }

    /// The shape, as a value that can sit in a database column and be filtered on
    /// without decoding the payload. Also what stops `LabSeries` plotting a word
    /// and a number on one axis.
    public var shape: LabValueShape {
        switch self {
        case .quantitative: return .quantitative
        case .censored: return .censored
        case .qualitative: return .qualitative
        case .notMeasured: return .notMeasured
        }
    }

    /// Whether this result carries a position on an axis at all.
    public var isPlottable: Bool { magnitude != nil }

    /// The value as the report would have printed it, without its unit.
    ///
    /// Precision follows the size of the number rather than the analyte, because
    /// an unknown analyte has no declared precision and inventing one would be
    /// dressing an arbitrary choice as knowledge. This is the rule
    /// `LabResult.formattedValue` has always used, moved here so every shape
    /// answers the same way.
    public var formatted: String {
        switch self {
        case .quantitative(let value):
            return Self.formatNumber(value)
        case .censored(let op, let value):
            return "\(op.symbol)\(Self.formatNumber(value))"
        case .qualitative(let result):
            return result.printed
        case .notMeasured:
            return "Not measured"
        }
    }

    static func formatNumber(_ value: Double) -> String {
        let magnitude = abs(value)
        let places: Int
        if magnitude >= 100 { places = 0 }
        else if magnitude >= 10 { places = 1 }
        else if magnitude >= 1 { places = 2 }
        else { places = 3 }
        return String(format: "%.\(places)f", value)
    }
}

/// Which way a censored bound points.
public enum LabCensorOperator: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case lessThan
    case lessOrEqual
    case greaterThan
    case greaterOrEqual

    public var symbol: String {
        switch self {
        case .lessThan: return "<"
        case .lessOrEqual: return "\u{2264}"
        case .greaterThan: return ">"
        case .greaterOrEqual: return "\u{2265}"
        }
    }

    /// Whether the true value lies above the printed bound.
    public var isLowerBound: Bool {
        switch self {
        case .greaterThan, .greaterOrEqual: return true
        case .lessThan, .lessOrEqual: return false
        }
    }

    /// One line for the reader, because `<5` on its own reads as a measurement of
    /// five to anyone not looking closely.
    public var explanation: String {
        isLowerBound
            ? "The assay does not measure above this point, so the true value is higher than shown."
            : "The assay does not measure below this point, so the true value is lower than shown."
    }
}

/// A worded result, kept exactly as printed and placed on a shared scale only
/// where the word is one the app recognises.
public struct LabQualitativeResult: Sendable, Equatable, Hashable, Codable {
    /// **Verbatim.** "Negative", "Not Detected", "DETECTED", "Non reactive". The
    /// report's own word is what the reader will compare against their paperwork,
    /// and three laboratories write the same finding three ways.
    public let printed: String
    /// Where `printed` sits on the shared scale — `nil` when the word is not one
    /// the app knows. **A word it cannot place is stored and shown, never
    /// guessed at**, for the same reason `LabAnalyte` keeps an uncatalogued
    /// analyte verbatim rather than converting it on a hunch.
    public let ordinal: LabQualitativeOrdinal?

    public init(printed: String, ordinal: LabQualitativeOrdinal?) {
        self.printed = printed
        self.ordinal = ordinal
    }

    /// Recognise a printed word, across the three vocabularies a pathology report
    /// actually uses: serology says reactive/non-reactive, nucleic-acid tests say
    /// detected/not detected, and everything else says positive/negative.
    public init(printed: String) {
        self.printed = printed
        self.ordinal = LabQualitativeOrdinal(printed: printed)
    }
}

/// The three-point scale the recognised words collapse onto.
///
/// ⚠️ **This is an ordering, not a grading.** `.positive` is not "bad" and
/// `.negative` is not "good", and this app must never render them that way. The
/// corpus that prompted this type contains the counter-example in plain sight: a
/// hepatitis B *surface antibody* of Negative means the reader is **not immune**,
/// which is the unwanted result — while a hepatitis B *surface antigen* of
/// Negative means no active infection, which is the wanted one. Same word, same
/// panel, opposite meanings. Nothing here may colour a result, and
/// `LabSeriesSpec.higherIsBetter` is `nil` for every analyte that carries one.
public enum LabQualitativeOrdinal: String, Sendable, Equatable, Hashable, Codable, CaseIterable, Comparable {
    case negative
    case equivocal
    case positive

    private static let negativeWords = [
        "not detected", "notdetected", "non reactive", "nonreactive", "non-reactive",
        "not isolated", "no growth", "negative", "nil detected", "absent", "undetected"
    ]
    private static let equivocalWords = [
        "equivocal", "indeterminate", "borderline", "inconclusive", "weak positive",
        "weakly reactive"
    ]
    private static let positiveWords = [
        "detected", "reactive", "positive", "isolated", "present"
    ]

    /// ⚠️ **Order matters and negatives are tested first.** "Not detected"
    /// contains "detected"; matching the positive list first would file every
    /// negative PCR in this reader's record as a positive one. Within each list
    /// the longest phrase is tried first for the same reason.
    public init?(printed: String) {
        let text = printed
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        func matches(_ words: [String]) -> Bool {
            words.sorted { $0.count > $1.count }.contains { text.contains($0) }
        }
        if matches(Self.negativeWords) { self = .negative; return }
        if matches(Self.equivocalWords) { self = .equivocal; return }
        if matches(Self.positiveWords) { self = .positive; return }
        return nil
    }

    public var displayName: String {
        switch self {
        case .negative: return "Negative"
        case .equivocal: return "Equivocal"
        case .positive: return "Positive"
        }
    }

    private var rank: Int {
        switch self {
        case .negative: return 0
        case .equivocal: return 1
        case .positive: return 2
        }
    }

    public static func < (lhs: LabQualitativeOrdinal, rhs: LabQualitativeOrdinal) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Why a result on a report carries no value.
public enum LabNotMeasuredReason: Sendable, Equatable, Hashable, Codable {
    /// The laboratory said why — "Specimen unsuitable", "platelet clumping".
    /// Kept verbatim: the reason is the useful part, and it is the laboratory's
    /// sentence rather than the app's opinion of it.
    case statedByLaboratory(String)
    /// The analyte appeared with no value and no reason beside it.
    case notStated

    public var explanation: String {
        switch self {
        case .statedByLaboratory(let reason): return reason
        case .notStated: return "The report listed this test but printed no result."
        }
    }
}

/// The four shapes a result can take, flat enough to store in a column.
public enum LabValueShape: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case quantitative
    case censored
    case qualitative
    case notMeasured

    /// Two results only belong on the same chart when they are the same shape.
    /// A censored point may join a quantitative series — it has a position — but
    /// a word may not.
    public var isChartable: Bool {
        switch self {
        case .quantitative, .censored: return true
        case .qualitative, .notMeasured: return false
        }
    }
}

// MARK: - Codable, and the legacy shape

extension LabValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, number, op, printed, ordinal, reason
    }

    private enum Kind: String, Codable {
        case quantitative, censored, qualitative, notMeasured
    }

    /// ⚠️ **The most load-bearing initialiser in this feature.**
    ///
    /// Every lab result the reader already has is stored as a JSON payload in
    /// `LabResultRecord`, written when `LabResult.value` was a bare `Double` —
    /// so those payloads hold `"value": 5.2`, a naked number where a keyed object
    /// now goes. `DataStore.labResults()` decodes each row with `try?` and
    /// `compactMap`s the failures away, which means **a decoder that cannot read
    /// the old shape does not throw, log or warn: it silently empties the
    /// reader's entire test-result history.**
    ///
    /// So the bare number is tried first and is a supported input shape
    /// permanently, not a migration to be removed once "everyone has upgraded".
    /// There is no migration event to hang that on — the payloads are data at
    /// rest, and a decoder is the only thing that ever reads them.
    /// `LabValueCodecTests` pins a literal legacy string against this.
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let number = try? single.decode(Double.self) {
            self = .quantitative(number)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .quantitative:
            self = .quantitative(try container.decode(Double.self, forKey: .number))
        case .censored:
            self = .censored(try container.decode(LabCensorOperator.self, forKey: .op),
                             try container.decode(Double.self, forKey: .number))
        case .qualitative:
            self = .qualitative(LabQualitativeResult(
                printed: try container.decode(String.self, forKey: .printed),
                ordinal: try container.decodeIfPresent(LabQualitativeOrdinal.self, forKey: .ordinal)))
        case .notMeasured:
            if let reason = try container.decodeIfPresent(String.self, forKey: .reason) {
                self = .notMeasured(.statedByLaboratory(reason))
            } else {
                self = .notMeasured(.notStated)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .quantitative(let value):
            try container.encode(Kind.quantitative, forKey: .kind)
            try container.encode(value, forKey: .number)
        case .censored(let op, let value):
            try container.encode(Kind.censored, forKey: .kind)
            try container.encode(op, forKey: .op)
            try container.encode(value, forKey: .number)
        case .qualitative(let result):
            try container.encode(Kind.qualitative, forKey: .kind)
            try container.encode(result.printed, forKey: .printed)
            try container.encodeIfPresent(result.ordinal, forKey: .ordinal)
        case .notMeasured(let reason):
            try container.encode(Kind.notMeasured, forKey: .kind)
            if case .statedByLaboratory(let text) = reason {
                try container.encode(text, forKey: .reason)
            }
        }
    }
}
