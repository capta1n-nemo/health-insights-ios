import Foundation

/// The compact on-disk encoding of the synced-sample cache.
///
/// The cache used to be `[HealthMetricSample]` through `JSONEncoder`, which
/// writes ~190 bytes per sample — a 36-character UUID string and a full
/// `{id, displayName}` source object repeated on every one of ~130k readings
/// that only ever name a handful of distinct sources. Decoding it was measured
/// at ~1 s and was the largest single cost left on a cold launch (68% of the
/// remaining time after the evaluation memo landed — see
/// `docs/activeContext.md` ▸ "Immediate next steps").
///
/// This format writes each distinct source and metric type **once**, in two
/// small tables, and then a fixed 28-byte record per sample: two table
/// indices and three raw doubles. No per-sample strings at all, which is
/// where both the bytes and the decode time were going.
///
/// **The per-sample UUID is deliberately not stored.** Nothing in the app
/// depends on a cached sample keeping its identity across launches — `id` is
/// SwiftUI list identity within a session; de-duplication keys on device
/// family, minute and value, and the cache-merge keys on `source.id`. Fresh
/// UUIDs are minted on decode. If something ever *does* need a stable
/// cross-launch identity, that is a format change: bump the version and store
/// it, don't derive it.
///
/// **Migration is one-way and free.** `DataStore.loadCachedSamples` tries
/// this format first and falls back to the legacy JSON file, so the first
/// launch after the update reads the old cache exactly as before; the next
/// save writes this format and retires the legacy file. A build downgraded
/// past this change would re-sync rather than read the new file — the cache
/// is a startup convenience, not a store of record, so that costs one
/// provider round-trip and loses nothing.
///
/// Everything multi-byte is **little-endian on disk**, stated explicitly
/// rather than assumed: every platform this app ships on is little-endian
/// today, and the explicit conversion is what keeps the file readable if that
/// ever stops being true.
public enum SampleCacheCodec {

    /// "HISC" — Health Insights Sample Cache. A legacy cache begins with `[`
    /// or whitespace, so the magic also cheaply distinguishes the formats.
    private static let magic: [UInt8] = [0x48, 0x49, 0x53, 0x43]
    private static let version: UInt8 = 1

    /// magic + version + three UInt32s (two table lengths and the record count).
    private static let headerSize = 4 + 1 + 4 + 4 + 4
    /// type index (2) + source index (2) + value, start, end (8 each).
    private static let recordSize = 2 + 2 + 8 + 8 + 8

    // MARK: - Encode

    /// Returns `nil` only if the sample set cannot be represented — more than
    /// 65 535 distinct sources or types, which no real dataset approaches. The
    /// caller keeps writing the legacy format in that case rather than
    /// dropping the cache.
    public static func encode(_ samples: [HealthMetricSample]) -> Data? {
        var sourceIndex: [MetricSource: UInt16] = [:]
        var sources: [MetricSource] = []
        var typeIndex: [MetricType: UInt16] = [:]
        var types: [MetricType] = []

        for sample in samples {
            if sourceIndex[sample.source] == nil {
                guard sources.count <= Int(UInt16.max) else { return nil }
                sourceIndex[sample.source] = UInt16(sources.count)
                sources.append(sample.source)
            }
            if typeIndex[sample.type] == nil {
                guard types.count <= Int(UInt16.max) else { return nil }
                typeIndex[sample.type] = UInt16(types.count)
                types.append(sample.type)
            }
        }

        // The two tables stay JSON: they are tens of entries, self-describing,
        // and `MetricSource` keeps its own Codable shape rather than this
        // codec restating it.
        guard let sourcesJSON = try? JSONEncoder().encode(sources),
              let typesJSON = try? JSONEncoder().encode(types.map(\.rawValue)),
              sourcesJSON.count <= Int(UInt32.max),
              typesJSON.count <= Int(UInt32.max),
              samples.count <= Int(UInt32.max)
        else { return nil }

        var data = Data(capacity: headerSize + sourcesJSON.count + typesJSON.count
                        + samples.count * recordSize)
        data.append(contentsOf: magic)
        data.append(version)
        appendUInt32(&data, UInt32(sourcesJSON.count))
        appendUInt32(&data, UInt32(typesJSON.count))
        appendUInt32(&data, UInt32(samples.count))
        data.append(sourcesJSON)
        data.append(typesJSON)

        for sample in samples {
            appendUInt16(&data, typeIndex[sample.type]!)
            appendUInt16(&data, sourceIndex[sample.source]!)
            appendUInt64(&data, sample.value.bitPattern)
            appendUInt64(&data, sample.start.timeIntervalSinceReferenceDate.bitPattern)
            appendUInt64(&data, sample.end.timeIntervalSinceReferenceDate.bitPattern)
        }
        return data
    }

    // MARK: - Decode

    /// Returns `nil` for anything that is not a well-formed file in this
    /// format — a legacy JSON cache, a truncated write, a corrupted table —
    /// so the caller can fall back rather than crash or half-load.
    ///
    /// A record whose type string no longer names a `MetricType` case is
    /// **skipped, not fatal**: a future build that removes a metric should
    /// still read the rest of its old cache.
    public static func decode(_ data: Data) -> [HealthMetricSample]? {
        // A Data *slice* keeps its parent's indices; everything below assumes
        // zero-based offsets, so rebase the rare non-zero-based input.
        let data = data.startIndex == 0 ? data : Data(data)
        guard data.count >= headerSize else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [HealthMetricSample]? in
            guard raw[0] == magic[0], raw[1] == magic[1],
                  raw[2] == magic[2], raw[3] == magic[3],
                  raw[4] == version else { return nil }

            let sourcesLength = Int(readUInt32(raw, at: 5))
            let typesLength = Int(readUInt32(raw, at: 9))
            let count = Int(readUInt32(raw, at: 13))

            // Overflow-safe bounds check: each part is validated against what
            // remains rather than summing untrusted lengths.
            var offset = headerSize
            guard data.count - offset >= sourcesLength else { return nil }
            let sourcesJSON = data.subdata(in: offset ..< offset + sourcesLength)
            offset += sourcesLength
            guard data.count - offset >= typesLength else { return nil }
            let typesJSON = data.subdata(in: offset ..< offset + typesLength)
            offset += typesLength
            guard count >= 0, (data.count - offset) / recordSize >= count else { return nil }

            guard let sources = try? JSONDecoder().decode([MetricSource].self, from: sourcesJSON),
                  let typeNames = try? JSONDecoder().decode([String].self, from: typesJSON)
            else { return nil }
            let types: [MetricType?] = typeNames.map(MetricType.init(rawValue:))

            var samples: [HealthMetricSample] = []
            samples.reserveCapacity(count)
            var minter = UUIDMinter()
            for record in 0 ..< count {
                let base = offset + record * recordSize
                let typeIdx = Int(readUInt16(raw, at: base))
                let sourceIdx = Int(readUInt16(raw, at: base + 2))
                guard typeIdx < types.count, sourceIdx < sources.count else { return nil }
                // A retired metric type: the table names it, the enum no
                // longer does. Drop the sample, keep the file.
                guard let type = types[typeIdx] else { continue }
                let value = Double(bitPattern: readUInt64(raw, at: base + 4))
                let start = Double(bitPattern: readUInt64(raw, at: base + 12))
                let end = Double(bitPattern: readUInt64(raw, at: base + 20))
                samples.append(HealthMetricSample(
                    id: minter.next(), type: type, value: value,
                    start: Date(timeIntervalSinceReferenceDate: start),
                    end: Date(timeIntervalSinceReferenceDate: end),
                    source: sources[sourceIdx]))
            }
            return samples
        }
    }

    /// Mints unique UUIDs at a counter's cost rather than a syscall's.
    ///
    /// `Foundation.UUID()` was measured at ~145 ms for a 108k-sample decode —
    /// by itself the whole of the remaining cache-read time. A cached
    /// sample's id only has to be *unique* (it is SwiftUI list identity for
    /// this session; nothing persists it), so: one random `UUID()` base per
    /// decode, low eight bytes replaced by an incrementing counter that
    /// starts from the base's own random low half. Ids stay distinct within
    /// a load by the counter, and across loads and against freshly synced
    /// samples by the 64 random high bits.
    private struct UUIDMinter {
        private let base: uuid_t
        private var counter: UInt64

        init() {
            base = UUID().uuid
            counter = UInt64(base.8) << 56 | UInt64(base.9) << 48
                | UInt64(base.10) << 40 | UInt64(base.11) << 32
                | UInt64(base.12) << 24 | UInt64(base.13) << 16
                | UInt64(base.14) << 8 | UInt64(base.15)
        }

        mutating func next() -> UUID {
            counter &+= 1
            let c = counter
            return UUID(uuid: (base.0, base.1, base.2, base.3,
                               base.4, base.5, base.6, base.7,
                               UInt8(truncatingIfNeeded: c >> 56),
                               UInt8(truncatingIfNeeded: c >> 48),
                               UInt8(truncatingIfNeeded: c >> 40),
                               UInt8(truncatingIfNeeded: c >> 32),
                               UInt8(truncatingIfNeeded: c >> 24),
                               UInt8(truncatingIfNeeded: c >> 16),
                               UInt8(truncatingIfNeeded: c >> 8),
                               UInt8(truncatingIfNeeded: c)))
        }
    }

    // MARK: - Little-endian plumbing

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
