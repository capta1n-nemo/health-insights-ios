import SwiftUI
import InsightKit

/// The reader's body, drawn from their own girths.
///
/// ## What this claims, and what it does not
///
/// It is **a representation, not a picture**. Every horizontal width comes from
/// a measured or estimated circumference at that height, so a waist that fell
/// 4 cm draws 4 cm narrower — but nothing here knows what the reader looks
/// like, and the caption says so wherever it appears.
///
/// ## Why an outline rather than a 3D mesh, for now
///
/// The reader asked for a body that morphs smoothly between scans and projects
/// forward, and *that* is the load-bearing requirement — `BodyModelParameters
/// .interpolate` already provides it. A rigged mesh renders the same seven
/// numbers with more polish and no more information, so it is a second pass,
/// not a prerequisite. Drawing the outline from the parameters directly means
/// the mesh can replace this view without touching anything upstream.
///
/// ## Circumference to width
///
/// Treated as an ellipse of fixed aspect: `width = girth / π × aspect`. A body
/// cross-section is not a circle, and pretending it is would draw everybody
/// rounder than they are — the aspect is the one shape assumption in here and
/// it is named rather than buried in a magic constant.
struct BodySilhouetteView: View {
    let parameters: BodyModelParameters
    /// Drawn dimmed and dashed when the body is a projection rather than a
    /// measurement, per `add-chart` §3: a dash means "not measured".
    var isProjected: Bool = false
    var tint: Color = Theme.accent

    /// Depth-to-width ratio of a torso cross-section. Bodies are wider than
    /// they are deep; 0.72 is the mid-range figure and the only shape
    /// assumption this view makes.
    private static let crossSectionAspect: Double = 0.72

    var body: some View {
        Canvas { context, size in
            let outline = Self.outline(parameters, in: size)
            guard !outline.isEmpty else { return }

            var path = Path()
            path.addLines(outline)
            path.closeSubpath()

            context.fill(path, with: .color(tint.opacity(isProjected ? 0.10 : 0.22)))
            context.stroke(
                path, with: .color(tint.opacity(isProjected ? 0.55 : 0.9)),
                style: isProjected
                    ? StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [4, 4])
                    : StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .accessibilityLabel(Self.speech(parameters, isProjected: isProjected))
    }

    /// The closed outline, left side down then right side up.
    ///
    /// `static` and taking a size so it is pure — the geometry can be reasoned
    /// about without a view, and the mesh renderer that eventually replaces the
    /// Canvas can read the same points.
    static func outline(_ parameters: BodyModelParameters, in size: CGSize) -> [CGPoint] {
        let stations = BodyStation.allCases.compactMap { station -> (Double, Double)? in
            guard let girth = parameters.girth(station) else { return nil }
            return (station.heightFraction, girth)
        }
        guard stations.count >= 3, size.width > 0, size.height > 0 else { return [] }

        // Scale so the widest station fills a comfortable share of the frame,
        // and heights span the full body. Both are relative, so two bodies
        // drawn side by side stay comparable.
        // `{ $0.1 }`, not `\.1` — key paths do not work on tuple elements,
        // which `verify.sh` lints for because it has broken this repo's CI before.
        let widest = stations.map { $0.1 }.max() ?? 1
        let maxHalfWidth = size.width * 0.34
        let centre = size.width / 2

        func point(_ fraction: Double, _ girth: Double, mirrored: Bool) -> CGPoint {
            let widthCm = girth / .pi * crossSectionAspect
            let widestCm = widest / .pi * crossSectionAspect
            let half = maxHalfWidth * (widthCm / max(widestCm, 0.0001))
            // heightFraction is measured from the floor; the canvas is y-down.
            let y = size.height * (1 - fraction)
            return CGPoint(x: centre + (mirrored ? half : -half), y: y)
        }

        let ordered = stations.sorted { $0.0 > $1.0 }        // head end first
        var points = ordered.map { point($0.0, $0.1, mirrored: false) }
        points += ordered.reversed().map { point($0.0, $0.1, mirrored: true) }
        return points
    }

    static func speech(_ parameters: BodyModelParameters, isProjected: Bool) -> String {
        let waist = parameters.girth(.waist).map { String(format: "%.0f cm", $0) } ?? "unknown"
        return isProjected
            ? "Projected body shape. Waist \(waist)."
            : "Your body shape, drawn from your measurements. Waist \(waist)."
    }
}
