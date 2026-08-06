import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A live diagnostic view: every connection attempt, API call and per-metric
/// import the app makes, with a pass / fail / null / info status. Read-only and
/// entirely on-device; helps pin down why a device "won't connect" or why a
/// stat is missing.
struct TroubleshootingView: View {
    @Environment(AppModel.self) private var model
    @State private var log = DiagnosticsLog.shared
    @State private var filter: DiagnosticsLog.Status?
    @State private var copied = false
    @State private var resetCopied: Task<Void, Never>?
    @State private var confirmingRebuild = false
    @State private var isRebuilding = false
    /// Which entries have their evidence expanded. Details are long (a server's
    /// error body plus what to do about it), so they stay folded until asked for.
    @State private var expanded: Set<UUID> = []

    private var shown: [DiagnosticsLog.Entry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.status == filter }
    }

    private var failures: [DiagnosticsLog.Entry] {
        log.entries.filter { $0.status == .fail }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    Text("All").tag(DiagnosticsLog.Status?.none)
                    Text("Passed").tag(DiagnosticsLog.Status?.some(.ok))
                    Text("Failed").tag(DiagnosticsLog.Status?.some(.fail))
                    Text("Empty").tag(DiagnosticsLog.Status?.some(.null))
                }
                .pickerStyle(.segmented)
            } footer: {
                // Still true, and kept for that reason (B8 R6): the diagnostics
                // log is in no sharing tier at all — `SharedRecord.Kind` has no
                // case for it — so "unless you copy it" remains the whole story
                // here even now that corrections can be shared.
                Text("A running record of syncs, API calls and imported data. Tap any line with a \u{201C}Details\u{201D} arrow to see the exact request, the provider's own error message, and what to do about it. Nothing here leaves your phone unless you copy it — the log is not part of what Data & model improvement can share.")
            }

            Section {
                Button {
                    Haptics.tap()
                    confirmingRebuild = true
                } label: {
                    HStack {
                        Label("Rebuild data from providers", systemImage: "arrow.clockwise.circle")
                        if isRebuilding {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRebuilding)
            } footer: {
                Text("Pull to refresh *merges* new readings into what's already stored, and a provider that fails to respond keeps its last-known copy — which is what you want when a device is simply offline, and not what you want when the app's reading of that data has changed. Rebuilding throws the stored copy away and re-reads every connected provider from scratch. Manual entries, grounding answers, substance logs and feedback are kept.")
            }

            // Anything red gets its own summary at the top, so a problem doesn't
            // have to be hunted for among hundreds of successful imports. Skipped
            // when already filtered to failures — that list is the same thing.
            if !failures.isEmpty, filter != .fail {
                Section {
                    ForEach(failures.prefix(5)) { entry in row(entry) }
                    if failures.count > 5 {
                        Button("Show all \(failures.count) failures") { filter = .fail }
                            .font(.subheadline)
                    }
                } header: {
                    Label("\(failures.count) failure\(failures.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.bad)
                }
            }

            if shown.isEmpty {
                Section {
                    Text("No activity yet. Pull to refresh on the Today tab, or connect a device, then come back.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(shown) { entry in row(entry) }
                } header: {
                    Text("\(shown.count) event\(shown.count == 1 ? "" : "s")")
                }
            }
        }
        .navigationTitle("Troubleshooting")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Rebuild data from providers?",
                            isPresented: $confirmingRebuild, titleVisibility: .visible) {
            Button("Rebuild", role: .destructive) {
                isRebuilding = true
                Task {
                    await model.rebuildFromProviders()
                    isRebuilding = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every reading synced from Apple Health, Oura, Withings and any other connected provider is discarded and fetched again. This takes as long as a normal sync.\n\nAnything you entered yourself is kept. A provider that can't be reached right now will have no data until it syncs successfully, so it's worth checking you're online first.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        copyLog()
                    } label: { Label(copied ? "Copied" : "Copy log", systemImage: "doc.on.doc") }
                    ShareLink(item: log.exportText()) {
                        Label("Share log", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        log.clear()
                        expanded.removeAll()
                    } label: { Label("Clear", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func row(_ entry: DiagnosticsLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.status.symbol)
                .foregroundStyle(color(entry.status))
                .font(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(entry.category) · \(entry.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
                if let detail = entry.detail {
                    detailDisclosure(entry, detail)
                }
            }
        }
    }

    @ViewBuilder
    private func detailDisclosure(_ entry: DiagnosticsLog.Entry, _ detail: String) -> some View {
        let isOpen = expanded.contains(entry.id)
        Button {
            Haptics.tap()
            withAnimation(.snappy) {
                if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
            }
        } label: {
            Label(isOpen ? "Hide details" : "Details",
                  systemImage: isOpen ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)

        if isOpen {
            Text(detail)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func color(_ status: DiagnosticsLog.Status) -> Color {
        switch status {
        case .ok: return Theme.good
        case .fail: return Theme.bad
        case .null: return Theme.warn
        case .info: return .secondary
        }
    }

    private func copyLog() {
        #if canImport(UIKit)
        UIPasteboard.general.string = log.exportText()
        #endif
        Haptics.tap()
        withAnimation { copied = true }
        // Cancel any in-flight reset, so a second copy restarts the clock
        // instead of an earlier timer clearing a fresh confirmation.
        resetCopied?.cancel()
        resetCopied = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { copied = false }
        }
    }
}
