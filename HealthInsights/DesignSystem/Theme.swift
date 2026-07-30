import SwiftUI
import UIKit
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

    // MARK: - Metric colours (the overlay chart's identity scale)

    /// Eight categorical hues, light and dark steps of the same set.
    ///
    /// Validated rather than chosen by eye: worst adjacent colour-blind ΔE 9.1
    /// light / 8.4 dark (target ≥ 8), worst normal-vision ΔE 19.6 / 19.3 (floor
    /// ≥ 15). Four light steps fall under 3:1 against the grouped background,
    /// which obliges the relief rule — hence the legend under every overlay
    /// listing each series by name and value, so identity is never colour alone.
    ///
    /// Existing charts key colour on *source* (`sourcePalette`); this keys on
    /// *metric*. They coexist because they answer different questions — "which
    /// device said this" versus "which signal is this".
    private static let metricPalette: [(light: UInt32, dark: UInt32)] = [
        (0x2a78d6, 0x3987e5),   // 1 blue
        (0xeb6834, 0xd95926),   // 2 orange
        (0x1baf7a, 0x199e70),   // 3 aqua
        (0xeda100, 0xc98500),   // 4 yellow
        (0xe87ba4, 0xd55181),   // 5 magenta
        (0x008300, 0x008300),   // 6 green
        (0x4a3aa7, 0x9085e9),   // 7 violet
        (0xe34948, 0xe66767)    // 8 red
    ]

    /// Which hue each metric wears. The slot assignment itself lives in
    /// InsightKit (`MetricType.colourSlot`) so its collision-safety can be
    /// tested — see the note there.
    /// Line dash, the second half of a series' identity.
    ///
    /// Needed because hue alone cannot carry seventeen series: eight validated
    /// hues is the ceiling for a categorical palette, and when any pair may be
    /// compared — as on an overlay where the eye picks its own two lines — no
    /// seven-hue subset of this palette clears the colour-blind separation
    /// floor. That was measured, not assumed. `MetricType.chartStyleIndex` gives
    /// every metric a unique (hue, dash) pair, so no chart can show two series
    /// that look alike.
    static func metricStroke(_ metric: MetricType) -> StrokeStyle {
        switch metric.dashIndex {
        case 0: return StrokeStyle(lineWidth: 2)
        case 1: return StrokeStyle(lineWidth: 2, dash: [5, 3])
        case 2: return StrokeStyle(lineWidth: 2, dash: [1.5, 3])
        default: return StrokeStyle(lineWidth: 2, dash: [6, 3, 1.5, 3])
        }
    }

    static func metricColor(_ metric: MetricType) -> Color {
        let slot = metricPalette[metric.colourSlot % metricPalette.count]
        return Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? slot.dark : slot.light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255,
                  green: CGFloat((rgb >> 8) & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255,
                  alpha: 1)
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
