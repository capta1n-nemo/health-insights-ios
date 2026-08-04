import Foundation

// BodyMesh.swift — the pure-geometry half of the Visbody-style wireframe body
// model (docs/planned-modules.md, "The body scanner's visual target", decided
// 2026-08-03). Girths in → ring vertices → a lofted surface → a `BodyMesh`
// value of vertices and indices.
//
// Nothing in this file imports SceneKit, RealityKit or SwiftUI, and nothing
// here may: the app target has no test target, so a rule living in a view is
// verified only by eye (add-chart §5). Every rule in this file — perimeter
// fidelity, no-overshoot lofting, provenance never laundered — is held by
// `BodyMeshTests` on any platform `swift test` runs on.
//
// Storage is the standard library's `SIMD3<Float>`; deliberately NOT
// `import simd`, which is a Darwin-only module and would end the Linux test
// run this package exists to keep. Generation arithmetic is all `Double`;
// `Float32` appears only at emission.

// MARK: - Configuration

/// Tessellation knobs. All output counts are a closed form of this struct
/// alone (see `BodyMeshBuilder.mesh`), so the bounds test asserts a formula,
/// not a magic number.
public struct BodyMeshConfiguration: Sendable, Equatable {
    /// Vertices per ring. Clamped to even and >= 8 on use (rounded DOWN to
    /// even). Even is load-bearing: theta = pi must be a sampled vertex so the
    /// shoulder ring's width (max x − min x) is exact by construction — the
    /// shoulder value is a breadth, not a girth, and the width test would
    /// otherwise chase a sampling artefact.
    public var ringVertexCount: Int
    /// Interior rings inserted between adjacent knots. Clamped >= 1 on use.
    public var ringsPerSpan: Int
    /// Arms are wholly schematic (no arm station exists — see the deliberate
    /// refusal on `BodyMeshBuilder.mesh`). This flag lets the renderer ship
    /// torso-and-legs first if the arm constants look wrong on device.
    public var includesArms: Bool

    public init(ringVertexCount: Int = 48, ringsPerSpan: Int = 8, includesArms: Bool = true) {
        self.ringVertexCount = ringVertexCount
        self.ringsPerSpan = ringsPerSpan
        self.includesArms = includesArms
    }

    public static let `default` = BodyMeshConfiguration()

    /// Depth/width of every cross-section ellipse — the mesh's ONE shape
    /// assumption, inherited verbatim from `BodySilhouetteView.crossSectionAspect`
    /// so the replacement changes dimension, not claims. Public so the
    /// app-target renderer can read it later; the silhouette itself is not
    /// touched by this change.
    public static let crossSectionAspect = 0.72

    /// `ringVertexCount` as actually used: rounded down to even, then floored
    /// at 8. Clamping happens on use, not in `init`, so the struct stores what
    /// the caller said and `Equatable` compares intent, not effect.
    var effectiveRingVertexCount: Int {
        let even = ringVertexCount.isMultiple(of: 2) ? ringVertexCount : ringVertexCount - 1
        return Swift.max(8, even)
    }

    /// `ringsPerSpan` as actually used: floored at 1.
    var effectiveRingsPerSpan: Int { Swift.max(1, ringsPerSpan) }
}

// MARK: - Provenance and limbs

/// Why a ring exists. Three states, never two:
///
/// - `.measured` — a station ring whose `BodyStationValue.isMeasured` was true;
/// - `.estimated` — a girth exists at this height but was estimated or
///   projected, or the ring lies between two stations and inherits the
///   both-ends rule (see `BodyMeshBuilder.ringProvenance`);
/// - `.schematic` — no girth exists at this height at all (head, arms, crotch,
///   below-calf). Distinct from `.estimated` so the legend and labels can say
///   "no measurement exists here" rather than "estimated", which would imply a
///   number that could have been measured and wasn't.
///
/// This is the dash-means-inferred rule (add-chart §3) carried into 3D: the
/// renderer must draw measured and everything-else differently, and the flag
/// deciding which is which is computed here, where it is tested — never in
/// the view.
public enum RingProvenance: String, Sendable, Equatable, Hashable, CaseIterable {
    case measured, estimated, schematic
}

/// Which limb a ring belongs to. Left/right are the MODEL's anatomical sides:
/// the model's left is at +x, the viewer's right (the mesh faces the viewer).
public enum BodyLimb: String, Sendable, Equatable, Hashable, CaseIterable {
    case torso, head, leftLeg, rightLeg, leftArm, rightArm
}

// MARK: - BodyMesh

/// The lofted body surface, as plain vertex and index arrays.
///
/// ## What the renderer session needs to know (SceneKit notes)
///
/// - `vertices` and `normals` go verbatim into `SCNGeometrySource`s; the two
///   index lists become two `SCNGeometryElement`s sharing that one source,
///   with two materials (measured hue / estimated hue — the legend names both
///   and notes that schematic stretches carry no measurement at all).
/// - Wireframe via line fill mode. `labelAnchors` drive the leader lines:
///   park labels in a left/right gutter, re-sort by projected Y each frame,
///   hide a label whose anchor rotates behind the body.
/// - A scrub rebuilds via `mesh(for: interpolate(...))` with ONE
///   `BodyMeshConfiguration` for both ends, and updates geometry sources
///   **in place** — topology is input-invariant for a fixed configuration.
/// - **No runtime subdivision or tessellation.** Subdividing inflates the
///   drawn circumference past the taped girth and silently breaks the
///   perimeter fidelity this type guarantees.
/// - The mandatory caveat stays: "a representation built from your
///   measurements, not a picture of you."
///
/// ## A predicted observation, for the first device screenshot
///
/// A perimeter-true mesh renders visibly bulkier than the frame-normalised
/// silhouette (true width ≈ girth/π vs the silhouette's 0.34-frame
/// normalisation); "the new one looks wider" is a predicted observation, not
/// a bug.
public struct BodyMesh: Sendable, Equatable {

    /// One horizontal cross-section of the loft.
    public struct Ring: Sendable, Equatable {
        /// Floor-up, same convention as `BodyStation.heightFraction`.
        public let heightMetres: Double
        public let provenance: RingProvenance
        /// A contiguous run of exactly `ringVertexCount` vertices. Vertex 0 of
        /// the run is theta = 0 (+x), increasing theta from there.
        public let vertexRange: Range<Int>
        /// Non-nil only where this ring realises a station *exactly* — the
        /// leg-top ring carries the thigh girth but is not the thigh station.
        public let station: BodyStation?
        public let limb: BodyLimb
        /// The emitted polygon's polyline perimeter, metres. "Circumference"
        /// throughout this type means exactly that: the closed polyline length
        /// of the drawn ring, which equals the girth by construction (uniform
        /// scaling of a polyline is exactly linear). At 48 vertices the
        /// polygon under-fills a true ellipse by <0.3% of radius — stated,
        /// not corrected, because correcting it would break the identity
        /// between the number on the label and the curve the reader orbits.
        public let circumferenceMetres: Double
    }

    /// Where a girth label attaches. The gutter layout, per-frame re-sort and
    /// hide-when-behind rules are the renderer's; the anchor is the geometry.
    public struct LabelAnchor: Sendable, Equatable {
        public let station: BodyStation
        /// Bitwise-equal to `vertices[vertexIndex]` — the renderer projects
        /// this point, it never re-derives it.
        public let position: SIMD3<Float>
        /// Index into `rings`.
        public let ringIndex: Int
        /// The +x (theta = 0) vertex of the station ring.
        public let vertexIndex: Int
        /// Verbatim from `BodyStationValue.isMeasured` — the blanket caption's
        /// honesty made per-label. An estimated girth must say so on the label
        /// itself.
        public let isMeasured: Bool
        /// What the label prints: circumference in cm for six stations,
        /// BREADTH in cm for `.shoulder` (the stored shoulder value is a
        /// width — see the shoulder knot in `BodyMeshBuilder`). The renderer
        /// formats "waist 92 cm" / "waist ~92 cm — estimated" /
        /// "shoulder width 45 cm".
        public let valueCentimetres: Double
    }

    /// Metres. y up, floor at y = 0, origin at floor centre, +z toward the
    /// viewer, +x the viewer's right (the model's anatomical left).
    /// Right-handed.
    public let vertices: [SIMD3<Float>]
    /// Unit, outward, analytic — computed from the ellipse gradient and the
    /// loft slope, never averaged from faces, so they are testable as exact
    /// properties rather than as accumulation artefacts.
    public let normals: [SIMD3<Float>]
    /// Hard provenance partition: two DISJOINT triangle index lists that
    /// together cover every face. A face is in `measuredTriangles` only when
    /// BOTH rings it spans are `.measured`; everything else — estimated,
    /// schematic, all cap fans — is in `estimatedTriangles`.
    ///
    /// The renderer draws them as two `SCNGeometryElement`s sharing one vertex
    /// source, with two materials. **Never a per-vertex colour attribute**:
    /// vertex colours interpolate the two hues into a third colour that means
    /// nothing — hatch-never-blend (add-chart §8) applied to 3D. Because the
    /// partition rides on the index lists over one shared vertex source, no
    /// face or wireframe segment can blend hues, and no station-ring vertex
    /// duplication is needed to keep the boundary crisp.
    public let measuredTriangles: [UInt32]
    /// See `measuredTriangles`. Schematic faces live here too — two materials
    /// stay two; `rings[].provenance` keeps the three-way distinction for
    /// legend and label copy.
    public let estimatedTriangles: [UInt32]
    /// Fixed emission order (torso bottom→top, head, left leg top→bottom,
    /// right leg, left arm, right arm) — the renderer never sorts.
    public let rings: [Ring]
    /// Exactly 7, in `BodyStation.allCases` order. Arms are schematic and
    /// deliberately un-anchored — no label may imply a measured arm.
    public let labelAnchors: [LabelAnchor]
    /// Mirrors `BodyModelParameters.isWhollyEstimated`, so the renderer can
    /// caption a pre-scan or projected body without re-deriving the fact.
    public let isWhollyEstimated: Bool
}

// MARK: - Monotone cubic curve (internal)

/// Multi-knot monotone cubic Hermite (Fritsch–Carlson 1980, the construction
/// behind PCHIP).
///
/// `GapBridge.smoothed()` (Presentation/SeriesSegmentation.swift) ships the
/// TWO-POINT reduction of this — its own comment says "Fritsch–Carlson in the
/// two-point case reduces to this". This is the general multi-knot case,
/// written fresh rather than extracted because there is no shared kernel to
/// extract (verified 2026-08-04); the cross-reference is one-way because that
/// file must not be touched by this change. If either implementation changes
/// shape, re-read the other.
///
/// ## The session-9 guarantee
///
/// What was rejected back then was Catmull-Rom and natural cubics
/// specifically — they overshoot outside the range of the values they join,
/// inventing an extremum in the one stretch nobody measured. It was never a
/// rejection of curvature. With tangents limited as below, the interpolant is
/// monotone on each span, has no interior extremum, and never leaves
/// [value_i, value_i+1] — curved, and incapable of claiming a bulge or hollow
/// no tape measured.
struct MonotoneCubicCurve {
    private let knotY: [Double]
    private let knotValue: [Double]
    private let slope: [Double]

    /// `knots.y` strictly increasing, count >= 2. Returns nil otherwise.
    init?(knots: [(y: Double, value: Double)]) {
        guard knots.count >= 2 else { return nil }
        guard zip(knots.dropFirst(), knots).allSatisfy({ $0.y > $1.y }) else { return nil }

        let count = knots.count
        let ys = knots.map { $0.y }
        let values = knots.map { $0.value }

        var secant = [Double](repeating: 0, count: count - 1)
        for i in 0..<(count - 1) {
            secant[i] = (values[i + 1] - values[i]) / (ys[i + 1] - ys[i])
        }

        // Initial slopes: ends take their one secant; interiors average their
        // two, except a sign change (a local extremum AT a knot) pins the
        // slope to zero so neither side overshoots past the knot.
        var m = [Double](repeating: 0, count: count)
        m[0] = secant[0]
        m[count - 1] = secant[count - 2]
        if count > 2 {
            for i in 1..<(count - 1) {
                m[i] = secant[i - 1] * secant[i] <= 0 ? 0 : (secant[i - 1] + secant[i]) / 2
            }
        }

        // Fritsch–Carlson limiter: keep (alpha, beta) inside the circle of
        // radius 3, which is a (conservative) subset of the exact
        // monotonicity region — this is the line that makes overshoot
        // impossible rather than merely unlikely.
        for i in 0..<(count - 1) {
            if secant[i] == 0 {
                m[i] = 0
                m[i + 1] = 0
            } else {
                var alpha = m[i] / secant[i]
                var beta = m[i + 1] / secant[i]
                if alpha < 0 { alpha = 0; m[i] = 0 }
                if beta < 0 { beta = 0; m[i + 1] = 0 }
                let radiusSquared = alpha * alpha + beta * beta
                if radiusSquared > 9 {
                    let tau = 3 / radiusSquared.squareRoot()
                    m[i] = tau * alpha * secant[i]
                    m[i + 1] = tau * beta * secant[i]
                }
            }
        }

        knotY = ys
        knotValue = values
        slope = m
    }

    /// Clamps to the end values outside the domain — a chain never asks for a
    /// height it has no knots around, so the clamp is a guard rail, not a
    /// feature anything leans on.
    func value(at y: Double) -> Double {
        if y <= knotY[0] { return knotValue[0] }
        if y >= knotY[knotY.count - 1] { return knotValue[knotValue.count - 1] }
        let i = spanIndex(y)
        let h = knotY[i + 1] - knotY[i]
        let t = (y - knotY[i]) / h
        let t2 = t * t
        let t3 = t2 * t
        // The same four Hermite basis polynomials `GapBridge.smoothed()` uses.
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * knotValue[i] + h10 * h * slope[i]
            + h01 * knotValue[i + 1] + h11 * h * slope[i + 1]
    }

    /// C1: at a knot this is the limited slope m_i — which is exactly what the
    /// analytic normal wants there, a tilt that agrees from both sides.
    /// Zero outside the domain, consistent with the clamped constant extension.
    func derivative(at y: Double) -> Double {
        if y < knotY[0] || y > knotY[knotY.count - 1] { return 0 }
        let i = spanIndex(y)
        let h = knotY[i + 1] - knotY[i]
        let t = (y - knotY[i]) / h
        let t2 = t * t
        let h00p = 6 * t2 - 6 * t
        let h10p = 3 * t2 - 4 * t + 1
        let h01p = -6 * t2 + 6 * t
        let h11p = 3 * t2 - 2 * t
        return (h00p * knotValue[i] + h01p * knotValue[i + 1]) / h
            + h10p * slope[i] + h11p * slope[i + 1]
    }

    /// Last span whose lower knot is <= y; y at exactly the final knot lands
    /// on the last span with t = 1, so knots evaluate to their values exactly.
    private func spanIndex(_ y: Double) -> Int {
        for i in 0..<(knotY.count - 1) where y < knotY[i + 1] { return i }
        return knotY.count - 2
    }
}

// MARK: - Knot constants

/// The synthetic-knot table: where the loft has structure the seven stations
/// do not describe. Every value here is an anthropometric stand-in — plausible
/// proportions, measured on nobody — which is why every ring they produce is
/// `RingProvenance.schematic`, never `.estimated`: "estimated" would imply a
/// number a scan could have produced, and no scan site exists at these heights.
enum BodyMeshKnots {
    /// Torso bottom knot; carries the hip girth (no tape is taken at a crotch).
    static let crotchFraction = 0.47
    /// Cap-fan apex under the torso, closing it below the crotch ring.
    static let crotchApexFraction = 0.44
    /// Skull maximum; girth is `headMaxToNeckRatio` × the neck girth.
    static let headMaxFraction = 0.94
    /// Last head ring; girth is `crownToHeadMaxRatio` × the skull maximum.
    static let crownRingFraction = 0.99
    /// Crown apex vertex — the top of the model, y = stature exactly.
    static let crownApexFraction = 1.00
    /// Leg tube top knot; carries the thigh girth so the tube meets the torso
    /// at full thickness. Its ring is open — hidden inside the body.
    static let legTopFraction = 0.47
    /// Ankle knot; girth is `ankleToCalfRatio` × the calf girth.
    static let ankleFraction = 0.06
    /// Foot cap apex, closing each leg below the ankle.
    static let footApexFraction = 0.02
    /// Arm tube top knot; girth is `armUpperGirthFraction` × stature.
    static let armTopFraction = 0.80
    /// Elbow knot; girth is `armElbowGirthFraction` × stature.
    static let elbowFraction = 0.63
    /// Wrist knot; girth is `armWristGirthFraction` × stature.
    static let wristFraction = 0.46
    /// Hand cap apex, closing each arm below the wrist.
    static let handApexFraction = 0.42
    /// Skull maximum over neck girth — heads are wider than necks.
    static let headMaxToNeckRatio = 1.5
    /// Crown ring over skull maximum: a small ring then a fan, which rounds
    /// the top; a fan straight off the skull maximum would draw a cone head.
    static let crownToHeadMaxRatio = 0.25
    /// Ankle over calf girth — the taper of a lower leg.
    static let ankleToCalfRatio = 0.62
    /// Upper-arm girth as a fraction of stature, in the same
    /// girth-to-stature convention `estimatedGirths` uses for real stations.
    static let armUpperGirthFraction = 0.185
    /// Elbow girth as a fraction of stature.
    static let armElbowGirthFraction = 0.14
    /// Wrist girth as a fraction of stature.
    static let armWristGirthFraction = 0.095
    /// Arms drift outward going down (10°), clearing the torso so the tubes
    /// read as separate limbs at every realistic hip/waist ratio.
    static let armAbductionRadians = Double.pi / 18
}

/// One knot of a loft chain: a height, a ring scale, and — where the knot
/// realises a station — which one. `station == nil` IS the definition of a
/// synthetic knot; provenance rule 1 keys off exactly this.
private struct MeshKnot {
    let y: Double
    /// Ring scale s: the semi-major axis in metres (the unit ring's semi-major
    /// is 1). Circumference is `s × unit perimeter`, always.
    let scale: Double
    let station: BodyStation?
}

/// A ring fully decided but not yet placed: geometry pass A output.
private struct MeshRingSpec {
    let y: Double
    let scale: Double
    let circumference: Double
    /// d(scale)/dy — the loft slope that tilts the analytic normal.
    let slope: Double
    let provenance: RingProvenance
    let station: BodyStation?
}

// MARK: - Builder

public enum BodyMeshBuilder {

    /// Total and deterministic: any `BodyModelParameters` that exists meshes
    /// (`build()` guards height > 0.5 m; `project()` floors girths at 1 cm).
    /// Equal (parameters, configuration) → bitwise-identical arrays.
    /// `parameters.date` is ignored — it must not leak into geometry.
    /// All generation arithmetic is `Double`; `Float32` only at emission.
    ///
    /// ## Deliberate refusal: no side channel for extra girths
    ///
    /// There is no `LimbGirths`-style parameter carrying a girth around
    /// `BodyModelParameters`. A girth the model layer never sees is invisible
    /// to `interpolate()` and `project()`: it would freeze mid-scrub carrying
    /// a stale `isMeasured` flag — modelled-dressed-as-measured in the API
    /// surface. The only honest upgrade path for arms is promoting `upperArm`
    /// to a `BodyStation` with its own heightFraction / site /
    /// massResponsiveness rows.
    ///
    /// ## Totality floors (hand-assembled models only)
    ///
    /// `BodyModelParameters.init` does not guard height or fill missing
    /// stations, so a hand-assembled model can arrive with a degenerate
    /// stature or a station absent. Stature is floored at 0.5 m (below it the
    /// knot heights collapse onto one plane) and a missing or sub-centimetre
    /// girth is floored at 1 cm, mirroring `project()`'s own floor. `build()`
    /// never produces either case; refusing to mesh would only push a guard
    /// into the renderer, which is the one place it cannot be tested.
    ///
    /// ## Closed-form output counts
    ///
    /// With R = effective ringsPerSpan, N = effective ringVertexCount,
    /// A = includesArms ? 1 : 0:
    ///
    ///     rings     = 16 + 13R + A(6 + 4R)
    ///     vertices  = N·rings + 4 + 2A
    ///     strips    = (R+1)(13 + 4A)
    ///     triangles = 2N·strips + N(4 + 2A)
    ///
    /// The counts test pins these formulas, and pins three evaluated triples
    /// so the formulas cannot drift in step with the code.
    public static func mesh(for parameters: BodyModelParameters,
                            configuration: BodyMeshConfiguration = .default) -> BodyMesh {
        let n = configuration.effectiveRingVertexCount
        let interiorsPerSpan = configuration.effectiveRingsPerSpan
        let includesArms = configuration.includesArms
        let aspect = BodyMeshConfiguration.crossSectionAspect
        // Totality floor — see the doc comment. `build()` already guards
        // heightMetres > 0.5, so this only catches hand-assembled models.
        let height = Swift.max(parameters.heightMetres, 0.5)

        // -- Unit cross-section -------------------------------------------
        // N vertices of the ellipse (cos θ, aspect·sin θ). The unit polygon
        // perimeter is computed, never hard-coded (≈ 5.44 at N = 48): a ring
        // of circumference C scales this polygon by C / unitPerimeter, and
        // uniform scaling multiplies a polyline length exactly linearly — so
        // the emitted polygon's perimeter IS the girth, to floating point.
        var unitX = [Double](repeating: 0, count: n)
        var unitZ = [Double](repeating: 0, count: n)
        for k in 0..<n {
            let theta = 2 * Double.pi * Double(k) / Double(n)
            unitX[k] = cos(theta)
            unitZ[k] = aspect * sin(theta)
        }
        var unitPerimeter = 0.0
        for k in 0..<n {
            let next = (k + 1) % n
            let dx = unitX[next] - unitX[k]
            let dz = unitZ[next] - unitZ[k]
            unitPerimeter += (dx * dx + dz * dz).squareRoot()
        }

        // -- Station values ------------------------------------------------
        var girthByStation: [BodyStation: Double] = [:]
        var measuredByStation: [BodyStation: Bool] = [:]
        for value in parameters.stations {
            girthByStation[value.station] = value.circumferenceCentimetres
            measuredByStation[value.station] = value.isMeasured
        }
        // 1 cm floor, mirroring project(); the `?? 1` is the missing-station
        // totality case, flagged unmeasured below.
        func girthCentimetres(_ station: BodyStation) -> Double {
            Swift.max(girthByStation[station] ?? 1, 1)
        }
        let isMeasured: (BodyStation) -> Bool = { measuredByStation[$0] ?? false }

        func stationKnot(_ station: BodyStation) -> MeshKnot {
            MeshKnot(y: station.heightFraction * height,
                     scale: girthCentimetres(station) / 100 / unitPerimeter,
                     station: station)
        }

        // -- The shoulder: a breadth, not a girth --------------------------
        // `BodyStation.site` maps shoulder to `.shoulderWidth`; the stored
        // value (~45 cm estimated at 1.75 m) is a WIDTH. Fed through the
        // circumference pipeline it would draw shoulders narrower than the
        // waist. Decided: treat it as the width it is — the ring's semi-major
        // axis is value/200 metres (half the breadth), and the torso loft's
        // shoulder knot value is the equivalent perimeter that ring actually
        // has, so C(y) stays self-consistent and the no-overshoot bounds stay
        // meaningful on the chest→shoulder and shoulder→neck spans. Sanity:
        // estimated 45 cm breadth → 22.5 cm half-width vs ≈17.7 cm chest
        // semi-major at 96 cm girth — shoulders render wider than the chest,
        // which is anatomically right. `Ring.circumferenceMetres` at the
        // shoulder is the true polygon perimeter; the LABEL prints the
        // breadth verbatim. Deciding this silently is how the first device
        // report would have been misdiagnosed, hence the paragraph.
        let shoulderKnot = MeshKnot(y: BodyStation.shoulder.heightFraction * height,
                                    scale: girthCentimetres(.shoulder) / 200,
                                    station: .shoulder)

        // -- Chains --------------------------------------------------------
        let hipScale = girthCentimetres(.hip) / 100 / unitPerimeter
        let torsoKnots: [MeshKnot] = [
            MeshKnot(y: BodyMeshKnots.crotchFraction * height, scale: hipScale, station: nil),
            stationKnot(.hip),
            stationKnot(.waist),
            stationKnot(.chest),
            shoulderKnot,
            stationKnot(.neck)
        ]

        let neckCircumference = girthCentimetres(.neck) / 100
        let headMaxCircumference = BodyMeshKnots.headMaxToNeckRatio * neckCircumference
        let crownCircumference = BodyMeshKnots.crownToHeadMaxRatio * headMaxCircumference
        // The neck knot anchors the head chain's curve, but its RING is owned
        // by the torso chain — the head chain suppresses it and the junction
        // strip stitches the two chains together.
        let headKnots: [MeshKnot] = [
            stationKnot(.neck),
            MeshKnot(y: BodyMeshKnots.headMaxFraction * height,
                     scale: headMaxCircumference / unitPerimeter, station: nil),
            MeshKnot(y: BodyMeshKnots.crownRingFraction * height,
                     scale: crownCircumference / unitPerimeter, station: nil)
        ]

        // Both legs share one knot list: the stored thigh/calf values are
        // already side-means, and drawing asymmetry would invent data.
        let thighScale = girthCentimetres(.thigh) / 100 / unitPerimeter
        let ankleCircumference = BodyMeshKnots.ankleToCalfRatio * girthCentimetres(.calf) / 100
        let legKnots: [MeshKnot] = [ // emission order: top → bottom
            MeshKnot(y: BodyMeshKnots.legTopFraction * height, scale: thighScale, station: nil),
            stationKnot(.thigh),
            stationKnot(.calf),
            MeshKnot(y: BodyMeshKnots.ankleFraction * height,
                     scale: ankleCircumference / unitPerimeter, station: nil)
        ]

        let armKnots: [MeshKnot] = [ // emission order: top → bottom
            MeshKnot(y: BodyMeshKnots.armTopFraction * height,
                     scale: BodyMeshKnots.armUpperGirthFraction * height / unitPerimeter,
                     station: nil),
            MeshKnot(y: BodyMeshKnots.elbowFraction * height,
                     scale: BodyMeshKnots.armElbowGirthFraction * height / unitPerimeter,
                     station: nil),
            MeshKnot(y: BodyMeshKnots.wristFraction * height,
                     scale: BodyMeshKnots.armWristGirthFraction * height / unitPerimeter,
                     station: nil)
        ]

        func lofting(_ knots: [MeshKnot]) -> MonotoneCubicCurve {
            let ascending = knots.sorted { $0.y < $1.y }
            // Knot heights are distinct fixed fractions of a floored stature,
            // so the failable init cannot fail here.
            return MonotoneCubicCurve(knots: ascending.map { (y: $0.y, value: $0.scale * unitPerimeter) })!
        }

        let torsoSpecs = chainRingSpecs(knots: torsoKnots, curve: lofting(torsoKnots),
                                        interiorsPerSpan: interiorsPerSpan,
                                        unitPerimeter: unitPerimeter,
                                        suppressFirstKnotRing: false, isMeasured: isMeasured)
        let headSpecs = chainRingSpecs(knots: headKnots, curve: lofting(headKnots),
                                       interiorsPerSpan: interiorsPerSpan,
                                       unitPerimeter: unitPerimeter,
                                       suppressFirstKnotRing: true, isMeasured: isMeasured)
        let legSpecs = chainRingSpecs(knots: legKnots, curve: lofting(legKnots),
                                      interiorsPerSpan: interiorsPerSpan,
                                      unitPerimeter: unitPerimeter,
                                      suppressFirstKnotRing: false, isMeasured: isMeasured)
        let armSpecs = includesArms
            ? chainRingSpecs(knots: armKnots, curve: lofting(armKnots),
                             interiorsPerSpan: interiorsPerSpan,
                             unitPerimeter: unitPerimeter,
                             suppressFirstKnotRing: false, isMeasured: isMeasured)
            : []

        // -- Placement -----------------------------------------------------
        // Legs sit at ±offsetX. The 1.02 clause keeps a tube strictly clear of
        // the centreline whatever the girths (min |x| >= 0.02 × the tube's own
        // largest radius); the 0.55 clause seats normal legs under the hip. An
        // extreme thigh pushes the legs outside the hip footprint — accepted,
        // and visible rather than self-intersecting.
        let legMaxScale = legSpecs.map { $0.scale }.max() ?? 0
        let legOffsetX = Swift.max(0.55 * hipScale, 1.02 * legMaxScale)

        // Arms hang from the shoulder breadth and drift outward with descent.
        // The tube deliberately overlaps the deltoid region — junctions are
        // unblended by design; a visible seam is acceptable in a wireframe.
        let armMaxScale = armSpecs.map { $0.scale }.max() ?? 0
        let armAttachX = Swift.max(shoulderKnot.scale, 1.05 * armMaxScale)
        let abductionSlope = tan(BodyMeshKnots.armAbductionRadians)
        func armCentreX(_ y: Double) -> Double {
            armAttachX + abductionSlope * (BodyMeshKnots.armTopFraction * height - y)
        }

        // -- Emission ------------------------------------------------------
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var rings: [BodyMesh.Ring] = []

        func emitRing(_ spec: MeshRingSpec, limb: BodyLimb, centreX: Double) {
            let start = vertices.count
            for k in 0..<n {
                vertices.append(SIMD3(Float(centreX + spec.scale * unitX[k]),
                                      Float(spec.y),
                                      Float(spec.scale * unitZ[k])))
                // Analytic normal: the ellipse's implicit-function gradient
                // (cos θ, sin θ / aspect), tilted by the loft slope. For legs
                // and arms the centre drift does not enter — rings are
                // horizontal, and the tilt is the radius change; the drift is
                // a placement, not a surface slope (a documented
                // simplification).
                let gradientX = unitX[k]
                let gradientZ = unitZ[k] / (aspect * aspect)
                let gradientLength = (gradientX * gradientX + gradientZ * gradientZ).squareRoot()
                let dx = gradientX / gradientLength
                let dz = gradientZ / gradientLength
                let ny = -spec.slope
                let length = (dx * dx + ny * ny + dz * dz).squareRoot()
                normals.append(SIMD3(Float(dx / length), Float(ny / length), Float(dz / length)))
            }
            rings.append(BodyMesh.Ring(heightMetres: spec.y, provenance: spec.provenance,
                                       vertexRange: start..<(start + n),
                                       station: spec.station, limb: limb,
                                       circumferenceMetres: spec.circumference))
        }

        // Fixed emission order — the renderer never sorts (see BodyMesh.rings).
        let torsoStart = rings.count
        for spec in torsoSpecs { emitRing(spec, limb: .torso, centreX: 0) }
        let torsoRange = torsoStart..<rings.count

        let headStart = rings.count
        for spec in headSpecs { emitRing(spec, limb: .head, centreX: 0) }
        let headRange = headStart..<rings.count

        // The model's LEFT is at +x (the mesh faces the viewer).
        let leftLegStart = rings.count
        for spec in legSpecs { emitRing(spec, limb: .leftLeg, centreX: legOffsetX) }
        let leftLegRange = leftLegStart..<rings.count

        let rightLegStart = rings.count
        for spec in legSpecs { emitRing(spec, limb: .rightLeg, centreX: -legOffsetX) }
        let rightLegRange = rightLegStart..<rings.count

        let leftArmStart = rings.count
        for spec in armSpecs { emitRing(spec, limb: .leftArm, centreX: armCentreX(spec.y)) }
        let leftArmRange = leftArmStart..<rings.count

        let rightArmStart = rings.count
        for spec in armSpecs { emitRing(spec, limb: .rightArm, centreX: -armCentreX(spec.y)) }
        let rightArmRange = rightArmStart..<rings.count

        // -- Apexes (after all ring vertices, fixed order) -----------------
        let crotchApex = vertices.count
        vertices.append(SIMD3(0, Float(BodyMeshKnots.crotchApexFraction * height), 0))
        normals.append(SIMD3(0, -1, 0))
        let crownApex = vertices.count
        vertices.append(SIMD3(0, Float(BodyMeshKnots.crownApexFraction * height), 0))
        normals.append(SIMD3(0, 1, 0))
        let leftFootApex = vertices.count
        vertices.append(SIMD3(Float(legOffsetX), Float(BodyMeshKnots.footApexFraction * height), 0))
        normals.append(SIMD3(0, -1, 0))
        let rightFootApex = vertices.count
        vertices.append(SIMD3(Float(-legOffsetX), Float(BodyMeshKnots.footApexFraction * height), 0))
        normals.append(SIMD3(0, -1, 0))
        var leftHandApex = -1
        var rightHandApex = -1
        if includesArms {
            // The hand apex continues the abduction line below the wrist —
            // "tan(10°) × 0.04H outward" of the wrist-height centre.
            let handX = armCentreX(BodyMeshKnots.handApexFraction * height)
            leftHandApex = vertices.count
            vertices.append(SIMD3(Float(handX), Float(BodyMeshKnots.handApexFraction * height), 0))
            normals.append(SIMD3(0, -1, 0))
            rightHandApex = vertices.count
            vertices.append(SIMD3(Float(-handX), Float(BodyMeshKnots.handApexFraction * height), 0))
            normals.append(SIMD3(0, -1, 0))
        }

        // -- Triangles -----------------------------------------------------
        var measuredTriangles: [UInt32] = []
        var estimatedTriangles: [UInt32] = []

        func appendTriangle(_ i0: Int, _ i1: Int, _ i2: Int, toMeasured: Bool) {
            if toMeasured {
                measuredTriangles.append(UInt32(i0))
                measuredTriangles.append(UInt32(i1))
                measuredTriangles.append(UInt32(i2))
            } else {
                estimatedTriangles.append(UInt32(i0))
                estimatedTriangles.append(UInt32(i1))
                estimatedTriangles.append(UInt32(i2))
            }
        }

        // One strip of 2N faces between two rings. Faces are wound CCW viewed
        // from outside. The spec's L/U pattern assumed the lower-emission ring
        // is the physically lower one, which is false for the top→down leg and
        // arm chains; canonicalising on the physically-lower ring applies the
        // authorised index swap exactly where the winding test demands it.
        // A face lands in `measuredTriangles` only when BOTH rings are
        // `.measured` — the both-ends rule at face granularity.
        func appendStrip(_ ringIndexA: Int, _ ringIndexB: Int) {
            let ringA = rings[ringIndexA]
            let ringB = rings[ringIndexB]
            let (bottom, top) = ringA.heightMetres <= ringB.heightMetres
                ? (ringA, ringB) : (ringB, ringA)
            let toMeasured = ringA.provenance == .measured && ringB.provenance == .measured
            let b0 = bottom.vertexRange.lowerBound
            let t0 = top.vertexRange.lowerBound
            for k in 0..<n {
                let kn = (k + 1) % n
                appendTriangle(b0 + k, t0 + k, b0 + kn, toMeasured: toMeasured)
                appendTriangle(b0 + kn, t0 + k, t0 + kn, toMeasured: toMeasured)
            }
        }

        // A fan of N faces closing a chain's terminal ring on an apex. Always
        // estimated: an apex is schematic by construction. Winding flips with
        // which side the apex sits on so faces stay outward.
        func appendFan(apex: Int, ringIndex: Int, apexIsBelow: Bool) {
            let base = rings[ringIndex].vertexRange.lowerBound
            for k in 0..<n {
                let kn = (k + 1) % n
                if apexIsBelow {
                    appendTriangle(apex, base + k, base + kn, toMeasured: false)
                } else {
                    appendTriangle(apex, base + kn, base + k, toMeasured: false)
                }
            }
        }

        func appendChainStrips(_ range: Range<Int>) {
            guard range.count > 1 else { return }
            for i in range.dropLast() { appendStrip(i, i + 1) }
        }

        appendChainStrips(torsoRange)
        // Junction: torso's neck ring to the head chain's first ring.
        appendStrip(torsoRange.upperBound - 1, headRange.lowerBound)
        appendChainStrips(headRange)
        appendChainStrips(leftLegRange)
        appendChainStrips(rightLegRange)
        appendChainStrips(leftArmRange)
        appendChainStrips(rightArmRange)

        appendFan(apex: crotchApex, ringIndex: torsoRange.lowerBound, apexIsBelow: true)
        appendFan(apex: crownApex, ringIndex: headRange.upperBound - 1, apexIsBelow: false)
        appendFan(apex: leftFootApex, ringIndex: leftLegRange.upperBound - 1, apexIsBelow: true)
        appendFan(apex: rightFootApex, ringIndex: rightLegRange.upperBound - 1, apexIsBelow: true)
        if includesArms {
            appendFan(apex: leftHandApex, ringIndex: leftArmRange.upperBound - 1, apexIsBelow: true)
            appendFan(apex: rightHandApex, ringIndex: rightArmRange.upperBound - 1, apexIsBelow: true)
        }
        // The leg-top and arm-top rings stay open (hidden inside the body):
        // their ring edges belong to exactly one face, which the manifold test
        // permits as a boundary.

        // -- Anchors -------------------------------------------------------
        // Exactly 7, BodyStation.allCases order. Thigh and calf anchor the
        // LEFT (+x) leg. `position` is bitwise the anchored vertex.
        var labelAnchors: [BodyMesh.LabelAnchor] = []
        for station in BodyStation.allCases {
            let limb: BodyLimb = (station == .thigh || station == .calf) ? .leftLeg : .torso
            // Every chain emits its station knot rings, so this cannot miss.
            let ringIndex = rings.firstIndex { $0.station == station && $0.limb == limb }!
            let vertexIndex = rings[ringIndex].vertexRange.lowerBound
            labelAnchors.append(BodyMesh.LabelAnchor(
                station: station,
                position: vertices[vertexIndex],
                ringIndex: ringIndex,
                vertexIndex: vertexIndex,
                isMeasured: isMeasured(station),
                valueCentimetres: girthCentimetres(station)))
        }

        return BodyMesh(vertices: vertices,
                        normals: normals,
                        measuredTriangles: measuredTriangles,
                        estimatedTriangles: estimatedTriangles,
                        rings: rings,
                        labelAnchors: labelAnchors,
                        isWhollyEstimated: parameters.isWhollyEstimated)
    }

    // MARK: - Provenance (the ONE deciding function)

    /// Ring provenance is decided here and nowhere else. Rules, in priority
    /// order:
    ///
    /// 1. A synthetic knot's ring, and any interior ring on a span with at
    ///    least one synthetic knot, is `.schematic` — head, arms, the crotch
    ///    ring and crotch→hip interiors, the leg-top ring and legTop→thigh
    ///    interiors, the ankle ring and calf→ankle interiors.
    /// 2. A station knot's ring is `.measured` iff its
    ///    `BodyStationValue.isMeasured`, else `.estimated`. (A station ring
    ///    bordering a schematic span keeps its own provenance — the tape was
    ///    really at the neck even though the head above it is schematic.)
    /// 3. An interior ring between two adjacent stations is `.measured` iff
    ///    BOTH bounding stations are measured — the both-ends rule
    ///    `interpolate()` already enforces temporally, applied vertically.
    ///    The stricter all-interiors-estimated reading was considered and
    ///    rejected: it renders a fully-taped body almost entirely
    ///    estimated-hued, which is the wrong message on screen.
    ///
    /// The dangerous direction is promotion (drawing a guess as a fact); the
    /// reverse is merely conservative. Because `project()` marks every station
    /// unmeasured and `interpolate()` never upgrades a flag, a projected model
    /// arrives here already-estimated and the mesh goes wholly estimated-hued
    /// with zero renderer cooperation — the rule lives where it is tested.
    static func ringProvenance(stationKnot: BodyStation?,
                               interiorSpan: (lower: BodyStation?, upper: BodyStation?)?,
                               isMeasured: (BodyStation) -> Bool) -> RingProvenance {
        if let interiorSpan {
            guard let lower = interiorSpan.lower, let upper = interiorSpan.upper else {
                return .schematic // rule 1: a synthetic knot taints its span
            }
            return isMeasured(lower) && isMeasured(upper) ? .measured : .estimated // rule 3
        }
        guard let stationKnot else { return .schematic } // rule 1: synthetic knot ring
        return isMeasured(stationKnot) ? .measured : .estimated // rule 2
    }

    // MARK: - Chain pass A

    /// Rings for one chain, in emission order: each knot's ring (station
    /// girths pinned, never read back off the curve — so a station ring's
    /// circumference is the girth to the last bit, not to interpolation
    /// error), with `interiorsPerSpan` uniformly spaced interior rings between
    /// adjacent knots, lofted along the monotone curve.
    private static func chainRingSpecs(knots: [MeshKnot], curve: MonotoneCubicCurve,
                                       interiorsPerSpan: Int, unitPerimeter: Double,
                                       suppressFirstKnotRing: Bool,
                                       isMeasured: (BodyStation) -> Bool) -> [MeshRingSpec] {
        var specs: [MeshRingSpec] = []
        for index in knots.indices {
            let knot = knots[index]
            if !(index == 0 && suppressFirstKnotRing) {
                specs.append(MeshRingSpec(
                    y: knot.y,
                    scale: knot.scale,
                    circumference: knot.scale * unitPerimeter,
                    slope: curve.derivative(at: knot.y) / unitPerimeter,
                    provenance: ringProvenance(stationKnot: knot.station, interiorSpan: nil,
                                               isMeasured: isMeasured),
                    station: knot.station))
            }
            guard index + 1 < knots.count else { continue }
            let nextKnot = knots[index + 1]
            for step in 1...interiorsPerSpan {
                let fraction = Double(step) / Double(interiorsPerSpan + 1)
                let y = knot.y + (nextKnot.y - knot.y) * fraction
                let scale = curve.value(at: y) / unitPerimeter
                specs.append(MeshRingSpec(
                    y: y,
                    scale: scale,
                    circumference: scale * unitPerimeter,
                    slope: curve.derivative(at: y) / unitPerimeter,
                    provenance: ringProvenance(stationKnot: nil,
                                               interiorSpan: (knot.station, nextKnot.station),
                                               isMeasured: isMeasured),
                    station: nil))
            }
        }
        return specs
    }
}
