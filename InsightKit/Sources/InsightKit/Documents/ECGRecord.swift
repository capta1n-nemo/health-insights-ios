import Foundation

/// **An ECG the reader brought in — kept, shown, and never interpreted.**
///
/// Backlog `I7`: *"ECG photo/PDF import with metadata."*
///
/// ## The line, and why it is not negotiable
///
/// ⚠️ **This app does not interpret an electrocardiogram, and no future version
/// of it will.** Reading a trace and saying what it shows — sinus rhythm, atrial
/// fibrillation, an inferior infarct, a QT interval anybody should act on — is a
/// regulated medical-device claim. Apple's own single-lead ECG is a cleared
/// device with a cleared indication; a picture of a printout in a personal
/// health app is not, and no amount of "for information only" wording changes
/// what a classification next to a trace means to the person reading it.
///
/// So this type stores three things and only three:
///
/// 1. **The document** — the image or PDF, unaltered, so the reader has their
///    trace where the rest of their health data is.
/// 2. **Metadata the source itself printed** — when, how long, what device,
///    what average rate. Transcribed, with the transcription's confidence
///    attached, exactly like a lab value.
/// 3. **What the source said**, verbatim and attributed. `printedFinding` is a
///    quotation of the classification the *recording device or clinician* put on
///    the trace. It is not this app's opinion, it is never generated, and
///    `ECGFindingProvenance` makes the attribution part of the data rather than
///    part of the wording.
///
/// There is deliberately **no computed field derived from the waveform** here,
/// and no place to put one. The absence is the design.
public struct ECGRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    /// When the trace was recorded, per the document or the reader.
    public let recordedAt: Date
    /// Whether `recordedAt` came from the document (or the reader) rather than
    /// defaulting to the import. Same honesty flag `LabResult` carries: a date
    /// nobody stated must not look like one somebody did.
    public let recordedAtIsExact: Bool
    public let source: ECGSource
    public let leads: ECGLeadConfiguration
    /// Seconds of trace, where the document prints it.
    public let durationSeconds: Double?
    /// The average rate **printed on the trace**, transcribed. Not measured
    /// here, not derived here, and nil when the document does not print one.
    public let printedAverageHeartRate: Int?
    /// The recording device as named on the document — "Apple Watch Series 10",
    /// "GE MAC 2000". Free text, because the set of ECG machines is not
    /// enumerable and inventing a taxonomy would lose the reader's own words.
    public let deviceDescription: String?
    /// ⚠️ **A quotation, never a conclusion.** What the recording device or the
    /// clinician printed on the trace, character for character.
    public let printedFinding: String?
    /// Who said it. Nil when `printedFinding` is nil.
    public let findingProvenance: ECGFindingProvenance?
    /// The reader's own note — symptoms at the time, what a doctor told them.
    /// Their words, stored as typed.
    public let readerNote: String?
    /// How many pages/images the document had.
    public let pageCount: Int
    /// Where the document itself lives in the app's own storage. A file name,
    /// not a path: the container moves between installs and an absolute path
    /// stored in a database is a broken link waiting for the next restore.
    public let attachmentFileName: String?
    /// What the metadata transcription checked and found. Nil when every field
    /// was typed by the reader.
    public let transcription: ECGTranscriptionEvidence?

    public init(id: UUID = UUID(), recordedAt: Date, recordedAtIsExact: Bool,
                source: ECGSource, leads: ECGLeadConfiguration,
                durationSeconds: Double? = nil,
                printedAverageHeartRate: Int? = nil,
                deviceDescription: String? = nil,
                printedFinding: String? = nil,
                findingProvenance: ECGFindingProvenance? = nil,
                readerNote: String? = nil,
                pageCount: Int = 1,
                attachmentFileName: String? = nil,
                transcription: ECGTranscriptionEvidence? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.recordedAtIsExact = recordedAtIsExact
        self.source = source
        self.leads = leads
        self.durationSeconds = durationSeconds
        self.printedAverageHeartRate = printedAverageHeartRate
        self.deviceDescription = deviceDescription
        self.printedFinding = printedFinding
        self.findingProvenance = findingProvenance
        self.readerNote = readerNote
        self.pageCount = pageCount
        self.attachmentFileName = attachmentFileName
        self.transcription = transcription
    }

    /// The sentence that must accompany any display of `printedFinding`.
    ///
    /// A method on the model rather than a string in a view, so the attribution
    /// cannot be dropped by a screen that renders the finding somewhere new. The
    /// UI is free to style it; it is not free to omit it.
    public var findingAttribution: String? {
        guard printedFinding != nil, let findingProvenance else { return nil }
        return findingProvenance.attribution
    }
}

/// How an ECG document reached the app.
public enum ECGSource: String, Sendable, Codable, CaseIterable, Identifiable {
    /// A photo of a printout or a screen.
    case photo
    /// A PDF — the shape Apple Health exports an ECG in, and what most clinics
    /// email.
    case pdf
    /// The system document scanner.
    case documentScan

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .pdf: return "PDF"
        case .documentScan: return "Scanned"
        }
    }
}

/// How many leads the trace carries.
///
/// It matters for one honest reason and no clinical one: a single-lead trace and
/// a twelve-lead trace are not the same document, and a reader scrolling a list
/// of ECGs should be able to tell a watch reading from a hospital one without
/// opening both.
public enum ECGLeadConfiguration: String, Sendable, Codable, CaseIterable, Identifiable {
    case singleLead
    case sixLead
    case twelveLead
    /// The document did not say, and nothing here guesses from the picture.
    case unstated

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .singleLead: return "Single lead"
        case .sixLead: return "6 lead"
        case .twelveLead: return "12 lead"
        case .unstated: return "Not stated"
        }
    }
}

/// Who produced the words in `ECGRecord.printedFinding`.
///
/// ⚠️ **There is no `.thisApp` case and there must never be one.** The type
/// exists so that a finding can only be stored *with* an attribution to somebody
/// outside this app — which is the structural version of the rule that this app
/// does not interpret ECGs. A case for "worked out here" would make the rule a
/// matter of discipline again.
public enum ECGFindingProvenance: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Printed by the device that made the recording — an Apple Watch's
    /// "Sinus Rhythm", a machine's automated statement.
    case recordingDevice
    /// Written or dictated by a clinician.
    case clinician
    /// The reader typing what they were told. Their report of somebody else's
    /// words, and labelled as that rather than as a finding.
    case readerRecollection

    public var id: String { rawValue }

    public var attribution: String {
        switch self {
        case .recordingDevice:
            return "As printed by the device that recorded this trace. This app does not interpret ECGs."
        case .clinician:
            return "As written by a clinician on this document. This app does not interpret ECGs."
        case .readerRecollection:
            return "Your note of what you were told. This app does not interpret ECGs."
        }
    }

    public var shortLabel: String {
        switch self {
        case .recordingDevice: return "From the device"
        case .clinician: return "From a clinician"
        case .readerRecollection: return "Your note"
        }
    }
}

/// What the metadata transcription read, and how sure it is.
///
/// The same shape as `LabExtractionEvidence` and for the same reason: a date or
/// a heart rate lifted off a document by OCR can be wrong, and a wrong date on
/// an ECG files it against the wrong week of everything else.
public struct ECGTranscriptionEvidence: Sendable, Equatable, Codable {
    /// The lines the fields were read from, kept because the document's text is
    /// not.
    public let matchedLines: [String]
    public let checks: [LabValueCheck]
    /// Fields the document simply did not print. Listed so the detail page can
    /// say *"the document did not state a duration"* rather than showing a gap
    /// that reads as a failure.
    public let absentFields: [ECGField]

    public init(matchedLines: [String], checks: [LabValueCheck],
                absentFields: [ECGField]) {
        self.matchedLines = matchedLines
        self.checks = checks
        self.absentFields = absentFields
    }

    public var confidence: LabConfidence {
        if checks.contains(where: \.isFailure) { return .doubtful }
        if checks.isEmpty { return .unverified }
        return checks.allSatisfy(\.isWeak) ? .unverified : .clear
    }
}

/// The metadata fields an ECG document might print.
public enum ECGField: String, Sendable, Codable, CaseIterable, Identifiable {
    case recordedAt
    case averageHeartRate
    case duration
    case device
    case leads
    case finding

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .recordedAt: return "Recorded"
        case .averageHeartRate: return "Average heart rate"
        case .duration: return "Duration"
        case .device: return "Device"
        case .leads: return "Leads"
        case .finding: return "Printed classification"
        }
    }
}
