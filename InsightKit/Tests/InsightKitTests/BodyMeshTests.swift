import XCTest
@testable import InsightKit

/// The wireframe body mesh: perimeter-true rings, monotone lofting, hard
/// provenance partition.
///
/// The mesh is the renderer's input, and the renderer lives in the app target
/// where nothing can be tested — so every property the drawing depends on is
/// pinned HERE (add-chart §5): the drawn ring's perimeter IS the girth, the
/// loft never overshoots a measured value, and provenance is never laundered.
/// All dates are pinned; `Date()` never appears (a mesh must not depend on
/// when it was built, and test 3 proves it).
final class BodyMeshTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_785_000_000)

    // MARK: - Builders (each test states only what it varies)

    private func fullMeasurements(neck: Double = 38, shoulder: Double = 45,
                                  chest: Double = 96, waist: Double = 92,
                                  hip: Double = 98, thigh: Double = 55,
                                  calf: Double = 37) -> BodyMeasurements {
        BodyMeasurements([
            .init(site: .neck, centimetres: neck),
            .init(site: .shoulderWidth, centimetres: shoulder),
            .init(site: .chest, centimetres: chest),
            .init(site: .waist, centimetres: waist),
            .init(site: .hip, centimetres: hip),
            .init(site: .thigh, side: .left, centimetres: thigh),
            .init(site: .calf, side: .left, centimetres: calf)
        ])
    }

    private func params(waist: Double = 92, neck: Double = 38, shoulder: Double = 45,
                        chest: Double = 96, hip: Double = 98, thigh: Double = 55,
                        calf: Double = 37, measured: Bool = true,
                        heightMetres: Double = 1.75, weightKg: Double = 80,
                        sex: BiologicalSex = .male,
                        at when: Date? = nil) -> BodyModelParameters {
        BodyModelParameters.build(
            heightMetres: heightMetres, weightKg: weightKg, bodyFatPercentage: 22,
            sex: sex,
            measurements: measured
                ? fullMeasurements(neck: neck, shoulder: shoulder, chest: chest,
                                   waist: waist, hip: hip, thigh: thigh, calf: calf)
                : nil,
            date: when ?? day)!
    }

    /// Waist and hip taped, everything else estimated — the state a real
    /// partial scan leaves the model in.
    private func partiallyMeasured() -> BodyModelParameters {
        BodyModelParameters.build(
            heightMetres: 1.75, weightKg: 80, bodyFatPercentage: 22, sex: .male,
            measurements: BodyMeasurements([.init(site: .waist, centimetres: 92),
                                            .init(site: .hip, centimetres: 98)]),
            date: day)!
    }

    private func velocity(kgPerWeek: Double, weight: Double = 80,
                          residual: Double = 0.4) -> CompositionVelocity {
        CompositionVelocity(windowDays: 90, kilogramsPerWeek: kgPerWeek,
                            percentPerWeek: kgPerWeek / weight * 100,
                            leanKilogramsPerWeek: nil, leanShareOfChange: nil,
                            residualSD: residual, weighIns: 30, latestWeight: weight)
    }

    /// A projection extreme enough that `project()`'s 1 cm floor catches every
    /// station — the smallest girths the pipeline can ever be handed.
    private func flooredProjection() -> BodyModelParameters {
        BodyModelParameters.project(params(), velocity: velocity(kgPerWeek: -80), weeks: 10)!
    }

    // MARK: - Geometry helpers

    private struct V3 {
        let x: Double
        let y: Double
        let z: Double
        init(_ v: SIMD3<Float>) { x = Double(v.x); y = Double(v.y); z = Double(v.z) }
        init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
        static func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        func dot(_ o: V3) -> Double { x * o.x + y * o.y + z * o.z }
        func cross(_ o: V3) -> V3 {
            V3(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
        }
        var length: Double { dot(self).squareRoot() }
    }

    /// Closed polyline length of a ring, from the EMITTED Float32 vertices —
    /// the tripwire against generation arithmetic drifting into Float.
    private func ringPerimeterMetres(_ ring: BodyMesh.Ring, in mesh: BodyMesh) -> Double {
        var total = 0.0
        for k in ring.vertexRange {
            let next = k + 1 == ring.vertexRange.upperBound ? ring.vertexRange.lowerBound : k + 1
            total += (V3(mesh.vertices[next]) - V3(mesh.vertices[k])).length
        }
        return total
    }

    /// Mirrors the builder's unit-perimeter loop operation for operation, so
    /// the expected value rounds identically.
    private func unitPerimeter(vertexCount n: Int) -> Double {
        let aspect = BodyMeshConfiguration.crossSectionAspect
        var unitX = [Double](repeating: 0, count: n)
        var unitZ = [Double](repeating: 0, count: n)
        for k in 0..<n {
            let theta = 2 * Double.pi * Double(k) / Double(n)
            unitX[k] = cos(theta)
            unitZ[k] = aspect * sin(theta)
        }
        var total = 0.0
        for k in 0..<n {
            let next = (k + 1) % n
            let dx = unitX[next] - unitX[k]
            let dz = unitZ[next] - unitZ[k]
            total += (dx * dx + dz * dz).squareRoot()
        }
        return total
    }

    private func stationRings(_ mesh: BodyMesh, _ station: BodyStation) -> [BodyMesh.Ring] {
        mesh.rings.filter { $0.station == station }
    }

    private func forEachFace(of lists: [[UInt32]], _ body: (Int, Int, Int) -> Void) {
        for list in lists {
            var i = 0
            while i < list.count {
                body(Int(list[i]), Int(list[i + 1]), Int(list[i + 2]))
                i += 3
            }
        }
    }

    private func faceKeys(_ list: [UInt32]) -> Set<UInt64> {
        var keys = Set<UInt64>()
        keys.reserveCapacity(list.count / 3)
        var i = 0
        while i < list.count {
            keys.insert(UInt64(list[i]) << 42 | UInt64(list[i + 1]) << 21 | UInt64(list[i + 2]))
            i += 3
        }
        return keys
    }

    private func expectedCounts(n: Int, r: Int, arms: Bool)
        -> (rings: Int, vertices: Int, triangles: Int, indices: Int) {
        let armFactor = arms ? 1 : 0
        let rings = 16 + 13 * r + armFactor * (6 + 4 * r)
        let vertices = n * rings + 4 + 2 * armFactor
        let strips = (r + 1) * (13 + 4 * armFactor)
        let triangles = 2 * n * strips + n * (4 + 2 * armFactor)
        return (rings, vertices, triangles, 3 * triangles)
    }

    // MARK: - 1. Perimeter fidelity

    /// **The drawn ring IS the girth.** The label says "waist 92 cm" and the
    /// polygon the reader orbits must have exactly that perimeter — asserted
    /// on the emitted Float32 vertices, which is the tripwire against
    /// generation arithmetic quietly moving into Float. Swept across measured,
    /// wholly-estimated (both sexes), floor-projected and extreme inputs, and
    /// across tessellation densities, because a perimeter identity that only
    /// holds at the default N is a coincidence, not a construction.
    func testStationCircumferenceExactOnEmittedFloats() {
        let cases: [(name: String, model: BodyModelParameters)] = [
            (name: "measured", model: params()),
            (name: "estimated male", model: params(measured: false, sex: .male)),
            (name: "estimated female", model: params(measured: false, sex: .female)),
            (name: "projected 1 cm floor", model: flooredProjection()),
            (name: "waist 200", model: params(waist: 200))
        ]
        for testCase in cases {
            for n in [8, 24, 48, 96] {
                let mesh = BodyMeshBuilder.mesh(
                    for: testCase.model,
                    configuration: BodyMeshConfiguration(ringVertexCount: n, ringsPerSpan: 2))
                for station in BodyStation.allCases where station != .shoulder {
                    let expected = testCase.model.girth(station)!
                    let rings = stationRings(mesh, station)
                    // Thigh and calf realise on BOTH legs; torso stations once.
                    XCTAssertEqual(rings.count,
                                   station == .thigh || station == .calf ? 2 : 1,
                                   "\(testCase.name) n=\(n) \(station)")
                    for ring in rings {
                        let perimeterCm = ringPerimeterMetres(ring, in: mesh) * 100
                        XCTAssertEqual(perimeterCm, expected, accuracy: expected * 1e-4,
                                       "\(testCase.name) n=\(n) \(station)")
                    }
                }
            }
        }
    }

    // MARK: - 2. Shoulder is a breadth

    /// **shoulderWidth is a breadth, not a girth.** Fed through the
    /// circumference pipeline it would draw shoulders narrower than the waist;
    /// the decided mapping makes the ring's WIDTH the stored value, and the
    /// loft carries the ring's equivalent perimeter. Deciding this silently is
    /// how the first device report would have been misdiagnosed — hence a test
    /// that names the decision.
    func testShoulderRingWidthEqualsStoredBreadth() throws {
        for model in [params(), params(measured: false)] {
            let mesh = BodyMeshBuilder.mesh(for: model)
            let ring = try XCTUnwrap(stationRings(mesh, .shoulder).first)
            let breadthMetres = model.girth(.shoulder)! / 100
            var minX = Double.infinity
            var maxX = -Double.infinity
            for k in ring.vertexRange {
                minX = min(minX, Double(mesh.vertices[k].x))
                maxX = max(maxX, Double(mesh.vertices[k].x))
            }
            XCTAssertEqual(maxX - minX, breadthMetres, accuracy: breadthMetres * 1e-4)
            let expectedPerimeter = model.girth(.shoulder)! / 200 * unitPerimeter(vertexCount: 48)
            XCTAssertEqual(ring.circumferenceMetres, expectedPerimeter,
                           accuracy: expectedPerimeter * 1e-9)
        }
    }

    // MARK: - 3. Determinism

    /// Equal inputs → bitwise-equal meshes, and the date must not leak into
    /// geometry: a scrubber rebuilds the mesh every frame from interpolated
    /// parameters whose date moves, and a date-dependent vertex would make the
    /// body wobble on a still scrub.
    func testDeterminismAndDateInsensitivity() {
        XCTAssertEqual(BodyMeshBuilder.mesh(for: params()), BodyMeshBuilder.mesh(for: params()))
        let later = params(at: day.addingTimeInterval(40 * 24 * 3600))
        XCTAssertEqual(BodyMeshBuilder.mesh(for: params()), BodyMeshBuilder.mesh(for: later))
    }

    // MARK: - 4. Indices, winding, manifold

    /// The renderer feeds these arrays straight to the GPU, which validates
    /// nothing: an out-of-range index is a crash on device only, a flipped
    /// face is an invisible patch under backface culling (the invisible-cards
    /// defect class), and an over-shared edge is a rendering artefact no CI
    /// run can see. Face normals are checked against the analytic vertex
    /// normals, which makes the winding test authoritative. Boundary edges at
    /// the open leg-top/arm-top rings appear once, which is allowed — this is
    /// a manifold-edge check, not a self-intersection check, and it does not
    /// pretend to be one.
    func testIndexValidityWindingAndManifold() {
        let configurations = [
            BodyMeshConfiguration(ringVertexCount: 8, ringsPerSpan: 1),
            BodyMeshConfiguration(ringVertexCount: 8, ringsPerSpan: 1, includesArms: false),
            BodyMeshConfiguration.default
        ]
        for configuration in configurations {
            let mesh = BodyMeshBuilder.mesh(for: params(), configuration: configuration)
            let lists = [mesh.measuredTriangles, mesh.estimatedTriangles]
            let counts = expectedCounts(n: configuration.effectiveRingVertexCount,
                                        r: configuration.effectiveRingsPerSpan,
                                        arms: configuration.includesArms)

            // Index validity, in one assert per list rather than 45k.
            for list in lists {
                XCTAssertEqual(list.count % 3, 0)
                XCTAssertLessThan(Int(list.max() ?? 0), mesh.vertices.count)
            }

            // Disjoint partition covering the closed-form face count.
            let measuredKeys = faceKeys(mesh.measuredTriangles)
            let estimatedKeys = faceKeys(mesh.estimatedTriangles)
            XCTAssertEqual(measuredKeys.count, mesh.measuredTriangles.count / 3,
                           "duplicate face inside the measured list")
            XCTAssertEqual(estimatedKeys.count, mesh.estimatedTriangles.count / 3,
                           "duplicate face inside the estimated list")
            XCTAssertTrue(measuredKeys.isDisjoint(with: estimatedKeys))
            XCTAssertEqual(measuredKeys.count + estimatedKeys.count, counts.triangles)

            // Winding: CCW seen from outside — the face normal must agree
            // with the mean analytic vertex normal.
            var badWinding = 0
            var referenced = [Bool](repeating: false, count: mesh.vertices.count)
            var edgeUse: [UInt64: Int] = [:]
            forEachFace(of: lists) { a, b, c in
                referenced[a] = true
                referenced[b] = true
                referenced[c] = true
                let va = V3(mesh.vertices[a])
                let faceNormal = (V3(mesh.vertices[b]) - va).cross(V3(mesh.vertices[c]) - va)
                let meanNormal = V3(mesh.normals[a]) + V3(mesh.normals[b]) + V3(mesh.normals[c])
                if faceNormal.dot(meanNormal) <= 0 { badWinding += 1 }
                for edge in [(a, b), (b, c), (c, a)] {
                    let lo = UInt64(min(edge.0, edge.1))
                    let hi = UInt64(max(edge.0, edge.1))
                    edgeUse[lo << 32 | hi, default: 0] += 1
                }
            }
            XCTAssertEqual(badWinding, 0, "faces wound away from their analytic normals")
            XCTAssertLessThanOrEqual(edgeUse.values.max() ?? 0, 2,
                                     "an edge is shared by more than two faces")
            for ring in mesh.rings {
                for k in ring.vertexRange where !referenced[k] {
                    XCTFail("ring vertex \(k) is referenced by no face")
                }
            }
        }
    }

    // MARK: - 5. Normals

    /// Analytic, unit, outward, finite — including at the 1 cm projection
    /// floor, where an accumulated (cross-product) normal scheme degenerates
    /// first. Outwardness is measured against the ring's own centre,
    /// reconstructed as the vertex mean so the test needs no private offsets.
    ///
    /// Unit + outward alone was NOT enough: on 2026-08-04 a canary zeroing the
    /// loft-slope tilt (`ny = -spec.slope` → `0` in `emitRing`) passed all 13
    /// tests — normalize keeps a zero-tilt normal unit, the horizontal
    /// component keeps the outward dot positive, and the winding test compares
    /// faces against these same normals, so consistency masqueraded as
    /// correctness. The tilt section below pins the spec §4.5 normal
    /// (n = normalize(d − s'(y)·(0,1,0))) by sign per span and by magnitude
    /// against a central finite difference of the EMITTED ring scales — which
    /// transitively pins `MonotoneCubicCurve.derivative(at:)` on non-flat
    /// spans, a path no other test reaches (the direct curve test only asserts
    /// derivatives that are zero).
    func testNormalsUnitOutwardFinite() {
        for model in [params(), flooredProjection()] {
            let mesh = BodyMeshBuilder.mesh(for: model)
            var nonFinite = 0
            for k in mesh.vertices.indices {
                let v = mesh.vertices[k]
                let nrm = mesh.normals[k]
                if !(v.x.isFinite && v.y.isFinite && v.z.isFinite) { nonFinite += 1 }
                if !(nrm.x.isFinite && nrm.y.isFinite && nrm.z.isFinite) { nonFinite += 1 }
            }
            XCTAssertEqual(nonFinite, 0)
            XCTAssertEqual(mesh.normals.count, mesh.vertices.count)

            var badLength = 0
            var inward = 0
            for ring in mesh.rings {
                var centre = V3(x: 0, y: 0, z: 0)
                for k in ring.vertexRange { centre = centre + V3(mesh.vertices[k]) }
                let count = Double(ring.vertexRange.count)
                centre = V3(x: centre.x / count, y: centre.y / count, z: centre.z / count)
                for k in ring.vertexRange {
                    let nrm = V3(mesh.normals[k])
                    if abs(nrm.length - 1) > 1e-4 { badLength += 1 }
                    if nrm.dot(V3(mesh.vertices[k]) - centre) <= 0 { inward += 1 }
                }
            }
            XCTAssertEqual(badLength, 0, "non-unit ring normal")
            XCTAssertEqual(inward, 0, "ring normal pointing inward")
        }

        // -- Tilt: the normal's y-component IS the loft slope ---------------
        // waist 76 < chest 96 < hip 98: girth shrinks rising hip→waist
        // (normals tilt UP, y > 0) and grows rising waist→chest (normals tilt
        // DOWN, y < 0). Same non-flat model and density as the no-overshoot
        // test, so both spans carry 12 interior rings each.
        let tiltModel = params(waist: 76, chest: 96, hip: 98)
        let tiltMesh = BodyMeshBuilder.mesh(
            for: tiltModel,
            configuration: BodyMeshConfiguration(ringVertexCount: 16, ringsPerSpan: 12))
        let unitP = unitPerimeter(vertexCount: 16)
        let waistY = BodyStation.waist.heightFraction * 1.75
        let chestY = BodyStation.chest.heightFraction * 1.75
        let hipY = BodyStation.hip.heightFraction * 1.75
        var tiltedSeen = 0
        var maxRisingTilt = 0.0
        for ring in tiltMesh.rings where ring.limb == .torso && ring.station == nil {
            guard ring.heightMetres > hipY && ring.heightMetres < chestY else { continue }
            tiltedSeen += 1
            let shrinking = ring.heightMetres < waistY
            for k in ring.vertexRange {
                let y = Double(tiltMesh.normals[k].y)
                if shrinking {
                    XCTAssertGreaterThan(y, 0,
                                         "shrinking girth must tilt normals up at y=\(ring.heightMetres)")
                } else {
                    XCTAssertLessThan(y, 0,
                                      "growing girth must tilt normals down at y=\(ring.heightMetres)")
                }
            }
            if shrinking {
                maxRisingTilt = max(maxRisingTilt,
                                    Double(tiltMesh.normals[ring.vertexRange.lowerBound].y))
            }
        }
        XCTAssertEqual(tiltedSeen, 24, "the spans under test lost their interior rings")

        // Magnitude floor: the mean of d(scale)/dy over hip→waist equals the
        // span's secant, so the largest sampled tilt must reach at least half
        // the secant's own tilt (|s|/√(1+s²)) — a floor a zeroed or
        // mis-scaled slope cannot fake.
        let secant = ((76.0 - 98.0) / 100 / unitP) / (waistY - hipY)
        let secantTilt = abs(secant) / (1 + secant * secant).squareRoot()
        XCTAssertGreaterThanOrEqual(maxRisingTilt, 0.5 * secantTilt)

        // Magnitude, ring by ring: at the θ = 0 vertex the ellipse gradient is
        // (1, 0), so the emitted normal is (1, −s, 0)/√(1+s²) and the slope is
        // exactly recoverable as −n.y / n.x. Hold it against a central finite
        // difference of the EMITTED ring scales (circumference / unit
        // perimeter). Only rings whose two neighbours are equidistant qualify
        // — uniform central difference is O(h²); a knot between unequal spans
        // is not. This is the assertion that pins derivative(at:) on non-flat
        // spans: a wrong magnitude (say, a slope never divided by the unit
        // perimeter) passes every sign test above.
        let torso = tiltMesh.rings.filter { $0.limb == .torso }
        var compared = 0
        for i in 1..<(torso.count - 1) {
            let prev = torso[i - 1]
            let ring = torso[i]
            let next = torso[i + 1]
            let below = ring.heightMetres - prev.heightMetres
            let above = next.heightMetres - ring.heightMetres
            guard abs(below - above) < 1e-12 else { continue }
            let normal = tiltMesh.normals[ring.vertexRange.lowerBound]
            let recovered = -Double(normal.y) / Double(normal.x)
            let finiteDifference = (next.circumferenceMetres - prev.circumferenceMetres)
                / unitP / (below + above)
            XCTAssertEqual(recovered, finiteDifference,
                           accuracy: 0.02 + 0.1 * abs(finiteDifference),
                           "loft slope at y=\(ring.heightMetres)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 20, "the finite-difference sweep went vacuous")
    }

    // MARK: - 6. No overshoot in the loft

    /// **Session 9 rejected overshoot, not curvature.** Catmull-Rom and
    /// natural cubics were rejected because they leave the interval their
    /// endpoints define — claiming a bulge or hollow no tape measured. The
    /// monotone cubic (Fritsch–Carlson, the same construction behind
    /// `GapBridge.smoothed()`) is curved AND bounded, so every interior ring
    /// between two stations must sit inside their girths. Judged by the
    /// overshoot property, exactly so no future session re-litigates the
    /// principle against lofting.
    func testMonotoneLoftNoOvershoot() {
        let model = params(waist: 76, chest: 96, hip: 98)
        let mesh = BodyMeshBuilder.mesh(
            for: model,
            configuration: BodyMeshConfiguration(ringVertexCount: 16, ringsPerSpan: 12))
        let waistY = BodyStation.waist.heightFraction * 1.75
        let chestY = BodyStation.chest.heightFraction * 1.75
        let hipY = BodyStation.hip.heightFraction * 1.75
        var interiorsSeen = 0
        for ring in mesh.rings where ring.limb == .torso && ring.station == nil {
            let cm = ring.circumferenceMetres * 100
            if ring.heightMetres > waistY && ring.heightMetres < chestY {
                interiorsSeen += 1
                XCTAssertGreaterThanOrEqual(cm, 76 - 1e-9)
                XCTAssertLessThanOrEqual(cm, 96 + 1e-9)
            }
            if ring.heightMetres > hipY && ring.heightMetres < waistY {
                interiorsSeen += 1
                XCTAssertGreaterThanOrEqual(cm, 76 - 1e-9)
                XCTAssertLessThanOrEqual(cm, 98 + 1e-9)
            }
        }
        XCTAssertEqual(interiorsSeen, 24, "the spans under test lost their interior rings")
    }

    // MARK: - 7. The curve itself

    /// Direct pin on the Fritsch–Carlson implementation: knots reproduced
    /// exactly, the classic overshoot input stays bounded (a Catmull-Rom
    /// undershoots below 0 on this exact input), flat spans have zero slope,
    /// and invalid knot lists refuse to build.
    func testMonotoneCubicCurveDirect() throws {
        let knots: [(y: Double, value: Double)] = [(0, 0), (1, 0), (2, 1), (3, 1)]
        let curve = try XCTUnwrap(MonotoneCubicCurve(knots: knots))
        for knot in knots {
            XCTAssertEqual(curve.value(at: knot.y), knot.value, "knot not reproduced exactly")
        }
        for i in 0...300 {
            let v = curve.value(at: Double(i) / 100)
            XCTAssertGreaterThanOrEqual(v, 0, "undershoot at y=\(Double(i) / 100)")
            XCTAssertLessThanOrEqual(v, 1, "overshoot at y=\(Double(i) / 100)")
        }
        XCTAssertLessThan(curve.value(at: 1.2), curve.value(at: 1.8), "lost monotonicity")
        XCTAssertEqual(curve.derivative(at: 0.5), 0, "flat span must have zero slope")
        XCTAssertEqual(curve.derivative(at: 1), 0, "flat-span knot must have zero slope")
        XCTAssertEqual(curve.derivative(at: 3), 0)
        XCTAssertEqual(curve.value(at: -5), 0, "clamps below the domain")
        XCTAssertEqual(curve.value(at: 9), 1, "clamps above the domain")
        XCTAssertNil(MonotoneCubicCurve(knots: [(0, 1)]))
        XCTAssertNil(MonotoneCubicCurve(knots: [(0, 1), (0, 2)]))
    }

    // MARK: - 8. Station rings pinned

    /// Station rings land at exactly `heightFraction × stature` with the
    /// station recorded on the ring — pinned, never read back off the curve —
    /// and in the fixed emission order the renderer depends on instead of
    /// sorting. Thigh and calf realise once per leg; their anchors reference
    /// the LEFT (+x) leg.
    func testStationRingsPinned() {
        let mesh = BodyMeshBuilder.mesh(for: params())
        for station in BodyStation.allCases {
            let rings = stationRings(mesh, station)
            if station == .thigh || station == .calf {
                XCTAssertEqual(rings.count, 2)
                XCTAssertEqual(Set(rings.map { $0.limb }), [.leftLeg, .rightLeg])
            } else {
                XCTAssertEqual(rings.count, 1)
                XCTAssertEqual(rings.first?.limb, .torso)
            }
            for ring in rings {
                // Exact: both sides compute fraction × stature identically.
                XCTAssertEqual(ring.heightMetres, station.heightFraction * 1.75)
            }
        }
        for anchor in mesh.labelAnchors
        where anchor.station == .thigh || anchor.station == .calf {
            XCTAssertEqual(mesh.rings[anchor.ringIndex].limb, .leftLeg)
            XCTAssertGreaterThan(mesh.vertices[anchor.vertexIndex].x, 0)
        }
    }

    // MARK: - 9. Provenance

    /// **The dangerous direction is promotion.** A guess drawn as a fact is
    /// the failure `MetricSource.calculated` exists upstream to prevent; the
    /// reverse is merely conservative. Pins: the both-ends rule vertically,
    /// schematic stretches even on a fully-taped body, a projection arriving
    /// wholly estimated with an EMPTY measured element (zero renderer
    /// cooperation needed), and the priority rule that a station ring keeps
    /// its own provenance while the span above it goes schematic.
    func testProvenanceNeverLaundered() throws {
        let full = BodyMeshBuilder.mesh(for: params())
        let waistY = BodyStation.waist.heightFraction * 1.75
        let chestY = BodyStation.chest.heightFraction * 1.75
        let hipY = BodyStation.hip.heightFraction * 1.75
        let thighY = BodyStation.thigh.heightFraction * 1.75
        let calfY = BodyStation.calf.heightFraction * 1.75

        // (a) Interiors between two measured stations are measured.
        for ring in full.rings
        where ring.limb == .torso && ring.station == nil
            && ring.heightMetres > waistY && ring.heightMetres < chestY {
            XCTAssertEqual(ring.provenance, .measured)
        }

        // (b) Between a measured and an estimated station: estimated.
        let partial = BodyMeshBuilder.mesh(for: partiallyMeasured())
        for ring in partial.rings
        where ring.limb == .torso && ring.station == nil
            && ring.heightMetres > waistY && ring.heightMetres < chestY {
            XCTAssertEqual(ring.provenance, .estimated, "chest is a guess; the span inherits it")
        }
        for ring in partial.rings
        where ring.limb == .torso && ring.station == nil
            && ring.heightMetres > hipY && ring.heightMetres < waistY {
            XCTAssertEqual(ring.provenance, .measured, "hip and waist were both taped")
        }
        XCTAssertEqual(try XCTUnwrap(stationRings(partial, .chest).first).provenance, .estimated)

        // (c) Schematic stretches stay schematic on a FULLY measured body:
        // no tape exists at these heights at all.
        for ring in full.rings {
            switch ring.limb {
            case .head, .leftArm, .rightArm:
                XCTAssertEqual(ring.provenance, .schematic)
            case .torso:
                if ring.heightMetres < hipY - 1e-12 {
                    XCTAssertEqual(ring.provenance, .schematic, "crotch region has no tape")
                }
            case .leftLeg, .rightLeg:
                if ring.heightMetres > thighY + 1e-12 {
                    XCTAssertEqual(ring.provenance, .schematic, "leg-top region has no tape")
                }
                if ring.heightMetres < calfY - 1e-12 {
                    XCTAssertEqual(ring.provenance, .schematic, "ankle region has no tape")
                }
            }
        }
        // Priority rule: the neck ring is measured even though the span above
        // it is schematic — the tape was really at the neck.
        XCTAssertEqual(try XCTUnwrap(stationRings(full, .neck).first).provenance, .measured)

        // (d) A projection has zero measured rings and an empty measured
        // element — `project()` marked every station unmeasured, and the mesh
        // must not resurrect any of them.
        let projected = BodyMeshBuilder.mesh(for: flooredProjection())
        XCTAssertTrue(projected.isWhollyEstimated)
        XCTAssertEqual(projected.rings.filter { $0.provenance == .measured }.count, 0)
        XCTAssertTrue(projected.measuredTriangles.isEmpty)

        // (e) Wholly estimated build: same story.
        let estimated = BodyMeshBuilder.mesh(for: params(measured: false))
        XCTAssertTrue(estimated.isWhollyEstimated)
        XCTAssertEqual(estimated.rings.filter { $0.provenance == .measured }.count, 0)
        XCTAssertTrue(estimated.measuredTriangles.isEmpty)

        // (f) On the fully measured body, the waist ring's faces live in the
        // measured element — and every measured index sits on a measured ring
        // (a face is measured only when BOTH its rings are).
        XCTAssertFalse(full.isWhollyEstimated)
        var measuredIndexes = Set<Int>()
        forEachFace(of: [full.measuredTriangles]) { a, b, c in
            measuredIndexes.insert(a)
            measuredIndexes.insert(b)
            measuredIndexes.insert(c)
        }
        let waistRing = try XCTUnwrap(stationRings(full, .waist).first)
        for k in waistRing.vertexRange {
            XCTAssertTrue(measuredIndexes.contains(k))
        }
        let measuredRingVertexes = Set(full.rings.filter { $0.provenance == .measured }
            .flatMap { Array($0.vertexRange) })
        XCTAssertTrue(measuredIndexes.isSubset(of: measuredRingVertexes),
                      "a measured face touches a non-measured ring")
    }

    // MARK: - 10. Anchors

    /// Exactly seven, in `BodyStation.allCases` order, each bitwise-anchored
    /// to a real vertex, with `isMeasured` and the printed value carried
    /// VERBATIM — the blanket caption's honesty made per-label. Uses the
    /// partially measured build so both flag states are exercised at once.
    func testAnchors() {
        let model = partiallyMeasured()
        let mesh = BodyMeshBuilder.mesh(for: model)
        XCTAssertEqual(mesh.labelAnchors.count, 7)
        XCTAssertEqual(mesh.labelAnchors.map { $0.station }, BodyStation.allCases)
        for anchor in mesh.labelAnchors {
            XCTAssertEqual(anchor.position, mesh.vertices[anchor.vertexIndex])
            let ring = mesh.rings[anchor.ringIndex]
            XCTAssertEqual(ring.station, anchor.station)
            XCTAssertEqual(anchor.vertexIndex, ring.vertexRange.lowerBound,
                           "anchor is the theta = 0 (+x) vertex")
            let stored = model.stations.first { $0.station == anchor.station }!
            XCTAssertEqual(anchor.isMeasured, stored.isMeasured)
            XCTAssertEqual(anchor.valueCentimetres, stored.circumferenceCentimetres)
        }
        XCTAssertTrue(mesh.labelAnchors.first { $0.station == .waist }!.isMeasured)
        XCTAssertFalse(mesh.labelAnchors.first { $0.station == .chest }!.isMeasured)
    }

    // MARK: - 11. Closed-form counts and topology invariance

    /// Counts are a formula of the configuration alone, pinned twice: as the
    /// formula AND as evaluated triples, so code and formula cannot drift in
    /// step. Topology invariance across different girths is the precondition
    /// for the renderer's in-place geometry updates during a scrub — if
    /// indices changed with girths, a scrub would corrupt the buffers.
    func testCountsMatchClosedForm() {
        let pinned: [(n: Int, r: Int, arms: Bool, rings: Int, vertices: Int,
                      triangles: Int, indices: Int)] = [
            (n: 48, r: 8, arms: true, rings: 158, vertices: 7590,
             triangles: 14976, indices: 44928),
            (n: 8, r: 1, arms: true, rings: 39, vertices: 318,
             triangles: 592, indices: 1776),
            (n: 48, r: 8, arms: false, rings: 120, vertices: 5764,
             triangles: 11424, indices: 34272)
        ]
        for expected in pinned {
            let formula = expectedCounts(n: expected.n, r: expected.r, arms: expected.arms)
            XCTAssertEqual(formula.rings, expected.rings)
            XCTAssertEqual(formula.vertices, expected.vertices)
            XCTAssertEqual(formula.triangles, expected.triangles)
            XCTAssertEqual(formula.indices, expected.indices)

            let mesh = BodyMeshBuilder.mesh(
                for: params(),
                configuration: BodyMeshConfiguration(ringVertexCount: expected.n,
                                                     ringsPerSpan: expected.r,
                                                     includesArms: expected.arms))
            XCTAssertEqual(mesh.rings.count, expected.rings)
            XCTAssertEqual(mesh.vertices.count, expected.vertices)
            XCTAssertEqual(mesh.normals.count, expected.vertices)
            XCTAssertEqual(mesh.measuredTriangles.count + mesh.estimatedTriangles.count,
                           expected.indices)
        }

        // Clamping: 9 rounds DOWN to even (8); 0 rings per span floors at 1.
        let clamped = BodyMeshBuilder.mesh(
            for: params(),
            configuration: BodyMeshConfiguration(ringVertexCount: 9, ringsPerSpan: 0))
        XCTAssertEqual(clamped.vertices.count, 318)

        // Arms off removes exactly the arm rings — everything emitted before
        // them keeps its indices — and no anchors (arms never had any).
        let armsOn = BodyMeshBuilder.mesh(for: params())
        let armsOff = BodyMeshBuilder.mesh(
            for: params(),
            configuration: BodyMeshConfiguration(includesArms: false))
        XCTAssertEqual(armsOff.rings,
                       armsOn.rings.filter { $0.limb != .leftArm && $0.limb != .rightArm })
        XCTAssertEqual(armsOff.labelAnchors, armsOn.labelAnchors)

        // Topology invariance: different girths, identical index arrays.
        let wide = BodyMeshBuilder.mesh(for: params(waist: 96))
        let narrow = BodyMeshBuilder.mesh(for: params(waist: 76))
        XCTAssertEqual(wide.measuredTriangles, narrow.measuredTriangles)
        XCTAssertEqual(wide.estimatedTriangles, narrow.estimatedTriangles)
        let heavy = BodyMeshBuilder.mesh(for: params(measured: false, weightKg: 100))
        let light = BodyMeshBuilder.mesh(for: params(measured: false, weightKg: 70))
        XCTAssertEqual(heavy.estimatedTriangles, light.estimatedTriangles)
        XCTAssertTrue(heavy.measuredTriangles.isEmpty)
    }

    // MARK: - 12. Degenerate inputs

    /// The floors (`build()` height > 0.5 m, `project()` 1 cm girths) define
    /// the worst inputs this pipeline can legally receive; all of them must
    /// mesh finite, with valid indices, and keep the perimeter identity. The
    /// identity tolerance is 1e-3 here rather than test 1's 1e-4: a 1 cm ring
    /// riding a ±0.14 m leg offset spends most of its Float32 mantissa on the
    /// offset, and that loss is the thing being measured.
    func testDegenerateInputsFinite() {
        let cases: [(name: String, model: BodyModelParameters)] = [
            (name: "minimum stature", model: params(heightMetres: 0.51)),
            (name: "all girths floored", model: flooredProjection()),
            (name: "hip 140 thigh 1", model: params(hip: 140, thigh: 1))
        ]
        for testCase in cases {
            let mesh = BodyMeshBuilder.mesh(
                for: testCase.model,
                configuration: BodyMeshConfiguration(ringVertexCount: 16, ringsPerSpan: 2))
            var nonFinite = 0
            for k in mesh.vertices.indices {
                let v = mesh.vertices[k]
                let nrm = mesh.normals[k]
                if !(v.x.isFinite && v.y.isFinite && v.z.isFinite) { nonFinite += 1 }
                if !(nrm.x.isFinite && nrm.y.isFinite && nrm.z.isFinite) { nonFinite += 1 }
            }
            XCTAssertEqual(nonFinite, 0, testCase.name)
            for list in [mesh.measuredTriangles, mesh.estimatedTriangles] {
                XCTAssertLessThan(Int(list.max() ?? 0), mesh.vertices.count, testCase.name)
            }
            for station in BodyStation.allCases where station != .shoulder {
                let expected = testCase.model.girth(station)!
                for ring in stationRings(mesh, station) {
                    XCTAssertEqual(ringPerimeterMetres(ring, in: mesh) * 100, expected,
                                   accuracy: expected * 1e-3, "\(testCase.name) \(station)")
                }
            }
        }

        // A leg tube never crosses the centreline, even when the hip dwarfs
        // the thigh: the 1.02 placement clause holds the clearance.
        let extreme = BodyMeshBuilder.mesh(
            for: params(hip: 140, thigh: 1),
            configuration: BodyMeshConfiguration(ringVertexCount: 16, ringsPerSpan: 2))
        for ring in extreme.rings where ring.limb == .leftLeg {
            for k in ring.vertexRange {
                XCTAssertGreaterThan(extreme.vertices[k].x, 0)
            }
        }
    }

    // MARK: - 13. The scrub

    /// The mesh of an interpolation's endpoints IS the endpoint mesh — exactly
    /// — and a small scrub step moves vertices a bounded amount. The bound is
    /// a generous continuity tripwire (it catches a knot-count discontinuity
    /// or a placement jump), NOT a tight Lipschitz claim; girth deltas here
    /// are integers so the endpoint identity is exact in floating point.
    func testScrubEndpointsAndContinuity() {
        let a = params(waist: 76, neck: 36, shoulder: 44, chest: 90, hip: 96,
                       thigh: 52, calf: 36)
        let b = params(waist: 96, neck: 40, shoulder: 48, chest: 104, hip: 104,
                       thigh: 60, calf: 40, at: day.addingTimeInterval(90 * 24 * 3600))

        XCTAssertEqual(BodyMeshBuilder.mesh(for: BodyModelParameters.interpolate(from: a, to: b, t: 0)),
                       BodyMeshBuilder.mesh(for: a))
        XCTAssertEqual(BodyMeshBuilder.mesh(for: BodyModelParameters.interpolate(from: a, to: b, t: 1)),
                       BodyMeshBuilder.mesh(for: b))

        let mid = BodyMeshBuilder.mesh(for: BodyModelParameters.interpolate(from: a, to: b, t: 0.5))
        let step = BodyMeshBuilder.mesh(for: BodyModelParameters.interpolate(from: a, to: b, t: 0.51))
        var maxDisplacement = 0.0
        for k in mid.vertices.indices {
            maxDisplacement = max(maxDisplacement,
                                  (V3(step.vertices[k]) - V3(mid.vertices[k])).length)
        }
        var maxGirthDeltaMetres = 0.0
        for station in BodyStation.allCases {
            maxGirthDeltaMetres = max(maxGirthDeltaMetres,
                                      abs(a.girth(station)! - b.girth(station)!) / 100)
        }
        let heightDelta = abs(a.heightMetres - b.heightMetres)
        let bound = 0.01 * 4 * (maxGirthDeltaMetres + heightDelta + 0.001)
        XCTAssertLessThanOrEqual(maxDisplacement, bound)
        XCTAssertGreaterThan(maxDisplacement, 0, "a scrub step must move something")
    }
}
