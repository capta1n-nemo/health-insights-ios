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
        // The stage breakdown, decoded at last. These fields have been in every
        // sleep payload since v2 shipped and the parser read seven of them, so
        // Sleep Quality was scoring a night from its length and its breathing
        // while the composition of that night sat unread in the same document.
        let deep_sleep_duration: Double?       // seconds
        let rem_sleep_duration: Double?        // seconds
        let time_in_bed: Double?               // seconds
        let efficiency: Double?                // percent, Oura's own figure
    }

    /// Parse a `usercollection/sleep` response.
    ///
    /// `bedtime_start` was decoded here for years and used only as a fallback
    /// for the record's *date* — the time of day was discarded, which is the
    /// whole reason circadian consistency was logged as blocked on a missing
    /// signal. It now also produces `.sleepOnset`.
    ///
    /// The instant is resolved against `Calendar.current`, not against the
    /// offset Oura stamps on it. That is right for someone at home and wrong on
    /// the second night of a trip, where the phone has moved zones and the ring
    /// recorded the old one. `Calendar` is not a parameter because the typed
    /// parsers are referenced as `(Data) throws -> [HealthMetricSample]` by the
    /// provider, and a defaulted argument cannot be dropped from a function
    /// reference. HealthKit has the same property, so both sources agree.
    public static func parseSleep(_ data: Data) throws -> [HealthMetricSample] {
        let list = try JSONDecoder().decode(SleepList.self, from: data)
        var samples: [HealthMetricSample] = []
        var bedtimes: [Date] = []
        for record in list.data {
            if let raw = record.bedtime_start,
               let instant = ISO8601DateFormatter().date(from: raw) {
                bedtimes.append(instant)
            }
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
            add(.sleepDeepMinutes, record.deep_sleep_duration.map { $0 / 60 })
            add(.sleepRemMinutes, record.rem_sleep_duration.map { $0 / 60 })
            // Oura publishes its own efficiency, so that is what is used —
            // deriving it from asleep/in-bed would produce a second, slightly
            // different number for the same named quantity.
            if let efficiency = record.efficiency {
                add(.sleepEfficiency, efficiency)
            } else if let asleep = record.total_sleep_duration,
                      let inBed = record.time_in_bed, inBed > 0 {
                add(.sleepEfficiency, asleep / inBed * 100)
            }
        }
        samples += SleepOnset.samples(fromSegmentStarts: bedtimes, source: .oura)
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

    // NOTE: the "scrape everything" raw capture that used to live here has been
    // replaced by `IngestionPipeline`. It only ever kept numbers, only descended
    // one level, and hard-coded Oura's field names — so booleans, strings
    // (resilience `level`, the sleep hypnogram) and every array were discarded,
    // and each new Oura field needed a code change. The pipeline walks any JSON
    // from any provider and keeps the type it arrived as. The typed parsers
    // above stay: they carry the unit and semantic knowledge that turns specific
    // Oura fields into canonical vitals, which is not something a generic walk
    // can infer.
}
