import Foundation

/// A single imported value of whatever type the provider actually sent.
///
/// The raw layer used to be `Double`-only, which quietly discarded every
/// non-numeric field a provider returned — Oura's resilience `level`
/// ("solid" / "strong"), its `sleep_phase_5_min` hypnogram string, Withings'
/// per-measurement `comment`, HealthKit's categorical states. Those are real
/// data, and several of them are the *headline* value of their endpoint.
///
/// Encoded as a bare JSON scalar rather than a tagged object, which is both
/// compact and makes the migration free: a cached blob written by an older
/// build stored `"value": 42.5`, and that decodes straight into `.number(42.5)`.
public enum RawValue: Codable, Sendable, Hashable {
    case number(Double)
    case text(String)
    case flag(Bool)

    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case number, text, flag
    }

    public var kind: Kind {
        switch self {
        case .number: return .number
        case .text: return .text
        case .flag: return .flag
        }
    }

    /// A plottable number, where one exists. Booleans count — a 0/1 step line is
    /// a perfectly good rendering of a flag over time. Free text does not; it is
    /// shown as a value, never charted.
    public var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .flag(let b): return b ? 1 : 0
        case .text: return nil
        }
    }

    /// What to show in a list row.
    public var displayString: String {
        switch self {
        case .number(let d):
            if d == d.rounded() && abs(d) < 1e15 { return String(format: "%.0f", d) }
            return String(format: abs(d) >= 100 ? "%.1f" : "%.2f", d)
        case .text(let s): return s
        case .flag(let b): return b ? "Yes" : "No"
        }
    }

    public var isPlottable: Bool { doubleValue != nil }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool first: JSONDecoder won't coerce a number into Bool, so `true`
        // only matches here and `1` falls through to `.number`.
        if let b = try? container.decode(Bool.self) { self = .flag(b); return }
        if let d = try? container.decode(Double.self) { self = .number(d); return }
        if let s = try? container.decode(String.self) { self = .text(s); return }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "RawValue expects a JSON number, string or boolean.")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let d): try container.encode(d)
        case .text(let s): try container.encode(s)
        case .flag(let b): try container.encode(b)
        }
    }
}

public extension RawValue {
    /// Build from a value straight out of `JSONSerialization`.
    ///
    /// The `CFBoolean` check matters: `JSONSerialization` hands back `true` as an
    /// `NSNumber`, so without it every boolean in a payload would be silently
    /// recorded as the number 1 or 0 and lose its type.
    init?(json: Any) {
        switch json {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .flag(n.boolValue) }
            else { self = .number(n.doubleValue) }
        case let s as String:
            self = .text(s)
        default:
            return nil
        }
    }
}
