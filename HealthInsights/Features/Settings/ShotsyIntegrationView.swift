import SwiftUI
import UniformTypeIdentifiers
import InsightKit

/// How the Shotsy integration works, because it is the one that needs saying.
///
/// Every other integration in this list is a switch: press Connect, authorise,
/// data arrives. This one is a gesture the reader performs in *another app*,
/// and nothing on their phone will ever teach them that. So the screen's main
/// job is the three steps — and the honest admission that the data is only as
/// fresh as the last time they did it.
struct ShotsyIntegrationView: View {
    @Environment(AppModel.self) private var model
    @State private var showingImporter = false
    @State private var importMessage: String?

    private var lastImport: Date? { ShotsyIntegration.lastImportDate }

    var body: some View {
        List {
            statusSection
            howSection
            importSection
            whatSection
        }
        .navigationTitle("Shotsy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusSection: some View {
        Section {
            if let lastImport {
                LabeledContent("Last file received") {
                    Text(lastImport.formatted(date: .abbreviated, time: .shortened))
                }
                if let summary = ShotsyIntegration.lastImportSummary {
                    Text(summary)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No file received yet.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Status")
        } footer: {
            // The one thing this integration must not let anyone assume.
            Text(lastImport == nil
                 ? "Shotsy has no API, so this app can't fetch from it. Data arrives only when you export and share a file."
                 : "Shotsy has no API, so nothing updates on its own — your Shotsy data here is as of the file above. Share a fresh export whenever you want it caught up.")
        }
    }

    private var howSection: some View {
        Section {
            step(1, "Open Shotsy, then Settings ▸ Manage My Data.")
            step(2, "Tap Export JSON. Shotsy makes the file and opens the share sheet.")
            step(3, "Choose Health Insights from the list. The import runs straight away.")
            Link(destination: URL(string: "shotsy://")!) {
                Label("Open Shotsy", systemImage: "arrow.up.forward.app")
            }
        } header: {
            Text("How to send your data")
        } footer: {
            // Deep links to third-party apps are a guess unless the developer
            // documents the scheme, and a dead button is worse than none — so
            // this says what to do if it doesn't work rather than pretending.
            Text("If \"Open Shotsy\" does nothing, the app doesn't publish a link scheme — open it from your home screen instead. Nothing else changes.")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showingImporter = true
            } label: {
                Label("Choose a file instead", systemImage: "folder")
            }
            if let importMessage {
                Text(importMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Text("For a backup you've already saved to Files. Sharing the same export twice is safe — nothing is imported twice.")
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: Self.acceptedTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importMessage = model.importSharedFile(at: url)
            case .failure(let error):
                importMessage = "Couldn't open that file: \(error.localizedDescription)"
            }
        }
    }

    /// Shotsy's export is `.shotsyjson`, which is its own type rather than
    /// `public.json` — a picker offering only JSON greys the file out. The
    /// imported declaration in Info.plist is what makes the first of these
    /// resolve at all.
    static var acceptedTypes: [UTType] {
        [UTType("com.shotsy.json"), .json, .data].compactMap { $0 }
    }

    private var whatSection: some View {
        Section {
            row("Injections", "every dose, its date, strength and site")
            row("Weight", "each weigh-in Shotsy holds")
            row("Body fat and lean mass", "where your scale reported them")
            row("Exercise minutes", "as Shotsy recorded them")
        } header: {
            Text("What comes across")
        } footer: {
            Text("Your injections replace any doses this app had estimated — a real record beats a guess. Calories and macros are in the file but aren't imported yet; the app has nowhere to put them.")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background(Theme.accent.opacity(0.15), in: Circle())
            Text(text).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
