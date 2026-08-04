import SwiftUI
import InsightKit

/// Every scored insight as one shape: the Insights tab's hero.
///
/// ## Why this is not `ScrollableMetricChart`, and not Swift Charts at all
///
/// `add-chart` §1 is "wrap `ScrollableMetricChart`", and it owns pan, zoom,
/// scrub and the y-scale **for a time axis**. This chart has no time axis — it
/// is nine categories on a polar layout — so there is nothing for it to own
/// here, exactly as `EnergyCurveChart` and `SleepOnsetStripChart` document for
/// their own reasons. Swift Charts has no polar mark either, so the shape is
/// `Path`, which also sidesteps §2's `Chart3DContent` overload hazard entirely:
/// there is no `ChartContent` builder in this file.
///
/// ## The encoding, and what it deliberately does not claim
///
/// - **Radius is the score**, linear, no inner floor, grid rings at 25/50/75/100.
/// - **Hue is the score band**, not the insight. `Theme.color(forScore:)` — the
///   same rule the dial on every card below uses, so the web and the dials
///   cannot disagree about what 68 looks like. This is a deliberate departure
///   from `add-chart` §3, where hue is identity: identity here is carried by the
///   **label and the angle**, which are fixed and always drawn. It is also the
///   only safe choice — there are nine insights and eight validated hues, so
///   `InsightPalette.slots` is forced into a collision at nine spokes, and a
///   collision is unreadable on a chart whose whole point is comparing all of
///   them at once.
/// - **The fill is banded per spoke, and never a gradient.** The reader asked
///   to see which cards have moved into green, amber and red, so the area is cut
///   into one wedge per spoke, each taking that spoke's own `Theme
///   .color(forScore:)`. Both gradient forms are forbidden and for different
///   reasons: a *linear* one resolves against the mark's bounding box (§7), so
///   it would shade by whichever spoke happens to point up and encode nothing;
///   an *angular* one would interpolate through amber between a green spoke and
///   a red one, inventing a band for a stretch of chart where no card sits,
///   which is §8's hatch-never-blend in polar form. Wedges give every coloured
///   region exactly one owner. See `WebWedgeShape`.
/// - **The reference outline is solid, never dashed.** Dash means "not
///   measured" and nothing else (§3). The reference is the mean of *stored*
///   score rows — days the app really did tell the reader a number — so it is
///   measured, and it is separated by weight and opacity rather than by dash.
/// - **Two fills, and they are allowed to overlap because one is colourless.**
///   The usual web is filled a flat unsaturated grey beneath the banded current
///   one, which is what the reader asked for — two outlines alone had to be
///   traced by eye to be compared. §8's hatch-never-blend is about two
///   *quantities* mixing into a third colour that reads as a real value; grey
///   under a band cannot be misread as a different band, because grey is not one
///   of the three. If the backdrop ever gains a hue, this stops being true.
struct ScoreBalanceWeb: View {
    let snapshot: BalanceWebSnapshot
    /// Tapping a spoke opens that card. The web is the tab's index as well as
    /// its summary — the whole point of drawing all nine.
    var onSelect: (InsightID) -> Void = { _ in }

    /// Radius as a fraction of the square's side. The rest of the box is the
    /// label ring: nine words have to sit outside the outer grid without
    /// touching it or the card's edge.
    private static let plotRadiusRatio: CGFloat = 0.29
    /// Where a label's centre sits, as a multiple of the plot radius.
    private static let labelRadiusRatio: CGFloat = 1.28

    /// Drives the draw-on: the shape grows out of the centre rather than
    /// appearing whole.
    ///
    /// Animated **once, on appear**, and deliberately not re-run when the
    /// snapshot is replaced. Resetting to 0 and re-growing on every refresh
    /// needs the reset to land in its own transaction or SwiftUI coalesces the
    /// two and nothing animates at all — and the honest version of that race is
    /// not to have it: a refreshed snapshot moves its vertices directly, while
    /// the cross-fade out of the skeleton is owned by `InsightsHeroModel`.
    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side * Self.plotRadiusRatio

            ZStack {
                grid
                referenceLayer
                currentLayer
                vertices(centre: centre, radius: radius)
                labels(centre: centre, radius: radius)
            }
        }
        .onAppear {
            guard progress == 0 else { return }
            withAnimation(.easeOut(duration: 0.55)) { progress = 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Balance of your scores")
    }

    // MARK: - Grid

    private var fractions: [Double] { snapshot.spokes.map(\.radiusFraction) }

    /// Rings at every quarter, plus a line out to each spoke.
    ///
    /// Polygonal rings rather than circles: a circular grid invites reading the
    /// distance between two *adjacent* vertices as though the chord meant
    /// something, and the polygon makes it plain that the only meaningful
    /// distance is along a spoke.
    private var grid: some View {
        let count = snapshot.spokes.count
        return ZStack {
            ForEach(BalanceWebGeometry.ringFractions, id: \.self) { ring in
                WebPolygonShape(fractions: Array(repeating: ring, count: count),
                                radiusRatio: Self.plotRadiusRatio, progress: 1)
                    .stroke(Color.primary.opacity(ring == 1 ? 0.16 : 0.08),
                            lineWidth: ring == 1 ? 1 : 0.5)
            }
            WebSpokesShape(count: count, radiusRatio: Self.plotRadiusRatio)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    // MARK: - The two shapes

    /// Where each card is being judged against.
    ///
    /// A closed outline only when every spoke has one — otherwise its edges
    /// would run straight past the vertices it has no value for, and nothing on
    /// screen would say which were skipped. `BalanceWebSnapshot
    /// .hasCompleteReference` owns that rule and is tested; the partial case
    /// draws per-spoke ticks, which can be individually absent without lying.
    @ViewBuilder private var referenceLayer: some View {
        let referenceFractions = snapshot.spokes.map { $0.referenceFraction ?? 0 }
        if snapshot.hasCompleteReference {
            // **Filled, faintly.** The reader asked for the usual web to sit
            // *under* the current one as a light grey body rather than a bare
            // outline, so the two shapes can be compared at a glance instead of
            // by tracing two lines. Grey and unsaturated on purpose: it is the
            // backdrop, and colour on this chart means a score band.
            WebPolygonShape(fractions: referenceFractions,
                            radiusRatio: Self.plotRadiusRatio, progress: progress)
                .fill(Color.secondary.opacity(0.10))
            WebPolygonShape(fractions: referenceFractions,
                            radiusRatio: Self.plotRadiusRatio, progress: progress)
                .stroke(Color.secondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        } else {
            WebReferenceTicksShape(fractions: snapshot.spokes.map(\.referenceFraction),
                                   radiusRatio: Self.plotRadiusRatio, progress: progress)
                .stroke(Color.secondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    /// Today's scores, **each wedge coloured by its own spoke's band**.
    ///
    /// ## Why wedges rather than one gradient
    ///
    /// The reader asked to see which parts of the web have moved into green,
    /// amber or red — the same reading the dials and the score-over-time charts
    /// give. The obvious implementation, one gradient across the polygon, is
    /// the thing `add-chart` §7 forbids and this file's own header already
    /// rejected: a linear gradient resolves against the mark's bounding box, so
    /// it would shade by *which spoke happens to point up* and encode nothing.
    ///
    /// An angular gradient is no better. Between a green spoke and a red one it
    /// interpolates through amber — inventing a middle band for a stretch of
    /// chart where no card sits. That is hatch-never-blend (§8) in polar form:
    /// two quantities drawn over one another must never mix into a third
    /// colour that reads as a real value.
    ///
    /// So the fill is **one wedge per spoke**, each running from the centre out
    /// to that spoke's vertex and halfway to each neighbour. Every coloured
    /// region therefore belongs to exactly one score and takes exactly that
    /// score's band colour, with hard edges where ownership changes. Nothing is
    /// interpolated and nothing is implied about the space between two cards.
    private var currentLayer: some View {
        ZStack {
            ForEach(Array(snapshot.spokes.enumerated()), id: \.offset) { index, spoke in
                WebWedgeShape(fractions: fractions, index: index,
                              radiusRatio: Self.plotRadiusRatio, progress: progress)
                    .fill(Theme.color(forScore: spoke.score).opacity(0.22))
            }
            // The outline stays one accent-coloured path rather than following
            // the bands: it is the shape's silhouette, and a stroke that
            // changed colour per segment would read as eleven separate marks
            // instead of one reading.
            WebPolygonShape(fractions: fractions,
                            radiusRatio: Self.plotRadiusRatio, progress: progress)
                .stroke(Theme.accent.opacity(0.85),
                        style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    // MARK: - Vertices and labels

    private func position(index: Int, fraction: Double,
                          centre: CGPoint, radius: CGFloat) -> CGPoint {
        let point = BalanceWebGeometry.point(index: index, count: snapshot.spokes.count,
                                             radiusFraction: fraction)
        return CGPoint(x: centre.x + CGFloat(point.x) * radius,
                       y: centre.y + CGFloat(point.y) * radius)
    }

    /// Where a label sits — outside the outer ring, so it needs its own maths.
    ///
    /// `BalanceWebGeometry.point` clamps to the outer ring, correctly: a score
    /// past 100 must not draw outside the grid. A label is not a score, so
    /// putting one through that function pins all nine *onto* the outer ring,
    /// on top of the gridline and the vertices.
    private func labelPosition(index: Int, centre: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = BalanceWebGeometry.angle(index: index, count: snapshot.spokes.count)
        let distance = radius * Self.labelRadiusRatio
        return CGPoint(x: centre.x + CGFloat(cos(angle)) * distance,
                       y: centre.y + CGFloat(sin(angle)) * distance)
    }

    private func vertices(centre: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(snapshot.spokes.enumerated()), id: \.element.id) { index, spoke in
            Button { onSelect(spoke.id) } label: {
                Circle()
                    .fill(Theme.color(forScore: spoke.score))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    // A 9pt dot is not a tap target; 44 is.
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(position(index: index, fraction: spoke.radiusFraction * progress,
                               centre: centre, radius: radius))
            .accessibilityLabel(speech(for: spoke))
            .accessibilityAddTraits(.isButton)
        }
    }

    private func labels(centre: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(snapshot.spokes.enumerated()), id: \.element.id) { index, spoke in
            HStack(spacing: 3) {
                Text(spoke.shortTitle)
                    .foregroundStyle(.secondary)
                Text("\(Int(spoke.score.rounded()))")
                    .foregroundStyle(Theme.color(forScore: spoke.score))
                    .monospacedDigit()
                if let arrow = arrow(for: spoke.direction) {
                    Image(systemName: arrow)
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                }
            }
            .font(.caption2.weight(.medium))
            .fixedSize()
            .position(labelPosition(index: index, centre: centre, radius: radius))
            .accessibilityHidden(true)   // the vertex button already speaks it
        }
    }

    /// Steady is a measured answer and gets no arrow rather than a misleading
    /// one — the same restraint `ScoreChangeChip` applies. `nil` is "not enough
    /// stored history to judge", which is a different silence and also correct.
    private func arrow(for direction: ScoreChange.Direction?) -> String? {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .steady, nil: return nil
        }
    }

    private func speech(for spoke: BalanceWebSnapshot.Spoke) -> String {
        var parts = ["\(spoke.title), \(Int(spoke.score.rounded())) out of 100"]
        if let reference = spoke.reference {
            parts.append("judged against \(Int(reference.rounded()))")
        }
        switch spoke.direction {
        case .up: parts.append("up")
        case .down: parts.append("down")
        case .steady: parts.append("no change")
        case nil: break
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Shapes

/// A closed polygon through one fraction per spoke.
///
/// `progress` is the only animatable value: the fractions belong to a snapshot,
/// and a snapshot is replaced wholesale rather than interpolated. Animating the
/// vertex list too would need an `AnimatableVector`, which buys a morph between
/// two shapes nobody asked to see mid-flight.
private struct WebPolygonShape: Shape {
    let fractions: [Double]
    let radiusRatio: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fractions.count >= 2 else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusRatio
        for (index, fraction) in fractions.enumerated() {
            let point = BalanceWebGeometry.point(index: index, count: fractions.count,
                                                 radiusFraction: fraction * progress)
            let screen = CGPoint(x: centre.x + CGFloat(point.x) * radius,
                                 y: centre.y + CGFloat(point.y) * radius)
            if index == 0 { path.move(to: screen) } else { path.addLine(to: screen) }
        }
        path.closeSubpath()
        return path
    }
}

/// Centre-to-rim lines, one per spoke.
private struct WebSpokesShape: Shape {
    let count: Int
    let radiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count >= 2 else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusRatio
        for index in 0..<count {
            let point = BalanceWebGeometry.point(index: index, count: count,
                                                 radiusFraction: 1)
            path.move(to: centre)
            path.addLine(to: CGPoint(x: centre.x + CGFloat(point.x) * radius,
                                     y: centre.y + CGFloat(point.y) * radius))
        }
        return path
    }
}

/// A short mark across each spoke at its reference value, for the case where
/// only some spokes have one. A `nil` fraction draws nothing, which is the whole
/// reason this exists rather than a closed outline through zeros.
private struct WebReferenceTicksShape: Shape {
    let fractions: [Double?]
    let radiusRatio: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Half-length of a tick, in points.
    private static let halfWidth: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = fractions.count
        guard count >= 2 else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusRatio
        for (index, fraction) in fractions.enumerated() {
            guard let fraction else { continue }
            let angle = BalanceWebGeometry.angle(index: index, count: count)
            let along = CGPoint(x: cos(angle), y: sin(angle))
            // Perpendicular to the spoke, so the tick reads as a level on it
            // rather than as a stray dot near it.
            let across = CGPoint(x: -along.y, y: along.x)
            let distance = radius * CGFloat(fraction * progress)
            let anchor = CGPoint(x: centre.x + along.x * distance,
                                 y: centre.y + along.y * distance)
            path.move(to: CGPoint(x: anchor.x - across.x * Self.halfWidth,
                                  y: anchor.y - across.y * Self.halfWidth))
            path.addLine(to: CGPoint(x: anchor.x + across.x * Self.halfWidth,
                                     y: anchor.y + across.y * Self.halfWidth))
        }
        return path
    }
}

// MARK: - Skeleton

/// What the hero renders while the snapshot is being built.
///
/// The grid is drawn for real and only the shape is missing, so the card does
/// not change size when the data lands — a skeleton that reserves the wrong
/// height causes the reflow it was added to prevent. It pulses rather than
/// shimmers: a shimmer sweep on a radial shape reads as a rotation, which
/// suggests something is spinning up that isn't.
struct ScoreBalanceWebSkeleton: View {
    /// Nine, because that is how many scored insights ship. The skeleton's job
    /// is to hold the right shape, and a five-sided placeholder followed by a
    /// nine-sided web is a visible jump.
    var spokes: Int = InsightID.allCases.count
    @State private var dim = false

    private static let plotRadiusRatio: CGFloat = 0.29

    var body: some View {
        ZStack {
            ForEach(BalanceWebGeometry.ringFractions, id: \.self) { ring in
                WebPolygonShape(fractions: Array(repeating: ring, count: spokes),
                                radiusRatio: Self.plotRadiusRatio, progress: 1)
                    .stroke(Color.primary.opacity(ring == 1 ? 0.16 : 0.08),
                            lineWidth: ring == 1 ? 1 : 0.5)
            }
            WebSpokesShape(count: spokes, radiusRatio: Self.plotRadiusRatio)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            WebPolygonShape(fractions: Array(repeating: 0.55, count: spokes),
                            radiusRatio: Self.plotRadiusRatio, progress: 1)
                .fill(Color.secondary.opacity(dim ? 0.07 : 0.16))
        }
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityLabel("Working out how your scores compare")
    }
}

/// One spoke's share of the filled area: centre → halfway to the previous
/// spoke → this spoke's vertex → halfway to the next.
///
/// **Why the fill is cut up at all.** The reader wanted the web to show which
/// cards sit in green, amber and red, the way the dials do. One gradient across
/// the polygon cannot: a linear one resolves against the bounding box and shades
/// by whichever spoke points up, and an angular one interpolates *through* amber
/// between a green spoke and a red one — inventing a band for a stretch of chart
/// where no card sits. `add-chart` §7 and §8 forbid both.
///
/// Cutting the area into per-spoke wedges makes every coloured region belong to
/// exactly one score, so its colour is that score's band and nothing is implied
/// about the space between two cards. The midpoint boundary is the only neutral
/// place to divide two neighbours.
///
/// The halfway points are taken along the **straight edge** between the two
/// vertices rather than at a fixed radius, so the wedges tile the polygon
/// exactly — no seams, no overlap, and the union is the same shape the outline
/// strokes.
private struct WebWedgeShape: Shape {
    let fractions: [Double]
    let index: Int
    let radiusRatio: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = fractions.count
        guard count >= 3, fractions.indices.contains(index) else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusRatio

        func vertex(_ i: Int) -> CGPoint {
            let wrapped = ((i % count) + count) % count
            let p = BalanceWebGeometry.point(index: wrapped, count: count,
                                             radiusFraction: fractions[wrapped] * progress)
            return CGPoint(x: centre.x + CGFloat(p.x) * radius,
                           y: centre.y + CGFloat(p.y) * radius)
        }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        let here = vertex(index)
        let beforeMid = midpoint(vertex(index - 1), here)
        let afterMid = midpoint(here, vertex(index + 1))

        path.move(to: centre)
        path.addLine(to: beforeMid)
        path.addLine(to: here)
        path.addLine(to: afterMid)
        path.closeSubpath()
        return path
    }
}
