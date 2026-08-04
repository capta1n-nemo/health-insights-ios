import Foundation

/// One night, drawn as it actually happened: stage bands per source, with the
/// gaps left visible.
///
/// Built for two questions no aggregate answers. *What was last night made of*
/// — how the hours divided into deep, light and REM, and where the wakes were.
/// And *why do my sources disagree* — the user's 07-29 read 4.3 h from Oura and
/// 8.5 h from Apple Health, and the only way to see that the difference is a
/// morning re-sleep (and not a parser bug) is to draw both sources' segments on
/// one axis and let the gap speak. Requested by the user on 2026-08-02 for
/// exactly that night.
///
/// In InsightKit because everything here — the phase-string decoding, the
/// night keying, which segments count — is arithmetic that can be quietly
/// wrong, and the app target has no test target.
public struct NightSleepDetail: Sendable, Equatable {

    /// Oura's 5-minute phase encoding: `1` deep, `2` light, `3` REM, `4` awake.
    public enum Stage: Character, Sendable, Equatable, CaseIterable {
        case deep = "1", light = "2", rem = "3", awake = "4"

        public var label: String {
            switch self {
            case .deep: return "Deep"
            case .light: return "Light"
            case .rem: return "REM"
            case .awake: return "Awake"
            }
        }
    }

    /// A stretch of the night in one state. `stage == nil` means "asleep, no
    /// stage detail" — a source that reports only its window is drawn as one
    /// block rather than pretending to know more.
    public struct Band: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        public let stage: Stage?

        public var id: String {
            "\(start.timeIntervalSince1970)-\(stage.map { String($0.rawValue) } ?? "window")"
        }
        public var hours: Double { end.timeIntervalSince(start) / 3600 }

        public init(start: Date, end: Date, stage: Stage?) {
            self.start = start
            self.end = end
            self.stage = stage
        }
    }

    /// One source's account of the night.
    public struct Lane: Sendable, Equatable, Identifiable {
        public let source: String
        public let bands: [Band]
        public var id: String { source }

        /// Hours actually asleep — awake bands are part of the picture, not of
        /// the sleep.
        public var asleepHours: Double {
            bands.filter { $0.stage != .awake }.reduce(0) { $0 + $1.hours }
        }
        public var hasStageDetail: Bool { bands.contains { $0.stage != nil } }
    }

    /// The wake day — the same keying the per-source nights table uses, so
    /// "night of 07-29" means the same thing on every surface.
    public let night: Date
    /// Stage-bearing lanes first, then window-only ones, alphabetical within.
    public let lanes: [Lane]

    /// The span the chart should draw, across every lane.
    public var window: ClosedRange<Date>? {
        let starts = lanes.flatMap { $0.bands.map(\.start) }
        let ends = lanes.flatMap { $0.bands.map(\.end) }
        guard let first = starts.min(), let last = ends.max(), first <= last else { return nil }
        return first...last
    }

    /// Five minutes per character of an Oura phase string.
    public static let phaseStep: TimeInterval = 300

    // MARK: - Building

    /// The most recent night with anything to draw, or nil when no source has
    /// ever recorded one.
    ///
    /// Oura's lane comes from the raw catalogue — `oura.sleep.sleep_phase_5_min`
    /// joined to `oura.sleep.type` by the record's start instant, the only join
    /// the raw pile keeps. Which segments count is
    /// `OuraResponseParser.countsTowardNight`, the same rule the canonical
    /// parser applies, so this picture can never disagree with the numbers.
    /// Every other source's lane comes from its canonical onset + duration —
    /// a window, honestly stageless.
    ///
    /// Nights are keyed by **wake day**: a segment belongs to the day twelve
    /// hours after it starts, which files an 11 pm bedtime and a 3 am one under
    /// the morning they end, matching the canonical night-of convention.
    public static func latest(raw: [RawMetricSample],
                              samples: [HealthMetricSample],
                              calendar: Calendar = .current) -> NightSleepDetail? {
        let ouraNights = ouraSegments(raw: raw, calendar: calendar)
        let appleNights = appleSegments(raw: raw, calendar: calendar)
        let windowNights = windowLanes(samples: samples, calendar: calendar)

        guard let night = Set(ouraNights.keys)
            .union(appleNights.keys)
            .union(windowNights.keys).max() else { return nil }

        var lanes: [Lane] = []
        if let bands = ouraNights[night], !bands.isEmpty {
            lanes.append(Lane(source: "Oura", bands: bands.sorted { $0.start < $1.start }))
        }
        // Apple's stage lanes, one per writing device, before the window
        // fallback — and the fallback is then suppressed for any source that
        // has real stages, or the same night would draw twice: once in colour
        // and once as a flat grey bar over it.
        for (source, bands) in (appleNights[night] ?? [:]).sorted(by: { $0.key < $1.key })
        where !bands.isEmpty {
            lanes.append(Lane(source: source, bands: bands.sorted { $0.start < $1.start }))
        }
        let staged = Set((appleNights[night] ?? [:]).keys)
        for (source, band) in (windowNights[night] ?? [:]).sorted(by: { $0.key < $1.key })
        where !staged.contains(source) {
            lanes.append(Lane(source: source, bands: [band]))
        }
        guard !lanes.isEmpty else { return nil }
        return NightSleepDetail(night: night, lanes: lanes)
    }

    /// The wake day a segment belongs to.
    static func wakeDay(of start: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: start.addingTimeInterval(12 * 3600))
    }

    /// Runs of one stage, decoded from a phase string. Consecutive equal
    /// characters merge into one band; an unknown character is skipped rather
    /// than guessed at, leaving a visible gap — the same fail-safe direction as
    /// the rest of the pipeline.
    static func bands(from phases: String, start: Date) -> [Band] {
        var out: [Band] = []
        var runStage: Stage?
        var runStart = start
        var cursor = start
        for character in phases {
            let stage = Stage(rawValue: character)
            if stage != runStage {
                if let running = runStage {
                    out.append(Band(start: runStart, end: cursor, stage: running))
                }
                runStage = stage
                runStart = cursor
            }
            cursor = cursor.addingTimeInterval(phaseStep)
        }
        if let running = runStage {
            out.append(Band(start: runStart, end: cursor, stage: running))
        }
        return out
    }

    private static func ouraSegments(raw: [RawMetricSample],
                                     calendar: Calendar) -> [Date: [Band]] {
        let typeByStart = Dictionary(
            raw.filter { $0.identifier == "oura.sleep.type" }
                .compactMap { sample -> (Date, String)? in
                    guard case .text(let type) = sample.value else { return nil }
                    return (sample.start, type)
                },
            uniquingKeysWith: { first, _ in first })

        var nights: [Date: [Band]] = [:]
        for record in raw where record.identifier == "oura.sleep.sleep_phase_5_min" {
            guard case .text(let phases) = record.value, !phases.isEmpty else { continue }
            let hour = calendar.component(.hour, from: record.start)
            guard OuraResponseParser.countsTowardNight(type: typeByStart[record.start],
                                                       localStartHour: hour) else { continue }
            nights[wakeDay(of: record.start, calendar: calendar), default: []]
                .append(contentsOf: bands(from: phases, start: record.start))
        }
        return nights
    }

    /// The identifier Apple's per-stage segments are catalogued under. Kept here
    /// beside its only reader; `HealthKitService` writes it.
    static let appleSegmentIdentifier = "apple_health.sleep_segment"

    /// night day → writing device → its stage bands.
    ///
    /// **Apple has recorded core/deep/REM since iOS 16 and the app was drawing a
    /// flat grey bar for it.** The segments were fetched and mapped, handed to
    /// `SleepNights` for the nightly totals, and then dropped — so this type had
    /// nothing to build a lane from and every Apple night fell through to
    /// `windowLanes`, which draws one `stage: nil` band. The reader's own export
    /// carries stage minutes on 132 nights, so the data was always there.
    ///
    /// Keyed by the **writing device** rather than by "Apple Health", because
    /// several devices write sleep into Health and drawing them as one lane
    /// would splice a watch's night onto a ring's.
    /// Apple's stage vocabulary mapped onto the chart's.
    ///
    /// **`core` becomes `light`**, which is the physiologically correct name for
    /// it and the one Oura's lane already uses — so the two lanes are directly
    /// comparable rather than the same sleep wearing two labels. Apple's own app
    /// says "Core"; matching Oura matters more here, because the whole point of
    /// showing both lanes is comparing them.
    ///
    /// `inBed` returns nil: it is time in bed, not a stage, and drawing it would
    /// lay a band under the entire night that every stage colour then sits on
    /// top of. `unspecified` is real sleep of unknown stage — an older watch, or
    /// a third-party app writing only "asleep" — and is drawn as light rather
    /// than dropped, since dropping it would leave a hole in a night that was
    /// genuinely slept.
    private static func stage(for kind: SleepSegment.Kind) -> Stage? {
        switch kind {
        case .deep: return .deep
        case .rem: return .rem
        case .core, .unspecified: return .light
        case .awake: return .awake
        case .inBed: return nil
        }
    }

    private static func appleSegments(raw: [RawMetricSample],
                                      calendar: Calendar) -> [Date: [String: [Band]]] {
        var nights: [Date: [String: [Band]]] = [:]
        for record in raw where record.identifier == appleSegmentIdentifier {
            guard case .text(let name) = record.value,
                  let kind = SleepSegment.Kind(rawValue: name) else { continue }
            guard let stage = Self.stage(for: kind) else { continue }
            guard record.end > record.start else { continue }
            nights[wakeDay(of: record.start, calendar: calendar), default: [:]][
                record.source.displayName, default: []
            ].append(Band(start: record.start, end: record.end, stage: stage))
        }
        return nights
    }

    /// night day → source name → its window band.
    private static func windowLanes(samples: [HealthMetricSample],
                                    calendar: Calendar) -> [Date: [String: Band]] {
        let sleepSamples = samples.filter { $0.source.id != MetricSource.oura.id }
        struct Key: Hashable { let day: Date; let source: String }
        var onsets: [Key: Double] = [:]
        var durations: [Key: Double] = [:]
        for sample in sleepSamples {
            let key = Key(day: calendar.startOfDay(for: sample.start),
                          source: sample.source.displayName)
            if sample.type == .sleepOnset { onsets[key] = sample.value }
            if sample.type == .sleepDurationHours { durations[key] = sample.value }
        }
        var out: [Date: [String: Band]] = [:]
        for (key, onset) in onsets {
            guard let hours = durations[key], hours > 0 else { continue }
            let start = key.day.addingTimeInterval(onset * 3600)
            out[key.day, default: [:]][key.source] =
                Band(start: start, end: start.addingTimeInterval(hours * 3600), stage: nil)
        }
        return out
    }
}
