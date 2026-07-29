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

    static func day(_ s: String?) -> Date? { s.flatMap { dayFormatter.date(from: $0) } }

    // MARK: - Additional daily endpoints (scrape everything Oura offers)

    /// `usercollection/daily_readiness` → skin-temperature deviation (°C).
    public static func parseDailyReadiness(_ data: Data) throws -> [HealthMetricSample] {
        struct List: Decodable { let data: [Rec] }
        struct Rec: Decodable { let day: String?; let temperature_deviation: Double? }
        let list = try JSONDecoder().decode(List.self, from: data)
        return list.data.compactMap { r -> HealthMetricSample? in
            guard let d = day(r.day), let dev = r.temperature_deviation else { return nil }
            return HealthMetricSample(type: .skinTemperatureDeviation, value: dev,
                                      start: d, end: d, source: .oura)
        }
    }

    /// `usercollection/daily_spo2` → blood oxygen (%).
    public static func parseDailySpo2(_ data: Data) throws -> [HealthMetricSample] {
        struct List: Decodable { let data: [Rec] }
        struct Rec: Decodable { let day: String?; let spo2_percentage: Pct? }
        struct Pct: Decodable { let average: Double? }
        let list = try JSONDecoder().decode(List.self, from: data)
        return list.data.compactMap { r -> HealthMetricSample? in
            guard let d = day(r.day), let avg = r.spo2_percentage?.average else { return nil }
            return HealthMetricSample(type: .oxygenSaturation, value: avg,
                                      start: d, end: d, source: .oura)
        }
    }

    /// `usercollection/daily_activity` → steps + active energy (kcal).
    public static func parseDailyActivity(_ data: Data) throws -> [HealthMetricSample] {
        struct List: Decodable { let data: [Rec] }
        struct Rec: Decodable { let day: String?; let steps: Double?; let active_calories: Double? }
        let list = try JSONDecoder().decode(List.self, from: data)
        var out: [HealthMetricSample] = []
        for r in list.data {
            guard let d = day(r.day) else { continue }
            if let s = r.steps {
                out.append(HealthMetricSample(type: .stepCount, value: s, start: d, end: d, source: .oura))
            }
            if let c = r.active_calories {
                out.append(HealthMetricSample(type: .activeEnergyBurned, value: c, start: d, end: d, source: .oura))
            }
        }
        return out
    }

    // MARK: - Generic "scrape everything" raw capture

    /// Fields already promoted to canonical metrics, so we don't also duplicate
    /// them into the "Other data" bucket.
    private static let mappedOuraKeys: Set<String> = [
        "lowest_heart_rate", "average_heart_rate", "average_hrv", "average_breath",
        "total_sleep_duration", "temperature_deviation", "spo2_percentage",
        "steps", "active_calories"
    ]

    private static let ignoredOuraKeys: Set<String> = [
        "id", "day", "timestamp", "bedtime_start", "bedtime_end"
    ]

    /// Capture **every** numeric field in an Oura daily document (top level and
    /// one level of nested objects, e.g. `contributors`) as `RawMetricSample`s,
    /// so nothing Oura returns is thrown away. Fields already modelled as
    /// canonical metrics are skipped. Namespaced `oura.<endpoint>.<field>`.
    public static func parseRawDaily(_ data: Data, endpoint: String) -> [RawMetricSample] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = obj["data"] as? [[String: Any]] else { return [] }
        var out: [RawMetricSample] = []
        for rec in records {
            guard let date = rawDate(rec) else { continue }
            func emit(_ key: String, _ subkey: String?, _ any: Any) {
                guard let value = numericValue(any) else { return }
                let idSuffix = subkey.map { "\(key).\($0)" } ?? key
                let name = subkey.map { "\(humanize(key)): \(humanize($0))" } ?? humanize(key)
                out.append(RawMetricSample(identifier: "oura.\(endpoint).\(idSuffix)",
                                           displayName: "\(name) (Oura)",
                                           value: value, unit: "", start: date, source: .oura))
            }
            for (key, val) in rec {
                if ignoredOuraKeys.contains(key) || mappedOuraKeys.contains(key) { continue }
                if numericValue(val) != nil {
                    emit(key, nil, val)
                } else if let nested = val as? [String: Any] {
                    for (subkey, subval) in nested where numericValue(subval) != nil {
                        emit(key, subkey, subval)
                    }
                }
            }
        }
        return out
    }

    private static func numericValue(_ any: Any) -> Double? {
        guard let n = any as? NSNumber else { return nil }
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }   // exclude true/false
        return n.doubleValue
    }

    private static func rawDate(_ rec: [String: Any]) -> Date? {
        if let d = (rec["day"] as? String).flatMap({ dayFormatter.date(from: $0) }) { return d }
        for key in ["timestamp", "bedtime_start"] {
            if let s = rec[key] as? String, let d = ISO8601DateFormatter().date(from: s) { return d }
        }
        return nil
    }

    static func humanize(_ raw: String) -> String {
        var out = ""
        for (i, ch) in raw.enumerated() {
            if i > 0, ch == "_" { out.append(" "); continue }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}
