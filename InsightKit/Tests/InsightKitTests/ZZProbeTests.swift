import XCTest
@testable import InsightKit

/// Scratch probe: does the proposed `Vitals` one-liner preserve the power of
/// testASustainedElevationIsFlaggedEvenWhenDenselySampled?
private let pNow = Date(timeIntervalSince1970: 1_700_000_000)
private let pCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func pDay(_ n: Int) -> Date {
    pCal.startOfDay(for: pNow.addingTimeInterval(-Double(n) * 86_400))
        .addingTimeInterval(12 * 3600)
}

final class ZZProbeTests: XCTestCase {

    /// The fixture as it exists today: today is elevated ALL DAY (24 readings).
    private func currentFixture() -> [HealthMetricSample] {
        var s: [HealthMetricSample] = []
        for day in 1...14 {
            for hour in 0..<24 {
                s.append(HealthMetricSample(type: .heartRate,
                    value: 62 + Double(hour % 5) + Double(day % 3),
                    start: pDay(day).addingTimeInterval(Double(hour) * 3600),
                    source: .appleHealth))
            }
        }
        for hour in 0..<24 {
            s.append(HealthMetricSample(type: .heartRate, value: 96 + Double(hour % 5),
                start: pDay(0).addingTimeInterval(Double(hour) * 3600), source: .appleHealth))
        }
        return s
    }

    /// The proposal's rewrite, read literally:
    ///   Vitals.fortnight(of:.heartRate, around: 63).sampled(timesPerDay: 24).then(.heartRate, 98)
    /// `.then` is documented as "today's departure" and takes a single scalar,
    /// so today gets ONE sample at 98.
    private func proposedFixture() -> [HealthMetricSample] {
        var s: [HealthMetricSample] = []
        for day in 1...14 {
            for hour in 0..<24 {
                s.append(HealthMetricSample(type: .heartRate,
                    value: 63 + Double(day % 3) - 1,
                    start: pDay(day).addingTimeInterval(Double(hour) * 3600),
                    source: .appleHealth))
            }
        }
        s.append(HealthMetricSample(type: .heartRate, value: 98,
            start: pDay(0).addingTimeInterval(12 * 3600), source: .appleHealth))
        return s
    }

    /// Reproduce the ORIGINAL defect: baseline = the last 60 raw readings.
    private func oldStyleZ(_ samples: [HealthMetricSample]) -> Double {
        let sorted = samples.sorted { $0.start < $1.start }
        let latest = sorted.last!.value
        let history = sorted.suffix(60).dropLast().map(\.value)
        let mean = history.reduce(0, +) / Double(history.count)
        let variance = history.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(history.count)
        let sd = variance.squareRoot()
        return sd < 1e-9 ? 0 : (latest - mean) / sd
    }

    func testProbe() {
        let cur = currentFixture()
        let prop = proposedFixture()

        // Both must pass against the CURRENT (fixed) implementation.
        let curOut = VitalSignsCheck.evaluate(samples: cur, now: pNow, calendar: pCal)
        let propOut = VitalSignsCheck.evaluate(samples: prop, now: pNow, calendar: pCal)
        let curR = curOut.readings.first { $0.metric == .heartRate }
        let propR = propOut.readings.first { $0.metric == .heartRate }
        print("PROBE current  -> status=\(curR?.status as Any) value=\(curR?.value ?? -1)")
        print("PROBE proposed -> status=\(propR?.status as Any) value=\(propR?.value ?? -1)")

        // Now: would each fixture CATCH a reintroduction of the suffix(60) bug?
        print("PROBE old-style z, current fixture  = \(oldStyleZ(cur))")
        print("PROBE old-style z, proposed fixture = \(oldStyleZ(prop))")
        print("PROBE today's raw reading count, current  = \(cur.filter { pCal.isDate($0.start, inSameDayAs: pNow) }.count)")
        print("PROBE today's raw reading count, proposed = \(prop.filter { pCal.isDate($0.start, inSameDayAs: pNow) }.count)")
    }
}
