import Foundation

/// Maps Oura API **v2** JSON into canonical `HealthMetricSample`s. Pure and
/// dependency-free so the mapping is unit-tested against recorded payloads
/// without any network or credentials.
///
/// Primary source is the `usercollection/sleep` endpoint, whose per-night
/// records carry the cardiovascular signals we care about:
///   - `lowest_heart_rate`  → resting heart rate (bpm)
///   - `average_hrv`        → HRV (rMSSD, ms)
///   - `average_breath`     → respiratory rate (breaths/min)
///   - `total_sleep_duration` (seconds) → sleep duration (hours)
public enum OuraResponseParser {

    private struct SleepList: Decodable {
        let data: [SleepRecord]
    }

    private struct SleepRecord: Decodable {
        let day: String?                       // "YYYY-MM-DD"
        let bedtime_start: String?             // ISO8601 with offset
        let lowest_heart_rate: Double?
        let average_heart_rate: Double?
        let average_hrv: Double?
        let average_breath: Double?
        let total_sleep_duration: Double?      // seconds
    }

    /// Parse a `usercollection/sleep` response.
    public static func parseSleep(_ data: Data) throws -> [HealthMetricSample] {
        let list = try JSONDecoder().decode(SleepList.self, from: data)
        var samples: [HealthMetricSample] = []
        for record in list.data {
            guard let date = date(from: record) else { continue }
            func add(_ type: MetricType, _ value: Double?) {
                guard let value else { return }
                samples.append(HealthMetricSample(type: type, value: value,
                                                  start: date, end: date, source: .oura))
            }
            // Prefer the sleeping low as a resting-HR proxy; fall back to average.
            add(.restingHeartRate, record.lowest_heart_rate ?? record.average_heart_rate)
            add(.heartRateVariabilityRMSSD, record.average_hrv)
            add(.respiratoryRate, record.average_breath)
            if let seconds = record.total_sleep_duration {
                add(.sleepDurationHours, seconds / 3600)
            }
        }
        return samples
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func date(from record: SleepRecord) -> Date? {
        if let day = record.day, let d = dayFormatter.date(from: day) { return d }
        if let start = record.bedtime_start {
            return ISO8601DateFormatter().date(from: start)
        }
        return nil
    }
}
