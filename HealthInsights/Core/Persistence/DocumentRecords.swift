import Foundation
import SwiftData
import InsightKit

/// Storage for the two things a reader brings in as a *document*: blood-test
/// results (backlog `Q7`, `I6`) and ECGs (`I7`).
///
/// ⚠️ **A `@Model` not listed in `DataStore`'s schema silently never
/// persists.** Both of these are in it; if you add a third, add it there too.
///
/// ## Why the value type is stored as JSON rather than shredded into columns
///
/// Every other record in this app is flat, and these two are not. The reason is
/// `LabResult.evidence` and `ECGRecord.transcription`: both are variable-length
/// lists of `LabValueCheck`, several of which carry associated values, and they
/// are the fields that must survive intact. **The confidence in a reading is not
/// derivable from the reading** — an OCR'd 5.2 and a typed 5.2 are the same
/// number and different facts — so a storage shape that loses the checks loses
/// the one thing this feature is careful about.
///
/// The queryable parts are still columns, so the Data tab sorts and the importer
/// deduplicates without decoding every row: `analyteKey`, `collectedAt`, `value`
/// and `confidenceRaw` are stored beside the payload and kept in step by the
/// initialiser, which is the only writer.
///
/// A payload that fails to decode yields `nil` rather than a default-constructed
/// result. A lab value invented by a decoding fallback is exactly the misread
/// class the parser spends four hundred lines avoiding.
///
/// ⚠️ **The payload is the authority and it outlives the schema.** Rows written
/// before 2026-08-09 hold `"value": 5.2` — a bare number where `LabValue` now
/// writes a keyed object — and `DataStore.labResults()` drops an undecodable row
/// silently. `LabValue.init(from:)` therefore accepts the bare number
/// permanently, and `LabValueCodecTests` pins it. Read that comment before
/// touching either codec.
@Model
final class LabResultRecord {
    @Attribute(.unique) var id: UUID
    /// `LabAnalyte.key` — catalogued (`hba1c`) or `other.<label>`.
    var analyteKey: String
    /// Denormalised for the Data tab's search, which matches on what the reader
    /// would type rather than on a key.
    var analyteName: String
    /// **The measured number, and nil for everything else** — a censored bound, a
    /// word, a test that produced no result. Optional since 2026-08-09; it was a
    /// non-optional `Double` when every result was assumed to be a number.
    ///
    /// Deliberately *not* the printed magnitude: a query filtering on this column
    /// is asking for measurements, and a `>90` answering it would be the ceiling
    /// masquerading as a reading. `magnitude` is the column for plotting.
    var value: Double?
    /// The number as printed, censored bounds included — what an axis needs.
    var magnitude: Double?
    /// `LabValueShape.rawValue`. Lets a chart select only the results that share
    /// a shape without decoding every payload.
    var shapeRaw: String
    var unit: String
    var collectedAt: Date
    var sourceRaw: String
    var confidenceRaw: String
    /// The whole `LabResult`, JSON-encoded. The authority; the columns above are
    /// a projection of it.
    var payload: Data

    init?(_ result: LabResult) {
        guard let payload = try? LabResultRecord.encoder.encode(result) else { return nil }
        self.id = result.id
        self.analyteKey = result.analyte.key
        self.analyteName = result.analyte.displayName
        self.value = result.value.measuredNumber
        self.magnitude = result.value.magnitude
        self.shapeRaw = result.value.shape.rawValue
        self.unit = result.unit
        self.collectedAt = result.collectedAt
        self.sourceRaw = result.source.rawValue
        self.confidenceRaw = result.confidence.rawValue
        self.payload = payload
    }

    /// The value type, or nil when the stored payload cannot be read.
    var result: LabResult? {
        try? LabResultRecord.decoder.decode(LabResult.self, from: payload)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// An imported ECG.
///
/// ⚠️ **The waveform is a file, not a column.** `attachmentFileName` names a
/// document in the app's own container (`DocumentAttachmentStore`); the bytes
/// are never in the database and never in the export. What is here is the
/// metadata printed *around* the trace and, where the document printed one, a
/// verbatim quotation of the classification **with the attribution attached** —
/// see `ECGFindingProvenance`, which has no case for a finding this app made
/// because this app makes none.
@Model
final class ECGRecordEntry {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var sourceRaw: String
    var attachmentFileName: String?
    var payload: Data

    init?(_ record: ECGRecord) {
        guard let payload = try? LabResultRecord.encoder.encode(record) else { return nil }
        self.id = record.id
        self.recordedAt = record.recordedAt
        self.sourceRaw = record.source.rawValue
        self.attachmentFileName = record.attachmentFileName
        self.payload = payload
    }

    var record: ECGRecord? {
        try? LabResultRecord.decoder.decode(ECGRecord.self, from: payload)
    }
}
