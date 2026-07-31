import SwiftUI
import UIKit
import MetalKit
import InsightKit

/// The launch heart, rendered live by Metal.
///
/// It replaces a pre-rendered video, and the reason is the three things that
/// were wrong with a video and cannot be fixed inside one: it was 608×1078 and a
/// modern iPhone upscaled it about 2.4×, its dot density was fixed at generation
/// time, and its speed was baked into the frames. Here those are the drawable's
/// own resolution, an integer, and a constant.
///
/// **What is and is not verified.** The point cloud is built and tested in
/// InsightKit — that it is a heart, that it is the same one every launch, that
/// building it is affordable. The projection maths in `shaderSource` mirrors a
/// reference implementation that was rendered and looked at, and that source
/// compiled cleanly as a `.metal` file on CI before it moved to runtime
/// compilation. What no test can reach is whether Metal draws any of it on a
/// real device — hence the Metal-unavailable fallback, the shader-compile
/// failure being logged to Diagnostics rather than swallowed, and the fact that
/// the first launch on the phone is the real test.
struct LaunchParticleView: UIViewRepresentable {

    func makeCoordinator() -> Renderer { Renderer() }

    /// Whether this device can draw at all. Checked before use rather than
    /// discovered as a blank screen — a launch screen that renders nothing is
    /// worse than the static poster it would replace.
    static var isAvailable: Bool { MTLCreateSystemDefaultDevice() != nil }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return view }
        view.device = device
        // Not the _srgb variant on purpose: blending in sRGB byte space is what
        // the reference render did, and matching it matters more here than
        // being colourimetrically correct about a cloud of pink dots.
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.851, green: 0.851, blue: 0.851, alpha: 1)
        view.isOpaque = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.start(device: device, view: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
    }

    // MARK: - Renderer

    final class Renderer: NSObject, MTKViewDelegate {
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var points: MTLBuffer?
        private var count = 0
        private var startedAt = CACurrentMediaTime()

        /// Matches the reference render: the heart sits a little above centre,
        /// and one model unit is 15.5% of the drawable's height.
        private static let scaleFraction: Float = 0.155
        private static let centreFraction: Float = 0.43
        /// ~4 px at 1179×2556, scaled so the mist stays the same *visual*
        /// fineness on a smaller or larger screen rather than the same pixel count.
        private static let pointFraction: Float = 0.0016

        func start(device: MTLDevice, view: MTKView) {
            queue = device.makeCommandQueue()
            startedAt = CACurrentMediaTime()

            // Compiled at runtime rather than from a `.metal` file in the target.
            //
            // Xcode 26 ships the Metal compiler as a separately downloadable
            // component. GitHub's macOS runners have it; the user's own Mac —
            // which is the runner that actually builds and installs the app —
            // did not, so `CompileMetalFile` failed with exit 65 and four
            // deploys in a row died while CI stayed green. Compiling the source
            // here needs no build-time toolchain on any machine.
            //
            // The trade is real and worth stating: the shader is no longer
            // checked by the compiler at build time. It is checked by CI having
            // compiled this exact source as a `.metal` file before the move, and
            // by the failure path below, which says so out loud rather than
            // leaving a blank screen to be puzzled over.
            let library: MTLLibrary
            do {
                library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            } catch {
                DiagnosticsLog.shared.fail("Launch screen",
                                           "Particle shader failed to compile",
                                           detail: "\(error)")
                return
            }
            guard let vertex = library.makeFunction(name: "launchParticleVertex"),
                  let fragment = library.makeFunction(name: "launchParticleFragment")
            else {
                DiagnosticsLog.shared.fail("Launch screen", "Particle shader is missing a function")
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            let colour = descriptor.colorAttachments[0]!
            colour.pixelFormat = view.colorPixelFormat
            // Premultiplied source-over — the shader has already multiplied.
            colour.isBlendingEnabled = true
            colour.rgbBlendOperation = .add
            colour.alphaBlendOperation = .add
            colour.sourceRGBBlendFactor = .one
            colour.sourceAlphaBlendFactor = .one
            colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            // Eighty-six thousand ray-bisections is ~0.2 s on a laptop and more
            // on a phone. It happens once, and it happens off the main actor,
            // because the entire point of this screen is that the main thread is
            // busy. Until it lands the view clears to the launch background,
            // which is the same colour the static launch screen is already
            // showing — so the wait is invisible rather than blank.
            Task.detached(priority: .userInitiated) {
                let cloud = LaunchParticleField.build()
                let bytes = cloud.count * MemoryLayout<SIMD4<Float>>.stride
                guard let buffer = cloud.withUnsafeBytes({ raw in
                    device.makeBuffer(bytes: raw.baseAddress!, length: bytes,
                                      options: .storageModeShared)
                }) else { return }
                await MainActor.run { [weak self] in
                    self?.points = buffer
                    self?.count = cloud.count
                }
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let queue, let points, count > 0,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commands = queue.makeCommandBuffer(),
                  let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor)
            else { return }

            let size = view.drawableSize
            let height = Float(size.height)
            let elapsed = Float(CACurrentMediaTime() - startedAt)
            let turn = Float(LaunchParticleField.secondsPerTurn)

            var uniforms = LaunchUniforms(
                heartAngle: elapsed / turn * 2 * .pi,
                ringAngle: elapsed / turn * 2 * .pi * Float(LaunchParticleField.ringTurnRatio),
                scale: height * Self.scaleFraction,
                centre: SIMD2(Float(size.width) * 0.5, height * Self.centreFraction),
                viewport: SIMD2(Float(size.width), height),
                pointSize: height * Self.pointFraction)

            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(points, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaunchUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
            encoder.endEncoding()
            commands.present(drawable)
            commands.commit()
        }
    }
}

/// Mirrors the `LaunchUniforms` struct in `LaunchParticles.metal`.
///
/// Field order and types must match exactly — there is no compiler check across
/// that boundary, and a mismatch shows up as a heart in the wrong place rather
/// than as an error.
private struct LaunchUniforms {
    var heartAngle: Float
    var ringAngle: Float
    var scale: Float
    var centre: SIMD2<Float>
    var viewport: SIMD2<Float>
    var pointSize: Float
}

// MARK: - Shader source

private extension LaunchParticleView.Renderer {

    /// The shader, verbatim. It lived in `LaunchParticles.metal` until the
    /// user's own Mac turned out not to have Xcode 26's separately-downloadable
    /// Metal toolchain, which made every build on that machine fail at
    /// `CompileMetalFile` while GitHub's runners — which do have it — kept CI
    /// green. `makeLibrary(source:)` needs no build-time toolchain anywhere.
    static let shaderSource = """
#include <metal_stdlib>
using namespace metal;

// The launch screen's heart, drawn as point sprites.
//
// Everything below is per-vertex work on eighty-six thousand points, which is
// nothing for a GPU and was impossible for the thing it replaces: a SwiftUI
// TimelineView redrawing on the main thread, on a screen that exists precisely
// because the main thread is busy.
//
// The point cloud itself is built in InsightKit (`LaunchParticleField`), where
// its shape can be tested. This file only turns and projects it.

struct LaunchUniforms {
    float  heartAngle;
    float  ringAngle;
    float  scale;        // pixels per model unit
    float2 centre;       // pixels
    float2 viewport;     // pixels
    float  pointSize;    // pixels, before perspective
};

struct ParticleOut {
    float4 position [[position]];
    float  size     [[point_size]];
    half4  colour;
};

vertex ParticleOut launchParticleVertex(uint vid [[vertex_id]],
                                        const device float4 *points [[buffer(0)]],
                                        constant LaunchUniforms &u [[buffer(1)]])
{
    float4 p = points[vid];
    bool isRing = p.w > 0.5;

    // The ring turns slower than the heart so the two never lock into one rigid
    // object — which is what makes a rotating cloud read as a solid instead.
    float a = isRing ? u.ringAngle : u.heartAngle;
    float c = cos(a);
    float s = sin(a);

    // Turn about the screen-vertical axis. For this heart surface that is model
    // z (lobes at +z, point at -z), with model y as the direction the camera
    // looks down. Rotating x against z instead spins it in the screen plane like
    // a pinwheel; the first prototype did exactly that.
    float rx = c * p.x - s * p.y;
    float ry = s * p.x + c * p.y;      // depth
    float rz = p.z;

    float persp = 3.6 / (3.6 + ry);
    float2 pixel = u.centre + float2(rx, -rz) * persp * u.scale;

    ParticleOut o;
    float2 ndc = pixel / u.viewport * 2.0 - 1.0;
    o.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    o.size = max(u.pointSize * persp, 1.0);

    // Front-lit: points nearer the camera pick up a white highlight. This is
    // what gives a flat scatter of dots the sense of a volume, and it is the
    // only lighting there is — there is no normal to shade with, because a point
    // sprite has no surface.
    float lit = clamp((0.45 - ry) / 1.35, 0.0, 1.0);
    half3 base = isRing ? half3(0.804h, 0.376h, 0.376h)
                        : half3(0.776h, 0.306h, 0.306h);
    half3 col = mix(base, half3(1.0h), half(lit * 0.82));

    // Premultiplied, so the blend below is a plain source-over and the order the
    // points arrive in stops mattering as much. It matters *some* — there is no
    // depth sort, because depth changes every frame under this rotation and
    // sorting eighty-six thousand points per frame would cost more than the
    // draw. Verified by eye against a sorted reference render: at these alphas
    // the difference is not visible.
    half alpha = half(clamp((isRing ? 0.40 : 0.30) * pow(persp, 2.2), 0.0, 1.0));
    o.colour = half4(col * alpha, alpha);
    return o;
}

fragment half4 launchParticleFragment(ParticleOut in [[stage_in]],
                                      float2 coord [[point_coord]])
{
    // A soft round dot rather than a square one. Without this the mist is
    // visibly made of pixels at close range, which is the whole complaint the
    // procedural version exists to answer.
    float d = length(coord - 0.5) * 2.0;
    half fade = half(smoothstep(1.0, 0.4, d));
    return in.colour * fade;
}

"""
}
