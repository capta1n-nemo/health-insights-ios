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
            // Absolute *skin* °C, around 33–35. Routed to `.bodyTemperature` it
            // sat below the 35.5 core floor every single night, which pinned a
            // Whoop user's Vitals Check score at zero.
            add(.skinTemperature, s.skin_temp_celsius)
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

    // MARK: Sleep

    private struct SleepList: Decodable { let records: [SleepRecord] }
    private struct SleepRecord: Decodable {
        let start: String?
        let score: Score?
        struct Score: Decodable {
            let respiratory_rate: Double?
            let stage_summary: Stages?
            struct Stages: Decodable {
                let total_in_bed_time_milli: Double?
                let total_awake_time_milli: Double?
                let total_slow_wave_sleep_time_milli: Double?
                let total_rem_sleep_time_milli: Double?
            }
        }
    }

    public static func parseSleep(_ data: Data) throws -> [HealthMetricSample] {
        let list = try JSONDecoder().decode(SleepList.self, from: data)
        var samples: [HealthMetricSample] = []
        // `start` is the moment sleep began, which is what `.sleepOnset` wants.
        // A record with no score still carries one, so this is gathered before
        // the guard below rather than inside it.
        samples += SleepOnset.samples(
            fromSegmentStarts: list.records.compactMap { date($0.start) }, source: .whoop)
        for record in list.records {
            guard let when = date(record.start), let s = record.score else { continue }
            if let rr = s.respiratory_rate {
                samples.append(HealthMetricSample(type: .respiratoryRate, value: rr, start: when, source: .whoop))
            }
            if let inBed = s.stage_summary?.total_in_bed_time_milli {
                let awake = s.stage_summary?.total_awake_time_milli ?? 0
                let asleep = max(0, inBed - awake)
                samples.append(HealthMetricSample(type: .sleepDurationHours, value: asleep / 3_600_000, start: when, source: .whoop))
                if inBed > 0 {
                    samples.append(HealthMetricSample(type: .sleepEfficiency,
                                                      value: asleep / inBed * 100,
                                                      start: when, source: .whoop))
                }
            }
            // Whoop calls deep sleep "slow wave", which is the same stage under
            // the polysomnography name.
            if let swsMilli = s.stage_summary?.total_slow_wave_sleep_time_milli {
                samples.append(HealthMetricSample(type: .sleepDeepMinutes,
                                                  value: swsMilli / 60_000,
                                                  start: when, source: .whoop))
            }
            if let remMilli = s.stage_summary?.total_rem_sleep_time_milli {
                samples.append(HealthMetricSample(type: .sleepRemMinutes,
                                                  value: remMilli / 60_000,
                                                  start: when, source: .whoop))
            }
        }
        return samples
    }
}
