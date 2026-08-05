import XCTest
@testable import InsightKit

/// **The optimisation that fixed the canonical cache was never applied to the
/// bigger file.** `SampleCacheCodec` exists because decoding the samples through
/// `JSONDecoder` was "the largest single cost left on a cold launch" — and it
/// landed for `synced_samples` (6.6 MB on the reader's record) while
/// `synced_other.json` (**109 MB**) stayed on plain `Codable`.
final class RawCacheCodecTests: XCTestCase {

    private func sample(_ identifier: String, _ value: RawValue,
                        secondsAgo: Double = 0) -> RawMetricSample {
        RawMetricSample(identifier: identifier,
                        displayName: identifier.replacingOccurrences(of: ".", with: " "),
                        value: value, unit: "unit",
                        start: Date(timeIntervalSinceReferenceDate: 700_000_000 - secondsAgo),
                        source: .oura)
    }

    private func assertRoundTrips(_ samples: [RawMetricSample],
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard let data = RawCacheCodec.encode(samples) else {
            return XCTFail("encode returned nil", file: file, line: line)
        }
        guard let back = RawCacheCodec.decode(data) else {
            return XCTFail("decode returned nil", file: file, line: line)
        }
        XCTAssertEqual(back.count, samples.count, file: file, line: line)
        for (a, b) in zip(samples, back) {
            XCTAssertEqual(a.identifier, b.identifier, file: file, line: line)
            XCTAssertEqual(a.displayName, b.displayName, file: file, line: line)
            XCTAssertEqual(a.unit, b.unit, file: file, line: line)
            XCTAssertEqual(a.value, b.value, file: file, line: line)
            XCTAssertEqual(a.source, b.source, file: file, line: line)
            XCTAssertEqual(a.start.timeIntervalSinceReferenceDate,
                           b.start.timeIntervalSinceReferenceDate, accuracy: 0.0001,
                           file: file, line: line)
        }
    }

    /// **All three value shapes**, because the string ones are often the most
    /// meaningful field in the payload and are the reason this codec needs a tag
    /// where the sample one does not.
    func testEveryValueShapeSurvives() {
        assertRoundTrips([
            sample("oura.sleep.hr", .number(58.5)),
            sample("oura.sleep.phases", .text("4443332211")),
            sample("oura.daily.active", .flag(true)),
            sample("oura.daily.inactive", .flag(false)),
            sample("apple.steps", .number(0)),
            sample("apple.negative", .number(-3.25)),
        ])
    }

    func testAnEmptySetRoundTrips() {
        assertRoundTrips([])
    }

    /// The interning has to hold when one identifier carries several units or
    /// display names — the triple is the key, not the identifier alone.
    func testTheSameIdentifierWithDifferentUnitsStaysDistinct() {
        let a = RawMetricSample(identifier: "x", displayName: "X", value: .number(1),
                                unit: "mg", start: Date(), source: .oura)
        let b = RawMetricSample(identifier: "x", displayName: "X", value: .number(2),
                                unit: "mcg", start: Date(), source: .oura)
        guard let back = RawCacheCodec.encode([a, b]).flatMap(RawCacheCodec.decode) else {
            return XCTFail("round trip failed")
        }
        XCTAssertEqual(back.map(\.unit), ["mg", "mcg"])
    }

    // MARK: - It has to refuse what it cannot read

    /// A legacy JSON cache must decode as nil so the caller falls back rather
    /// than half-loading. A JSON array begins with `[`, which the magic
    /// distinguishes cheaply.
    func testALegacyJSONCacheIsRefusedRatherThanMisread() {
        let json = Data(#"[{"identifier":"x"}]"#.utf8)
        XCTAssertNil(RawCacheCodec.decode(json))
    }

    func testTruncationAndCorruptionAreRefused() {
        let samples = [sample("a", .number(1)), sample("b", .text("hello"))]
        let data = try! XCTUnwrap(RawCacheCodec.encode(samples))
        // Every prefix short of the whole file must be refused, never
        // half-decoded — a truncated write is the realistic corruption here.
        for cut in stride(from: 0, to: data.count, by: max(1, data.count / 40)) {
            XCTAssertNil(RawCacheCodec.decode(data.prefix(cut)),
                         "a \(cut)-byte prefix decoded as though it were whole")
        }
        XCTAssertNil(RawCacheCodec.decode(Data()))
        XCTAssertNil(RawCacheCodec.decode(Data([0x48, 0x49, 0x52, 0x43, 99])),
                     "a future version number was accepted by this build")
    }

    /// A `Data` slice keeps its parent's indices, and every offset in the
    /// decoder is zero-based — the sample codec documents the same trap.
    func testASliceWithNonZeroIndicesStillDecodes() {
        let samples = [sample("a", .number(1))]
        let data = try! XCTUnwrap(RawCacheCodec.encode(samples))
        let padded = Data([0, 0, 0]) + data
        XCTAssertNotNil(RawCacheCodec.decode(padded.dropFirst(3)))
    }

    // MARK: - The point of the exercise

    /// **The measurement, not the claim.** A realistic shape — 200 identifiers,
    /// a handful of sources, a repeated hypnogram string — must come out
    /// dramatically smaller than `JSONEncoder`, because the size is the decode
    /// time.
    func testItIsFarSmallerThanJSONOnARealisticShape() throws {
        var samples: [RawMetricSample] = []
        let hypnogram = String(repeating: "4443332211", count: 40)
        for i in 0..<20_000 {
            let id = "oura.daily_activity.field_\(i % 200)"
            let value: RawValue = i % 50 == 0 ? .text(hypnogram) : .number(Double(i) * 1.5)
            samples.append(sample(id, value, secondsAgo: Double(i) * 60))
        }
        let compact = try XCTUnwrap(RawCacheCodec.encode(samples))
        let json = try XCTUnwrap(try? JSONEncoder().encode(samples))
        let ratio = Double(json.count) / Double(compact.count)
        XCTAssertGreaterThan(ratio, 5,
                             "compact is only \(String(format: "%.1f", ratio))x smaller than JSON — the interning is not working")
        // And it still round-trips at that size.
        XCTAssertEqual(RawCacheCodec.decode(compact)?.count, samples.count)
    }
}
