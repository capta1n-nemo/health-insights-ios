import UIKit
import SwiftUI
import UniformTypeIdentifiers
import InsightKit

/// The share sheet's **bottom row**.
///
/// The user, looking at Shotsy's share sheet with three other apps listed under
/// the app row: *"why is it not in the bottom like other 3 apps that support
/// actions, I want an action."* That row is Action Extensions, which is a
/// different mechanism from the document-type declaration that put us in the
/// row above — see `SharedInbox` for why the two cannot be the same code.
///
/// ## What it does, and what it deliberately does not
///
/// It copies the shared file into the App Group container and says so. It does
/// **not** parse, score, or write to the store: an extension runs in its own
/// process with a hard memory ceiling, and a Shotsy backup is several hundred
/// SwiftData inserts and a full re-score. Doing that here is how an extension
/// gets killed mid-write. The app drains the inbox on next launch or foreground
/// and runs the one importer.
///
/// So the copy has to be fast and the message has to be honest about what
/// happens next — "saved, open the app" rather than "imported".
@objc(ActionViewController)
final class ActionViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        let host = UIHostingController(
            rootView: ShotsyActionView(providers: providers) { [weak self] in
                // `completeRequest` rather than `cancelRequest`: the reader
                // asked for this and it either worked or it explained itself.
                // Cancelling makes the host app think the action was dismissed.
                self?.extensionContext?.completeRequest(returningItems: nil)
            })

        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// The whole extension UI: one line of status and one button.
///
/// Deliberately tiny. An action extension is a thing that happens *to* a file
/// the reader is already looking at; a second app's worth of chrome inside a
/// sheet over Shotsy would be a worse version of the app they can already open.
struct ShotsyActionView: View {
    let providers: [NSItemProvider]
    let onDone: () -> Void

    @State private var status: Status = .working

    enum Status {
        case working
        case staged(String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 14) {
            icon
            Text(headline)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDone) {
                Text(isWorking ? "Cancel" : "Done")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task { await stage() }
    }

    private var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    @ViewBuilder private var icon: some View {
        switch status {
        case .working:
            ProgressView().controlSize(.large)
        case .staged:
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle).foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundStyle(.orange)
        }
    }

    private var headline: String {
        switch status {
        case .working: return "Saving to Health Insights…"
        case .staged: return "Saved to Health Insights"
        case .failed: return "Couldn't take that file"
        }
    }

    /// The honest version of what just happened. It says the import happens on
    /// *opening the app*, because it does — claiming otherwise would leave the
    /// reader wondering why their weight hadn't moved.
    private var detail: String {
        switch status {
        case .working:
            return "Copying the file across."
        case .staged(let name):
            return "\(name) is ready. Open Health Insights and it will be imported — your doses, weight and body composition are merged, and sharing the same file twice doesn't duplicate anything."
        case .failed(let reason):
            return reason
        }
    }

    // MARK: - The copy

    private func stage() async {
        guard !isAlreadyResolved else { return }
        do {
            guard let file = try await firstFile() else {
                status = .failed("Nothing here looked like a file. Share the JSON that Shotsy's own export produces.")
                return
            }
            let url = try SharedInbox.stage(file.data, originalName: file.name)
            status = .staged(url.lastPathComponent.components(separatedBy: "-").dropFirst(2)
                                .joined(separator: "-"))
        } catch let error as SharedInboxError {
            status = .failed(error.localizedDescription)
        } catch {
            status = .failed("Couldn't save the file: \(error.localizedDescription)")
        }
    }

    /// `.task` can fire again on a re-render; the copy is not something to do
    /// twice.
    private var isAlreadyResolved: Bool {
        if case .working = status { return false }
        return true
    }

    /// The first attachment that yields bytes.
    ///
    /// Asked for as a **file URL first, data second**. A provider that hands
    /// over a URL is the common case and costs nothing to read; asking for
    /// `public.data` first can make the system materialise a copy the extension
    /// then has to hold in memory twice.
    private func firstFile() async throws -> (data: Data, name: String)? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = try? await loadURL(from: provider),
               let data = try? Data(contentsOf: url) {
                return (data, url.lastPathComponent)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.json.identifier),
               let data = try? await loadData(from: provider, type: UTType.json.identifier) {
                return (data, provider.suggestedName ?? "shared.shotsyjson")
            }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let url = item as? URL { continuation.resume(returning: url); return }
                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8),
                   let url = URL(string: string) {
                    continuation.resume(returning: url); return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private func loadData(from provider: NSItemProvider, type: String) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }
}
