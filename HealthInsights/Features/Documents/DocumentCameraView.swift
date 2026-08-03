import SwiftUI
#if canImport(VisionKit)
import VisionKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The system document scanner, as a SwiftUI view.
///
/// `VNDocumentCameraViewController` is what iOS uses for Notes' "Scan
/// Documents": edge detection, perspective correction and per-page capture,
/// none of which this app should be writing itself. It is a UIKit controller
/// that must be presented modally, so it arrives here through
/// `UIViewControllerRepresentable` and is shown as a `fullScreenCover`.
///
/// **It hands back every page**, not the first. A pathology report runs to two
/// or three sheets and the cholesterol panel is rarely on the one you happen to
/// scan first — the caller decides what to do with them.
///
/// Behind `canImport(VisionKit)` so this file stays compilable where the
/// framework is not, which is how the rest of the app's platform-specific
/// code is written. `isAvailable` is the caller's gate: the scanner is not
/// supported on a device without a camera, and a button that presents nothing
/// is worse than no button.
struct DocumentCameraView: View {
    /// Pages, in the order they were scanned. Empty when the reader cancels.
    let onFinish: ([PlatformImage]) -> Void

    /// Whether the system scanner can run here at all.
    static var isAvailable: Bool {
        #if canImport(VisionKit) && canImport(UIKit)
        return VNDocumentCameraViewController.isSupported
        #else
        return false
        #endif
    }

    var body: some View {
        #if canImport(VisionKit) && canImport(UIKit)
        Representable(onFinish: onFinish)
            .ignoresSafeArea()
        #else
        // Unreachable through `isAvailable`, and present so the type exists on
        // every platform this target is compiled for.
        Color.clear.onAppear { onFinish([]) }
        #endif
    }

    #if canImport(VisionKit) && canImport(UIKit)
    private struct Representable: UIViewControllerRepresentable {
        let onFinish: ([PlatformImage]) -> Void

        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let controller = VNDocumentCameraViewController()
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_ controller: VNDocumentCameraViewController,
                                    context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

        /// Every delegate route ends in exactly one `onFinish`, including the
        /// failure one. A scanner that reports nothing when the camera errors
        /// leaves the sheet up with a spinner behind it and no way to tell what
        /// happened.
        final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
            private let onFinish: ([PlatformImage]) -> Void
            init(onFinish: @escaping ([PlatformImage]) -> Void) { self.onFinish = onFinish }

            func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                              didFinishWith scan: VNDocumentCameraScan) {
                let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
                onFinish(pages)
            }

            func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
                onFinish([])
            }

            func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                              didFailWithError error: Error) {
                DiagnosticsLog.shared.fail("Import", "Document scanner failed: \(error.localizedDescription)")
                onFinish([])
            }
        }
    }
    #endif
}
