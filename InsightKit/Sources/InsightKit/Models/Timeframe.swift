import Foundation

/// A selectable viewing window for charts and lists, mirroring the day / week /
/// month / 6-month / year / all pattern used by Apple Health, Oura and Withings.
public enum Timeframe: String, CaseIterable, Sendable, Identifiable {
    case day, week, month, sixMonths, year, all

    public var id: String { rawValue }

    /// Compact label for a segmented control.
    public var shortLabel: String {
        switch self {
        case .day: return "D"
        case .week: return "W"
        case .month: return "M"
        case .sixMonths: return "6M"
        case .year: return "Y"
        case .all: return "All"
        }
    }

    /// Full label for headings / accessibility.
    public var longLabel: String {
        switch self {
        case .day: return "Today"
        case .week: return "Past week"
        case .month: return "Past month"
        case .sixMonths: return "Past 6 months"
        case .year: return "Past year"
        case .all: return "All time"
        }
    }

    /// Lookback length in seconds; `nil` means all-time (no lower bound).
    public var window: TimeInterval? {
        switch self {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .sixMonths: return 182 * 24 * 3600
        case .year: return 365 * 24 * 3600
        case .all: return nil
        }
    }

    /// The earliest date included, or `nil` for all-time.
    public func startDate(from now: Date = Date()) -> Date? {
        window.map { now.addingTimeInterval(-$0) }
    }
}
