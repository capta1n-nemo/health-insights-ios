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

    /// Never show a chart window narrower than this, so a one-reading history
    /// can't produce a zero-width domain.
    public static let minimumChartWindow: TimeInterval = 24 * 3600

    /// Seconds of history one chart-width shows, given the span the data
    /// actually covers.
    ///
    /// `.all` has no fixed length, so it derives from that span. Call sites used
    /// to substitute a fixed ~12-year constant, which exceeded the chart's
    /// x-scale domain and squashed a real history into a strip at the leading
    /// edge. The 2% is trailing padding so the newest reading isn't flush
    /// against the border.
    public func chartWindow(spanning span: TimeInterval?) -> TimeInterval {
        if let window { return window }
        guard let span, span > 0 else { return Self.minimumChartWindow }
        return Swift.max(span * 1.02, Self.minimumChartWindow)
    }
}

/// How dense the x-axis labels should be for a given span of time.
public enum AxisTickGranularity: Sendable, Equatable {
    case hour, day, month, year
}

public extension Timeframe {
    /// Picks axis labels from how much time is on screen, so an all-time chart
    /// reads "2022 · 2024 · 2026" rather than repeating a day-level format.
    static func tickGranularity(forSpan span: TimeInterval) -> AxisTickGranularity {
        let day: TimeInterval = 24 * 3600
        if span > 730 * day { return .year }
        if span > 60 * day { return .month }
        if span > 2 * day { return .day }
        return .hour
    }
}
