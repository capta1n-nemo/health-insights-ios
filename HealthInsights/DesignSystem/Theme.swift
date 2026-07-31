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

    /// Where a score stops being one thing and starts being another.
    ///
    /// Named because two things read them now — the dot colour below and the
    /// area fill under the score line — and a fill whose green started somewhere
    /// the dots didn't would be worse than no fill at all. Same reasoning as the
    /// blood-pressure bands, which are pinned by a test for the same reason.
    ///
    /// Note these are 45 and 70, while `ScoreHistoryChart` draws its dashed
    /// reference lines at 50 and 70 — those are *readiness's* own bands, so that
    /// "80" on the chart means "Primed" on the card. Two different band systems,
    /// both deliberate; the fill follows this one because it must agree with the
    /// dots sitting on it.
    static let scoreWarnFloor: Double = 45
    static let scoreGoodFloor: Double = 70

    static func color(forScore score: Double) -> Color {
        switch score {
        case scoreGoodFloor...: return good
        case scoreWarnFloor..<scoreGoodFloor: return warn
        default: return bad
        }
    }

    /// The fill under a score line, coloured by the band each height falls in.
    ///
    /// Green where the line is high, amber through the middle, red at the
    /// bottom, fading between rather than stepping — so a card that peaks into
    /// the seventies reads as green at the peak while its troughs read as red,
    /// without the reader consulting the axis.
    ///
    /// The stops assume the gradient is resolved against the **plot area**,
    /// which is why this is only ever used on a chart with a fixed `0...100`
    /// y-domain. If it turns out to resolve against the *mark's* bounding box
    /// instead, the ordering still holds — green stays high and red stays low —
    /// but the thresholds compress toward the highest score on screen, and the
    /// fix is to compute these locations against that maximum rather than 100.
    static func scoreFill(opacity: Double = 0.30) -> LinearGradient {
        // location 0 is the top of the plot, i.e. a score of 100.
        func location(_ score: Double) -> Double { 1 - score / 100 }
        return LinearGradient(
            stops: [
                .init(color: good.opacity(opacity), location: 0),
                .init(color: good.opacity(opacity), location: location(scoreGoodFloor)),
                .init(color: warn.opacity(opacity), location: location(scoreWarnFloor)),
                .init(color: bad.opacity(opacity * 0.75), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
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
    /// This insight's hue on a chart that has resolved its own slots.
    ///
    /// Pass the assignment from `InsightPalette.slots(for:)` so two cards on one
    /// chart can never share a hue. Without it an insight falls back to its
    /// preferred slot, which is right for a single-card tint and only a
    /// *preference* on a crowded comparison chart.
    ///
    /// This used to be a fixed table here in the view, with a doc comment
    /// claiming safety because "never more than four are on screen at once" —
    /// but the user chooses which four, and four pairs shared a hue. The slot
    /// assignment now lives in InsightKit (`InsightID.colourSlot`) where its
    /// collision-safety can be tested, exactly as `MetricType.colourSlot` is.
    static func insightTint(_ id: InsightID, slots: [InsightID: Int]? = nil) -> Color {
        paletteColour(slot: slots?[id] ?? id.colourSlot)
    }

    /// Every measured series is a solid line. **Dash now means one thing only:
    /// this value was not measured** — a gap, a projection, a reference level.
    ///
    /// Dash used to be the second half of a series' identity, because eight
    /// hues cannot separate seventeen signals. That was measurably safe and
    /// practically wrong: a dashed line reads as an estimate, so the dashes were
    /// being read as missing data. Charts now keep the number of visible series
    /// inside what hue alone carries (`MetricPalette`) rather than encoding the
    /// overflow in a stroke that means something else.
    static func metricStroke(_ metric: MetricType) -> StrokeStyle {
        StrokeStyle(lineWidth: 2)
    }

    /// For a stretch the chart inferred rather than measured — a fitted line, a
    /// projection, a bridged gap.
    static let projectedStroke = StrokeStyle(lineWidth: 1.5, dash: [3, 4])

    /// For a level that was never measured at all: a threshold, a band edge, a
    /// published reference range.
    ///
    /// A sibling to `projectedStroke` rather than a fourth hand-rolled dash.
    /// Three patterns — `[4, 3]`, `[3, 3]` and `[3, 4]` — were expressing this
    /// one meaning across three files, which is how a fourth gets invented.
    static let referenceStroke = StrokeStyle(lineWidth: 1, dash: [3, 3])

    /// A hue by slot, for the few charts whose series aren't metrics —
    /// the two computed ages, for instance. Drawn from the same validated
    /// eight so they sit beside the metric charts without clashing.
    static func paletteColour(slot index: Int) -> Color {
        let step = metricPalette[abs(index) % metricPalette.count]
        return Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? step.dark : step.light)
        })
    }

    /// This metric's hue on a chart that has resolved its own slots.
    ///
    /// Pass the assignment from `MetricPalette.slots(for:)` so two series on one
    /// chart can never share a hue. Without it a metric falls back to its
    /// preferred slot, which is right for a single-series chart and only a
    /// preference on a crowded one.
    static func metricColor(_ metric: MetricType, slots: [MetricType: Int]? = nil) -> Color {
        paletteColour(slot: slots?[metric] ?? metric.colourSlot)
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
