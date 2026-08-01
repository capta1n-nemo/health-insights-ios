import XCTest
@testable import InsightKit

final class SampleCacheCodecTests: XCTestCase {

    private func sample(_ type: MetricType = .heartRate, value: Double = 62,
                        minutesAgo: Double = 0,
                        source: MetricSource = .appleHealthDevice("Apple Watch"),
                        spanMinutes: Double = 0) -> HealthMetricSample {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000 - minutesAgo * 60)
        return HealthMetricSample(type: type, value: value, start: start,
                                  end: start.addingTimeInterval(spanMinutes * 60),
                                  source: source)
    }

    // MARK: - Round trip

    func testRoundTripPreservesEverythingExceptID() throws {
        let originals = [
            sample(.heartRate, value: 62.5, minutesAgo: 120),
            sample(.restingHeartRate, value: 48, minutesAgo: 60, source: .oura),
            sample(.sleepDurationHours, value: 7.4, minutesAgo: 30,
                   source: .whoop, spanMinutes: 444),
            // A signed metric with a fractional value, to catch any lossy
            // numeric path — bit patterns must survive exactly.
            sample(.sleepOnset, value: -1.25, minutesAgo: 10, source: .manual),
        ]
        let data = try XCTUnwrap(SampleCacheCodec.encode(originals))
        let decoded = try XCTUnwrap(SampleCacheCodec.decode(data))

        XCTAssertEqual(decoded.count, originals.count)
        for (a, b) in zip(originals, decoded) {
            XCTAssertEqual(a.type, b.type)
            XCTAssertEqual(a.value, b.value, "values must round-trip bit-exactly")
            XCTAssertEqual(a.start, b.start)
            XCTAssertEqual(a.end, b.end)
            XCTAssertEqual(a.source, b.source)
        }
    }

    func testRoundTripOfEmptyArray() throws {
        let data = try XCTUnwrap(SampleCacheCodec.encode([]))
        XCTAssertEqual(SampleCacheCodec.decode(data)?.count, 0)
    }

    func testDecodedIDsAreUnique() throws {
        let originals = (0 ..< 500).map { sample(value: Double($0)) }
        let data = try XCTUnwrap(SampleCacheCodec.encode(originals))
        let decoded = try XCTUnwrap(SampleCacheCodec.decode(data))
        XCTAssertEqual(Set(decoded.map(\.id)).count, decoded.count)
    }

    func testSourcesWithSameIDButDifferentNamesStayDistinct() throws {
        // Two Apple Health devices share the "apple_health/…" prefix scheme but
        // are different sources; interning must key on the whole source.
        let watch = MetricSource.appleHealthDevice("Apple Watch")
        let ring = MetricSource.appleHealthDevice("Oura")
        let originals = [sample(source: watch), sample(source: ring)]
        let data = try XCTUnwrap(SampleCacheCodec.encode(originals))
        let decoded = try XCTUnwrap(SampleCacheCodec.decode(data))
        XCTAssertEqual(decoded.map(\.source), [watch, ring])
    }

    // MARK: - The size claim, measured rather than asserted in prose

    func testCompactFormatIsAtLeastFourTimesSmallerThanJSON() throws {
        // A realistic shape: many samples, few sources, few types.
        let sources: [MetricSource] = [.appleHealthDevice("Apple Watch"), .oura, .withings]
        let types: [MetricType] = [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .bodyMass]
        let samples = (0 ..< 2000).map { i in
            sample(types[i % types.count], value: Double(40 + i % 60),
                   minutesAgo: Double(i), source: sources[i % sources.count])
        }
        let compact = try XCTUnwrap(SampleCacheCodec.encode(samples)).count
        let json = try JSONEncoder().encode(samples).count
        XCTAssertLessThan(compact * 4, json,
                          "compact \(compact) B vs JSON \(json) B — the format has lost its point")
    }

    // MARK: - Robustness: anything malformed is nil, never a crash or half-read

    func testLegacyJSONCacheIsNotMistakenForCompactFormat() throws {
        let json = try JSONEncoder().encode([sample()])
        XCTAssertNil(SampleCacheCodec.decode(json))
    }

    func testGarbageAndTruncationDecodeToNil() throws {
        XCTAssertNil(SampleCacheCodec.decode(Data()))
        XCTAssertNil(SampleCacheCodec.decode(Data([0x00, 0x01, 0x02])))

        let good = try XCTUnwrap(SampleCacheCodec.encode([sample(), sample(.bodyMass)]))
        // Every truncation point: header, tables, records.
        for length in [4, 10, good.count - 1, good.count - 20] where length < good.count {
            XCTAssertNil(SampleCacheCodec.decode(good.prefix(length)),
                         "truncated to \(length) of \(good.count) bytes must not decode")
        }
    }

    func testWrongVersionDecodesToNil() throws {
        var data = try XCTUnwrap(SampleCacheCodec.encode([sample()]))
        data[4] = 99
        XCTAssertNil(SampleCacheCodec.decode(data))
    }

    func testCorruptedTableLengthDecodesToNil() throws {
        var data = try XCTUnwrap(SampleCacheCodec.encode([sample()]))
        // Claim a sources table far past the end of the file.
        data.replaceSubrange(5 ..< 9, with: withUnsafeBytes(of: UInt32.max.littleEndian) { Data($0) })
        XCTAssertNil(SampleCacheCodec.decode(data))
    }

    func testUnknownMetricTypeSkipsItsSamplesAndKeepsTheRest() throws {
        // Simulate a future build that retired a metric: rewrite the type
        // table so one entry no longer names a case.
        let originals = [sample(.heartRate), sample(.bodyMass, value: 80)]
        let data = try XCTUnwrap(SampleCacheCodec.encode(originals))

        let heartRate = Data("\"heartRate\"".utf8)
        let retired = Data("\"heartRat_\"".utf8)  // same length, unknown name
        let range = try XCTUnwrap(data.range(of: heartRate))
        var edited = data
        edited.replaceSubrange(range, with: retired)

        let decoded = try XCTUnwrap(SampleCacheCodec.decode(edited))
        XCTAssertEqual(decoded.map(\.type), [.bodyMass],
                       "the retired type's sample is dropped, the rest survive")
    }
}
