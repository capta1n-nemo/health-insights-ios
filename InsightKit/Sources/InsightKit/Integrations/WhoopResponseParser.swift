import Foundation

/// Maps the WHOOP **v2** API JSON into canonical samples. Pure and dependency-free
/// so the mapping is unit-tested against recorded payloads without credentials.
///
/// Recovery records carry the daily cardiovascular signals; cycle records carry
/// Day Strain (0–21 cumulative cardiovascular load) — useful for the substance /
/// strain features.
public enum WhoopResponseParser {

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: Recovery

    private struct RecoveryList: Decodable { let records: [RecoveryRecord] }
    private struct RecoveryRecord: Decodable {
        let created_at: String?
        let score: Score?
        struct Score: Decodable {
            let resting_heart_rate: Double?
            let hrv_rmssd_milli: Double?
            let spo2_percentage: Double?
            let skin_temp_celsius: Double?
        }
    }

    public static func parseRecovery(_ data: Data) throws -> [HealthMetricSample] {
        let list = try JSONDecoder().decode(RecoveryList.self, from: data)
        var samples: [HealthMetricSample] = []
        for record in list.records {
            guard let when = date(record.created_at), let s = record.score else { continue }
            func add(_ type: MetricType, _ value: Double?) {
                guard let value else { return }
                samples.append(HealthMetricSample(type: type, value: value, start: when, source: .whoop))
            }
            add(.restingHeartRate, s.resting_heart_rate)
            add(.heartRateVariabilityRMSSD, s.hrv_rmssd_milli)
            add(.oxygenSaturation, s.spo2_percentage)
            add(.bodyTemperature, s.skin_temp_celsius)   // WHOOP reports absolute °C
        }
        return samples
    }

    // MARK: Cycles (Day Strain)

    private struct CycleList: Decodable { let records: [CycleRecord] }
    private struct CycleRecord: Decodable {
        let start: String?
        let score: Score?
        struct Score: Decodable { let strain: Double? }
    }

    public static func parseCycles(_ data: Data) throws -> [HealthMetricSample] {
        let list = try JSONDecoder().decode(CycleList.self, from: data)
        return list.records.compactMap { record in
            guard let when = date(record.start), let strain = record.score?.strain else { return nil }
            return HealthMetricSample(type: .dayStrain, value: strain, start: when, source: .whoop)
        }
    }
}
