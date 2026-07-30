import Foundation

/// Maps the Withings **Measure API** (`action=getmeas`) JSON into canonical
/// samples. Pure and dependency-free for unit testing.
///
/// Withings encodes each measure as `real = value × 10^unit` with a numeric
/// `type`. We map the types we understand and ignore the rest:
///   1  → weight (kg)                6  → fat ratio (%)
///   5  → fat-free (lean) mass (kg)  9  → diastolic BP (mmHg)
///   10 → systolic BP (mmHg)
public enum WithingsResponseParser {

    private struct Response: Decodable {
        let status: Int
        let body: Body?
    }
    private struct Body: Decodable {
        let measuregrps: [MeasureGroup]
    }
    private struct MeasureGroup: Decodable {
        let date: Double                 // epoch seconds
        let measures: [Measure]
    }
    private struct Measure: Decodable {
        let value: Double
        let type: Int
        let unit: Int
    }

    enum WithingsError: Error { case apiStatus(Int) }

    /// Parse a `getmeas` response into canonical samples.
    public static func parseMeasures(_ data: Data) throws -> [HealthMetricSample] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status == 0 else { throw WithingsError.apiStatus(response.status) }
        guard let groups = response.body?.measuregrps else { return [] }

        var samples: [HealthMetricSample] = []
        for group in groups {
            let date = Date(timeIntervalSince1970: group.date)
            for measure in group.measures {
                guard let metric = metricType(for: measure.type) else { continue }
                let real = measure.value * pow(10, Double(measure.unit))
                samples.append(HealthMetricSample(type: metric, value: real,
                                                  start: date, end: date, source: .withings))
            }
        }
        return samples
    }

    // The "other measures" capture that used to live here is now
    // `WithingsMeasureIngestor`, which keeps every measure type — not only the
    // unmapped ones — along with the group metadata (`attrib`, `category`,
    // `deviceid`) and the free-text `comment` this could not represent.

    static func metricType(for withingsType: Int) -> MetricType? {
        switch withingsType {
        case 1: return .bodyMass                 // kg
        case 5: return .leanBodyMass             // kg (fat-free mass)
        case 6: return .bodyFatPercentage        // %
        case 9: return .bloodPressureDiastolic   // mmHg
        case 10: return .bloodPressureSystolic   // mmHg
        case 11: return .heartRate               // bpm (heart pulse)
        case 54: return .oxygenSaturation        // % SpO2
        // 71 and 73 are different measurements and were sharing a type. A skin
        // reading is two to three degrees cooler than a core one, so through the
        // core bounds every type-73 value read as hypothermia.
        case 71: return .bodyTemperature         // °C body temperature (core)
        case 73: return .skinTemperature         // °C skin temperature
        case 76: return .muscleMass              // kg
        case 77: return .bodyWaterPercentage     // %
        case 88: return .boneMass                // kg
        default: return nil
        }
    }
}
