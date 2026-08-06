import Foundation

/// **The menstrual cycle log, and the arithmetic over it.**
///
/// Backlog #31 / §A3. Refused three times — zero rows, contraceptive claims need
/// clearance, and it rested on an unstated assumption about who the reader is —
/// and reversed by the reader on 2026-08-06: *"YES! THAT'S THE WHOLE POINT.
/// Basically do everything Flo does."*
///
/// ## Who this is for, because it changes the design
///
/// The reader's **wife**, who wears an Oura ring and pays monthly for Oura's
/// cycle insights. The competitor is that subscription, and the win condition is
/// *the same conclusions from the same sensors without it*.
///
/// ⚠️ **She installs the app on her own phone, with her own key** (decided
/// 2026-08-06, backlog Q25). The app is structurally single-user — one provider
/// account per install, one profile — and this is a feature of a single-user
/// app, not a second-profile concept. Nothing here may acquire a "whose body is
/// this" dimension without that decision being taken again.
///
/// ## What this file is, and what it deliberately is not
///
/// This is **the log and the arithmetic over the log**: what was recorded, how
/// long the cycles were, and how much they varied. That is a complete period
/// tracker on its own.
///
/// It contains **no phase model, no fertile window and no prediction**. Those
/// are the next slice and they need something this one provides: cycles to
/// predict from. A design that starts at the phase model is a design that ships
/// nothing — this repo has three recorded instances of exactly that, and one of
/// them is the reason `docs/backlog.md` exists.
///
/// ## The honesty rule that shapes every figure here
///
/// **A cycle length is reported as a range, never as a number.** Published
/// variation between cycles in the same person is several days, and a tracker
/// that says "your cycle is 28 days" from three observations is asserting a
/// precision it cannot have — which is exactly the complaint every consumer
/// cycle app attracts. `CycleSummary` has no `averageLength` property, on
/// purpose: there is nowhere for one to be read from.
public enum MenstrualFlowLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case spotting, light, medium, heavy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spotting: return "Spotting"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }

    /// How HealthKit grades it. Kept as a mapping rather than a raw-value match
    /// because Apple's ordinal is not a name, and a silent off-by-one here would
    /// turn a light day into a heavy one everywhere downstream.
    public static func fromHealthKitValue(_ value: Int) -> MenstrualFlowLevel? {
        switch value {
        case 1: return .spotting   // HKCategoryValueVaginalBleeding.light on old SDKs
        case 2: return .light
        case 3: return .medium
        case 4: return .heavy
        default: return nil        // 0 is "unspecified", 5 is "none" — neither is a flow
        }
    }

    /// Relative strength, for drawing. Not a clinical scale and never scored.
    public var intensity: Double {
        switch self {
        case .spotting: return 0.25
        case .light: return 0.5
        case .medium: return 0.75
        case .heavy: return 1.0
        }
    }
}

/// One logged day.
public struct CycleDay: Sendable, Equatable, Identifiable, Hashable, Codable {
    /// Start of the day, in the reader's own calendar. **A cycle date is a local
    /// day, always** — `DayStamp.local` exists because the app has already been
    /// bitten by treating a date-only field as an instant, and a cycle sheared
    /// by one day at a timezone boundary would move every length in this file.
    public let day: Date
    public let flow: MenstrualFlowLevel

    public init(day: Date, flow: MenstrualFlowLevel) {
        self.day = day
        self.flow = flow
    }

    public var id: Date { day }
}

/// One cycle: a period, and the gap until the next one began.
public struct Cycle: Sendable, Equatable, Identifiable {
    /// First bleeding day — day 1, by the convention every source uses.
    public let start: Date
    /// Last consecutive bleeding day of that period.
    public let periodEnd: Date
    /// Day before the next cycle started. Nil for the cycle in progress, which
    /// has no length yet and must not be given one.
    public let end: Date?

    public let days: [CycleDay]

    public var id: Date { start }

    /// Length in days, or nil while it is still running.
    ///
    /// **Nil rather than "days so far"** — a running cycle reported as a length
    /// would drag every average down, and it is the single most common way a
    /// tracker misleads.
    public func length(calendar: Calendar) -> Int? {
        guard let end else { return nil }
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    public func periodLength(calendar: Calendar) -> Int {
        (calendar.dateComponents([.day], from: start, to: periodEnd).day ?? 0) + 1
    }

    public var isInProgress: Bool { end == nil }
}

public struct CycleSummary: Sendable, Equatable {
    public let cycles: [Cycle]
    /// Completed cycle lengths, oldest first.
    public let lengths: [Int]
    /// Period lengths for completed cycles.
    public let periodLengths: [Int]
    /// The cycle currently running, if any.
    public let current: Cycle?
    /// Days since the current cycle began — day 1 is the first bleeding day.
    public let currentDay: Int?

    /// **The range, which is what gets reported.** Nil below
    /// `CycleModel.minimumCyclesForRange` completed cycles: two observations do
    /// not describe a range, they describe two observations.
    public var lengthRange: ClosedRange<Int>? {
        guard lengths.count >= CycleModel.minimumCyclesForRange,
              let low = lengths.min(), let high = lengths.max() else { return nil }
        return low...high
    }

    /// Median completed length — used *inside* the range sentence, never on its
    /// own. Deliberately median rather than mean: one long cycle after an
    /// illness should not move the typical figure.
    public var medianLength: Int? {
        guard !lengths.isEmpty else { return nil }
        let sorted = lengths.sorted()
        return sorted[sorted.count / 2]
    }

    /// How much the reader's cycles vary, in days — the figure a cycle app
    /// normally hides. Nil until there is a range to speak of.
    public var spread: Int? {
        lengthRange.map { $0.upperBound - $0.lowerBound }
    }
}

public enum CycleModel {

    /// A gap this long between bleeding days starts a new cycle rather than
    /// continuing the last period.
    ///
    /// Two days, so a single unlogged day mid-period does not split one period
    /// into two cycles and halve every length. That failure mode is worse than
    /// its opposite: a missed day is common, and a genuinely two-day gap between
    /// separate periods is not.
    public static let maximumGapWithinAPeriod = 2

    /// Completed cycles needed before a range is offered.
    ///
    /// Three, because two numbers are a pair and not a range — and because the
    /// whole claim of this file is that variation is the interesting quantity.
    public static let minimumCyclesForRange = 3

    /// Build cycles from logged days.
    ///
    /// The rule is the standard one and worth stating because every downstream
    /// number depends on it: **day 1 is the first bleeding day**, a cycle runs
    /// until the day before the next one starts, and the most recent cycle has
    /// no length until a later one begins.
    public static func summarise(days: [CycleDay], now: Date = Date(),
                                 calendar: Calendar = .current) -> CycleSummary {
        let sorted = days
            .map { CycleDay(day: calendar.startOfDay(for: $0.day), flow: $0.flow) }
            .sorted { $0.day < $1.day }
        guard !sorted.isEmpty else {
            return CycleSummary(cycles: [], lengths: [], periodLengths: [],
                                current: nil, currentDay: nil)
        }

        // Group consecutive bleeding days into periods.
        var periods: [[CycleDay]] = [[sorted[0]]]
        for entry in sorted.dropFirst() {
            let previous = periods[periods.count - 1].last!.day
            let gap = calendar.dateComponents([.day], from: previous, to: entry.day).day ?? 0
            if gap <= maximumGapWithinAPeriod {
                periods[periods.count - 1].append(entry)
            } else {
                periods.append([entry])
            }
        }

        var cycles: [Cycle] = []
        for (index, period) in periods.enumerated() {
            guard let start = period.first?.day, let periodEnd = period.last?.day
            else { continue }
            let end: Date? = index + 1 < periods.count
                ? periods[index + 1].first.flatMap {
                    calendar.date(byAdding: .day, value: -1, to: $0.day)
                }
                : nil
            cycles.append(Cycle(start: start, periodEnd: periodEnd, end: end, days: period))
        }

        let completed = cycles.filter { !$0.isInProgress }
        let current = cycles.last.flatMap { $0.isInProgress ? $0 : nil }
        let currentDay = current.map {
            (calendar.dateComponents([.day], from: $0.start,
                                     to: calendar.startOfDay(for: now)).day ?? 0) + 1
        }

        return CycleSummary(
            cycles: cycles,
            lengths: completed.compactMap { $0.length(calendar: calendar) },
            periodLengths: completed.map { $0.periodLength(calendar: calendar) },
            current: current,
            // A "day 400" from a log that stopped a year ago is noise, not a
            // cycle in progress. Reported only while it is plausibly running.
            currentDay: (currentDay ?? 0) <= 90 ? currentDay : nil)
    }

    /// The sentence the tab leads with.
    ///
    /// ⚠️ **Every branch reports a range or says it cannot.** There is no path
    /// through this function that prints a single cycle length, because there is
    /// no number of observations at which "your cycle is 28 days" becomes true.
    public static func headline(_ summary: CycleSummary) -> String {
        if let day = summary.currentDay {
            return "Day \(day)"
        }
        if summary.cycles.isEmpty {
            return "Nothing logged yet"
        }
        return "Between periods"
    }

    /// What the tab says about length, in one line.
    public static func lengthSentence(_ summary: CycleSummary) -> String {
        guard let range = summary.lengthRange, let median = summary.medianLength,
              let spread = summary.spread else {
            let have = summary.lengths.count
            let need = minimumCyclesForRange - have
            if have == 0 {
                return "Log a few periods and this will start describing your own cycle rather than an average of other people's."
            }
            return "\(have) complete cycle\(have == 1 ? "" : "s") so far. \(need) more and this can describe the range yours actually falls in — which is the number worth having, and the one most apps replace with a single average."
        }
        if spread == 0 {
            return "Your last \(summary.lengths.count) cycles were all \(median) days. That is unusually regular."
        }
        return "Your cycles have run \(range.lowerBound) to \(range.upperBound) days across \(summary.lengths.count) of them — typically about \(median). The spread of \(spread) day\(spread == 1 ? "" : "s") is the part worth knowing: an app that told you \"\(median) days\" would be hiding it."
    }
}
