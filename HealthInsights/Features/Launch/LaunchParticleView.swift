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
/// building it is affordable. The projection maths in `LaunchParticles.metal`
/// mirrors a reference implementation that was rendered and looked at. What no
/// test here can reach is whether Metal draws any of it on a real device; that
/// is what `fallbackIfUnavailable` and the first build on the phone are for.
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

            guard let library = try? device.makeDefaultLibrary(bundle: .main),
                  let vertex = library.makeFunction(name: "launchParticleVertex"),
                  let fragment = library.makeFunction(name: "launchParticleFragment")
            else { return }

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
