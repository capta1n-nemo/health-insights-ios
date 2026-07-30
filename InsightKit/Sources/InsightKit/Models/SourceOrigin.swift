import Foundation

/// The route a reading took to reach the app.
///
/// The same physical device can report through more than one path — an Oura ring
/// synced directly from Oura's API *and* mirrored into Apple Health. Those are
/// deliberately merged into a single series (see `MetricSource.deviceFamily`) so
/// one reading can't be counted twice, but the user should still be able to see
/// where a number actually came from, and spot the lag between a direct pull and
/// an Apple Health sync.
public enum SourceOrigin: String, Codable, Sendable, Hashable, CaseIterable {
    /// Pulled straight from the provider's own API (Oura, Withings, Whoop, Hume).
    case directAPI
    /// Bridged through Apple Health from another app or device.
    case appleHealth
    /// Bridged through Apple Health, measured by an Apple Watch.
    case appleWatch
    /// Typed in by hand.
    case manual
    /// Read out of an imported document, e.g. a blood-test PDF.
    case document

    /// SF Symbol for the badge beside a source row.
    public var badgeSymbol: String {
        switch self {
        case .directAPI: return "bolt.horizontal.fill"
        case .appleHealth: return "heart.text.square"
        case .appleWatch: return "applewatch"
        case .manual: return "hand.raised.fill"
        case .document: return "doc.text.fill"
        }
    }

    /// Parenthetical suffix for a source label, e.g. "Oura (Direct API)".
    public var shortLabel: String {
        switch self {
        case .directAPI: return "Direct API"
        case .appleHealth: return "via Apple Health"
        case .appleWatch: return "Apple Watch"
        case .manual: return "Entered by hand"
        case .document: return "From a document"
        }
    }
}

public extension Set where Element == SourceOrigin {
    /// How to describe a series fed by these paths.
    ///
    /// A merged series can genuinely have more than one — saying "Direct API +
    /// via Apple Health" is more honest than silently picking whichever reading
    /// happened to be newest.
    var combinedLabel: String {
        let ordered = SourceOrigin.allCases.filter { contains($0) }
        guard !ordered.isEmpty else { return "" }
        return ordered.map(\.shortLabel).joined(separator: " + ")
    }
}
