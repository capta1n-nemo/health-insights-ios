import XCTest
@testable import InsightKit

/// The launch heart is drawn by Metal, and no test here can see a pixel of it.
/// What these pin is everything *upstream* of the draw call: that the buffer
/// describes a heart, that it is the same heart every launch, and that building
/// it is fast enough to do at launch — which is the whole reason it can live in
/// the app at all.
final class LaunchParticleFieldTests: XCTestCase {

    /// The implicit surface the heart points are supposed to lie on.
    private func F(_ p: SIMD4<Float>) -> Double {
        let x = Double(p.x), y = Double(p.y), z = Double(p.z)
        let a = x * x + 2.25 * y * y + z * z - 1
        return a * a * a - x * x * z * z * z - 0.1125 * y * y * z * z * z
    }

    private func field(heart: Int = 4_000, ring: Int = 2_000) -> [SIMD4<Float>] {
        LaunchParticleField.build(heartCount: heart, ringCount: ring)
    }

    // MARK: - It is actually a heart

    /// The one that would catch a sign error, a swapped axis or a bad constant —
    /// all of which would still produce a plausible-looking blob.
    ///
    /// Asserted as a *radial* distance, not as the value of `F`. `F` is not a
    /// distance: near the cusp its gradient is steep, so a point sitting the
    /// intended 1.2% off the shell can return a residual twenty times larger
    /// than one sitting the same distance off a flat flank. Testing `F` directly
    /// measures the surface's curvature as much as the cloud's accuracy — the
    /// first version of this did exactly that and failed on a point that was
    /// perfectly well placed.
    func testHeartPointsLieOnTheHeartSurface() {
        let heart = field().filter { $0.w == 0 }
        XCTAssertEqual(heart.count, 4_000)

        /// Where the surface actually is along this point's own direction.
        func surfaceRadius(along p: SIMD4<Float>) -> Double {
            let len = (Double(p.x * p.x + p.y * p.y + p.z * p.z)).squareRoot()
            let d = (Double(p.x) / len, Double(p.y) / len, Double(p.z) / len)
            var lo = 1e-3, hi = 2.2
            for _ in 0..<60 {
                let mid = 0.5 * (lo + hi)
                let x = d.0 * mid, y = d.1 * mid, z = d.2 * mid
                let a = x * x + 2.25 * y * y + z * z - 1
                if a * a * a - x * x * z * z * z - 0.1125 * y * y * z * z * z < 0 {
                    lo = mid
                } else { hi = mid }
            }
            return 0.5 * (lo + hi)
        }

        var worst = 0.0
        var total = 0.0
        for p in heart {
            let len = (Double(p.x * p.x + p.y * p.y + p.z * p.z)).squareRoot()
            let offset = abs(len - surfaceRadius(along: p)) / surfaceRadius(along: p)
            worst = max(worst, offset)
            total += offset
        }
        // The scatter is a 1.2% Gaussian, so a handful of points sit five sigma
        // out; anything past 10% is a point that is not on this surface at all.
        XCTAssertLessThan(worst, 0.10, "a point is nowhere near the surface")
        XCTAssertLessThan(total / Double(heart.count), 0.02,
                          "the cloud has drifted off the surface")
        // And the scatter is really there — a shell with no thickness is not a mist.
        XCTAssertGreaterThan(total / Double(heart.count), 0.002,
                             "the cloud has no thickness to look into")
    }

    /// A heart is not a sphere: it is wider than it is deep, and its widest part
    /// is above its middle. Both would survive a broken implicit function that
    /// still produced *something* closed.
    func testTheCloudHasHeartProportionsAndNotSphereOnes() {
        let heart = field(heart: 20_000, ring: 0).filter { $0.w == 0 }
        let width = heart.map { abs($0.x) }.max() ?? 0
        let depth = heart.map { abs($0.y) }.max() ?? 0
        let height = heart.map { abs($0.z) }.max() ?? 0
        XCTAssertGreaterThan(width, depth * 1.6, "should be much wider than deep")
        XCTAssertGreaterThan(height, 0.7)

        // The lobes are at +z and the point at −z, so the upper half carries the
        // width. If the surface were flipped this comparison inverts.
        let upperWidth = heart.filter { $0.z > 0.3 }.map { abs($0.x) }.max() ?? 0
        let lowerWidth = heart.filter { $0.z < -0.3 }.map { abs($0.x) }.max() ?? 0
        XCTAssertGreaterThan(upperWidth, lowerWidth,
                             "the heart is upside down — lobes should be at +z")
    }

    /// The cleft between the lobes: on the vertical centreline, the very top of
    /// the heart dips *in*. A sphere or an egg has no such notch.
    func testThereIsAClaftBetweenTheLobes() {
        let heart = field(heart: 40_000, ring: 0).filter { $0.w == 0 }
        // Points near the x = 0 plane, i.e. the centreline where the cleft is.
        let centre = heart.filter { abs($0.x) < 0.06 }
        let topOfCentreline = centre.map(\.z).max() ?? 0
        // Points out on a lobe.
        let lobe = heart.filter { abs($0.x - 0.45) < 0.06 }
        let topOfLobe = lobe.map(\.z).max() ?? 0
        XCTAssertGreaterThan(topOfLobe, topOfCentreline,
                            "no cleft — the lobes do not rise above the centreline")
    }

    // MARK: - The ring

    func testTheRingIsALoopAroundTheHeartAndTallerThanItIsWide() {
        let ring = field(heart: 0, ring: 12_000).filter { $0.w == 1 }
        XCTAssertEqual(ring.count, 12_000)
        let width = ring.map { abs($0.x) }.max() ?? 0
        let height = ring.map { abs($0.z) }.max() ?? 0
        XCTAssertGreaterThan(height, width, "the ring should frame a portrait screen")
        // A loop, not a disc: nothing should sit near the middle.
        let radii = ring.map { ($0.x * $0.x + ($0.z / 2.15) * ($0.z / 2.15)).squareRoot() }
        XCTAssertGreaterThan(radii.min() ?? 0, 0.7, "the ring has filled in")
    }

    func testTheRingClearsTheHeart() {
        let all = field(heart: 20_000, ring: 12_000)
        let heartWidth = all.filter { $0.w == 0 }.map { abs($0.x) }.max() ?? 0
        let ringInner = all.filter { $0.w == 1 }.map { abs($0.x) }.min() ?? 0
        // They may overlap in projection, but the ring's *loop* must not be
        // swallowed by the heart's silhouette or it stops reading as a frame.
        XCTAssertGreaterThan(all.filter { $0.w == 1 }.map { abs($0.z) }.max() ?? 0,
                             heartWidth, "the ring is inside the heart")
        XCTAssertGreaterThanOrEqual(ringInner, 0)
    }

    // MARK: - Reproducibility

    /// The static `UILaunchScreen` image is rendered from this arrangement, so a
    /// cloud that varied between launches would show as a jump the instant the
    /// live view took over.
    func testTheCloudIsIdenticalEveryTime() {
        let a = field()
        let b = field()
        XCTAssertEqual(a, b)
        let different = LaunchParticleField.build(heartCount: 4_000, ringCount: 2_000,
                                                  seed: 99)
        XCTAssertNotEqual(a, different, "the seed does nothing")
    }

    func testNothingIsNaNOrRunsAway() {
        for p in field(heart: 20_000, ring: 8_000) {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite, "non-finite point")
            XCTAssertLessThan(abs(p.x), 6)
            XCTAssertLessThan(abs(p.y), 6)
            XCTAssertLessThan(abs(p.z), 6)
        }
    }

    // MARK: - It has to be affordable

    /// Building the full cloud happens once, at launch, on a screen that exists
    /// because launching is already slow. Sixty thousand ray-bisections is not
    /// obviously cheap, so it is measured rather than assumed.
    ///
    /// **Measured against itself, not against the clock.**
    ///
    /// This used to assert a wall-clock budget of two seconds, and on
    /// 2026-08-04 it failed the local gate twice — 2.07 s and then 4.20 s —
    /// while passing three times out of three in isolation and passing on CI.
    /// Nothing about the cloud had changed: the machine was busy decoding a
    /// quarter of a million samples in a simulator at the time. A wall-clock
    /// budget on a shared machine measures the machine.
    ///
    /// That is this repo's "guard reporting a failure whose own premise is
    /// false" class, and it cost a red gate that got pushed through.
    ///
    /// The property actually worth defending is that generation stays roughly
    /// **linear** in the particle count — the real regressions it was written
    /// for are a bisection loop gaining a zero or a rejection sampler creeping
    /// back in, and both of those bend the *shape* of the curve. Timing two
    /// sizes back to back cancels the machine out, because whatever load
    /// distorts one measurement distorts the other. The ceiling is generous
    /// (6× for a 4× size increase) so ordinary noise cannot trip it; only a
    /// change of complexity class can.
    func testCloudGenerationStaysLinearInTheParticleCount() {
        func elapsed(_ body: () -> Void) -> TimeInterval {
            let started = Date()
            body()
            return Date().timeIntervalSince(started)
        }
        // Warm up first: the first call pays for lazily-initialised tables and
        // would otherwise be charged to the small size, flattering the ratio.
        _ = LaunchParticleField.build(heartCount: 200, ringCount: 0)

        let small = max(elapsed { _ = LaunchParticleField.build(heartCount: 2_000, ringCount: 0) }, 1e-6)
        let large = elapsed { _ = LaunchParticleField.build(heartCount: 8_000, ringCount: 0) }

        XCTAssertLessThan(large / small, 6.0,
                          "generation is scaling worse than linearly in the particle count "
                          + "(4× the points took \(large / small)× the time) — a bisection or "
                          + "rejection loop has probably regained a factor")
    }

    /// The cloud is the size it says it is. Kept separate from the timing above
    /// so a slow machine can never make a *correctness* assertion fail.
    func testTheFullCloudIsTheSizeItClaims() {
        XCTAssertEqual(LaunchParticleField.build().count,
                       LaunchParticleField.heartCount + LaunchParticleField.ringCount)
    }

    /// Slower than the video it replaces, which is the entire point of the
    /// change. Stated as a test because it is one number in one file and the
    /// reason for it lives only in a comment.
    func testTheHeartTurnsSlowlyEnoughToReadAsADrift() {
        XCTAssertGreaterThanOrEqual(LaunchParticleField.secondsPerTurn, 12,
                                    "this is a spin, not a drift")
        XCTAssertLessThan(LaunchParticleField.ringTurnRatio, 1,
                          "the ring should lag the heart, not lead it")
    }
}
