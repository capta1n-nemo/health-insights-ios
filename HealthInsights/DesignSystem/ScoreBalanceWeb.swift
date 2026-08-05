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
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: BalanceWebSnapshot
    /// Tapping a spoke opens that card. The web is the tab's index as well as
    /// its summary — the whole point of drawing all nine.
    var onSelect: (InsightID) -> Void = { _ in }

    /// Radius as a fraction of the square's side. The rest of the box is the
    /// label ring: nine words have to sit outside the outer grid without
    /// touching it or the card's edge.
    ///
    /// **0.29 → 0.335 on 2026-08-05**, at the reader's request ("make the web on
    /// insights a bit bigger"). The ceiling is the label ring, not the card: at
    /// 0.335 a label's centre sits 0.40 of the side out from the middle, leaving
    /// a tenth of the side each way for the word itself — measured against the
    /// longest one the tab can produce, "Substances", at the tightest diagonal.
    private static let plotRadiusRatio: CGFloat = 0.335
    /// Where a label's centre sits, as a multiple of the plot radius.
    ///
    /// Pulled in from 1.28 as the plot grew, so the labels move outward by less
    /// than the shape does and the ring of words does not walk off the card.
    private static let labelRadiusRatio: CGFloat = 1.20

    // MARK: - What "usual" is painted in

    /// **Measured, not chosen.** The reader: *"make the 'usual' web more
    /// visible, let's try some different colours and find the best one that
    /// looks good, doesn't clash in a weird way, but is visible enough."*
    ///
    /// First move was §9 of the add-chart skill — read the pixel before picking
    /// another colour. Sampled off the simulator against this reader's own data:
    ///
    /// | | composited |
    /// | --- | --- |
    /// | card behind the web | rgb(239,237,241) |
    /// | usual fill at `secondary.opacity(0.16)` | **rgb(221,220,224)** |
    ///
    /// Eighteen levels. A contrast ratio of 1.16:1 — below every legibility
    /// threshold there is, and the reason it read as "barely there" rather than
    /// as a shape.
    ///
    /// ⚠️ **It stays colourless, and that is not timidity.** This file's own
    /// rule: *"grey under a band cannot be misread as a different band, because
    /// grey is not one of the three. If the backdrop ever gains a hue, this
    /// stops being true."* The current web is painted red→amber→green by score.
    /// A blue or indigo usual would read as a fourth band to anyone who has not
    /// been told otherwise, and — worse — it sits *under* a translucent fill, so
    /// every overlap would mix into a colour that means nothing (§8,
    /// hatch-never-blend, which cost five rounds on the water band). The honest
    /// louder version of "context" is a louder grey, not a different hue.
    ///
    /// So: opacity roughly doubled, and the outline given real weight, because a
    /// visible **edge** does more for reading a shape than a visible interior.
    /// ⚠️ **A louder grey was tried first and it clashed — measured.** At
    /// `opacity(0.44)` the usual reached rgb(191,192,194) against the card, a
    /// perfectly readable 1.42:1 — and where it lay under the banded current
    /// fill the two mixed into rgb(207,164,153), a dusty pink-brown next to a
    /// clean band of rgb(231,218,186). That is §8's third colour that means
    /// nothing, and it is the whole reason the water band is hatched.
    ///
    /// So: **hatched, which cannot mix**, at a grey strong enough to see. Every
    /// pixel is either the stripe or the band under it, both stay themselves,
    /// and the stripes make the shape unmistakably *context* rather than a
    /// fourth score band — which no amount of grey ever quite managed.
    @MainActor static func usualHatch(_ scheme: ColorScheme) -> ImagePaint {
        Theme.hatch(light: 0xB0B0B6, dark: 0x8E8E93, scheme)
    }
    /// The edge does more for reading a shape than the interior does, and it is
    /// the part that has to survive being drawn over a coloured fill.
    private static let usualStroke = Color.secondary.opacity(0.85)

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
                // ⚠️ **The usual goes on TOP of today, and §8 is why.** A hatch
                // only refuses to mix if it is the thing being painted *over*:
                // underneath a translucent band fill its stripes would be
                // tinted by it and the mixing this exists to avoid would happen
                // anyway, one layer down. Painted over, every pixel is either a
                // stripe or the band beneath it. The band stays fully itself in
                // the gaps — which is exactly the claim the water-over-muscle
                // chart rests on — so today is still the louder reading and the
                // usual reads as texture over it rather than as a fourth value.
                currentLayer(radius: radius)
                referenceLayer
                referenceDots(centre: centre, radius: radius)
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

        // **The grey body is drawn per spoke, so a partial reference still
        // shows one.**
        //
        // This used to be all-or-nothing: a filled polygon when *every* spoke
        // had a reference, and bare ticks otherwise. The reasoning for refusing
        // the closed outline is sound — its edges would run straight past the
        // vertices it has no value for, and nothing on screen would say which
        // were skipped — but the conclusion was too strong. On a real record
        // only four of eight cards had accumulated stored score rows, so the
        // reader got ticks and could not see the comparison the shape exists to
        // make. "Correct" is not the same as "useful", and an honest partial
        // beats an accurate blank.
        //
        // Per-spoke wedges have neither problem: grey appears exactly where
        // there is a usual to show and is absent where there is not, so the
        // gaps are visible as gaps rather than bridged by a straight edge that
        // invents values for them. Same geometry as the banded current fill, so
        // the two shapes tile identically and can be read against each other.
        ForEach(Array(snapshot.spokes.enumerated()), id: \.offset) { index, spoke in
            if spoke.referenceFraction != nil {
                WebWedgeShape(fractions: referenceFractions, index: index,
                              radiusRatio: Self.plotRadiusRatio, progress: progress)
                    .fill(Self.usualHatch(colorScheme))
            }
        }

        if snapshot.hasCompleteReference {
            // With every spoke present the closed outline is honest, and it
            // reads better than eight wedge edges.
            WebPolygonShape(fractions: referenceFractions,
                            radiusRatio: Self.plotRadiusRatio, progress: progress)
                .stroke(Self.usualStroke,
                        style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    /// Each spoke's usual, as a dot on its own spoke.
    ///
    /// **Dots rather than the short perpendicular ticks this used to draw.** The
    /// ticks read as "stoppers" — little barriers across the spoke — rather than
    /// as a value sitting on it, and they matched nothing else on the chart. The
    /// current score is a dot; its usual should be the same mark in grey, so the
    /// eye pairs them without being told to. Smaller and hollow-free so the
    /// coloured dot stays the louder of the two: today is the reading, the usual
    /// is the context.
    private func referenceDots(centre: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(snapshot.spokes.enumerated()), id: \.element.id) { index, spoke in
            if let fraction = spoke.referenceFraction {
                Circle()
                    .fill(Color.secondary.opacity(0.75))
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1))
                    .position(position(index: index, fraction: fraction * progress,
                                       centre: centre, radius: radius))
                    .allowsHitTesting(false)
            }
        }
    }

    /// Today's scores, filled with the **radial** band ramp.
    ///
    /// ## Why radial, after two wrong answers
    ///
    /// The reader wanted the same reading the dials and the score-over-time
    /// area give: red is bad, green is good, and the colour means the same
    /// thing on every chart. Two earlier attempts were rejected for reasons
    /// that still stand:
    ///
    /// - **A linear gradient** resolves against the mark's bounding box, so it
    ///   shades by *which spoke happens to point up* — it encodes the chart's
    ///   rotation, not the reader's scores (`add-chart` §7).
    /// - **An angular gradient** interpolates between a green spoke and a red
    ///   one through amber, inventing a middle band for a stretch of chart
    ///   where no card sits — hatch-never-blend (§8) in polar form.
    ///
    /// **A radial ramp has neither freedom, because its axis is the one the
    /// geometry already uses: distance from the centre is the score.** A point
    /// at 70% of the plot radius is green because 70 is green, wherever it sits
    /// around the circle. That is the same rule as `Theme.scoreFill`, read from
    /// the centre outward instead of the top down, and it is why the wedges are
    /// gone: they coloured a *region* by one card's band, so the same colour
    /// meant a different value at different radii.
    ///
    /// ⚠️ **The gradient is anchored to the score-100 radius, not to the
    /// polygon.** Anchored to the shape's own extent — which is what a bare
    /// `.fill(gradient)` does — a profile scoring 30 across the board would get
    /// the whole ramp inside its small shape and read green at its rim. That is
    /// §7's warning in radial form, and it is the one thing to check if this
    /// ever looks wrong again.
    private func currentLayer(radius: CGFloat) -> some View {
        ZStack {
            WebPolygonShape(fractions: fractions,
                            radiusRatio: Self.plotRadiusRatio, progress: progress)
                .fill(Theme.scoreRadialFill(radius: radius, opacity: 0.34))
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
