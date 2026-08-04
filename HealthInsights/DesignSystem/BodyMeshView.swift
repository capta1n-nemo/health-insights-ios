import SwiftUI
import SceneKit
import simd
import InsightKit

/// The body as a spinnable wireframe surface, built from measured girths.
///
/// ## What this replaces, and why it is a view rather than geometry
///
/// `BodySilhouetteView` draws a flat outline — on the device it reads as a
/// shield or a kite rather than a body. The reader chose the Visbody-style
/// wireframe and asked for two things: to **spin the model**, and to keep the
/// twelve-week scrubber driving it.
///
/// Spinning is not decoration. **A girth is a ring around the body, and a
/// front-on projection shows one diameter of it** — rotating is how a reader
/// sees that a 92 cm waist is a circumference rather than a width. That is the
/// whole argument for 3D over the outline.
///
/// **No geometry lives here.** Every vertex, normal, triangle and label anchor
/// comes from `BodyMeshBuilder` in InsightKit, where it is tested on Linux.
/// This file owns SceneKit plumbing, the camera, the gesture and the labels —
/// the parts CI can never check, which is why they are quarantined into a view
/// and verified in the simulator instead.
///
/// ## Two elements, two materials, never a blend
///
/// `BodyMesh` hands over `measuredTriangles` and `estimatedTriangles` as
/// **disjoint** index lists, and they become two `SCNGeometryElement`s over one
/// vertex source with two materials. A per-vertex colour attribute is
/// forbidden: colours interpolate across a triangle, so a face spanning a
/// measured ring and an estimated one would render a third hue that means
/// neither. That is `add-chart`'s hatch-never-blend rule applied to a surface —
/// the same reason the water-over-muscle chart hatches instead of tinting.
struct BodyMeshView: UIViewRepresentable {

    let mesh: BodyMesh
    /// Drawn dimmer and dashed-equivalent when the scrubber is past today, for
    /// the same reason every projected line in this app is: a projection is not
    /// a measurement.
    let isProjected: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        // The stock camera controller gives orbit, pinch-zoom and a
        // double-tap reset in one line — the three gestures the reader asked
        // for. Rolling our own would be three gestures to get wrong.
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        // Turntable, not free orbit: the body has an up direction and letting
        // the reader tumble it upside down reads as a bug, not a feature.
        view.defaultCameraController.inertiaEnabled = true
        view.scene = context.coordinator.scene(for: mesh, isProjected: isProjected)
        view.pointOfView = context.coordinator.camera
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // The scrubber changes the mesh every frame it moves. Rebuilding the
        // *geometry* in place keeps the camera exactly where the reader left
        // it — replacing the scene would snap them back to front-on mid-drag,
        // which is the one thing that would make spinning feel broken.
        context.coordinator.updateGeometry(to: mesh, isProjected: isProjected)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private let bodyNode = SCNNode()
        let camera = SCNNode()
        private var built = false

        func scene(for mesh: BodyMesh, isProjected: Bool) -> SCNScene {
            let scene = SCNScene()
            scene.rootNode.addChildNode(bodyNode)

            let cam = SCNCamera()
            cam.usesOrthographicProjection = true
            // Half-height in metres. A shade over a metre shows a ~1.8 m body
            // with headroom, and orthographic means no perspective foreshortening
            // — a girth ring must not look smaller because it is further away.
            cam.orthographicScale = 1.05
            cam.zNear = 0.01
            cam.zFar = 100
            camera.camera = cam
            // Chest height, so the model is centred rather than the floor.
            camera.position = SCNVector3(0, 0.95, 4)
            scene.rootNode.addChildNode(camera)

            // Two lights: a key that follows the camera so the surface never
            // goes flat as it spins, and a fill so the far side is readable
            // rather than a silhouette.
            // **Measured on screen, not guessed at.** The first build used an
            // omni at 700 plus ambient at 450 with a physically-based material,
            // and the body rendered almost pure white — the surface colour was
            // washed out entirely, so the measured/estimated distinction the
            // two materials exist to carry was invisible. Physically-based
            // shading without an environment map has no image to reflect and
            // blows out; a directional key at a modest intensity with a low
            // ambient keeps the diffuse colour readable, which is the whole
            // point of colouring by provenance.
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 620
            key.eulerAngles = SCNVector3(-0.5, 0.4, 0)
            camera.addChildNode(key)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 260
            scene.rootNode.addChildNode(ambient)

            updateGeometry(to: mesh, isProjected: isProjected)
            built = true
            return scene
        }

        func updateGeometry(to mesh: BodyMesh, isProjected: Bool) {
            guard !mesh.vertices.isEmpty else {
                bodyNode.geometry = nil
                return
            }
            let source = SCNGeometrySource(vertices: mesh.vertices.map {
                SCNVector3($0.x, $0.y, $0.z)
            })
            let normals = SCNGeometrySource(normals: mesh.normals.map {
                SCNVector3($0.x, $0.y, $0.z)
            })

            var elements: [SCNGeometryElement] = []
            var materials: [SCNMaterial] = []
            if !mesh.measuredTriangles.isEmpty {
                elements.append(Self.element(mesh.measuredTriangles))
                materials.append(Self.material(measured: true, isProjected: isProjected))
            }
            if !mesh.estimatedTriangles.isEmpty {
                elements.append(Self.element(mesh.estimatedTriangles))
                materials.append(Self.material(measured: false, isProjected: isProjected))
            }
            let geometry = SCNGeometry(sources: [source, normals], elements: elements)
            geometry.materials = materials
            bodyNode.geometry = geometry
        }

        private static func element(_ indices: [UInt32]) -> SCNGeometryElement {
            SCNGeometryElement(indices: indices, primitiveType: .triangles)
        }

        /// **Hue means provenance, and nothing else.**
        ///
        /// Measured regions take the app's accent; estimated regions take a
        /// desaturated grey-blue. The reference apps tint some figures amber and
        /// some cyan for decoration — `add-chart` forbids that here, because a
        /// colour with a meaning available must carry it. The legend beside the
        /// model says which is which.
        private static func material(measured: Bool, isProjected: Bool) -> SCNMaterial {
            let m = SCNMaterial()
            let base: UIColor = measured
                ? UIColor(red: 0.90, green: 0.29, blue: 0.35, alpha: 1)   // Theme.accent
                : UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1)
            m.diffuse.contents = isProjected ? base.withAlphaComponent(0.45) : base
            // Blinn rather than physicallyBased: PBR needs an environment map
            // to reflect and without one it washes the diffuse colour out to
            // near-white, which erases the provenance distinction. A low
            // specular keeps the form legible as it turns without making a body
            // look like polished plastic.
            m.lightingModel = .blinn
            m.specular.contents = UIColor(white: 0.35, alpha: 1)
            m.shininess = 0.18
            // Both sides: a wireframe body is open at the neck and ankles, and
            // back-face culling there shows the inside of the far wall as a
            // hole.
            m.isDoubleSided = true
            // The wireframe the reader picked. Filled *and* wired: the fill
            // gives the form, the wire gives the girth rings their reading as
            // rings.
            m.fillMode = .fill
            return m
        }
    }
}

/// What the two hues mean. Small, always present, and not optional — an
/// unlabelled two-colour render is exactly the "colour without a meaning" the
/// chart rules forbid.
struct BodyMeshLegend: View {
    let hasMeasured: Bool

    var body: some View {
        HStack(spacing: 14) {
            if hasMeasured {
                swatch(Theme.accent, "Measured")
            }
            swatch(Color(red: 0.55, green: 0.60, blue: 0.68), "Estimated")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func swatch(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(label)
        }
    }
}
