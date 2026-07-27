import Foundation

/// Extracts grounding values (currently blood lipids) from the free text of a
/// blood-test report — e.g. OCR'd from a photo. Pure and dependency-free so the
/// extraction logic is unit-tested against realistic report text without any
/// camera, Vision, or model dependency.
///
/// It is deliberately conservative: it looks for a recognised analyte label
/// followed by a plausible number and unit, converts to the app's canonical
/// unit (mmol/L for lipids), and returns candidates for the user to confirm — it
/// never silently writes values it isn't reasonably sure about.
public enum LabReportParser {

    public struct Extracted: Sendable, Equatable {
        public let kind: GroundingKind
        public let value: Double            // canonical unit (mmol/L for lipids)
        public let displayUnit: String
        public let matchedText: String
    }

    /// mmol/L ↔ mg/dL factor for cholesterol.
    private static let cholFactor = 38.67

    /// Label synonyms per target analyte. Order matters: HDL/LDL are matched
    /// before the bare "cholesterol" so "HDL cholesterol" isn't read as total.
    private static let targets: [(kind: GroundingKind, labels: [String])] = [
        (.hdlCholesterol, ["hdl cholesterol", "hdl-c", "hdl chol", "hdl"]),
        (.totalCholesterol, ["total cholesterol", "cholesterol total", "chol total", "cholesterol", "total chol"])
    ]

    public static func extract(from text: String) -> [Extracted] {
        let lower = text.lowercased()
        var results: [Extracted] = []
        var consumedRanges: [Range<String.Index>] = []

        for target in targets {
            for label in target.labels {
                guard let labelRange = lower.range(of: label) else { continue }
                // Skip if this region was already consumed by a more specific label.
                if consumedRanges.contains(where: { $0.overlaps(labelRange) }) { continue }

                // Look at the ~48 characters following the label for "number unit".
                let windowEnd = lower.index(labelRange.upperBound,
                                            offsetBy: 48, limitedBy: lower.endIndex) ?? lower.endIndex
                let window = String(lower[labelRange.upperBound..<windowEnd])
                guard let (value, unit) = firstNumberWithUnit(in: window) else { continue }

                let mmol = normaliseCholesterol(value, unit: unit)
                // Sanity range for cholesterol in mmol/L.
                guard (0.3...30).contains(mmol) else { continue }

                results.append(.init(kind: target.kind, value: mmol, displayUnit: "mmol/L",
                                     matchedText: label))
                consumedRanges.append(labelRange)
                break // first matching synonym wins for this analyte
            }
        }
        return results
    }

    /// Convert a cholesterol figure to mmol/L based on the detected (or assumed) unit.
    static func normaliseCholesterol(_ value: Double, unit: String?) -> Double {
        if let unit, unit.contains("mg") { return value / cholFactor }
        // Heuristic: unlabelled values above ~25 are almost certainly mg/dL.
        if unit == nil, value > 25 { return value / cholFactor }
        return value
    }

    /// Find the first number in `s`, plus a following unit token if present.
    static func firstNumberWithUnit(in s: String) -> (Double, String?)? {
        guard let match = s.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) else { return nil }
        guard let value = Double(s[match]) else { return nil }
        let rest = String(s[match.upperBound...])
        var unit: String? = nil
        if let u = rest.range(of: #"mmol/?l|mg/?dl"#, options: .regularExpression) {
            unit = String(rest[u])
        }
        return (value, unit)
    }
}
