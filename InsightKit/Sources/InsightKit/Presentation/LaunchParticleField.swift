import Foundation

/// The point cloud behind the launch screen's heart.
///
/// Lives in InsightKit for the usual reason — the app target has no test target
/// — but also for a less usual one: this is the only part of a GPU renderer that
/// *can* be tested. Whether Metal draws the buffer is something only a device
/// answers; whether the buffer describes a heart is arithmetic, and arithmetic
/// belongs where `swift test` can reach it.
///
/// It replaces a pre-rendered video. The video was 608×1078, which a modern
/// iPhone upscales about 2.4×, and its dot density was fixed at generation time.
/// Both of those were the actual complaints, and neither is fixable in a file:
/// you cannot add dots to a video. Here they are two integers.
public enum LaunchParticleField {

    // MARK: - Shape

    /// Points per cloud, set by measurement rather than by eye.
    ///
    /// The first version (60k / 26k) came out at 15.9% ink coverage against the
    /// reference animation's 30.6%, and its ring band at 7% against 29% — which
    /// on the phone read as "too light, not dense enough, ring barely visible".
    /// These counts put coverage at 33% and the bands at ~25%. The ring needs
    /// far more points than the heart because it is spread over most of the
    /// screen rather than concentrated.
    ///
    /// On a GPU a third of a million point sprites costs nothing. The cost that
    /// *is* real is generating them — only the heart pays for ray-bisection —
    /// which is why `build` is measured by a test rather than guessed at.
    public static let heartCount = 85_000
    public static let ringCount = 240_000

    /// Seconds for the heart to turn once.
    ///
    /// The video it replaces ran a full cycle in about seven seconds and the
    /// user's word for it was "spinning too fast". Eighteen seconds is a drift
    /// rather than a spin: over the second or two the screen is actually up, the
    /// heart turns perhaps forty degrees. Slow enough to read as considered.
    public static let secondsPerTurn: Double = 18

    /// The ring turns slower still, so the two never lock into one rigid object.
    public static let ringTurnRatio: Double = 0.3

    // MARK: - Building

    /// The cloud, as `(x, y, z, kind)` — `kind` 0 for the heart, 1 for the ring.
    ///
    /// Packed flat because it is about to become a Metal vertex buffer and this
    /// is the layout the vertex shader indexes. `SIMD4<Float>` rather than a
    /// struct so the memory layout is guaranteed rather than assumed.
    ///
    /// Deterministic given `seed`: the same cloud every launch. That matters for
    /// more than testing — the static `UILaunchScreen` image is rendered from
    /// this same arrangement, so a cloud that varied would show as a jump the
    /// moment the live view took over.
    public static func build(heartCount: Int = heartCount,
                             ringCount: Int = ringCount,
                             seed: UInt64 = 0x5EED_1EAF) -> [SIMD4<Float>] {
        var rng = SplitMix64(state: seed)
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(heartCount + ringCount)
        for _ in 0..<heartCount {
            let p = heartPoint(&rng)
            out.append(SIMD4(p.0, p.1, p.2, 0))
        }
        for _ in 0..<ringCount {
            let p = ringPoint(&rng)
            out.append(SIMD4(p.0, p.1, p.2, 1))
        }
        return out
    }

    /// One point on the implicit heart surface
    ///
    ///     (x² + 9/4 y² + z²  −  1)³  −  x² z³  −  9/80 y² z³  =  0
    ///
    /// found by firing a ray from the origin and bisecting for the radius where
    /// the sign flips. Uniform in direction, exact on the surface, and no
    /// rejection sampling — which at sixty thousand points is the difference
    /// between milliseconds and a visible pause.
    ///
    /// The surface's own axes are not the screen's: **z is up** (the lobes sit
    /// at +z, the point at −z) and **y is the thin direction**, which is what
    /// the camera looks down. Getting that wrong spins the heart in the screen
    /// plane like a pinwheel instead of turning it.
    static func heartPoint(_ rng: inout SplitMix64) -> (Float, Float, Float) {
        var dx = rng.gaussian(), dy = rng.gaussian(), dz = rng.gaussian()
        var len = (dx * dx + dy * dy + dz * dz).squareRoot()
        // A zero-length direction has no ray to fire; astronomically unlikely and
        // trivially handled, but a NaN here would poison the whole buffer.
        if len < 1e-6 { dx = 0; dy = 0; dz = 1; len = 1 }
        dx /= len; dy /= len; dz /= len

        func inside(_ s: Double) -> Bool {
            let x = Double(dx) * s, y = Double(dy) * s, z = Double(dz) * s
            let a = x * x + 2.25 * y * y + z * z - 1
            return a * a * a - x * x * z * z * z - 0.1125 * y * y * z * z * z < 0
        }

        var lo = 1e-3, hi = 2.2
        for _ in 0..<32 {
            let mid = 0.5 * (lo + hi)
            if inside(mid) { lo = mid } else { hi = mid }
        }
        // A shell is not a mist: scatter each point a little along its own radius
        // so the cloud has thickness to look into.
        let r = Float(0.5 * (lo + hi)) * (1 + rng.gaussian() * 0.012)
        return (dx * r, dy * r, dz * r)
    }

    /// One point in the ribbon that frames the screen: a closed loop with a
    /// couple of harmonics on its radius, spread in depth so it reads as a band
    /// of mist rather than a drawn line. Taller than wide, because the screen is.
    static func ringPoint(_ rng: inout SplitMix64) -> (Float, Float, Float) {
        let t = rng.uniform() * 2 * .pi
        var r = 1.42 * (1 + 0.16 * sin(6 * t) + 0.07 * sin(3 * t + 1.2))
        r += Double(rng.gaussian()) * 0.055
        return (Float(r * cos(t)),
                rng.gaussian() * 0.22,
                Float(r * sin(t) * 2.15))
    }
}

/// SplitMix64 — small, fast, and above all *reproducible across platforms*.
///
/// `SystemRandomNumberGenerator` would give a different cloud on every launch,
/// which would make both the tests below and the static launch image impossible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1). 53 bits, so the spacing is finer than a Float can hold.
    mutating func uniform() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Box–Muller, one value per call. The discarded second value costs a little
    /// speed and buys a stateless generator, which is worth more here.
    mutating func gaussian() -> Float {
        let u1 = max(uniform(), 1e-12)
        let u2 = uniform()
        return Float((-2 * Foundation.log(u1)).squareRoot() * cos(2 * .pi * u2))
    }
}
