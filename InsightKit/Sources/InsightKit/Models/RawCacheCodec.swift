import Foundation

/// The compact on-disk encoding of the **raw** sample cache — `SampleCacheCodec`
/// for the other half of the store.
///
/// ⚠️ **The optimisation that fixed the canonical cache was never applied to
/// the larger file.** `SampleCacheCodec`'s own comment records that decoding
/// `[HealthMetricSample]` through `JSONDecoder` cost ~1 s and was "the largest
/// single cost left on a cold launch", against single-digit milliseconds for a
/// packed format. That landed for `synced_samples`, which is **6.6 MB** on the
/// reader's record — and left `synced_other.json`, which is **109 MB**, on
/// plain `Codable`.
///
/// The waste is the same and worse: 320,913 rows carrying a 36-character UUID
/// string, an `identifier`, a `displayName`, a `unit` and a `{id, displayName}`
/// source object each, when the whole file names roughly two hundred distinct
/// identifiers and a handful of sources. Interning them is most of the file.
///
/// **The evidence that the format is the problem and not the file:** Python's C
/// JSON parser reads the same 109 MB in 0.58 s. Swift's `Codable` decodes 320k
/// structs with a custom enum far more slowly than that, and it does it before
/// the first frame.
///
/// Same design decisions as `SampleCacheCodec`, and for the same reasons:
///
/// - **The per-sample UUID is not stored.** `id` is SwiftUI list identity
///   within a session; nothing depends on it surviving a launch. Fresh UUIDs
///   are minted on decode.
/// - **The tables stay JSON.** They are hundreds of entries, self-describing,
///   and `MetricSource` keeps its own `Codable` shape rather than this codec
///   restating it.
/// - **Migration is one-way and free.** `loadCachedOther` tries this first and
///   falls back to the JSON file, so the first launch after the update reads
///   the old cache exactly as before and the next save retires it.
/// - **Little-endian on disk, explicitly**, so the file stays readable if that
///   ever stops being the default.
///
/// The one thing this format has that the sample one does not is a value
/// *tag*: a raw value is a number, a string or a flag, and the string ones are
/// often the most meaningful field in the payload. Strings are interned into
/// their own table, because a hypnogram repeated across a night is the same
/// handful of characters thousands of times.
public enum RawCacheCodec {

    /// "HIRC" — Health Insights Raw Cache. A legacy cache begins with `[` or
    /// whitespace, so the magic also cheaply distinguishes the formats.
    private static let magic: [UInt8] = [0x48, 0x49, 0x52, 0x43]
    private static let version: UInt8 = 1

    /// magic + version + four UInt32s (three table lengths and the record count).
    private static let headerSize = 4 + 1 + 4 + 4 + 4 + 4
    /// field index (4) + source index (2) + tag (1) + payload (8) + start, end (8 each).
    private static let recordSize = 4 + 2 + 1 + 8 + 8 + 8

    private enum Tag: UInt8 { case number = 0, text = 1, flag = 2 }

    /// The three strings that travel together on every row. Interned as one
    /// triple rather than three tables: `identifier` determines the other two
    /// in practice, so splitting them would triple the lookups to save nothing.
    private struct Field: Codable, Hashable {
        let identifier: String
        let displayName: String
        let unit: String
    }

    // MARK: - Encode

    /// `nil` only when the set cannot be represented — more than 65 535 distinct
    /// sources, or more than `UInt32.max` of anything. The caller keeps writing
    /// JSON in that case rather than dropping the cache.
    public static func encode(_ samples: [RawMetricSample]) -> Data? {
        var fieldIndex: [Field: UInt32] = [:]
        var fields: [Field] = []
        var sourceIndex: [MetricSource: UInt16] = [:]
        var sources: [MetricSource] = []
        var textIndex: [String: UInt32] = [:]
        var texts: [String] = []

        for sample in samples {
            let field = Field(identifier: sample.identifier,
                              displayName: sample.displayName, unit: sample.unit)
            if fieldIndex[field] == nil {
                fieldIndex[field] = UInt32(fields.count)
                fields.append(field)
            }
            if sourceIndex[sample.source] == nil {
                guard sources.count <= Int(UInt16.max) else { return nil }
                sourceIndex[sample.source] = UInt16(sources.count)
                sources.append(sample.source)
            }
            if case .text(let s) = sample.value, textIndex[s] == nil {
                textIndex[s] = UInt32(texts.count)
                texts.append(s)
            }
        }

        guard let fieldsJSON = try? JSONEncoder().encode(fields),
              let sourcesJSON = try? JSONEncoder().encode(sources),
              let textsJSON = try? JSONEncoder().encode(texts),
              fieldsJSON.count <= Int(UInt32.max),
              sourcesJSON.count <= Int(UInt32.max),
              textsJSON.count <= Int(UInt32.max),
              samples.count <= Int(UInt32.max)
        else { return nil }

        var data = Data(capacity: headerSize + fieldsJSON.count + sourcesJSON.count
                        + textsJSON.count + samples.count * recordSize)
        data.append(contentsOf: magic)
        data.append(version)
        appendUInt32(&data, UInt32(fieldsJSON.count))
        appendUInt32(&data, UInt32(sourcesJSON.count))
        appendUInt32(&data, UInt32(textsJSON.count))
        appendUInt32(&data, UInt32(samples.count))
        data.append(fieldsJSON)
        data.append(sourcesJSON)
        data.append(textsJSON)

        for sample in samples {
            let field = Field(identifier: sample.identifier,
                              displayName: sample.displayName, unit: sample.unit)
            appendUInt32(&data, fieldIndex[field]!)
            appendUInt16(&data, sourceIndex[sample.source]!)
            switch sample.value {
            case .number(let d):
                data.append(Tag.number.rawValue)
                appendUInt64(&data, d.bitPattern)
            case .text(let s):
                data.append(Tag.text.rawValue)
                appendUInt64(&data, UInt64(textIndex[s]!))
            case .flag(let b):
                data.append(Tag.flag.rawValue)
                appendUInt64(&data, b ? 1 : 0)
            }
            appendUInt64(&data, sample.start.timeIntervalSinceReferenceDate.bitPattern)
            appendUInt64(&data, sample.end.timeIntervalSinceReferenceDate.bitPattern)
        }
        return data
    }

    // MARK: - Decode

    /// `nil` for anything that is not a well-formed file in this format — a
    /// legacy JSON cache, a truncated write, a corrupted table — so the caller
    /// falls back rather than crashing or half-loading.
    public static func decode(_ data: Data) -> [RawMetricSample]? {
        // A Data *slice* keeps its parent's indices; everything below assumes
        // zero-based offsets.
        let data = data.startIndex == 0 ? data : Data(data)
        guard data.count >= headerSize else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [RawMetricSample]? in
            guard raw[0] == magic[0], raw[1] == magic[1],
                  raw[2] == magic[2], raw[3] == magic[3],
                  raw[4] == version else { return nil }

            let fieldsLength = Int(readUInt32(raw, at: 5))
            let sourcesLength = Int(readUInt32(raw, at: 9))
            let textsLength = Int(readUInt32(raw, at: 13))
            let count = Int(readUInt32(raw, at: 17))

            // Overflow-safe: each part is checked against what remains rather
            // than by summing untrusted lengths.
            var offset = headerSize
            var remaining = raw.count - offset
            guard fieldsLength <= remaining else { return nil }
            let fieldsData = Data(raw[offset..<(offset + fieldsLength)])
            offset += fieldsLength; remaining -= fieldsLength
            guard sourcesLength <= remaining else { return nil }
            let sourcesData = Data(raw[offset..<(offset + sourcesLength)])
            offset += sourcesLength; remaining -= sourcesLength
            guard textsLength <= remaining else { return nil }
            let textsData = Data(raw[offset..<(offset + textsLength)])
            offset += textsLength; remaining -= textsLength
            guard count <= remaining / recordSize else { return nil }

            guard let fields = try? JSONDecoder().decode([Field].self, from: fieldsData),
                  let sources = try? JSONDecoder().decode([MetricSource].self, from: sourcesData),
                  let texts = try? JSONDecoder().decode([String].self, from: textsData)
            else { return nil }

            var out: [RawMetricSample] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                let base = offset + i * recordSize
                let fieldIdx = Int(readUInt32(raw, at: base))
                let sourceIdx = Int(readUInt16(raw, at: base + 4))
                // Offsets: field 0..3, source 4..5, tag 6, payload 7..14,
                // start 15..22, end 23..30. Written out because the first
                // version of this read the tag at +5 — inside the source index
                // — and every field after it was shifted by a byte, which
                // decoded as plausible-looking garbage rather than failing.
                let tagByte = raw[base + 6]
                let payload = readUInt64(raw, at: base + 7)
                let start = readUInt64(raw, at: base + 15)
                let end = readUInt64(raw, at: base + 23)

                // A table index out of range means a corrupt file, not a
                // skippable row — everything after it is suspect too.
                guard fieldIdx < fields.count, sourceIdx < sources.count,
                      let tag = Tag(rawValue: tagByte) else { return nil }
                let field = fields[fieldIdx]
                let value: RawValue
                switch tag {
                case .number: value = .number(Double(bitPattern: payload))
                case .flag: value = .flag(payload != 0)
                case .text:
                    guard Int(payload) < texts.count else { return nil }
                    value = .text(texts[Int(payload)])
                }
                out.append(RawMetricSample(
                    identifier: field.identifier,
                    displayName: field.displayName,
                    value: value,
                    unit: field.unit,
                    start: Date(timeIntervalSinceReferenceDate: Double(bitPattern: start)),
                    end: Date(timeIntervalSinceReferenceDate: Double(bitPattern: end)),
                    source: sources[sourceIdx]))
            }
            return out
        }
    }

    // MARK: - Little-endian primitives

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    private static func appendUInt64(_ data: inout Data, _ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    private static func readUInt16(_ raw: UnsafeRawBufferPointer, at offset: Int) -> UInt16 {
        UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }
    private static func readUInt32(_ raw: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
    private static func readUInt64(_ raw: UnsafeRawBufferPointer, at offset: Int) -> UInt64 {
        UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }
}
