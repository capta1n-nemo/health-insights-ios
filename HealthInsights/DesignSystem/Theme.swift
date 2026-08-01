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
    /// - Parameter peak: the highest score the filled shape reaches.
    ///
    /// **The gradient resolves against the mark's own bounding box, not the plot
    /// area.** That was the open question when this shipped and the phone
    /// answered it: a card scoring 15 drew the full green-amber-red ramp squeezed
    /// into the bottom sixth of the chart, because the shape it was filling only
    /// spanned 0–15. So the stops are computed against `peak` — the top of the
    /// shape — rather than against 100.
    ///
    /// The consequence worth stating: a chart that never rises above 45 is
    /// entirely red, which is the correct reading and the one the previous
    /// version could not produce.
    static func scoreFill(peak: Double, opacity: Double = 0.30) -> LinearGradient {
        let top = Swift.max(peak, 1)          // never divide by zero
        // location 0 is the top of the filled shape, i.e. a score of `top`.
        func location(_ score: Double) -> Double {
            Swift.max(0, Swift.min(1, (top - score) / top))
        }
        var stops: [Gradient.Stop] = []
        if top > scoreGoodFloor {
            stops.append(.init(color: good.opacity(opacity), location: 0))
            stops.append(.init(color: good.opacity(opacity), location: location(scoreGoodFloor)))
        }
        if top > scoreWarnFloor {
            if stops.isEmpty {
                stops.append(.init(color: warn.opacity(opacity), location: 0))
            }
            stops.append(.init(color: warn.opacity(opacity), location: location(scoreWarnFloor)))
        }
        if stops.isEmpty {
            // Never clears the amber floor, so there is nothing here but red.
            stops.append(.init(color: bad.opacity(opacity), location: 0))
        }
        stops.append(.init(color: bad.opacity(opacity), location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Body composition
    //
    // A palette of its own, and the one place in this app where hue is *not*
    // identity. Everywhere else a colour says "which signal is this" and is
    // assigned by `MetricType.colourSlot` for collision-safety alone — which is
    // why the first version of this chart drew fat green, muscle red and bone
    // blue. Those are five perfectly distinguishable hues that say nothing, and
    // on a picture of what a body is *made of* the reader already knows what
    // colour fat and bone are. Here the substance names the colour.
    //
    // Distinguishability is not lost by doing so: the bands are stacked and
    // labelled, and the two reds are separated by both lightness and temperature.

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }

    /// Adipose — warm amber.
    static let compositionFat = adaptive(light: 0xE0952F, dark: 0xE8A64B)
    /// Muscle that is not water — deep red.
    static let compositionMuscle = adaptive(light: 0xB23A3A, dark: 0xC44E4E)

    /// Water, as itself — the legend dot, the change row, and the film that goes
    /// over muscle.
    ///
    /// **Cyan-leaning rather than a pure blue, and that is the whole trick.**
    /// Purple is what you get when red and blue are close and green is low, so a
    /// blue with a suppressed green channel laid over the muscle red can only
    /// ever come out plum — the previous version measured rgb(126, 88, 121),
    /// which is plum by definition. Pushing the green up carries it through the
    /// mix: the film now lands on rgb(72, 126, 163), green above red and blue
    /// dominant, which reads as blue over red rather than as purple.
    static let compositionWater = adaptive(light: 0x0FA3DC, dark: 0x3FBFF0)

    /// How opaque the water film is where it lies over muscle.
    ///
    /// The film sits on an intact muscle band, so the red beneath still shows
    /// through and the top of the band stays plainly red — that is what makes it
    /// read as water *on* muscle rather than as a substance of its own.
    ///
    /// Raised from 0.40, where the red was strong enough through the film to
    /// pull it to plum. With the cyan-leaning blue above, this is the point at
    /// which the film reads unambiguously blue while the muscle underneath is
    /// still doing visible work.
    static let waterFilmOpacity: Double = 0.65

    /// Kept for the `muscleWater` legend case, which now resolves to plain blue:
    /// water is never drawn as a band of its own any more.
    static let compositionMuscleWater = compositionWater
    /// Bone — pale ivory, deepened just enough to hold an edge on a light card.
    static let compositionBone = adaptive(light: 0xD9C9A3, dark: 0xBFAE86)
    /// Lean mass before the scale began separating muscle from bone.
    static let compositionLean = adaptive(light: 0xB5665C, dark: 0xC47C72)
    /// Lean tissue the scale measured but did not attribute.
    static let compositionOtherLean = adaptive(light: 0xC98F8F, dark: 0xD4A3A3)

    /// The card's own background, for washing out a stretch of chart that is
    /// inferred rather than measured. Not `.white`, which would be a stain in
    /// dark mode.
    static let cardScrim = adaptive(light: 0xF2F2F7, dark: 0x1C1C1E)

    /// The colour a band is *drawn* in, inside a bar or a chart.
    static func compositionColour(_ kind: BodyCompositionSplit.Band.Kind) -> Color {
        switch kind {
        case .fat: return compositionFat
        case .muscleWater: return compositionMuscleWater
        case .muscle: return compositionMuscle
        case .bone: return compositionBone
        case .otherLean: return compositionOtherLean
        case .lean: return compositionLean
        }
    }

    /// The colour a band is *named* in — a legend dot, a change row.
    ///
    /// Identical to the drawn colour for everything except water, which is drawn
    /// as it appears inside muscle but named as itself. A key answers "which
    /// substance is this", and the answer for water is blue; the muscle red under
    /// it is a fact about where it sits, not about what it is.
    static func compositionLegendColour(_ kind: BodyCompositionSplit.Band.Kind) -> Color {
        kind == .muscleWater ? compositionWater : compositionColour(kind)
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
