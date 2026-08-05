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
    /// recorded the old one. HealthKit has the same property, so both sources
    /// agree.
    ///
    /// **The calendar is injectable, and the entry point above keeps the bare
    /// signature.** The old comment here said `Calendar` could not be a
    /// parameter because the provider references the typed parsers as
    /// `(Data) throws -> [HealthMetricSample]` and a defaulted argument cannot
    /// be dropped from a function reference. The constraint is real; the
    /// conclusion was not. A two-line forwarding overload satisfies both, and
    /// without it *nothing could test this parser's timezone behaviour at all*.
    ///
    /// What that cost, found on 2026-08-04 — the first session to run this
    /// suite outside CI's UTC container: three tests here encode UTC-only
    /// answers and fail on the user's UTC+8 Mac, in **both** directions.
    /// `SleepOnset.hoursFromMidnight` keeps only bedtimes within ±6 h of *local*
    /// midnight, so `23:10+10:00` (13:10 UTC) is discarded in UTC and kept at
    /// UTC+8, while `23:00+00:00` is kept in UTC and discarded at UTC+8 — where
    /// it reads as 07:00. `isMorningReSleep`'s "before noon" test moves the same
    /// way, which disables the split-night fix for a reader far enough east.
    ///
    /// **This is a test-reach problem, not a scoring one**: the shipped
    /// behaviour is deliberate and unchanged. But a suite that can only be
    /// correct in one timezone is a suite that says nothing about the phone,
    /// and every night-bucketing bug this file records was found on a device.
    public static func parseSleep(_ data: Data) throws -> [HealthMetricSample] {
        try parseSleep(data, calendar: .current)
    }

    static func parseSleep(_ data: Data, calendar: Calendar) throws -> [HealthMetricSample] {
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
            //
            // **One nap-typed shape does join the night: a morning re-sleep.**
            // Oura closes "the night" at the first real wake and types a
            // return to bed at 8 am `late_nap` — so the user's 07-29 read
            // 4.3 h from Oura and 8.5 h from Apple Health, whose path sums
            // every segment. The user's ruling (2026-08-02): that is one
            // night's sleep. `isMorningReSleep` is deliberately narrow — the
            // start time must be *known* and before noon — so every case the
            // nap filter exists for (afternoon naps, evening dozes, untimed
            // rest records) stays excluded, and a morning re-sleep still never
            // provides the night's bedtime or latency.
            guard Self.isNight(record.type)
                    || Self.isMorningReSleep(record, calendar: calendar) else { continue }
            // `PayloadDate.parse`, never a bare `ISO8601DateFormatter()` — see
            // the note on `bedtimeInstant` below. This line silently produced
            // no bedtimes at all for the whole of the reader's history.
            if Self.isNight(record.type),
               let instant = Self.bedtimeInstant(record) {
                bedtimes.append(instant)
            }
            guard let date = date(from: record, calendar: calendar) else { continue }
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
        samples += SleepOnset.samples(fromSegmentStarts: bedtimes, source: .oura,
                                      calendar: calendar)
        return samples
    }

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

    /// A nap-typed record that is really the second half of the night: it
    /// *begins* in the morning (before noon, local time). Oura closes a night
    /// at the first real wake and types the return to bed `late_nap`; the user
    /// ruled that a morning re-sleep is part of one night's sleep, which is
    /// also the convention the Apple Health path (`SleepNights`) already sums
    /// by. The start time must be known — an untimed nap record cannot prove
    /// it was a morning, and defaulting it in would re-open the afternoon-nap
    /// contamination this filter exists to stop.
    private static func isMorningReSleep(_ record: SleepRecord,
                                         calendar: Calendar = .current) -> Bool {
        guard !isNight(record.type),
              let instant = bedtimeInstant(record) else { return false }
        return calendar.component(.hour, from: instant) < 12
    }

    /// A record's `bedtime_start` as an instant — **the one door**, because all
    /// three callers of it were wrong in the same way.
    ///
    /// Each read the string with a bare `ISO8601DateFormatter()`, which accepts
    /// `2026-07-19T23:30:00+08:00` and rejects the fractional-seconds form. A
    /// rejection is `nil`, and `nil` is indistinguishable here from "Oura sent
    /// no bedtime": the bedtime collector skipped the record, `isMorningReSleep`
    /// returned false, and nothing anywhere logged a parse failure.
    ///
    /// What that cost, measured against the reader's own export rather than
    /// argued: **119 Oura `sleepLatencyMinutes` samples and zero Oura
    /// `sleepOnset` samples.** The typed parser demonstrably ran on 119 nights
    /// and every bedtime it emitted evaporated — so circadian consistency had
    /// no Oura input at all, and the split-night fix (`isMorningReSleep`, added
    /// 2026-08-02 for exactly the "7.5 h reported as 4 h" defect) was disabled
    /// from the day it shipped, silently, while its tests passed on
    /// hand-written fixtures with no fractional seconds.
    ///
    /// `PayloadDate.parse` tries the fractional form, then the plain one, so
    /// **this is correct without establishing which one Oura actually sends** —
    /// a question the diagnosis had parked as needing a captured live payload.
    /// Tolerating both retires it instead of answering it.
    private static func bedtimeInstant(_ record: SleepRecord) -> Date? {
        record.bedtime_start.flatMap(PayloadDate.parse)
    }

    /// The one rule for "does this segment count toward the night", callable
    /// from code that holds only a type and a local start hour (the raw
    /// catalogue) rather than a full record. The parser and the
    /// model-internals export must agree on this or the export's
    /// "counted as night?" column lies about the parser.
    public static func countsTowardNight(type: String?, localStartHour: Int?) -> Bool {
        isNight(type) || (localStartHour.map { $0 < 12 } ?? false)
    }

    private static func date(from record: SleepRecord, calendar: Calendar) -> Date? {
        if let day = record.day, let d = DayStamp.local(day, calendar: calendar) { return d }
        return bedtimeInstant(record)
    }

    /// Oura's `day` is a bare `yyyy-MM-dd`, so it names a calendar day and lands
    /// at **local** midnight — see `DayStamp` for why that is a decision rather
    /// than an obvious reading, and for why it must not be reported as a
    /// sensitivity fix.
    ///
    /// `day` deliberately stays *ahead* of `bedtime_start` here, unlike
    /// `EnvelopeSpec.oura.startDateKeys` on the raw side, and the asymmetry is
    /// the point: on the raw side the date is the *instant a row happened*, so
    /// the real bedtime is right. Here it is the **grouping key for a night**,
    /// and every period of one broken night carries the same `day` while each
    /// carries a different `bedtime_start`. Dating by the bedtime here would
    /// give each period its own bucket and undo the split-night summing
    /// directly above.
    static func day(_ s: String?, calendar: Calendar) -> Date? {
        s.flatMap { DayStamp.local($0, calendar: calendar) }
    }

    // MARK: - Additional daily endpoints (scrape everything Oura offers)

    /// `usercollection/daily_readiness` → skin-temperature deviation (°C).
    public static func parseDailyReadiness(_ data: Data) throws -> [HealthMetricSample] {
        try parseDailyReadiness(data, calendar: .current)
    }

    static func parseDailyReadiness(_ data: Data, calendar: Calendar) throws -> [HealthMetricSample] {
        struct List: Decodable { let data: [Rec] }
        struct Rec: Decodable { let day: String?; let temperature_deviation: Double? }
        let list = try JSONDecoder().decode(List.self, from: data)
        return list.data.compactMap { r -> HealthMetricSample? in
            guard let d = day(r.day, calendar: calendar),
                  let dev = r.temperature_deviation else { return nil }
            return HealthMetricSample(type: .skinTemperatureDeviation, value: dev,
                                      start: d, end: d, source: .oura)
        }
    }

    /// `usercollection/daily_spo2` → blood oxygen (%).
    public static func parseDailySpo2(_ data: Data) throws -> [HealthMetricSample] {
        try parseDailySpo2(data, calendar: .current)
    }

    static func parseDailySpo2(_ data: Data, calendar: Calendar) throws -> [HealthMetricSample] {
        struct List: Decodable { let data: [Rec] }
        struct Rec: Decodable { let day: String?; let spo2_percentage: Pct? }
        struct Pct: Decodable { let average: Double? }
        let list = try JSONDecoder().decode(List.self, from: data)
        return list.data.compactMap { r -> HealthMetricSample? in
            guard let d = day(r.day, calendar: calendar),
                  let avg = r.spo2_percentage?.average else { return nil }
            return HealthMetricSample(type: .oxygenSaturation, value: avg,
                                      start: d, end: d, source: .oura)
        }
    }

    /// `usercollection/daily_activity` → steps + active energy (kcal).
    public static func parseDailyActivity(_ data: Data) throws -> [HealthMetricSample] {
        try parseDailyActivity(data, calendar: .current)
    }

    static func parseDailyActivity(_ data: Data, calendar: Calendar) throws -> [HealthMetricSample] {
        struct List: Decodable { let data: [Rec] }
        struct Rec: Decodable { let day: String?; let steps: Double?; let active_calories: Double? }
        let list = try JSONDecoder().decode(List.self, from: data)
        var out: [HealthMetricSample] = []
        for r in list.data {
            guard let d = day(r.day, calendar: calendar) else { continue }
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
