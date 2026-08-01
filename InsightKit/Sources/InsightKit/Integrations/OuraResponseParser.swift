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
        /// `long_sleep` | `sleep` | `late_nap` | `rest`.
        ///
        /// Decoded at last, and it is the difference between a sleep card that
        /// works and one that lies. Oura's `sleep` endpoint returns **segments**,
        /// not nights: naps and "rest" periods arrive in the same list as the
        /// night. Nothing read this field, so every one of them became a night —
        /// and because `MetricType.bucketStatistic` averages same-day sleep
        /// samples, a 7.5 h night plus a 20-minute nap was reported to the user
        /// as a 4 h night.
        ///
        /// Found from the user's own data export: sleep duration had a median of
        /// 5.6 h and a *minimum of 0.01 h* — a 36-second `rest` record scored as
        /// a night's sleep.
        let type: String?
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
        /// Seconds from getting into bed to falling asleep. Decoded here — in
        /// the nap-aware typed parser — rather than promoted from the generic
        /// pipeline on purpose: every nap and rest segment carries a latency
        /// too, and a 20-minute doze's instant onset must not become the
        /// night's figure. Same hazard, same defence as the bedtime above.
        let latency: Double?                   // seconds
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
        var bedtimes: [Date] = []

        // Group the night's periods before emitting anything. Oura splits a
        // broken night into several records (`period` 0, 1, 2… — typically one
        // `long_sleep` plus `sleep` continuations), every one stamped with the
        // same `day` — and `MetricType.bucketStatistic` *averages* same-day
        // sleep samples. Emitted per record, a night slept in two 4.3 h halves
        // reached the user as a 4.3 h night while Apple Health's path (which
        // sums segments per night in `SleepNights`) said 8.7 h. Found in the
        // user's first model-internals export, as four nights where Oura read
        // exactly half of Apple. Same "7.5 h night reported as 4 h" symptom as
        // the nap bug and the midnight-crossing bug, from a third cause.
        var nights: [Date: [SleepRecord]] = [:]
        for record in list.data {
            // **First, before anything reads this record.** Naps and rest
            // periods are real, and they are not nights. They stay in the raw
            // catalogue under `oura.sleep.*`; what they must not do is become a
            // night's duration, lend their *awake* heart rate to
            // `.restingHeartRate`, or — the subtlest of the three — become the
            // night's bedtime. An 8 pm nap encodes as −4.0 h, which is inside
            // `SleepOnset.plausibleHours`, and `SleepOnset.samples` keeps the
            // *earliest* segment of each night. So a nap would outrank the real
            // 11 pm bedtime and quietly become it.
            guard Self.isNight(record.type) else { continue }
            if let raw = record.bedtime_start,
               let instant = ISO8601DateFormatter().date(from: raw) {
                bedtimes.append(instant)
            }
            guard let date = date(from: record) else { continue }
            nights[date, default: []].append(record)
        }

        var samples: [HealthMetricSample] = []
        for (date, periods) in nights.sorted(by: { $0.key < $1.key }) {
            func add(_ type: MetricType, _ value: Double?) {
                guard let value else { return }
                samples.append(HealthMetricSample(type: type, value: value,
                                                  start: date, end: date, source: .oura))
            }
            // Durations add across the night's periods.
            func summed(_ field: (SleepRecord) -> Double?) -> Double? {
                let values = periods.compactMap(field)
                return values.isEmpty ? nil : values.reduce(0, +)
            }
            // Rates hold across them, so they combine as a sleep-time-weighted
            // mean — a 6 h period must outweigh a 40-minute continuation.
            func weightedMean(_ field: (SleepRecord) -> Double?) -> Double? {
                let pairs = periods.compactMap { p -> (Double, Double)? in
                    guard let v = field(p) else { return nil }
                    return (v, p.total_sleep_duration ?? p.time_in_bed ?? 1)
                }
                let weight = pairs.reduce(0) { $0 + $1.1 }
                guard weight > 0 else { return pairs.first?.0 }
                return pairs.reduce(0) { $0 + $1.0 * $1.1 } / weight
            }

            add(.sleepDurationHours, summed(\.total_sleep_duration).map { $0 / 3600 })
            add(.sleepDeepMinutes, summed(\.deep_sleep_duration).map { $0 / 60 })
            add(.sleepRemMinutes, summed(\.rem_sleep_duration).map { $0 / 60 })
            // The night's sleeping low is the lowest of any period's low.
            // Prefer each period's sleeping low as a resting-HR proxy; fall
            // back to its average.
            add(.restingHeartRate,
                periods.compactMap { $0.lowest_heart_rate ?? $0.average_heart_rate }.min())
            add(.heartRateVariabilityRMSSD, weightedMean(\.average_hrv))
            add(.respiratoryRate, weightedMean(\.average_breath))
            // "Fell asleep in about N min" is a claim about going to bed, so it
            // is the *first* period's figure — a continuation's near-instant
            // re-onset after a 4 am wake must not halve the night's latency.
            let first = periods.min { a, b in
                (a.bedtime_start ?? "\u{FFFF}") < (b.bedtime_start ?? "\u{FFFF}")
            }
            add(.sleepLatencyMinutes, first?.latency.map { $0 / 60 })
            // Oura publishes its own efficiency, so a single-period night uses
            // that figure untouched — deriving it would produce a second,
            // slightly different number for the same named quantity. Across
            // periods it combines time-in-bed-weighted, which reduces to the
            // published figure when there is one period.
            let efficiencies = periods.compactMap { p -> (Double, Double)? in
                if let e = p.efficiency { return (e, p.time_in_bed ?? p.total_sleep_duration ?? 1) }
                if let asleep = p.total_sleep_duration, let inBed = p.time_in_bed, inBed > 0 {
                    return (asleep / inBed * 100, inBed)
                }
                return nil
            }
            let efficiencyWeight = efficiencies.reduce(0) { $0 + $1.1 }
            if efficiencyWeight > 0 {
                add(.sleepEfficiency,
                    efficiencies.reduce(0) { $0 + $1.0 * $1.1 } / efficiencyWeight)
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

    /// Whether a sleep segment is a night.
    ///
    /// **An unrecognised or absent `type` counts as a night**, deliberately. The
    /// alternative — a allow-list that drops anything it doesn't know — would
    /// empty the sleep card the day Oura adds a value, and it would do it
    /// silently. This repo has shipped a guard whose premise was wrong twice
    /// (the `tunnelState` deploy check, the Oura scope skip); both failed by
    /// rejecting something valid. Rejecting only what is *known* to be a nap
    /// fails the safe way instead.
    static func isNight(_ type: String?) -> Bool {
        guard let type = type?.lowercased() else { return true }
        return !["late_nap", "nap", "rest"].contains(type)
    }

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
