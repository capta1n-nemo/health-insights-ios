import SwiftUI
import InsightKit

/// **One lab value, with how much the app should be believed about it.**
///
/// One view rather than three, because the confidence badge is the part that
/// gets dropped. It has to appear on the import screen (where the reader decides
/// whether to keep a value), on the Data tab (where they come back to it a month
/// later) and nowhere differently — a value that looks certain on one screen and
/// flagged on another is worse than one that looks flagged everywhere.
///
/// ⚠️ **The badge is about the *reading*, never the reader's health.** "Check
/// this one" means the app is unsure it transcribed the number correctly. It
/// never means the value is abnormal, and the wording is chosen so it cannot be
/// read that way — see `LabConfidence.explanation`.
struct LabResultRow: View {
    let result: LabResult
    /// Whether to show the checks under the value. On the import screen the
    /// reader is deciding, so they see everything; in a list they see the badge
    /// and tap through.
    var showsChecks: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.analyte.displayName)
                    if !result.analyte.isKnown {
                        // Named, not silently different. An analyte the app does
                        // not know cannot be range-checked or unit-converted,
                        // and the reader is entitled to know which of their
                        // values are being carried rather than understood.
                        Text("Not an analyte the app knows — stored exactly as printed")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text(result.formattedWithUnit)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                LabConfidenceBadge(confidence: result.confidence)
                Text(result.source.displayName)
                    .font(.caption2).foregroundStyle(.tertiary)
                if let range = result.referenceRange {
                    Text("Lab range \(range.printed)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            if showsChecks, let evidence = result.evidence {
                ForEach(Array(evidence.noteworthyChecks.enumerated()), id: \.offset) { _, check in
                    Label(check.explanation, systemImage: check.isFailure
                          ? "exclamationmark.triangle.fill" : "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(check.isFailure ? Theme.warn : .secondary)
                }
                if !evidence.rawLine.isEmpty {
                    Text("Read from: \(evidence.rawLine)")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// The confidence badge. Its own view so the colour and the words are decided in
/// one place — a badge that says "Read clearly" in amber somewhere is a mixed
/// signal about the one thing this feature is careful about.
struct LabConfidenceBadge: View {
    let confidence: LabConfidence

    var body: some View {
        Label(confidence.title, systemImage: symbol)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var symbol: String {
        switch confidence {
        case .typed: return "keyboard"
        case .clear: return "checkmark.circle.fill"
        case .unverified: return "questionmark.circle"
        case .doubtful: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch confidence {
        // Typed is not "good", it is *certain* — a person read the paper. Using
        // the good/bad palette here would put a health colour on a provenance
        // fact, which is the confusion this whole badge exists to avoid.
        case .typed: return .secondary
        case .clear: return Theme.good
        case .unverified: return .secondary
        case .doubtful: return Theme.warn
        }
    }
}
