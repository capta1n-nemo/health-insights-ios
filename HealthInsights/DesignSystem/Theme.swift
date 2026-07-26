import SwiftUI
import InsightKit

/// Central design tokens. Inspired by Apple Health / Oura: soft cards, generous
/// spacing, a warm accent, and colour used to signal state (good/attention).
enum Theme {
    static let corner: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 16

    // Accent + semantic colours (adapt to light/dark via system materials).
    static let accent = Color(red: 0.90, green: 0.29, blue: 0.35)   // heart red
    static let good = Color(red: 0.20, green: 0.72, blue: 0.51)
    static let warn = Color(red: 0.98, green: 0.68, blue: 0.20)
    static let bad = Color(red: 0.90, green: 0.32, blue: 0.30)

    static func color(forScore score: Double) -> Color {
        switch score {
        case 70...: return good
        case 45..<70: return warn
        default: return bad
        }
    }

    static func color(for confidence: InsightConfidence) -> Color {
        switch confidence {
        case .high: return good
        case .moderate: return warn
        case .low: return .secondary
        case .experimental: return .purple
        }
    }
}

/// A rounded, subtly-shadowed container used for every dashboard tile.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

/// Small pill describing a result's confidence, so numbers are never shown as
/// more certain than they are.
struct ConfidenceBadge: View {
    let confidence: InsightConfidence
    var body: some View {
        let label: String = {
            switch confidence {
            case .high: return "Validated"
            case .moderate: return "Estimate"
            case .low: return "Needs data"
            case .experimental: return "Experimental"
            }
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.color(for: confidence).opacity(0.16), in: Capsule())
            .foregroundStyle(Theme.color(for: confidence))
    }
}
