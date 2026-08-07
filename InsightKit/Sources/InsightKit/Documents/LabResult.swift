import Foundation

/// **One analyte's value, and how much the app should be believed about it.**
///
/// Backlog `Q7`. A lab result that arrives by OCR is not the same kind of fact
/// as one the reader typed, and this type refuses to let those two look alike.
/// `source` says how it got here; `evidence` — nil for anything typed — carries
/// the checks that were run on the reading and what they found.
///
/// ⚠️ **A misread lab value is worse than no lab value.** A cholesterol of 5.2
/// OCR'd as 52 is not noise, it is a different person's report, and it flows
/// into SCORE2 as a grounding fact and out into the export as a data point.
/// Everything in `LabValueCheck` exists because of that sentence.
public struct LabResult: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let analyte: LabAnalyte
    /// In `analyte.canonicalUnit` where the analyte is catalogued and the unit
    /// was recognised; otherwise exactly as printed, with `unit` saying so.
    public let value: Double
    /// The unit `value` is expressed in. For an unknown analyte this is the
    /// report's own string, unconverted — see `LabAnalyte.canonicalUnit`.
    public let unit: String
    /// The interval the **report itself printed** beside the value, in the same
    /// unit as `value`. Not the app's opinion of normal, and never used as one.
    public let referenceRange: LabReferenceRange?
    /// When the blood was taken, as best known. For a typed entry the reader
    /// says; for an imported report this is the collection date on the document
    /// where one was found, and the import date otherwise — `collectedAtIsExact`
    /// is the flag that keeps those two apart.
    public let collectedAt: Date
    public let collectedAtIsExact: Bool
    public let source: LabResultSource
    /// Nil for a typed value: there is nothing to be uncertain about when a
    /// human read the paper and typed the number.
    public let evidence: LabExtractionEvidence?
    /// Whether the reader has looked at this value and said it is right.
    ///
    /// **Nothing extracted is stored unconfirmed.** The import screen shows
    /// every candidate with its checks and the reader taps to keep them, so a
    /// stored result is always either typed or confirmed. The flag is kept
    /// anyway because it is the field a future background import would need,
    /// and a `false` here must be visible rather than assumed impossible.
    public let isConfirmedByReader: Bool

    public init(id: UUID = UUID(), analyte: LabAnalyte, value: Double, unit: String,
                referenceRange: LabReferenceRange? = nil,
                collectedAt: Date, collectedAtIsExact: Bool = false,
                source: LabResultSource,
                evidence: LabExtractionEvidence? = nil,
                isConfirmedByReader: Bool = false) {
        self.id = id
        self.analyte = analyte
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.collectedAt = collectedAt
        self.collectedAtIsExact = collectedAtIsExact
        self.source = source
        self.evidence = evidence
        self.isConfirmedByReader = isConfirmedByReader
    }

    /// How confident the app is that this number is the number on the paper.
    ///
    /// ⚠️ **This is confidence in the *reading*, never in the reader's health.**
    /// It says nothing about whether the value is good or bad, and the UI wording
    /// keeps that separation — "read clearly" and "check this one", not "normal"
    /// and "abnormal".
    public var confidence: LabConfidence {
        guard let evidence else { return .typed }
        return evidence.confidence
    }

    /// The formatted value, at the precision the analyte deserves.
    ///
    /// Precision follows the size of the number rather than the analyte, because
    /// an unknown analyte has no declared precision and inventing one would be
    /// dressing an arbitrary choice as knowledge.
    public var formattedValue: String {
        let magnitude = abs(value)
        let places: Int
        if magnitude >= 100 { places = 0 }
        else if magnitude >= 10 { places = 1 }
        else if magnitude >= 1 { places = 2 }
        else { places = 3 }
        return String(format: "%.\(places)f", value)
    }

    public var formattedWithUnit: String {
        unit.isEmpty ? formattedValue : "\(formattedValue) \(unit)"
    }
}

/// How a lab result reached the app. The reader named all four (`Q7`).
public enum LabResultSource: String, Sendable, Codable, CaseIterable, Identifiable {
    /// The reader typed it. The only route with no extraction uncertainty.
    case typed
    /// A photograph from the library, OCR'd on device.
    case photo
    /// A PDF, read from its text layer where it has one and OCR'd where it does not.
    case pdf
    /// The system document scanner — edge-detected, perspective-corrected pages.
    case documentScan
    /// A structured file shared in from another app.
    case fileImport

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .typed: return "Typed in"
        case .photo: return "Photo"
        case .pdf: return "PDF"
        case .documentScan: return "Scanned"
        case .fileImport: return "Imported file"
        }
    }

    /// Whether a value from this route was read by a machine rather than a person.
    public var isMachineRead: Bool {
        switch self {
        case .typed: return false
        case .photo, .pdf, .documentScan, .fileImport: return true
        }
    }
}

/// The interval a report printed next to a value.
///
/// ⚠️ **The laboratory's, not the app's.** It is stored so the reader sees what
/// their own paperwork said and so the parser can cross-check a reading against
/// it — never so a card can grade anybody. Nothing in this app scores a lab
/// value against this range.
public struct LabReferenceRange: Sendable, Equatable, Codable {
    public let low: Double?
    public let high: Double?
    /// Exactly as printed — "3.5 - 5.0", "< 5.0", "> 1.0 (male)". Kept verbatim
    /// so a range the parser only half understood can still be shown to the
    /// reader in the laboratory's own words.
    public let printed: String

    public init(low: Double?, high: Double?, printed: String) {
        self.low = low
        self.high = high
        self.printed = printed
    }

    /// Whether a value sits inside the printed interval. An open end is treated
    /// as satisfied, so "< 5.0" bounds only from above.
    public func contains(_ value: Double) -> Bool {
        if let low, value < low { return false }
        if let high, value > high { return false }
        return true
    }

    /// How far outside the interval a value falls, as a multiple of the
    /// interval's own width. Used only by the misread guard: a value ten
    /// interval-widths out is far more likely a decimal-point error than a
    /// finding. Nil when the interval has no width to measure against.
    public func excursion(_ value: Double) -> Double? {
        guard let low, let high, high > low else { return nil }
        let width = high - low
        if value < low { return (low - value) / width }
        if value > high { return (value - high) / width }
        return 0
    }
}

/// **How sure the app is that it read the number correctly.**
public enum LabConfidence: String, Sendable, Codable, Comparable, CaseIterable {
    /// A person typed it. Nothing to doubt about the reading.
    case typed
    /// Every check that could run, ran and passed.
    case clear
    /// Read, and at least one check could not run — usually because the report
    /// printed no reference interval and the analyte is not catalogued.
    case unverified
    /// A check failed, or two routes disagreed. Shown, flagged, and **never
    /// written to a grounding fact without the reader confirming it.**
    case doubtful

    public static func < (lhs: LabConfidence, rhs: LabConfidence) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ c: LabConfidence) -> Int {
        switch c {
        case .typed: return 0
        case .clear: return 1
        case .unverified: return 2
        case .doubtful: return 3
        }
    }

    public var title: String {
        switch self {
        case .typed: return "Typed in"
        case .clear: return "Read clearly"
        case .unverified: return "Read, not cross-checked"
        case .doubtful: return "Check this one"
        }
    }

    /// One line saying what the label means, in the reader's terms.
    public var explanation: String {
        switch self {
        case .typed:
            return "You entered this yourself."
        case .clear:
            return "The number, its unit and the range printed beside it all agree."
        case .unverified:
            return "The number was read, but the report printed nothing to check it against — no reference range, and this is not an analyte the app knows the usual size of."
        case .doubtful:
            return "Something did not add up. Compare it against your report before you keep it."
        }
    }
}

/// **What was checked, and what the check found.**
///
/// The prior art is the screen-time parser, which cross-checks a total against a
/// figure the same image already prints — and which was later extended to
/// *select* the right value rather than only to reject a wrong one. A pathology
/// report offers the same affordance and more of it: **it prints its own
/// reference interval next to almost every value.** That interval is a second,
/// independent statement about the magnitude the number should have, produced by
/// the same laboratory, on the same page, in the same unit.
///
/// So the guard is:
///
/// - a value inside its printed interval corroborates the reading;
/// - a value far outside it is a *candidate misread* rather than a finding, and
///   where the line offered more than one number the parser **re-selects** —
///   the same extension the screen-time reader got;
/// - a value outside the analyte's plausible range is a misread outright;
/// - a value whose unit was not recognised is never converted, because a wrong
///   conversion is invisible afterwards.
///
/// ⚠️ **"Outside the range" is never reported to the reader as a health
/// finding.** A genuinely high cholesterol is outside its interval and is not a
/// misread. That is why the excursion threshold is deliberately far out
/// (`LabValueCheck.grossExcursion`) and why the resulting label reads "check
/// this one" rather than anything clinical.
public enum LabValueCheck: Sendable, Equatable, Codable {
    /// The value sits inside the interval the report printed.
    case insidePrintedRange
    /// The value sits outside it, by this many interval-widths.
    case outsidePrintedRange(excursion: Double)
    /// So far outside the printed interval that a decimal-point or digit misread
    /// is more likely than a real value.
    case grosslyOutsidePrintedRange(excursion: Double)
    /// The report printed no interval for this analyte.
    case noPrintedRange
    /// Within the widest value the analyte could honestly have been printed at.
    case plausibleMagnitude
    /// Outside it — a misread, not a finding.
    case implausibleMagnitude
    /// The analyte is not catalogued, so no plausible range exists to check.
    case magnitudeUncheckable
    /// The unit was printed and recognised.
    case unitRecognised(String)
    /// The unit was printed but the app does not know it. The value is stored
    /// unconverted and the unit kept verbatim.
    case unitUnrecognised(String)
    /// No unit was printed. The value was taken at the analyte's canonical unit
    /// only because the printed reference interval agreed with that reading.
    case unitInferredFromRange(String)
    /// No unit was printed and nothing could infer one.
    case unitMissing
    /// The line offered more than one number and the printed interval chose
    /// between them. Carries what was picked and what was rejected — the
    /// screen-time parser's *select, don't merely reject* extension.
    case selectedByPrintedRange(chosen: Double, rejected: [Double])
    /// Vision's own confidence in the recognised text, where a route supplies it.
    case ocrConfidence(Double)
    /// The characters in the number are ones OCR confuses (`O`/`0`, `l`/`1`,
    /// `S`/`5`), or the decimal separator was ambiguous.
    case ambiguousCharacters(String)
    /// The on-device model proposed this analyte and the number it gave was
    /// found verbatim in the recognised text.
    case corroboratedInSourceText
    /// The on-device model proposed a number that does not appear in the
    /// recognised text. **The result is discarded, never stored** — this case
    /// exists so the discard can be counted and shown.
    case notFoundInSourceText

    /// Whether this check, on its own, makes the reading doubtful.
    public var isFailure: Bool {
        switch self {
        case .grosslyOutsidePrintedRange, .implausibleMagnitude,
             .unitUnrecognised, .notFoundInSourceText, .ambiguousCharacters:
            return true
        case .ocrConfidence(let c):
            return c < 0.5
        case .insidePrintedRange, .outsidePrintedRange, .noPrintedRange,
             .plausibleMagnitude, .magnitudeUncheckable, .unitRecognised,
             .unitInferredFromRange, .unitMissing, .selectedByPrintedRange,
             .corroboratedInSourceText:
            return false
        }
    }

    /// Whether this check leaves the reading merely un-corroborated rather than
    /// wrong. Two of these and nothing corroborating means `.unverified`.
    public var isWeak: Bool {
        switch self {
        case .noPrintedRange, .magnitudeUncheckable, .unitMissing:
            return true
        default:
            return false
        }
    }

    /// One line, in the reader's terms. Shown under a flagged value so a warning
    /// says what it is about rather than being a coloured dot.
    public var explanation: String {
        switch self {
        case .insidePrintedRange:
            return "Matches the range printed beside it on the report."
        case .outsidePrintedRange:
            return "Outside the range printed beside it — which may simply be your result."
        case .grosslyOutsidePrintedRange(let excursion):
            return String(format: "Far outside the printed range (%.0fx its width) — more likely a misread digit than a result.", excursion)
        case .noPrintedRange:
            return "The report printed no reference range beside this value, so there was nothing to check it against."
        case .plausibleMagnitude:
            return "The size of the number is possible for this analyte."
        case .implausibleMagnitude:
            return "The number is outside anything this analyte is printed at — a misread, not a result."
        case .magnitudeUncheckable:
            return "The app does not know this analyte, so it cannot say whether the number is the right size."
        case .unitRecognised(let unit):
            return "Unit read as \(unit)."
        case .unitUnrecognised(let unit):
            return "Unit \"\(unit)\" is not one the app knows, so the value was stored exactly as printed and not converted."
        case .unitInferredFromRange(let unit):
            return "No unit was printed; \(unit) was inferred from the reference range on the same line."
        case .unitMissing:
            return "No unit was printed and none could be worked out."
        case .selectedByPrintedRange(let chosen, let rejected):
            let others = rejected.map { String(format: "%g", $0) }.joined(separator: ", ")
            return String(format: "The line held several numbers; %g fits the printed range and %@ did not.", chosen, others)
        case .ocrConfidence(let c):
            return String(format: "Text recognition confidence %.0f%%.", c * 100)
        case .ambiguousCharacters(let raw):
            return "The characters read (\"\(raw)\") include ones text recognition confuses."
        case .corroboratedInSourceText:
            return "The on-device model named this analyte, and the number it gave appears verbatim in the scanned text."
        case .notFoundInSourceText:
            return "The on-device model gave a number that is not in the scanned text, so it was discarded."
        }
    }
}

/// **What the parser saw, kept beside what it concluded.**
///
/// Stored rather than recomputed, because the text it was derived from is not
/// kept: the app OCRs a report, extracts values, and discards the page. Without
/// this the reader has no way to ask "where did that come from" a month later,
/// and neither does anyone debugging a wrong number.
public struct LabExtractionEvidence: Sendable, Equatable, Codable {
    /// The label exactly as printed on the report.
    public let rawLabel: String
    /// The value's own characters as recognised, before parsing. This is the
    /// field that makes a decimal-comma or an `O`-for-`0` visible after the fact.
    public let rawValueText: String
    /// The whole line, for a reader comparing against their paperwork.
    public let rawLine: String
    /// What produced this result.
    public let method: LabExtractionMethod
    public let checks: [LabValueCheck]

    public init(rawLabel: String, rawValueText: String, rawLine: String,
                method: LabExtractionMethod, checks: [LabValueCheck]) {
        self.rawLabel = rawLabel
        self.rawValueText = rawValueText
        self.rawLine = rawLine
        self.method = method
        self.checks = checks
    }

    /// The overall verdict, from the checks.
    ///
    /// One failure is enough to be doubtful — the checks are independent
    /// statements and any one of them being wrong means the reading is not
    /// trustworthy. Passing nothing but weak checks is `.unverified`: honest
    /// about having read a number with nothing to compare it to, which is a
    /// different thing from having read it well.
    public var confidence: LabConfidence {
        if checks.contains(where: \.isFailure) { return .doubtful }
        let corroborating = checks.contains {
            if case .insidePrintedRange = $0 { return true }
            if case .selectedByPrintedRange = $0 { return true }
            return false
        }
        let plausible = checks.contains {
            if case .plausibleMagnitude = $0 { return true }
            return false
        }
        if corroborating && plausible { return .clear }
        if corroborating || plausible { return .clear }
        return .unverified
    }

    /// The checks worth putting in front of the reader — failures first, then
    /// anything that explains a missing cross-check. Passing checks are dropped:
    /// a screen listing every test that succeeded buries the one that did not.
    public var noteworthyChecks: [LabValueCheck] {
        checks.filter { $0.isFailure || $0.isWeak }
    }
}

/// Which route produced a value. Separate from `LabResultSource`, which says
/// what the *document* was: a PDF can be parsed deterministically or by the
/// on-device model, and those two deserve different scrutiny.
public enum LabExtractionMethod: String, Sendable, Codable, CaseIterable {
    /// The rule-based parser in `LabReportParser`. Runs everywhere, including
    /// on a device with no Apple Intelligence, and is the path the tests cover.
    case deterministic
    /// Apple's on-device Foundation model, used **only to name analytes the
    /// deterministic parser did not recognise** — never to produce a number.
    /// Backlog `I6`.
    case onDeviceModel
    /// The reader typed it.
    case manual

    public var displayName: String {
        switch self {
        case .deterministic: return "Read by the app's parser"
        case .onDeviceModel: return "Named by the on-device model"
        case .manual: return "Typed in"
        }
    }
}
